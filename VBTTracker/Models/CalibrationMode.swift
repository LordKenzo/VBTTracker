//
//  CalibrationMode.swift
//  VBTTracker
//
//  Semplificato: rimosso supporto alla calibrazione manuale
//

import Foundation
import SwiftUI

// MARK: - Calibration Mode (solo automatica)

enum CalibrationMode: String, Codable {
    case automatic

    var displayName: String { "Automatica" }
    var description: String {
        "2 ripetizioni complete\n• Veloce (30 sec)\n• Senza assistenza"
    }
    var icon: String { "wand.and.stars" }
    var color: Color { .blue }
}

// MARK: - Automatic Calibration State (invariato)

enum AutomaticCalibrationState: Equatable {
    case idle
    case waitingForFirstRep
    case detectingReps
    case analyzing
    case waitingForLoad
    case completed
    case failed(String)
}
