//
//  TrainingSessionManager.swift
//  VBTTracker
//
//  AGGIORNATO: Gestisce MPV/PPV + look-ahead sincronizzato con Settings
//

import Foundation
import Combine

class TrainingSessionManager: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var isRecording = false
    @Published var currentVelocity: Double = 0.0
    
    // Velocità separate secondo standard VBT
    @Published var meanPropulsiveVelocity: Double = 0.0   // MPV corrente
    @Published var peakPropulsiveVelocity: Double = 0.0   // PPV corrente
    
    // Legacy (per retrocompatibilità UI)
    @Published var peakVelocity: Double = 0.0
    @Published var meanVelocity: Double = 0.0
    @Published var velocityLoss: Double = 0.0
    
    @Published var repCount: Int = 0
    @Published var currentZone: TrainingZone = .tooSlow
    
    @Published var lastRepInTarget: Bool = true
    @Published var lastRepPeakVelocity: Double = 0.0
    
    // Tracking separato MPV ultima rep
    @Published var lastRepMPV: Double = 0.0
    @Published var lastRepPPV: Double = 0.0
    
    // MARK: - Sample rate / Look-ahead
    
    /// Frequenza di campionamento del sensore (Hz). Aggiornala da fuori (TrainingSessionView) leggendo dal BLE.
    var sampleRateHz: Double = 200.0 {
        didSet {
            // Debounce: max 1 chiamata al secondo
            let now = Date()
            if now.timeIntervalSince(lastConfigTime) > 1.0 {
                lastConfigTime = now
                configureLookAhead()
            }
        }
    }
    
    // Track ultima configurazione per debounce
    private var lastConfigTime: Date = .distantPast

    /// Numero di campioni di look-ahead per il rilevamento rep (derivato da Settings + sampleRateHz)
    private var lookAheadSamples: Int {
        let seconds = SettingsManager.shared.repLookAheadMs / 1000.0
        let n = Int(round(seconds * sampleRateHz))
        return min(max(n, 10), 80) // clamp a 10-80 campioni (~0.05-0.4 s @200 Hz)
    }
    
    /// Comodo setter da chiamare dalla View
    func setSampleRateHz(_ hz: Double) {
        self.sampleRateHz = hz
    }
    
    var targetZone: TrainingZone = .strength
    
    // MARK: - Private Properties
    
    private var velocity: Double = 0.0
    private var isMoving = false
    private var phase: MovementPhase = .idle
    
    let repDetector = VBTRepDetector()
    private let voiceFeedback = VoiceFeedbackManager()

    private var inConcentricPhase = false
    private var concentricPeakReached = false
    private var lastRepTime: Date?
    private var movementStartTime: Date?
    
    // Storage MPV/PPV per rep
    var repMeanPropulsiveVelocities: [Double] = []  // MPV per ogni rep
    var repPeakPropulsiveVelocities: [Double] = []  // PPV per ogni rep
    
    // Legacy storage (mantiene PPV per retrocompatibilita)
    var repPeakVelocities: [Double] = []
    var firstRepPeakVelocity: Double?
    
    // Prima rep per calcolo velocity loss
    var firstRepMPV: Double?
    var firstRepPPV: Double?
    
    private var cancellables = Set<AnyCancellable>()
    
    enum MovementPhase {
        case idle
        case concentric
        case eccentric
    }
    
    // MARK: - Init
    
    init() {
        // Reagisci ai cambi del look-ahead nei Settings (senza riavvio)
        SettingsManager.shared.$repLookAheadMs
            .sink { [weak self] _ in self?.configureLookAhead() }
            .store(in: &cancellables)
        
        // Config iniziale
        configureLookAhead()
    }
    
    // MARK: - Config
    
    /// Centralizza la configurazione dipendente da sampleRate/look-ahead
    private func configureLookAhead() {
        let hz = max(5.0, min(sampleRateHz, 200.0))
        let la = lookAheadSamples

        // passa i parametri al detector (se li usa)
        repDetector.sampleRateHz = hz
        repDetector.lookAheadSamples = la
    }
    
    // MARK: - Public Methods
    
    func startRecording() {
        isRecording = true
        resetMetrics()
        configureLookAhead()
        
        // Logga pattern appreso se disponibile
        if let pattern = repDetector.learnedPattern {
            print("Pattern appreso caricato:")
            print("ROM: \(String(format: "%.0f", pattern.estimatedROM * 100))cm")
            print("Soglia min: \(String(format: "%.2f", pattern.dynamicMinAmplitude))g")
            print("Velocità media: \(String(format: "%.2f", pattern.avgPeakVelocity)) m/s")
        } else {
            print("Nessun pattern appreso - Usando soglie adaptive")
        }
        
        // 🔊 Callback: annuncia lo "Stacco" (unrack) una volta
        repDetector.onUnrack = { [weak self] in
            self?.voiceFeedback.announceBarUnrack()
        }

        // Callback di fase (opzionale: lascia vuoto "stacco" qui)
        repDetector.onPhaseChange = { [weak self] phase in
            guard let self else { return }
            DispatchQueue.main.async {
                switch phase {
                case .descending:
                    self.currentZone = .strength  // o un log provvisorio
                case .ascending, .idle, .completed:
                    break
                }
            }
        }
        
        voiceFeedback.announceWorkoutStart()
        print("Sessione allenamento iniziata - Target: \(targetZone.rawValue)")
        print("Modalità velocità: \(SettingsManager.shared.velocityMeasurementMode == .concentricOnly ? "Concentrica (Standard VBT)" : "Full ROM")")
        print("Look-ahead attivo: \(Int(SettingsManager.shared.repLookAheadMs)) ms \(lookAheadSamples) campioni")
    }

    func stopRecording() {
        isRecording = false
        calculateFinalMetrics()
        voiceFeedback.announceWorkoutEnd(reps: repCount)
        
        print("Sessione terminata - Reps: \(repCount)")
        print("• MPV medio: \(String(format: "%.3f", meanVelocity)) m/s")
        print("• Velocity Loss: \(String(format: "%.1f", velocityLoss))%")
    }

    func processSensorData(
        acceleration: [Double],
        angularVelocity: [Double],
        angles: [Double],
        isCalibrated: Bool
    ) {
        guard isRecording else { return }
            
        guard acceleration.count >= 3 else { return }

        
        // 1) Ottieni accelerazione Z (verticale) e togli la gravità (coerente con il detector)
        let accZ = acceleration[2]
        let accZNoGravity = accZ - 1.0  // Rimuove la gravità (1.0g) -> fermo = 0g

        
        repDetector.velocityMode = SettingsManager.shared.velocityMeasurementMode
        // let result = repDetector.addSample(accZ: accZNoGravity, timestamp: Date())
        
        // 🔍 DEBUG: ogni 100 samples stampa stato
        if repDetector.getSamples().count % 100 == 0 {
            print("\n⏱️  Samples: \(repDetector.getSamples().count)")
            repDetector.printDebugState()
            print(repDetector.validateCurrentMovement())
        }
        // 2) Passa modalità velocità al detector
        repDetector.velocityMode = SettingsManager.shared.velocityMeasurementMode
        
        // 3) Rileva rep (nuova API)
        let result = repDetector.addSample(accZ: accZNoGravity, timestamp: Date())
        
        // 4) Elabora risultato con MPV e PPV
        if result.repDetected {
            let mpv = result.meanPropulsiveVelocity ?? result.peakVelocity ?? 0.0
            let ppv = result.peakPropulsiveVelocity ?? result.peakVelocity ?? 0.0
            countRep(mpv: mpv, ppv: ppv)
        }
        
        // 5) Aggiorna zona e velocità correnti
        DispatchQueue.main.async {
            let velocityForZone = self.meanPropulsiveVelocity > 0.1 ?
                self.meanPropulsiveVelocity : self.peakPropulsiveVelocity
            
            if velocityForZone > 0.1 {
                self.currentZone = SettingsManager.shared.getTrainingZone(for: velocityForZone)
            }
            
            self.currentVelocity = abs(result.currentValue) * 9.81 // da g a m/s^2
            
            if let mpv = result.meanPropulsiveVelocity, mpv > self.meanPropulsiveVelocity {
                self.meanPropulsiveVelocity = mpv
            }
            if let ppv = result.peakPropulsiveVelocity, ppv > self.peakPropulsiveVelocity {
                self.peakPropulsiveVelocity = ppv
            }
            self.peakVelocity = self.peakPropulsiveVelocity // legacy
        }
    }

    /// Aggiungi una ripetizione dal sensore di distanza (Arduino)
    func addRepetitionFromDistance(
        mpv: Double,
        ppv: Double,
        displacement: Double,
        concentricDuration: TimeInterval
    ) {
        guard isRecording else { return }

        // Aggiorna contatori e storage
        repCount += 1
        repMeanPropulsiveVelocities.append(mpv)
        repPeakPropulsiveVelocities.append(ppv)
        repPeakVelocities.append(ppv)  // Per retrocompatibilità

        // Prima rep: stabilisci baseline
        if firstRepMPV == nil {
            firstRepMPV = mpv
            firstRepPPV = ppv
            firstRepPeakVelocity = ppv
        }

        // Calcola velocity loss
        if let baseline = firstRepMPV {
            let loss = ((baseline - mpv) / baseline) * 100.0
            velocityLoss = max(0, loss)
        }

        // Aggiorna last rep
        lastRepMPV = mpv
        lastRepPPV = ppv
        lastRepPeakVelocity = ppv
        currentVelocity = ppv
        meanPropulsiveVelocity = mpv
        peakPropulsiveVelocity = ppv

        // Determina zona
        let zone = SettingsManager.shared.getTrainingZone(for: mpv)
        currentZone = zone
        lastRepInTarget = (zone == targetZone)

        // Voice feedback
        if SettingsManager.shared.voiceFeedbackEnabled {
            voiceFeedback.announceRep(number: repCount, isInTarget: lastRepInTarget)
        }

        print("✅ Rep #\(repCount) rilevata (Arduino)")
        print("   • MPV: \(String(format: "%.3f", mpv)) m/s")
        print("   • PPV: \(String(format: "%.3f", ppv)) m/s")
        print("   • ROM: \(String(format: "%.3f", displacement)) m")
        print("   • Durata: \(String(format: "%.2f", concentricDuration)) s")
        print("   • Zona: \(zone.rawValue) \(lastRepInTarget ? "✅" : "❌")")
    }

    // MARK: - Public Helpers

    func getAccelerationSamples() -> [AccelerationSample] {
        return repDetector.getSamples()
    }
    
    func averageMPV() -> Double {
        guard !repMeanPropulsiveVelocities.isEmpty else { return 0 }
        return repMeanPropulsiveVelocities.reduce(0, +) / Double(repMeanPropulsiveVelocities.count)
    }
    func averagePPV() -> Double {
        guard !repPeakPropulsiveVelocities.isEmpty else { return 0 }
        return repPeakPropulsiveVelocities.reduce(0, +) / Double(repPeakPropulsiveVelocities.count)
    }
    
    func getRepPeakVelocities() -> [Double] {
        return repPeakVelocities
    }
    
    // MARK: - Private Methods
    
    private func countRep(mpv: Double, ppv: Double) {
        // Store MPV e PPV
        repMeanPropulsiveVelocities.append(mpv)
        repPeakPropulsiveVelocities.append(ppv)
        
        // Legacy: usa PPV
        repPeakVelocities.append(ppv)
        
        // Prima rep: salva per calcolo velocity loss
        if firstRepMPV == nil {
            firstRepMPV = mpv
            firstRepPPV = ppv
            firstRepPeakVelocity = ppv  // Legacy
        }
        
        // Check target (usa MPV come standard VBT)
        let isInTarget = checkIfInTarget(velocity: mpv)
        
        DispatchQueue.main.async {
            self.repCount += 1
            
            // Aggiorna metriche separate
            self.lastRepMPV = mpv
            self.lastRepPPV = ppv
            self.lastRepPeakVelocity = ppv  // Legacy
            self.lastRepInTarget = isInTarget
            
            self.calculateMeanVelocity()
            self.calculateVelocityLoss()
            
            // Reset velocità correnti per prossima rep
            self.meanPropulsiveVelocity = 0.0
            self.peakPropulsiveVelocity = 0.0
            self.peakVelocity = 0.0
            
            // Annuncia rep completata
            self.voiceFeedback.announceRep(number: self.repCount, isInTarget: isInTarget)
            
            // Check velocity loss
            if SettingsManager.shared.stopOnVelocityLoss &&
               self.velocityLoss >= SettingsManager.shared.velocityLossThreshold {
                self.voiceFeedback.announceVelocityLoss(percentage: self.velocityLoss)
            }
        }
        
        let emoji = isInTarget ? "✅" : "❌"
        print("\(emoji) RIPETIZIONE #\(repCount + 1) completata")
        print("   • MPV: \(String(format: "%.3f", mpv)) m/s")
        print("   • PPV: \(String(format: "%.3f", ppv)) m/s")
        print("   • Target: \(isInTarget ? "IN TARGET" : "FUORI TARGET")")
        
        // Runtime pattern recognition dopo 3-5 reps
        let newRepCount = repCount + 1
        if newRepCount == 3 || newRepCount == 5 {
            print("Analizzando pattern dopo \(newRepCount) reps...")
            repDetector.recognizePatternIfPossible()
        }
    }
    
    private func checkIfInTarget(velocity: Double) -> Bool {
        let targetRange = getRangeForTargetZone()
        return targetRange.contains(velocity)
    }

    private func getRangeForTargetZone() -> ClosedRange<Double> {
        let ranges = SettingsManager.shared.velocityRanges
        switch targetZone {
        case .maxStrength:   return ranges.maxStrength
        case .strength:      return ranges.strength
        case .strengthSpeed: return ranges.strengthSpeed
        case .speed:         return ranges.speed
        case .maxSpeed:      return ranges.maxSpeed
        case .tooSlow:       return 0.0...0.15
        }
    }
    
    /// Usa MPV per calcolo media (standard VBT)
    private func calculateMeanVelocity() {
        guard !repMeanPropulsiveVelocities.isEmpty else { return }
        meanVelocity = repMeanPropulsiveVelocities.reduce(0, +) / Double(repMeanPropulsiveVelocities.count)
    }
    
    /// Usa MPV per velocity loss (standard VBT)
    private func calculateVelocityLoss() {
        guard let firstMPV = firstRepMPV,
              let lastMPV = repMeanPropulsiveVelocities.last,
              firstMPV > 0 else {
            velocityLoss = 0.0
            return
        }
        
        let loss = ((firstMPV - lastMPV) / firstMPV) * 100.0
        velocityLoss = max(0, loss)
    }
    
    private func calculateFinalMetrics() {
        calculateMeanVelocity()
        calculateVelocityLoss()
        
        print("Metriche finali:")
        print("• Ripetizioni: \(repCount)")
        print("• MPV Medio: \(String(format: "%.3f", meanVelocity)) m/s")
        print("• Velocity Loss: \(String(format: "%.1f", velocityLoss))%")
        
        if let firstMPV = firstRepMPV, let lastMPV = repMeanPropulsiveVelocities.last {
            print("• Prima rep MPV: \(String(format: "%.3f", firstMPV)) m/s")
            print("• Ultima rep MPV: \(String(format: "%.3f", lastMPV)) m/s")
        }
        if let firstPPV = firstRepPPV, let lastPPV = repPeakPropulsiveVelocities.last {
            print("• Prima rep PPV: \(String(format: "%.3f", firstPPV)) m/s")
            print("• Ultima rep PPV: \(String(format: "%.3f", lastPPV)) m/s")
        }
    }
    
    private func resetMetrics() {
        velocity = 0.0
        currentVelocity = 0.0
        
        // Reset velocità separate
        meanPropulsiveVelocity = 0.0
        peakPropulsiveVelocity = 0.0
        
        // Legacy
        peakVelocity = 0.0
        meanVelocity = 0.0
        velocityLoss = 0.0
        repCount = 0

        inConcentricPhase = false
        concentricPeakReached = false
        lastRepTime = nil
        movementStartTime = nil
        
        // Reset storage separate
        repMeanPropulsiveVelocities.removeAll()
        repPeakPropulsiveVelocities.removeAll()
        firstRepMPV = nil
        firstRepPPV = nil
        
        // Legacy
        repPeakVelocities.removeAll()
        firstRepPeakVelocity = nil
        currentZone = .tooSlow
        
        // Reset ultima rep
        lastRepMPV = 0.0
        lastRepPPV = 0.0
        
        repDetector.reset()
    }
}
