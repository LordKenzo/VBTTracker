//
//  TrainingSessionManager.swift
//  VBTTracker
//
//  ✅ AGGIORNATO: Gestisce MPV e PPV separatamente secondo standard VBT
//

import Foundation
import Combine

class TrainingSessionManager: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var isRecording = false
    @Published var currentVelocity: Double = 0.0
    
    // ✅ NUOVO: Velocità separate secondo standard VBT
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
    
    // ✅ NUOVO: Tracking separato MPV ultima rep
    @Published var lastRepMPV: Double = 0.0
    @Published var lastRepPPV: Double = 0.0
    
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
    
    // ✅ NUOVO: Storage separato per MPV e PPV
    var repMeanPropulsiveVelocities: [Double] = []  // MPV per ogni rep
    var repPeakPropulsiveVelocities: [Double] = []  // PPV per ogni rep
    
    // Legacy storage (mantiene PPV per retrocompatibilità)
    var repPeakVelocities: [Double] = []
    var firstRepPeakVelocity: Double?
    
    // ✅ NUOVO: Prima rep MPV per calcolo velocity loss
    var firstRepMPV: Double?
    var firstRepPPV: Double?
    
    // Constants
    private let dt: Double = 0.02 // 20ms sampling
    
    enum MovementPhase {
        case idle
        case concentric
        case eccentric
    }
    
    // MARK: - Public Methods
    
    func startRecording() {
        isRecording = true
        resetMetrics()
        
        // ✅ Logga pattern appreso se disponibile
        if let pattern = repDetector.learnedPattern {
            print("🎓 Pattern appreso caricato:")
            print("   • ROM: \(String(format: "%.0f", pattern.estimatedROM * 100))cm")
            print("   • Soglia min: \(String(format: "%.2f", pattern.dynamicMinAmplitude))g")
            print("   • Velocità media: \(String(format: "%.2f", pattern.avgPeakVelocity)) m/s")
        } else {
            print("⚠️ Nessun pattern appreso - Usando soglie adaptive")
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
        print("▶️ Sessione allenamento iniziata - Target: \(targetZone.rawValue)")
        print("📊 Modalità velocità: \(SettingsManager.shared.velocityMeasurementMode == .concentricOnly ? "Concentrica (Standard VBT)" : "Full ROM")")
    }

    func stopRecording() {
        isRecording = false
        calculateFinalMetrics()
        
        // Annuncia fine
        voiceFeedback.announceWorkoutEnd(reps: repCount)
        
        print("⏹️ Sessione terminata - Reps: \(repCount)")
        print("   • MPV medio: \(String(format: "%.3f", meanVelocity)) m/s")
        print("   • Velocity Loss: \(String(format: "%.1f", velocityLoss))%")
    }

    func processSensorData(
        acceleration: [Double],
        angularVelocity: [Double],
        angles: [Double],
        isCalibrated: Bool
    ) {
        guard isRecording else { return }
        
        // 1. Ottieni accelerazione Z (verticale)
        let accX = acceleration[0]
        let accY = acceleration[1]
        let accZ = acceleration[2]
        
        let accZNoGravity = isCalibrated ? accZ : (accZ - 1.0)
        
        // 2. Passa modalità velocità al detector
        repDetector.velocityMode = SettingsManager.shared.velocityMeasurementMode
        
        // 3. Rileva rep
        let result = repDetector.addMultiAxisSample(
            accX: accX,
            accY: accY,
            accZ: accZNoGravity,
            gyro: angularVelocity,
            timestamp: Date()
        )
        
        // 4. ✅ NUOVO: Elabora risultato con MPV e PPV
        if result.repDetected {
            // Estrai velocità (con fallback a legacy)
            let mpv = result.meanPropulsiveVelocity ?? result.peakVelocity ?? 0.0
            let ppv = result.peakPropulsiveVelocity ?? result.peakVelocity ?? 0.0
            
            countRep(mpv: mpv, ppv: ppv)
        }
        
        // 5. AGGIORNA ZONA CORRENTE
        DispatchQueue.main.async {
            // Usa MPV per determinare zona (standard VBT)
            let velocityForZone = self.meanPropulsiveVelocity > 0.1 ?
                self.meanPropulsiveVelocity : self.peakPropulsiveVelocity
            
            if velocityForZone > 0.1 {
                self.currentZone = SettingsManager.shared.getTrainingZone(for: velocityForZone)
            }
            
            // Aggiorna currentVelocity con valore smoothed
            self.currentVelocity = abs(result.currentValue) * 9.81 // g → m/s²
            
            // ✅ Aggiorna MPV e PPV durante la rep
            if let mpv = result.meanPropulsiveVelocity, mpv > self.meanPropulsiveVelocity {
                self.meanPropulsiveVelocity = mpv
            }
            
            if let ppv = result.peakPropulsiveVelocity, ppv > self.peakPropulsiveVelocity {
                self.peakPropulsiveVelocity = ppv
            }
            
            // Legacy: usa PPV come peakVelocity
            self.peakVelocity = self.peakPropulsiveVelocity
        }
    }
    
    // MARK: - Public Methods
    
    /// Ottieni campioni accelerazione per il grafico
    func getAccelerationSamples() -> [AccelerationSample] {
        return repDetector.getSamples()
    }
    
    // MARK: - Private Methods
    
    /// ✅ AGGIORNATO: Conta rep con MPV e PPV separate
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
            
            // ✅ Aggiorna metriche separate
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
        
        let emoji = isInTarget ? "✅" : "⚠️"
        print("\(emoji) RIPETIZIONE #\(repCount + 1) completata")
        print("   • MPV: \(String(format: "%.3f", mpv)) m/s")
        print("   • PPV: \(String(format: "%.3f", ppv)) m/s")
        print("   • Target: \(isInTarget ? "IN TARGET" : "FUORI TARGET")")
    }
    
    // Helper method
    private func checkIfInTarget(velocity: Double) -> Bool {
        let targetRange = getRangeForTargetZone()
        return targetRange.contains(velocity)
    }

    private func getRangeForTargetZone() -> ClosedRange<Double> {
        let ranges = SettingsManager.shared.velocityRanges
        switch targetZone {
        case .maxStrength:
            return ranges.maxStrength
        case .strength:
            return ranges.strength
        case .strengthSpeed:
            return ranges.strengthSpeed
        case .speed:
            return ranges.speed
        case .maxSpeed:
            return ranges.maxSpeed
        case .tooSlow:
            return 0.0...0.15
        }
    }
    
    /// ✅ AGGIORNATO: Usa MPV per calcolo media (standard VBT)
    private func calculateMeanVelocity() {
        guard !repMeanPropulsiveVelocities.isEmpty else { return }
        meanVelocity = repMeanPropulsiveVelocities.reduce(0, +) / Double(repMeanPropulsiveVelocities.count)
    }
    
    /// ✅ AGGIORNATO: Usa MPV per velocity loss (standard VBT)
    private func calculateVelocityLoss() {
        guard let firstMPV = firstRepMPV,
              let lastMPV = repMeanPropulsiveVelocities.last,
              firstMPV > 0 else {
            velocityLoss = 0.0
            return
        }
        
        let loss = ((firstMPV - lastMPV) / firstMPV) * 100.0
        velocityLoss = max(0, loss) // Ensure non-negative
    }
    
    private func calculateFinalMetrics() {
        calculateMeanVelocity()
        calculateVelocityLoss()
        
        print("📊 Metriche finali:")
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
        
        // ✅ Reset velocità separate
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
        
        // ✅ Reset storage separate
        repMeanPropulsiveVelocities.removeAll()
        repPeakPropulsiveVelocities.removeAll()
        firstRepMPV = nil
        firstRepPPV = nil
        
        // Legacy
        repPeakVelocities.removeAll()
        firstRepPeakVelocity = nil
        currentZone = .tooSlow
        
        // ✅ Reset ultima rep
        lastRepMPV = 0.0
        lastRepPPV = 0.0
        
        repDetector.reset()
    }
}
