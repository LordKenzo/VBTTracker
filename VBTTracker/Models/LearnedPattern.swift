//
//  LearnedPattern.swift
//  VBTTracker
//
//  Pattern appreso da calibrazione ROM (con metadata dual-mode)
//

import Foundation

struct LearnedPattern: Codable {
    
    // MARK: - Pattern Data (esistente)
    
    let avgAmplitude: Double            // Ampiezza media movimento (g)
    let avgConcentricDuration: Double   // Durata media fase concentrica (s)
    let avgEccentricDuration: Double    // Durata media fase eccentrica (s)
    let avgPeakVelocity: Double         // Velocità picco media (m/s)
    let estimatedROM: Double            // Range of Motion stimato (m)
    
    // Soglie derivate
    let unrackThreshold: Double         // Soglia rilevamento stacco (g)
    let restThreshold: Double           // Soglia rilevamento pausa (g)
    
    // MARK: - Metadata (NUOVO)
    
    let calibrationMode: CalibrationMode  // Automatica o Manuale
    let calibrationDate: Date            // Quando è stata fatta
    let exerciseType: String?            // "Panca", "Squat", etc. (futuro)
    
    // MARK: - Computed Properties
    
    /// Ampiezza minima dinamica (50% della media appresa)
    var dynamicMinAmplitude: Double {
        avgAmplitude * 0.5
    }
    
    /// Durata totale rep (eccentrica + concentrica)
    var totalRepDuration: Double {
        avgEccentricDuration + avgConcentricDuration
    }
    
    /// Descrizione leggibile del pattern
    var description: String {
        let mode = calibrationMode.displayName
        let date = calibrationDate.formatted(date: .abbreviated, time: .shortened)
        let exercise = exerciseType ?? "Generico"
        return "\(exercise) • \(mode) • \(date)"
    }
    
    /// Descrizione breve per UI
    var shortDescription: String {
        let mode = calibrationMode == .automatic ? "Auto" : "Man"
        let date = calibrationDate.formatted(date: .abbreviated, time: .omitted)
        return "\(mode) - \(date)"
    }
    
    /// Check validità pattern
    var isValid: Bool {
        return avgAmplitude > 0.1 &&
               avgConcentricDuration > 0.2 &&
               avgPeakVelocity > 0.1 &&
               estimatedROM > 0.15
    }
    
    // MARK: - Initialization
    
    init(
        avgAmplitude: Double,
        avgConcentricDuration: Double,
        avgEccentricDuration: Double,
        avgPeakVelocity: Double,
        unrackThreshold: Double,
        restThreshold: Double,
        estimatedROM: Double,
        calibrationMode: CalibrationMode = .automatic,
        calibrationDate: Date = Date(),
        exerciseType: String? = nil
    ) {
        self.avgAmplitude = avgAmplitude
        self.avgConcentricDuration = avgConcentricDuration
        self.avgEccentricDuration = avgEccentricDuration
        self.avgPeakVelocity = avgPeakVelocity
        self.unrackThreshold = unrackThreshold
        self.restThreshold = restThreshold
        self.estimatedROM = estimatedROM
        self.calibrationMode = calibrationMode
        self.calibrationDate = calibrationDate
        self.exerciseType = exerciseType
    }
    
    // MARK: - Factory Methods
    
    /// Pattern default per fallback
    static var defaultPattern: LearnedPattern {
        return LearnedPattern(
            avgAmplitude: 0.7,
            avgConcentricDuration: 0.8,
            avgEccentricDuration: 1.0,
            avgPeakVelocity: 1.0,
            unrackThreshold: 0.15,
            restThreshold: 0.08,
            estimatedROM: 0.45,
            calibrationMode: .automatic,
            calibrationDate: Date(),
            exerciseType: "Default"
        )
    }
    
    /// Crea pattern da calibrazione automatica (2 rep)
    static func fromAutomaticCalibration(
        amplitude: Double,
        concentricDuration: Double,
        eccentricDuration: Double,
        peakVelocity: Double,
        rom: Double
    ) -> LearnedPattern {
        return LearnedPattern(
            avgAmplitude: amplitude,
            avgConcentricDuration: concentricDuration,
            avgEccentricDuration: eccentricDuration,
            avgPeakVelocity: peakVelocity,
            unrackThreshold: amplitude * 0.2,
            restThreshold: amplitude * 0.1,
            estimatedROM: rom,
            calibrationMode: .automatic,
            calibrationDate: Date(),
            exerciseType: nil
        )
    }
    
    /// Crea pattern da calibrazione manuale (5 step)
    static func fromManualCalibration(
        unrackData: StepRecording,
        eccentricData: [StepRecording],
        concentricData: [StepRecording]
    ) -> LearnedPattern {
        // Media dati eccentriche
        let avgEccentricDuration = eccentricData.map { $0.duration }.reduce(0, +) / Double(eccentricData.count)
        let avgEccentricAmplitude = eccentricData.map { $0.amplitude }.reduce(0, +) / Double(eccentricData.count)
        
        // Media dati concentriche
        let avgConcentricDuration = concentricData.map { $0.duration }.reduce(0, +) / Double(concentricData.count)
        let avgConcentricAmplitude = concentricData.map { $0.amplitude }.reduce(0, +) / Double(concentricData.count)
        let avgConcentricVelocity = concentricData.map { $0.estimatedVelocity }.reduce(0, +) / Double(concentricData.count)
        
        // ROM totale stimato
        let estimatedROM = (avgEccentricAmplitude + avgConcentricAmplitude) * 0.25
        
        return LearnedPattern(
            avgAmplitude: avgConcentricAmplitude,
            avgConcentricDuration: avgConcentricDuration,
            avgEccentricDuration: avgEccentricDuration,
            avgPeakVelocity: avgConcentricVelocity,
            unrackThreshold: unrackData.peakAcceleration * 0.3,
            restThreshold: unrackData.peakAcceleration * 0.15,
            estimatedROM: estimatedROM,
            calibrationMode: .manual,
            calibrationDate: Date(),
            exerciseType: nil
        )
    }
}

// MARK: - Debug Description

extension LearnedPattern: CustomStringConvertible {
    var debugDescription: String {
        return """
        LearnedPattern {
          Mode: \(calibrationMode.displayName)
          Date: \(calibrationDate.formatted())
          Amplitude: \(String(format: "%.2f", avgAmplitude))g
          Concentric: \(String(format: "%.2f", avgConcentricDuration))s
          Eccentric: \(String(format: "%.2f", avgEccentricDuration))s
          Peak Velocity: \(String(format: "%.2f", avgPeakVelocity)) m/s
          ROM: \(String(format: "%.2f", estimatedROM * 100))cm
          Valid: \(isValid)
        }
        """
    }
}
