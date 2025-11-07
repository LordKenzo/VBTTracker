//
//  DistanceSample.swift
//  VBTTracker
//
//  Modello dati per un campione di distanza (Arduino laser sensor)
//

import Foundation

/// Modello dati per un campione di distanza
struct DistanceSample: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let distance: Double      // Distanza in millimetri
    let velocity: Double      // Velocità in mm/s
    var isRepStart: Bool      // Marker per inizio rep (inizio fase eccentrica)
    var isRepEnd: Bool        // Marker per fine rep (fine fase concentrica)

    // MARK: - Initialization

    init(timestamp: Date, distance: Double, velocity: Double = 0.0, isRepStart: Bool = false, isRepEnd: Bool = false) {
        self.id = UUID()
        self.timestamp = timestamp
        self.distance = distance
        self.velocity = velocity
        self.isRepStart = isRepStart
        self.isRepEnd = isRepEnd
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id
        case timestamp
        case distance
        case velocity
        case isRepStart
        case isRepEnd
    }
}
