//
//  AccelerationSample.swift
//  VBTTracker
//
//  Created by Lorenzo Franceschini on 17/10/25.
//


//
//  AccelerationSample.swift
//  VBTTracker
//
//  Created by Lorenzo Franceschini on 17/10/25.
//

import Foundation

/// Modello dati per un campione di accelerazione
struct AccelerationSample: Identifiable {
    let id = UUID()
    let timestamp: Date
    let accZ: Double // Accelerazione asse Z in g
    var isPeak: Bool = false    // Marker per picco (rep rilevata)
    var isValley: Bool = false  // Marker per valle
}