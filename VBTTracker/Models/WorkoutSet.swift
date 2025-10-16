//
//  WorkoutSet.swift
//  VBTTracker
//
//  Modello dati per una serie di allenamento completa
//

import Foundation

struct WorkoutSet: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let exerciseName: String        // "Bench Press", "Squat", etc.
    let loadKg: Double              // Carico utilizzato
    let targetReps: Int             // Ripetizioni target
    
    let reps: [RepData]             // Ripetizioni registrate
    
    // Calibrazione utilizzata
    let calibrationData: CalibrationData?
    
    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        exerciseName: String,
        loadKg: Double,
        targetReps: Int,
        reps: [RepData],
        calibrationData: CalibrationData? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.exerciseName = exerciseName
        self.loadKg = loadKg
        self.targetReps = targetReps
        self.reps = reps
        self.calibrationData = calibrationData
    }
    
    // MARK: - Computed Properties
    
    var actualReps: Int {
        reps.count
    }
    
    var avgPeakVelocity: Double {
        guard !reps.isEmpty else { return 0 }
        return reps.map { $0.peakVelocity }.reduce(0, +) / Double(reps.count)
    }
    
    var avgMeanVelocity: Double {
        guard !reps.isEmpty else { return 0 }
        return reps.map { $0.meanVelocity }.reduce(0, +) / Double(reps.count)
    }
    
    var maxPeakVelocity: Double {
        reps.map { $0.peakVelocity }.max() ?? 0
    }
    
    var totalVolume: Double {
        loadKg * Double(actualReps)
    }
    
    var totalDuration: Double {
        reps.map { $0.totalDuration }.reduce(0, +)
    }
    
    /// Calcola Velocity Loss % (primo vs ultimo rep)
    var velocityLoss: Double? {
        guard reps.count >= 2 else { return nil }
        let firstVelocity = reps.first!.peakVelocity
        let lastVelocity = reps.last!.peakVelocity
        guard firstVelocity > 0 else { return nil }
        
        return ((firstVelocity - lastVelocity) / firstVelocity) * 100
    }
}
