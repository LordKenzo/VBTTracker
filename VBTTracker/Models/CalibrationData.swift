//
//  CalibrationData.swift
//  VBTTracker
//
//  Created by Lorenzo Franceschini on 16/10/25.
//


//
//  CalibrationData.swift
//  VBTTracker
//
//  Modello dati per calibrazione sensore
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
    
    var isValid: Bool {
        sampleCount >= 50 && duration >= 2.0
    }
    
    /// Applica calibrazione ai dati raw del sensore
    func applyCalibration(
        acceleration: [Double],
        angularVelocity: [Double],
        angles: [Double]
    ) -> (acceleration: [Double], angularVelocity: [Double], angles: [Double]) {
        
        return (
            acceleration: zip(acceleration, accelerationOffset).map { $0 - $1 },
            angularVelocity: zip(angularVelocity, angularVelocityOffset).map { $0 - $1 },
            angles: zip(angles, anglesOffset).map { $0 - $1 }
        )
    }
}