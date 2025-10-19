//
//  LearnedPattern.swift
//  VBTTracker
//
//  Created by Lorenzo Franceschini on 18/10/25.
//


//
//  LearnedPattern.swift
//  VBTTracker
//
//  Pattern appreso da calibrazione ROM
//

import Foundation

/// Pattern appreso durante calibrazione ROM
struct LearnedPattern: Codable {
    let avgAmplitude: Double
    let avgConcentricDuration: Double
    let avgEccentricDuration: Double
    let avgPeakVelocity: Double
    let unrackThreshold: Double
    let restThreshold: Double
    let estimatedROM: Double
    let timestamp: Date  // ✅ Rimuovi il valore di default
    
    // ✅ AGGIUNGI init per fornire timestamp
    init(avgAmplitude: Double,
         avgConcentricDuration: Double,
         avgEccentricDuration: Double,
         avgPeakVelocity: Double,
         unrackThreshold: Double,
         restThreshold: Double,
         estimatedROM: Double,
         timestamp: Date = Date()) {  // Default solo nell'init
        self.avgAmplitude = avgAmplitude
        self.avgConcentricDuration = avgConcentricDuration
        self.avgEccentricDuration = avgEccentricDuration
        self.avgPeakVelocity = avgPeakVelocity
        self.unrackThreshold = unrackThreshold
        self.restThreshold = restThreshold
        self.estimatedROM = estimatedROM
        self.timestamp = timestamp
    }
    
    var dynamicMinAmplitude: Double {
        avgAmplitude * 0.5
    }
    
    var movementThreshold: Double {
        avgAmplitude * 0.15
    }
}
