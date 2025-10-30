//
//  CalibrationData.swift
//  VBTTracker
//
//  FIX: La calibrazione deve rimuovere SOLO gli offset,
//       NON la gravità (che serve per rilevare movimento verticale)
//

import Foundation

struct CalibrationData: Codable {
    let timestamp: Date
    
    // Offset calcolati (media su N campioni)
    let accelerationOffset: [Double]      // [X, Y, Z] in g
    let angularVelocityOffset: [Double]   // [X, Y, Z] in °/s
    let anglesOffset: [Double]            // [Roll, Pitch, Yaw] in °
    
    // Statistiche calibrazione
    let sampleCount: Int
    let duration: TimeInterval
    
    // ⭐ NUOVO: Memorizza quale asse è verticale
    let verticalAxis: Int  // 0=X, 1=Y, 2=Z
    let gravityDirection: Double  // +1 o -1
    
    var isValid: Bool {
        sampleCount >= 50 && duration >= 2.0
    }
    
    /// Applica calibrazione ai dati raw del sensore
    /// IMPORTANTE: Mantiene 1g sull'asse verticale per detection movimento
    func applyCalibration(
        acceleration: [Double],
        angularVelocity: [Double],
        angles: [Double]
    ) -> (acceleration: [Double], angularVelocity: [Double], angles: [Double]) {
        
        // 1. Sottrai offset da tutti gli assi
        var calibratedAcceleration = zip(acceleration, accelerationOffset).map { $0 - $1 }
        
        // 2. ⭐ RIPRISTINA gravità sull'asse verticale
        calibratedAcceleration[verticalAxis] += gravityDirection * 1.0
        
        return (
            acceleration: calibratedAcceleration,
            angularVelocity: zip(angularVelocity, angularVelocityOffset).map { $0 - $1 },
            angles: zip(angles, anglesOffset).map { $0 - $1 }
        )
    }
}

// MARK: - Factory Helper

extension CalibrationData {
    
    /// Crea CalibrationData con auto-detect asse verticale
    static func create(
        timestamp: Date,
        accelerationOffset: [Double],
        angularVelocityOffset: [Double],
        anglesOffset: [Double],
        sampleCount: Int,
        duration: TimeInterval
    ) -> CalibrationData {
        
        // Trova asse verticale (quello con valore assoluto più alto)
        let absValues = accelerationOffset.map { abs($0) }
        let maxValue = absValues.max() ?? 0
        let verticalAxis = absValues.firstIndex(of: maxValue) ?? 2  // Default Z
        
        // Determina direzione gravità (+1 o -1)
        let gravityDirection = accelerationOffset[verticalAxis] > 0 ? 1.0 : -1.0
        
        print("📐 Asse verticale rilevato: \(["X","Y","Z"][verticalAxis]) " +
              "(\(gravityDirection > 0 ? "+" : "-")\(String(format: "%.3f", abs(accelerationOffset[verticalAxis])))g)")
        
        return CalibrationData(
            timestamp: timestamp,
            accelerationOffset: accelerationOffset,
            angularVelocityOffset: angularVelocityOffset,
            anglesOffset: anglesOffset,
            sampleCount: sampleCount,
            duration: duration,
            verticalAxis: verticalAxis,
            gravityDirection: gravityDirection
        )
    }
}
