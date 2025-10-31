//
//  CalibrationPreviewHelper.swift
//  VBTTracker
//
//  Preview helpers – Automatic Calibration
//

import Foundation

#if DEBUG
extension ROMCalibrationManager {

    static var previewAutomatic: ROMCalibrationManager {
        let manager = ROMCalibrationManager()
        manager.automaticState = .detectingReps
        manager.calibrationProgress = 0.5
        manager.statusMessage = "Rep 1/2 completata…"
        return manager
    }

    static var previewCompleted: ROMCalibrationManager {
        let manager = ROMCalibrationManager()
        manager.automaticState = .completed
        manager.isCalibrated = true
        manager.calibrationProgress = 1.0
        manager.statusMessage = "✅ Calibrazione completata!"
        manager.learnedPattern = .mockPattern    // ✅ nuovo mock compatibile
        return manager
    }
}
#endif
#if DEBUG
extension LearnedPattern {
    static var mockPattern: LearnedPattern {
        LearnedPattern(
            rom: 0.52,             // 52 cm
            minThreshold: 0.42,    // g - soglia dinamica appresa
            avgVelocity: 1.15,     // m/s - picco medio
            avgConcentricDuration: 0.75,
            restThreshold: 0.09    // g   - soglia “fermo”
        )
    }
}
#endif
