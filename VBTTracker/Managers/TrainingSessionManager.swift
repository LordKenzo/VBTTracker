//
//  TrainingSessionManager.swift
//  VBTTracker
//
//  Created by Lorenzo Franceschini on 17/10/25.
//


//
//  TrainingSessionManager.swift
//  VBTTracker
//
//  Gestisce la logica di una sessione di allenamento VBT
//

import Foundation
import Combine

class TrainingSessionManager: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var isRecording = false
    @Published var currentVelocity: Double = 0.0
    @Published var peakVelocity: Double = 0.0
    @Published var meanVelocity: Double = 0.0
    @Published var velocityLoss: Double = 0.0
    
    @Published var repCount: Int = 0
    @Published var currentZone: TrainingZone = .tooSlow
    
    @Published var lastRepInTarget: Bool = true
    @Published var lastRepPeakVelocity: Double = 0.0
    
    var targetZone: TrainingZone = .strength
    
    // MARK: - Private Properties
    
    private var integratedVelocity: Double = 0.0
    private var isMoving = false
    private var phase: MovementPhase = .idle

    let repDetector = VBTRepDetector()
    private let voiceFeedback = VoiceFeedbackManager()


    private var inConcentricPhase = false
    private var concentricPeakReached = false
    private var lastRepTime: Date?
    private var movementStartTime: Date?
    
    // Rep data storage
    var repPeakVelocities: [Double] = []
    var firstRepPeakVelocity: Double?
    
    // Constants
    private let defaultSampleInterval: Double = 0.02 // 20ms sampling
    private let maxReasonableVelocity: Double = 5.0 // m/s guardrail

    private var lastSampleTime: Date?
    // private let movementThreshold: Double = 2.5 // m/s²
    
    enum MovementPhase {
        case idle
        case concentric
        case eccentric
    }
    
    // MARK: - Public Methods
    
    func startRecording() {
        isRecording = true
        resetMetrics()

        lastSampleTime = nil

        // ✅ NUOVO: Logga se pattern appreso è disponibile
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
                case .descending:  // ✅ Aggiornato da .eccentric
                    if self.repCount == 0 && !self.repDetector.hasAnnouncedUnrack {
                        self.voiceFeedback.announceBarUnrack()
                    }
                    /*else {
                        self.voiceFeedback.announceEccentric()
                    }*/
                    
                case .ascending:  // ✅ Aggiornato da .concentric
                    //self.voiceFeedback.announceConcentric()
                    break
                case .idle, .completed:  // ✅ Aggiornato da .returnToRack
                    break
                }
            }
        }
        
        voiceFeedback.announceWorkoutStart()
        print("▶️ Sessione allenamento iniziata - Target: \(targetZone.rawValue)")
    }

    func stopRecording() {
        isRecording = false
        calculateFinalMetrics()

        // Annuncia fine
        voiceFeedback.announceWorkoutEnd(reps: repCount)

        print("⏹️ Sessione terminata - Reps: \(repCount), Mean: \(String(format: "%.3f", meanVelocity)) m/s")

        // Reset integratore per evitare drift tra sessioni
        integratedVelocity = 0.0
        currentVelocity = 0.0
        lastSampleTime = nil
    }

    
    func processSensorData(
        acceleration: [Double],
        angularVelocity: [Double],
        angles: [Double],
        isCalibrated: Bool
    ) {
        guard isRecording else { return }
        
        // 1. Ottieni accelerazione Z (verticale)
        let accelZ = acceleration[2]
        
        let accelNoGravity: Double
        if isCalibrated {
            accelNoGravity = accelZ
        } else {
            accelNoGravity = accelZ - 1.0
        }

        // 2. Passa modalità velocità al detector
        repDetector.velocityMode = SettingsManager.shared.velocityMeasurementMode

        // 3. Rileva rep
        let timestamp = Date()
        let result = repDetector.addSample(
            accZ: accelNoGravity,
            timestamp: timestamp
        )

        // 4. Integra accelerazione filtrata per ottenere la velocità in m/s
        let filteredAcceleration = result.currentValue

        let deltaTime: Double
        if let lastTime = lastSampleTime {
            let measuredDt = timestamp.timeIntervalSince(lastTime)
            deltaTime = min(max(measuredDt, 0.005), 0.05)
        } else {
            deltaTime = defaultSampleInterval
        }
        lastSampleTime = timestamp

        var linearAcceleration = filteredAcceleration * 9.81

        // Piccolo filtro anti-rumore: ignora accelerazioni molto piccole
        if abs(linearAcceleration) < 0.15 {
            linearAcceleration = 0.0
        }

        integratedVelocity += linearAcceleration * deltaTime

        // Smorza lentamente per ridurre drift quando il sensore è fermo
        if abs(linearAcceleration) < 0.2 {
            integratedVelocity *= 0.98
            if abs(integratedVelocity) < 0.02 {
                integratedVelocity = 0.0
            }
        }

        integratedVelocity = max(-maxReasonableVelocity, min(maxReasonableVelocity, integratedVelocity))
        let velocityMagnitude = abs(integratedVelocity)

        // 5. Se rilevata rep, aggiorna contatori
        if result.repDetected, let peakVel = result.peakVelocity {
            countRep(peakVelocity: peakVel)
        }

        let currentVelocityMagnitude = velocityMagnitude

        // 6. AGGIORNA ZONA CORRENTE (basata su velocità corrente o picco)
        DispatchQueue.main.async {
            // Usa currentVelocity se disponibile, altrimenti peakVelocity
            let velocityForZone: Double

            if currentVelocityMagnitude > 0.1 {
                velocityForZone = currentVelocityMagnitude
            } else {
                velocityForZone = self.peakVelocity
            }

            if velocityForZone > 0.1 {
                self.currentZone = SettingsManager.shared.getTrainingZone(for: velocityForZone)
            }

            // Aggiorna velocità corrente con l'integrata (m/s)
            self.currentVelocity = currentVelocityMagnitude

            // Aggiorna peakVelocity durante la rep
            if let peakVel = result.peakVelocity, peakVel > self.peakVelocity {
                self.peakVelocity = peakVel
            }
        }
    }
    
    // MARK: - Public Methods
       
       /// Ottieni campioni accelerazione per il grafico
       func getAccelerationSamples() -> [AccelerationSample] {
           return repDetector.getSamples()
       }
    
    // MARK: - Private Methods
    
    private func handlePhaseChange(_ phase: VBTRepDetector.Phase) {
        DispatchQueue.main.async {
            switch phase {
            case .descending:
                if self.repCount == 0 && !self.repDetector.hasAnnouncedUnrack {
                    self.voiceFeedback.announceBarUnrack()
                }
                /*else {
                    self.voiceFeedback.announceEccentric()
                }*/
                
            case .ascending:
                break;
                //self.voiceFeedback.announceConcentric()
                
            case .idle, .completed:
                break
            }
        }
    }

    private func countRep(peakVelocity: Double) {
        repPeakVelocities.append(peakVelocity)
        
        if firstRepPeakVelocity == nil {
            firstRepPeakVelocity = peakVelocity
        }
        
        let isInTarget = checkIfInTarget(velocity: peakVelocity)
        
        DispatchQueue.main.async {
            self.repCount += 1
            self.lastRepPeakVelocity = peakVelocity
            self.lastRepInTarget = isInTarget
            self.calculateMeanVelocity()
            self.calculateVelocityLoss()

            // Annuncia rep completata
            self.voiceFeedback.announceRep(number: self.repCount, isInTarget: isInTarget)

            if let referenceVelocity = self.repDetector.learnedPattern?.avgPeakVelocity {
                let meanString = String(format: "%.3f", self.meanVelocity)
                let referenceString = String(format: "%.3f", referenceVelocity)
                print("🔍 Debug: Mean velocity rep #\(self.repCount): \(meanString) m/s (ref ≈ \(referenceString) m/s)")
            }

            // Check velocity loss
            if SettingsManager.shared.stopOnVelocityLoss &&
               self.velocityLoss >= SettingsManager.shared.velocityLossThreshold {
                self.voiceFeedback.announceVelocityLoss(percentage: self.velocityLoss)
            }
        }
        
        let emoji = isInTarget ? "✅" : "⚠️"
        print("\(emoji) RIPETIZIONE #\(repCount + 1) completata - Peak: \(String(format: "%.3f", peakVelocity)) m/s - \(isInTarget ? "IN TARGET" : "FUORI TARGET")")
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
    
    private func calculateMeanVelocity() {
        guard !repPeakVelocities.isEmpty else { return }
        meanVelocity = repPeakVelocities.reduce(0, +) / Double(repPeakVelocities.count)
    }
    
    private func calculateVelocityLoss() {
        guard let firstPeak = firstRepPeakVelocity,
              let lastPeak = repPeakVelocities.last,
              firstPeak > 0 else {
            velocityLoss = 0.0
            return
        }
        
        let loss = ((firstPeak - lastPeak) / firstPeak) * 100.0
        velocityLoss = max(0, loss) // Ensure non-negative
    }
    
    private func calculateFinalMetrics() {
        calculateMeanVelocity()
        calculateVelocityLoss()
        
        print("📊 Metriche finali:")
        print("   - Ripetizioni: \(repCount)")
        print("   - Velocità Media: \(String(format: "%.3f", meanVelocity)) m/s")
        print("   - Velocity Loss: \(String(format: "%.1f", velocityLoss))%")
        print("   - Prima rep: \(String(format: "%.3f", firstRepPeakVelocity ?? 0)) m/s")
        print("   - Ultima rep: \(String(format: "%.3f", repPeakVelocities.last ?? 0)) m/s")
    }
    
    private func resetMetrics() {
        integratedVelocity = 0.0
        currentVelocity = 0.0
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
        
        repPeakVelocities.removeAll()
        firstRepPeakVelocity = nil
        currentZone = .tooSlow

        repDetector.reset()
        lastSampleTime = nil
    }
}
