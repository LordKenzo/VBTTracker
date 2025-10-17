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
    
    private var velocity: Double = 0.0
    private var isMoving = false
    private var phase: MovementPhase = .idle
    
    private let repDetector = VBTRepDetector()

    private var inConcentricPhase = false
    private var concentricPeakReached = false
    private var lastRepTime: Date?
    private var movementStartTime: Date?
    
    // Rep data storage
    private var repPeakVelocities: [Double] = []
    private var firstRepPeakVelocity: Double?
    
    // Constants
    private let dt: Double = 0.02 // 20ms sampling
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
        print("▶️ Sessione allenamento iniziata - Target: \(targetZone.rawValue)")
    }
    
    func stopRecording() {
        isRecording = false
        calculateFinalMetrics()
        print("⏹️ Sessione terminata - Reps: \(repCount), Mean: \(String(format: "%.3f", meanVelocity)) m/s")
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
        let result = repDetector.addSample(
            accZ: accelNoGravity,
            timestamp: Date()
        )
        
        // 4. Se rilevata rep, aggiorna contatori
        if result.repDetected, let peakVel = result.peakVelocity {
            countRep(peakVelocity: peakVel)
        }
        
        // 5. ⭐ AGGIORNA ZONA CORRENTE (basata su velocità corrente o picco)
        DispatchQueue.main.async {
            // Usa currentVelocity se disponibile, altrimenti peakVelocity
            let velocityForZone = self.currentVelocity > 0.1 ? self.currentVelocity : self.peakVelocity
            
            if velocityForZone > 0.1 {
                self.currentZone = SettingsManager.shared.getTrainingZone(for: velocityForZone)
            }
            
            // Aggiorna anche currentVelocity con valore smoothed
            self.currentVelocity = abs(result.currentValue) * 9.81 // g → m/s²
            
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
        velocity = 0.0
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
    }
}
