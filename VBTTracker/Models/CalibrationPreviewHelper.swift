//
//  CalibrationPreviewHelper.swift
//  VBTTracker
//
//  Helper per SwiftUI Previews - Calibrazione
//

import Foundation

#if DEBUG
extension ROMCalibrationManager {
    
    /// Manager per preview UI - Modalità Automatica in progress
    static var previewAutomatic: ROMCalibrationManager {
        let manager = ROMCalibrationManager()
        manager.calibrationMode = .automatic
        manager.automaticState = .detectingReps
        manager.calibrationProgress = 0.5
        manager.statusMessage = "Rep 1/2 completata..."
        return manager
    }
    
    /// Manager per preview UI - Modalità Manuale step 2
    static var previewManualStep2: ROMCalibrationManager {
        let manager = ROMCalibrationManager()
        manager.calibrationMode = .manual
        manager.currentManualStep = .step2_eccentricDown
        manager.manualState = .instructionsShown(.step2_eccentricDown)
        manager.calibrationProgress = 0.2
        manager.statusMessage = "Step 2/5: Leggi le istruzioni"
        return manager
    }
    
    /// Manager per preview UI - Modalità Manuale recording
    static var previewManualRecording: ROMCalibrationManager {
        let manager = ROMCalibrationManager()
        manager.calibrationMode = .manual
        manager.currentManualStep = .step3_concentricUp
        manager.manualState = .recording(.step3_concentricUp)
        manager.isRecordingStep = true
        manager.calibrationProgress = 0.4
        manager.statusMessage = "🔴 REGISTRAZIONE in corso..."
        return manager
    }
    
    /// Manager per preview UI - Completata
    static var previewCompleted: ROMCalibrationManager {
        let manager = ROMCalibrationManager()
        manager.calibrationMode = .automatic
        manager.automaticState = .completed
        manager.isCalibrated = true
        manager.calibrationProgress = 1.0
        manager.statusMessage = "✅ Calibrazione completata!"
        manager.learnedPattern = .mockPattern
        return manager
    }
}

extension LearnedPattern {
    
    /// Pattern mock per preview
    static var mockPattern: LearnedPattern {
        return LearnedPattern(
            avgAmplitude: 0.85,
            avgConcentricDuration: 0.75,
            avgEccentricDuration: 1.20,
            avgPeakVelocity: 1.15,
            unrackThreshold: 0.17,
            restThreshold: 0.09,
            estimatedROM: 0.52,
            calibrationMode: .automatic,
            calibrationDate: Date(),
            exerciseType: "Panca Piana"
        )
    }
    
    /// Pattern mock manuale
    static var mockManualPattern: LearnedPattern {
        return LearnedPattern(
            avgAmplitude: 0.92,
            avgConcentricDuration: 0.68,
            avgEccentricDuration: 1.35,
            avgPeakVelocity: 1.28,
            unrackThreshold: 0.21,
            restThreshold: 0.10,
            estimatedROM: 0.58,
            calibrationMode: .manual,
            calibrationDate: Date().addingTimeInterval(-86400), // 1 giorno fa
            exerciseType: "Panca Piana"
        )
    }
}

extension StepRecording {
    
    /// Recording mock per preview
    static var mockRecording: StepRecording {
        let samples = (0..<50).map { i in
            AccelerationSample(
                timestamp: Date().addingTimeInterval(Double(i) * 0.02),
                accZ: sin(Double(i) * 0.2) * 0.8
            )
        }
        
        return StepRecording(
            step: .step2_eccentricDown,
            samples: samples,
            startTime: Date(),
            endTime: Date().addingTimeInterval(1.0)
        )
    }
}
#endif
