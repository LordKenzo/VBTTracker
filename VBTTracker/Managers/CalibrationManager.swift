//
//  CalibrationManager.swift
//  VBTTracker
//
//  Created by Lorenzo Franceschini on 16/10/25.
//


//
//  CalibrationManager.swift
//  VBTTracker
//
//  Gestisce il processo di calibrazione del sensore
//

import Foundation
import Combine

class CalibrationManager: ObservableObject {
    
    @Published var isCalibrating = false
    @Published var calibrationProgress: Double = 0.0
    @Published var statusMessage = "Pronto per calibrazione"
    @Published var currentCalibration: CalibrationData?
    
    private var samples: [(acceleration: [Double], angularVelocity: [Double], angles: [Double])] = []
    private var startTime: Date?
    
    private let requiredSamples = 100
    private let calibrationDuration: TimeInterval = 3.0
    
    // MARK: - Calibration Process
    
    func startCalibration() {
        guard !isCalibrating else { return }
        
        samples.removeAll()
        startTime = Date()
        isCalibrating = true
        calibrationProgress = 0.0
        statusMessage = "Calibrazione in corso... Tieni il sensore FERMO!"
        
        print("🎯 Calibrazione iniziata - Target: \(requiredSamples) campioni in \(calibrationDuration)s")
    }
    
    func addSample(acceleration: [Double], angularVelocity: [Double], angles: [Double]) {
        guard isCalibrating else { return }
        
        samples.append((acceleration, angularVelocity, angles))
        
        // Aggiorna progress
        let progress = min(Double(samples.count) / Double(requiredSamples), 1.0)
        
        DispatchQueue.main.async {
            self.calibrationProgress = progress
        }
        
        // Check completamento
        if samples.count >= requiredSamples {
            completeCalibration()
        }
    }
    
    private func completeCalibration() {
        guard let start = startTime else { return }
        
        let duration = Date().timeIntervalSince(start)
        
        // Calcola offset medi
        let avgAcceleration = calculateAverage(samples.map { $0.acceleration })
        let avgAngularVelocity = calculateAverage(samples.map { $0.angularVelocity })
        let avgAngles = calculateAverage(samples.map { $0.angles })
        
        // ⭐ USA FACTORY METHOD con auto-detect asse verticale
        let calibration = CalibrationData.create(
            timestamp: Date(),
            accelerationOffset: avgAcceleration,
            angularVelocityOffset: avgAngularVelocity,
            anglesOffset: avgAngles,
            sampleCount: samples.count,
            duration: duration
        )
        
        DispatchQueue.main.async {
            self.currentCalibration = calibration
            self.isCalibrating = false
            self.calibrationProgress = 1.0
            self.statusMessage = "✅ Calibrazione completata!"
            
            print("✅ Calibrazione completata:")
            print("   Campioni: \(calibration.sampleCount)")
            print("   Durata: \(String(format: "%.1f", calibration.duration))s")
            print("   Accel offset: [\(calibration.accelerationOffset.map { String(format: "%.3f", $0) }.joined(separator: ", "))]")
        }
    }
    
    func cancelCalibration() {
        isCalibrating = false
        samples.removeAll()
        calibrationProgress = 0.0
        statusMessage = "Calibrazione annullata"
        print("⚠️ Calibrazione annullata")
    }
    
    func resetCalibration() {
        currentCalibration = nil
        statusMessage = "Calibrazione resettata"
        print("🔄 Calibrazione resettata")
    }
    
    // MARK: - Helpers
    
    private func calculateAverage(_ arrays: [[Double]]) -> [Double] {
        guard !arrays.isEmpty else { return [0, 0, 0] }
        
        let count = Double(arrays.count)
        let sums = arrays.reduce([0.0, 0.0, 0.0]) { result, array in
            return zip(result, array).map { $0 + $1 }
        }
        
        return sums.map { $0 / count }
    }
}
