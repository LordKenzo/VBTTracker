//
//  RepDetectionManager.swift
//  VBTTracker
//
//  Created by Lorenzo Franceschini on 17/10/25.
//


//
//  RepDetectionManager.swift
//  VBTTracker
//
//  Manager per rilevamento automatico ripetizioni con algoritmo VBT
//

import Foundation
import Combine

class RepDetectionManager: ObservableObject {
    
    // MARK: - Published Properties
    @Published var isDetecting = false
    @Published var currentRepCount = 0
    @Published var currentVelocity: Double = 0.0
    @Published var currentPhase: MovementPhase = .idle
    
    // MARK: - Public Properties
    private(set) var detectedReps: [RepData] = []
    
    // MARK: - Private Properties
    private var velocity: Double = 0.0
    private var peakVelocity: Double = 0.0
    private var isMoving = false
    private var inConcentricPhase = false
    private var concentricPeakReached = false
    
    private var movementStartTime: Date?
    private var concentricStartTime: Date?
    private var eccentricStartTime: Date?
    private var lastRepTime: Date?
    
    private var velocityHistory: [Double] = []
    private var accelerationHistory: [Double] = []
    
    // Parametri algoritmo
    private let dt: Double = 0.02 // 20ms (50Hz)
    private let movementThreshold: Double = 3.5 // m/s²
    private let velocityNoiseThreshold: Double = 0.05 // m/s
    private let minTimeBetweenReps: Double = 0.5 // secondi
    private let maxRepDuration: Double = 3.0 // secondi
    
    // MARK: - Movement Phase
    enum MovementPhase {
        case idle           // Fermo
        case concentric     // Fase concentrica (salita)
        case eccentric      // Fase eccentrica (discesa)
    }
    
    // MARK: - Public Methods
    
    func startDetection() {
        guard !isDetecting else { return }
        
        isDetecting = true
        currentRepCount = 0
        detectedReps.removeAll()
        resetState()
        
        print("▶️ RepDetection: avviato")
    }
    
    func stopDetection() {
        isDetecting = false
        resetState()
        
        print("⏹️ RepDetection: fermato - \(currentRepCount) ripetizioni rilevate")
    }
    
    func reset() {
        stopDetection()
        currentRepCount = 0
        detectedReps.removeAll()
    }
    
    /// Processa un campione di dati dal sensore
    func processSample(acceleration: [Double], isCalibrated: Bool) {
        guard isDetecting else { return }
        
        // Estrai accelerazione verticale (asse Z)
        let accelZ = acceleration[2]
        
        // Gestione calibrazione
        let accelNoGravity = isCalibrated ? accelZ : (accelZ - 1.0)
        let accelMS2 = accelNoGravity * 9.81 // Converti in m/s²
        
        // Algoritmo rilevamento
        detectMovement(acceleration: accelMS2)
        
        // Aggiorna properties pubblicate
        DispatchQueue.main.async {
            self.currentVelocity = self.velocity
            self.currentPhase = self.phase
        }
    }
    
    // MARK: - Private Methods
    
    private var phase: MovementPhase {
        if !isMoving { return .idle }
        if inConcentricPhase { return .concentric }
        return .eccentric
    }
    
    private func detectMovement(acceleration accelMS2: Double) {
        // 1. Rileva inizio movimento
        let movementDetected = abs(accelMS2) > movementThreshold
        
        if movementDetected && !isMoving {
            startMovement(acceleration: accelMS2)
        }
        
        if isMoving {
            // 2. Integra velocità
            let previousVelocity = velocity
            velocity += accelMS2 * dt
            
            // 3. Gestione fasi e rilevamento ripetizione
            handlePhases(previousVelocity: previousVelocity, currentVelocity: velocity)
            
            // 4. Rileva fine movimento
            checkMovementEnd(acceleration: accelMS2)
            
            // 5. Salva storico
            velocityHistory.append(velocity)
            accelerationHistory.append(accelMS2)
        } else {
            // Fermo - mantieni velocità a zero
            velocity = 0.0
        }
    }
    
    private func startMovement(acceleration: Double) {
        isMoving = true
        velocity = 0.0
        peakVelocity = 0.0
        inConcentricPhase = false
        concentricPeakReached = false
        movementStartTime = Date()
        
        print("🟢 Movimento iniziato - accel: \(String(format: "%.2f", acceleration)) m/s²")
    }
    
    private func handlePhases(previousVelocity: Double, currentVelocity: Double) {
        // FASE CONCENTRICA (velocità positiva)
        if currentVelocity > 0.15 {
            if !inConcentricPhase {
                inConcentricPhase = true
                concentricPeakReached = false
                concentricStartTime = Date()
                print("⬆️ Fase concentrica iniziata")
            }
            
            // Aggiorna picco
            if currentVelocity > peakVelocity {
                peakVelocity = currentVelocity
            }
        }
        
        // RILEVAMENTO PICCO: velocità smette di crescere
        if inConcentricPhase && !concentricPeakReached {
            if previousVelocity > currentVelocity && peakVelocity > 0.2 {
                concentricPeakReached = true
                print("🔝 Picco: \(String(format: "%.3f", peakVelocity)) m/s")
            }
        }
        
        // FASE ECCENTRICA (velocità negativa)
        if currentVelocity < -0.15 {
            if !eccentricStartTime.isNil && inConcentricPhase {
                eccentricStartTime = Date()
            }
            
            // CONTA RIPETIZIONE se completato ciclo concentrico
            if concentricPeakReached && inConcentricPhase {
                tryCountRepetition()
            }
        }
    }
    
    private func tryCountRepetition() {
        // Validazione timing
        let timeSinceLastRep = lastRepTime?.timeIntervalSinceNow ?? -1.0
        let isValidTiming = abs(timeSinceLastRep) > minTimeBetweenReps || lastRepTime == nil
        
        guard isValidTiming else {
            print("⏭️ Rep ignorata (troppo veloce, \(String(format: "%.2f", abs(timeSinceLastRep)))s)")
            resetRepFlags()
            return
        }
        
        // Calcola durate
        guard let concStart = concentricStartTime,
              let eccStart = eccentricStartTime else {
            resetRepFlags()
            return
        }
        
        let concentricDuration = eccStart.timeIntervalSince(concStart)
        let eccentricDuration = Date().timeIntervalSince(eccStart)
        
        // Calcola velocità media propulsiva (solo valori positivi)
        let positiveVelocities = velocityHistory.filter { $0 > 0 }
        let meanVelocity = positiveVelocities.isEmpty ? 0 : 
            positiveVelocities.reduce(0, +) / Double(positiveVelocities.count)
        
        // Picco accelerazione
        let peakAccel = accelerationHistory.map { abs($0) }.max() ?? 0
        
        // Crea RepData
        let rep = RepData(
            repNumber: currentRepCount + 1,
            peakVelocity: peakVelocity,
            meanVelocity: meanVelocity,
            concentricDuration: concentricDuration,
            eccentricDuration: eccentricDuration,
            peakAcceleration: peakAccel,
            rom: nil,
            isValid: true
        )
        
        // Salva ripetizione
        detectedReps.append(rep)
        currentRepCount += 1
        lastRepTime = Date()
        
        print("✅ RIPETIZIONE #\(currentRepCount) completata")
        print("   Peak: \(String(format: "%.3f", peakVelocity)) m/s")
        print("   Mean: \(String(format: "%.3f", meanVelocity)) m/s")
        
        // Reset per prossima rep
        resetRepFlags()
        velocityHistory.removeAll()
        accelerationHistory.removeAll()
    }
    
    private func checkMovementEnd(acceleration: Double) {
        guard let startTime = movementStartTime else { return }
        
        let movementDuration = Date().timeIntervalSince(startTime)
        let isAlmostStopped = abs(velocity) < 0.12
        let lowAcceleration = abs(acceleration) < 2.0
        let minDurationPassed = movementDuration > 0.3
        
        // Stop normale
        if isAlmostStopped && lowAcceleration && minDurationPassed {
            print("🔴 Fine movimento - Durata: \(String(format: "%.2f", movementDuration))s")
            stopMovement()
        }
        
        // Safety: force stop dopo maxRepDuration
        if movementDuration > maxRepDuration {
            print("⚠️ Force stop - movimento troppo lungo")
            stopMovement()
        }
    }
    
    private func stopMovement() {
        isMoving = false
        velocity = 0.0
        resetRepFlags()
    }
    
    private func resetRepFlags() {
        inConcentricPhase = false
        concentricPeakReached = false
        concentricStartTime = nil
        eccentricStartTime = nil
    }
    
    private func resetState() {
        velocity = 0.0
        peakVelocity = 0.0
        isMoving = false
        inConcentricPhase = false
        concentricPeakReached = false
        movementStartTime = nil
        concentricStartTime = nil
        eccentricStartTime = nil
        lastRepTime = nil
        velocityHistory.removeAll()
        accelerationHistory.removeAll()
    }
}

// MARK: - Optional Extension

extension Optional {
    var isNil: Bool {
        return self == nil
    }
}