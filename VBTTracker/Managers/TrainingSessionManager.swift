//
//  TrainingSessionManager.swift
//  VBTTracker
//
//  âœ… AGGIORNATO: Gestisce MPV/PPV + look-ahead sincronizzato con Settings
//

import Foundation
import Combine

class TrainingSessionManager: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var isRecording = false
    @Published var currentVelocity: Double = 0.0
    
    // âœ… VelocitÃ  separate secondo standard VBT
    @Published var meanPropulsiveVelocity: Double = 0.0   // MPV corrente
    @Published var peakPropulsiveVelocity: Double = 0.0   // PPV corrente
    
    // Legacy (per retrocompatibilitÃ  UI)
    @Published var peakVelocity: Double = 0.0
    @Published var meanVelocity: Double = 0.0
    @Published var velocityLoss: Double = 0.0
    
    @Published var repCount: Int = 0
    @Published var currentZone: TrainingZone = .tooSlow
    
    @Published var lastRepInTarget: Bool = true
    @Published var lastRepPeakVelocity: Double = 0.0
    
    // âœ… Tracking separato MPV ultima rep
    @Published var lastRepMPV: Double = 0.0
    @Published var lastRepPPV: Double = 0.0
    
    // MARK: - Sample rate / Look-ahead
    
    /// Frequenza di campionamento del sensore (Hz). Aggiornala da fuori (TrainingSessionView) leggendo dal BLE.
    var sampleRateHz: Double = 200.0 {
        didSet { configureLookAhead() }
    }

    /// Numero di campioni di look-ahead per il rilevamento rep (derivato da Settings + sampleRateHz)
    private var lookAheadSamples: Int {
        let seconds = SettingsManager.shared.repLookAheadMs / 1000.0
        let n = Int(round(seconds * sampleRateHz))
        return min(max(n, 10), 80) // clamp a 10â€“80 campioni (~0.05â€“0.4 s @200 Hz)
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
    
    // âœ… Storage MPV/PPV per rep
    var repMeanPropulsiveVelocities: [Double] = []  // MPV per ogni rep
    var repPeakPropulsiveVelocities: [Double] = []  // PPV per ogni rep
    
    // Legacy storage (mantiene PPV per retrocompatibilitÃ )
    var repPeakVelocities: [Double] = []
    var firstRepPeakVelocity: Double?
    
    // âœ… Prima rep per calcolo velocity loss
    var firstRepMPV: Double?
    var firstRepPPV: Double?
    
    // Constants
    private let dt: Double = 0.02 // 20ms sampling
    
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
        let ms = SettingsManager.shared.repLookAheadMs
        let la = lookAheadSamples
        print("âš™ï¸ Look-ahead configurato: \(Int(ms)) ms @ \(Int(sampleRateHz)) Hz â†’ \(la) campioni")
        
        // Se il detector in futuro espone un parametro di look-ahead,
        // puoi abilitarlo qui:
        // repDetector.sampleRateHz = sampleRateHz              // â¬…ï¸ se supportato
        // repDetector.lookAheadSamples = la                    // â¬…ï¸ se supportato
    }
    
    // MARK: - Public Methods
    
    func startRecording() {
        isRecording = true
        resetMetrics()
        configureLookAhead()
        
        // âœ… Logga pattern appreso se disponibile
        if let pattern = repDetector.learnedPattern {
            print("ðŸŽ“ Pattern appreso caricato:")
            print("   â€¢ ROM: \(String(format: "%.0f", pattern.estimatedROM * 100))cm")
            print("   â€¢ Soglia min: \(String(format: "%.2f", pattern.dynamicMinAmplitude))g")
            print("   â€¢ VelocitÃ  media: \(String(format: "%.2f", pattern.avgPeakVelocity)) m/s")
        } else {
            print("âš ï¸ Nessun pattern appreso - Usando soglie adaptive")
        }
        
        // Setup voice feedback callback
        repDetector.onPhaseChange = { [weak self] phase in
            guard let self = self else { return }
            DispatchQueue.main.async {
                switch phase {
                case .descending:
                    if self.repCount == 0 && !self.repDetector.hasAnnouncedUnrack {
                        self.voiceFeedback.announceBarUnrack()
                    }
                case .ascending:
                    break
                case .idle, .completed:
                    break
                }
            }
        }
        
        voiceFeedback.announceWorkoutStart()
        print("â–¶ï¸ Sessione allenamento iniziata - Target: \(targetZone.rawValue)")
        print("ðŸ“Š ModalitÃ  velocitÃ : \(SettingsManager.shared.velocityMeasurementMode == .concentricOnly ? "Concentrica (Standard VBT)" : "Full ROM")")
        print("ðŸ‘‚ Look-ahead attivo: \(Int(SettingsManager.shared.repLookAheadMs)) ms â†’ \(lookAheadSamples) campioni")
    }

    func stopRecording() {
        isRecording = false
        calculateFinalMetrics()
        
        // Annuncia fine
        voiceFeedback.announceWorkoutEnd(reps: repCount)
        
        print("â¹ï¸ Sessione terminata - Reps: \(repCount)")
        print("   â€¢ MPV medio: \(String(format: "%.3f", meanVelocity)) m/s")
        print("   â€¢ Velocity Loss: \(String(format: "%.1f", velocityLoss))%")
    }

    func processSensorData(
        acceleration: [Double],
        angularVelocity: [Double],
        angles: [Double],
        isCalibrated: Bool
    ) {
        guard isRecording else { return }
        
        // 1. Ottieni accelerazione Z (verticale)
        let accZ = acceleration[2]
        let accZNoGravity = isCalibrated ? accZ : (accZ - 1.0)
        
        // 2. Passa modalitÃ  velocitÃ  al detector
        repDetector.velocityMode = SettingsManager.shared.velocityMeasurementMode
        
        // 3. Rileva rep (nuova API)
        let result = repDetector.addSample(accZ: accZNoGravity, timestamp: Date())
        
        // 4. âœ… Elabora risultato con MPV e PPV
        if result.repDetected {
            let mpv = result.meanPropulsiveVelocity ?? result.peakVelocity ?? 0.0
            let ppv = result.peakPropulsiveVelocity ?? result.peakVelocity ?? 0.0
            countRep(mpv: mpv, ppv: ppv)
        }
        
        // 5. Aggiorna zona e velocitÃ  correnti
        DispatchQueue.main.async {
            let velocityForZone = self.meanPropulsiveVelocity > 0.1 ?
                self.meanPropulsiveVelocity : self.peakPropulsiveVelocity
            
            if velocityForZone > 0.1 {
                self.currentZone = SettingsManager.shared.getTrainingZone(for: velocityForZone)
            }
            
            self.currentVelocity = abs(result.currentValue) * 9.81 // g â†’ m/sÂ²
            
            if let mpv = result.meanPropulsiveVelocity, mpv > self.meanPropulsiveVelocity {
                self.meanPropulsiveVelocity = mpv
            }
            if let ppv = result.peakPropulsiveVelocity, ppv > self.peakPropulsiveVelocity {
                self.peakPropulsiveVelocity = ppv
            }
            self.peakVelocity = self.peakPropulsiveVelocity // legacy
        }
    }

    
    // MARK: - Public Helpers
    
    func getAccelerationSamples() -> [AccelerationSample] {
        return repDetector.getSamples()
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
            
            // âœ… Aggiorna metriche separate
            self.lastRepMPV = mpv
            self.lastRepPPV = ppv
            self.lastRepPeakVelocity = ppv  // Legacy
            self.lastRepInTarget = isInTarget
            
            self.calculateMeanVelocity()
            self.calculateVelocityLoss()
            
            // Reset velocitÃ  correnti per prossima rep
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
        
        let emoji = isInTarget ? "âœ…" : "âš ï¸"
        print("\(emoji) RIPETIZIONE #\(repCount + 1) completata")
        print("   â€¢ MPV: \(String(format: "%.3f", mpv)) m/s")
        print("   â€¢ PPV: \(String(format: "%.3f", ppv)) m/s")
        print("   â€¢ Target: \(isInTarget ? "IN TARGET" : "FUORI TARGET")")
        
        // ✅ STEP 3: Runtime pattern recognition dopo 3-5 reps
        let newRepCount = repCount + 1
        if newRepCount == 3 || newRepCount == 5 {
            print("🔍 Analizzando pattern dopo \(newRepCount) reps...")
            
            // Riconosci pattern dai samples attuali
            // recognizePatternIfPossible() già fa il match e aggiorna il pattern se necessario
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
    
    /// âœ… Usa MPV per calcolo media (standard VBT)
    private func calculateMeanVelocity() {
        guard !repMeanPropulsiveVelocities.isEmpty else { return }
        meanVelocity = repMeanPropulsiveVelocities.reduce(0, +) / Double(repMeanPropulsiveVelocities.count)
    }
    
    /// âœ… Usa MPV per velocity loss (standard VBT)
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
        
        print("ðŸ“Š Metriche finali:")
        print("   - Ripetizioni: \(repCount)")
        print("   - MPV Medio: \(String(format: "%.3f", meanVelocity)) m/s")
        print("   - Velocity Loss: \(String(format: "%.1f", velocityLoss))%")
        
        if let firstMPV = firstRepMPV, let lastMPV = repMeanPropulsiveVelocities.last {
            print("   - Prima rep MPV: \(String(format: "%.3f", firstMPV)) m/s")
            print("   - Ultima rep MPV: \(String(format: "%.3f", lastMPV)) m/s")
        }
        if let firstPPV = firstRepPPV, let lastPPV = repPeakPropulsiveVelocities.last {
            print("   - Prima rep PPV: \(String(format: "%.3f", firstPPV)) m/s")
            print("   - Ultima rep PPV: \(String(format: "%.3f", lastPPV)) m/s")
        }
    }
    
    private func resetMetrics() {
        velocity = 0.0
        currentVelocity = 0.0
        
        // âœ… Reset velocitÃ  separate
        meanPropulsiveVelocity = 0.0
        peakPropulsiveVelocity = 0.0
        
        // Legacy
        peakVelocity = 0.0
        meanVelocity = 0.0
        velocityLoss = 0.0
        repCount = 0
        
        isMoving = false
        phase = .idle
        inConcentricPhase = false
        concentricPeakReached = false
        lastRepTime = nil
        movementStartTime = nil
        
        // âœ… Reset storage separate
        repMeanPropulsiveVelocities.removeAll()
        repPeakPropulsiveVelocities.removeAll()
        firstRepMPV = nil
        firstRepPPV = nil
        
        // Legacy
        repPeakVelocities.removeAll()
        firstRepPeakVelocity = nil
        currentZone = .tooSlow
        
        // âœ… Reset ultima rep
        lastRepMPV = 0.0
        lastRepPPV = 0.0
        
        repDetector.reset()
    }
}
