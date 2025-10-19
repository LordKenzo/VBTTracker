//
//  CalibrationMode.swift
//  VBTTracker
//
//  Enums e strutture per sistema calibrazione dual-mode
//

import Foundation
import SwiftUI

// MARK: - Calibration Mode

enum CalibrationMode: String, Codable {
    case automatic  // 2 rep complete automatiche
    case manual     // 5 step guidati con assistente
    
    var displayName: String {
        switch self {
        case .automatic: return "Automatica"
        case .manual: return "Manuale"
        }
    }
    
    var description: String {
        switch self {
        case .automatic:
            return "2 ripetizioni complete\n• Veloce (30 sec)\n• Senza assistenza"
        case .manual:
            return "5 step guidati\n• Precisa (2 min)\n• Richiede assistente"
        }
    }
    
    var icon: String {
        switch self {
        case .automatic: return "wand.and.stars"
        case .manual: return "hand.raised.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .automatic: return .blue
        case .manual: return .purple
        }
    }
}

// MARK: - Automatic Calibration State

enum AutomaticCalibrationState: Equatable {
    case idle
    case waitingForFirstRep
    case detectingReps
    case analyzing
    case waitingForLoad      // Aspetta caricamento bilanciere
    case completed
    case failed(String)
}

// MARK: - Manual Calibration Step

enum ManualCalibrationStep: Int, CaseIterable, Codable {
    case step1_unrackAndLockout = 0
    case step2_eccentricDown = 1
    case step3_concentricUp = 2
    case step4_eccentricDown2 = 3
    case step5_concentricUp2 = 4
    
    var title: String {
        switch self {
        case .step1_unrackAndLockout: return "Step 1: Stacco e Lockout"
        case .step2_eccentricDown: return "Step 2: Discesa"
        case .step3_concentricUp: return "Step 3: Salita"
        case .step4_eccentricDown2: return "Step 4: Discesa (2)"
        case .step5_concentricUp2: return "Step 5: Salita (2)"
        }
    }
    
    var shortTitle: String {
        switch self {
        case .step1_unrackAndLockout: return "Stacco"
        case .step2_eccentricDown, .step4_eccentricDown2: return "Discesa"
        case .step3_concentricUp, .step5_concentricUp2: return "Salita"
        }
    }
    
    var instructions: String {
        switch self {
        case .step1_unrackAndLockout:
            return "Premi START quando sei pronto.\n\nStacca il bilanciere e porta le braccia in completa distensione (lockout).\n\nQuando hai raggiunto la posizione, l'assistente preme STOP."
        case .step2_eccentricDown, .step4_eccentricDown2:
            return "L'assistente preme START.\n\nAbbassa lentamente il bilanciere fino al petto controllando la discesa.\n\nQuando il bilanciere tocca il petto, l'assistente preme STOP."
        case .step3_concentricUp, .step5_concentricUp2:
            return "L'assistente preme START.\n\nSpingi il bilanciere verso l'alto fino al lockout completo.\n\nQuando le braccia sono distese, l'assistente preme STOP."
        }
    }
    
    var icon: String {
        switch self {
        case .step1_unrackAndLockout: return "arrow.up.to.line.circle.fill"
        case .step2_eccentricDown, .step4_eccentricDown2: return "arrow.down.circle.fill"
        case .step3_concentricUp, .step5_concentricUp2: return "arrow.up.circle.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .step1_unrackAndLockout: return .blue
        case .step2_eccentricDown, .step4_eccentricDown2: return .red
        case .step3_concentricUp, .step5_concentricUp2: return .green
        }
    }
    
    var phaseType: PhaseType {
        switch self {
        case .step1_unrackAndLockout: return .unrack
        case .step2_eccentricDown, .step4_eccentricDown2: return .eccentric
        case .step3_concentricUp, .step5_concentricUp2: return .concentric
        }
    }
    
    var progressValue: Double {
        return Double(self.rawValue + 1) / Double(ManualCalibrationStep.allCases.count)
    }
    
    var isLastStep: Bool {
        return self == .step5_concentricUp2
    }
    
    func next() -> ManualCalibrationStep? {
        guard !isLastStep else { return nil }
        return ManualCalibrationStep(rawValue: self.rawValue + 1)
    }
}

// MARK: - Phase Type

enum PhaseType: String, Codable {
    case unrack     // Stacco dal rack
    case eccentric  // Fase di discesa
    case concentric // Fase di salita
    case rest       // Pausa tra rep
    
    var displayName: String {
        switch self {
        case .unrack: return "Stacco"
        case .eccentric: return "Eccentrica"
        case .concentric: return "Concentrica"
        case .rest: return "Pausa"
        }
    }
}

// MARK: - Step Recording

struct StepRecording: Codable {
    let step: ManualCalibrationStep
    let samples: [AccelerationSample]
    let startTime: Date
    let endTime: Date
    
    var duration: TimeInterval {
        endTime.timeIntervalSince(startTime)
    }
    
    var avgAcceleration: Double {
        guard !samples.isEmpty else { return 0 }
        let sum = samples.map { $0.accZ }.reduce(0, +)
        return sum / Double(samples.count)
    }
    
    var peakAcceleration: Double {
        samples.map { abs($0.accZ) }.max() ?? 0
    }
    
    var amplitude: Double {
        guard let max = samples.map({ $0.accZ }).max(),
              let min = samples.map({ $0.accZ }).min() else {
            return 0
        }
        return max - min
    }
    
    var estimatedVelocity: Double {
        // Stima velocità dalla durata e ampiezza
        // v = s / t, con ROM stimato da ampiezza
        let estimatedROM = amplitude * 0.30 // Conversione empirica g → metri
        guard duration > 0.05 else {
            // Fallback cinematico: v = sqrt(2*a*s)
            let accelMS2 = amplitude * 9.81
            return sqrt(2.0 * accelMS2 * estimatedROM)
        }
        return estimatedROM / duration
    }
    
    var sampleCount: Int {
        samples.count
    }
    
    var averageSamplingRate: Double {
        guard duration > 0 else { return 0 }
        return Double(samples.count) / duration
    }
}

// MARK: - Manual Calibration State

enum ManualCalibrationState: Equatable {
    case idle
    case instructionsShown(ManualCalibrationStep)
    case recording(ManualCalibrationStep)
    case stepCompleted(ManualCalibrationStep)
    case analyzing
    case completed
    case failed(String)
    
    var currentStep: ManualCalibrationStep? {
        switch self {
        case .instructionsShown(let step),
             .recording(let step),
             .stepCompleted(let step):
            return step
        default:
            return nil
        }
    }
}

// MARK: - Calibration Summary

struct CalibrationSummary: Codable {
    let mode: CalibrationMode
    let date: Date
    let pattern: LearnedPattern
    
    // Statistiche aggiuntive (opzionali)
    let exerciseType: String?
    let notes: String?
    
    var displayDate: String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
    
    var displayMode: String {
        mode.displayName
    }
}
