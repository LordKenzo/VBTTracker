//
//  AccelerationSample.swift
//  VBTTracker
//
//  Modello dati per un campione di accelerazione
//

import Foundation

/// Modello dati per un campione di accelerazione
struct AccelerationSample: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let accZ: Double // Accelerazione asse Z in g
    var isPeak: Bool    // Marker per picco (rep rilevata)
    var isValley: Bool  // Marker per valle
    
    // MARK: - Initialization
    
    init(timestamp: Date, accZ: Double, isPeak: Bool = false, isValley: Bool = false) {
        self.id = UUID()
        self.timestamp = timestamp
        self.accZ = accZ
        self.isPeak = isPeak
        self.isValley = isValley
    }
    
    // MARK: - Codable
    
    enum CodingKeys: String, CodingKey {
        case id
        case timestamp
        case accZ
        case isPeak
        case isValley
    }
}
