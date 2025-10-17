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
    
    var targetZone: TrainingZone = .strength
    
    // MARK: - Private Properties
    
    private var velocity: Double = 0.0
    private var isMoving = false
    private var phase: MovementPhase = .idle
    
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
        
        // 1. Get vertical acceleration (Z axis)
        let accelZ = acceleration[2]
        
        let accelNoGravity: Double
        if isCalibrated {
            accelNoGravity = accelZ
        } else {
            accelNoGravity = accelZ - 1.0
        }
        
        let accelMS2 = accelNoGravity * 9.81
        
        // 2. Detect movement start
        let minAccel = SettingsManager.shared.repMinAcceleration
        let movementDetected = abs(accelMS2) > minAccel
        
        if movementDetected && !isMoving {
            // 🟢 START MOVEMENT
            isMoving = true
            velocity = 0.0
            peakVelocity = 0.0
            inConcentricPhase = false
            concentricPeakReached = false
            movementStartTime = Date()
        }
        
        if isMoving {
            // 3. Integrate velocity
            let previousVelocity = velocity
            velocity += accelMS2 * dt
            
            // 4. Phase detection and rep counting
            
            let minVel = SettingsManager.shared.repMinVelocity
            if velocity > minVel {
                if !inConcentricPhase {
                    inConcentricPhase = true
                    concentricPeakReached = false
                }
                
                phase = .concentric
                
                // Update peak
                if velocity > peakVelocity {
                    peakVelocity = velocity
                }
            }
            
            // Peak detection: velocity starts decreasing after concentric phase
            if inConcentricPhase && !concentricPeakReached {
                let minPeak = SettingsManager.shared.repMinPeakVelocity
                if previousVelocity > velocity && peakVelocity > minPeak {
                    concentricPeakReached = true
                    
                    // Update current zone based on peak velocity
                    DispatchQueue.main.async {
                        self.currentZone = SettingsManager.shared.getTrainingZone(for: self.peakVelocity)
                    }
                }
            }
            
            // ECCENTRIC PHASE (downward, velocity < -0.15 m/s)
            if velocity < -0.15 {
                phase = .eccentric
                
                // ⭐ COUNT REP: with anti-double-counting
                if concentricPeakReached && inConcentricPhase {
                    let timeSinceLastRep = lastRepTime?.timeIntervalSinceNow ?? -1.0
                    let isValidTiming = abs(timeSinceLastRep) > 0.3 || lastRepTime == nil  // Da 0.5s a 0.3s
                    
                    if isValidTiming {
                        countRep(peakVelocity: peakVelocity)
                        lastRepTime = Date()
                        
                        // Reset flags for next rep
                        inConcentricPhase = false
                        concentricPeakReached = false
                    } else {
                        // Reset flags even when ignoring (avoid infinite loop)
                        inConcentricPhase = false
                        concentricPeakReached = false
                    }
                }
            }
            
            // 5. Detect END of movement
            let movementDuration = Date().timeIntervalSince(movementStartTime ?? Date())
            let isAlmostStopped = abs(velocity) < 0.12
            let lowAcceleration = abs(accelMS2) < 2.0
            let minDurationPassed = movementDuration > 0.3
            
            if isAlmostStopped && lowAcceleration && minDurationPassed {
                // 🔴 END MOVEMENT
                isMoving = false
                phase = .idle
                velocity = 0.0
                inConcentricPhase = false
                concentricPeakReached = false
            }
            
            // Safety: force stop after 3 seconds
            if movementDuration > 3.0 {
                isMoving = false
                phase = .idle
                velocity = 0.0
                inConcentricPhase = false
                concentricPeakReached = false
            }
            
            // Update current velocity for UI
            DispatchQueue.main.async {
                self.currentVelocity = self.velocity
            }
            
        } else {
            // IDLE
            velocity = 0.0
            phase = .idle
            
            DispatchQueue.main.async {
                self.currentVelocity = 0.0
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func countRep(peakVelocity: Double) {
        repPeakVelocities.append(peakVelocity)
        
        if firstRepPeakVelocity == nil {
            firstRepPeakVelocity = peakVelocity
        }
        
        DispatchQueue.main.async {
            self.repCount += 1
            self.calculateMeanVelocity()
            self.calculateVelocityLoss()
        }
        
        print("✅ RIPETIZIONE #\(repCount + 1) completata - Peak: \(String(format: "%.3f", peakVelocity)) m/s")
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
    }
}
