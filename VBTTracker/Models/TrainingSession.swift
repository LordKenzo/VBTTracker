//
//  TrainingSession.swift
//  VBTTracker
//
//  Modello per sessioni di training salvate
//

import Foundation

struct TrainingSession: Identifiable, Codable {
    let id: UUID
    let date: Date
    let targetZone: TrainingZoneRaw
    let targetReps: Int
    let completedReps: Int
    let repsInTarget: Int
    let velocityLoss: Double
    let velocityLossThreshold: Double
    let meanVelocity: Double
    let reps: [SavedRepData]
    let wasSuccessful: Bool
    
    init(
        id: UUID = UUID(),
        date: Date,
        targetZone: TrainingZoneRaw,
        targetReps: Int,
        completedReps: Int,
        repsInTarget: Int,
        velocityLoss: Double,
        velocityLossThreshold: Double,
        meanVelocity: Double,
        reps: [SavedRepData],
        wasSuccessful: Bool
    ) {
        self.id = id
        self.date = date
        self.targetZone = targetZone
        self.targetReps = targetReps
        self.completedReps = completedReps
        self.repsInTarget = repsInTarget
        self.velocityLoss = velocityLoss
        self.velocityLossThreshold = velocityLossThreshold
        self.meanVelocity = meanVelocity
        self.reps = reps
        self.wasSuccessful = wasSuccessful
    }
    
    // Factory method da TrainingSessionData
    static func from(_ data: TrainingSessionData, targetReps: Int) -> TrainingSession {
        // Converti RepData in SavedRepData
        let savedReps = data.reps.map { rep in
            SavedRepData(
                meanVelocity: rep.meanVelocity,
                peakVelocity: rep.peakVelocity,
                velocityLossFromFirst: rep.velocityLossFromFirst
            )
        }
        
        return TrainingSession(
            date: data.date,
            targetZone: TrainingZoneRaw(from: data.targetZone),
            targetReps: targetReps,
            completedReps: data.totalReps,
            repsInTarget: data.repsInTarget,
            velocityLoss: data.velocityLoss,
            velocityLossThreshold: data.velocityLossThreshold,
            meanVelocity: data.reps.map(\.meanVelocity).reduce(0, +) / Double(max(data.reps.count, 1)),
            reps: savedReps,
            wasSuccessful: data.wasSuccessful
        )
    }
    
    // Computed properties
    var duration: TimeInterval {
        // Stima: ~3-5 secondi per rep
        return Double(completedReps) * 4.0
    }
    
    var targetPercentage: Double {
        guard targetReps > 0 else { return 0 }
        return Double(completedReps) / Double(targetReps)
    }
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    var shortDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - SavedRepData (Codable version of RepData)

struct SavedRepData: Identifiable, Codable {
    let id: UUID
    let meanVelocity: Double
    let peakVelocity: Double
    let velocityLossFromFirst: Double
    
    init(
        id: UUID = UUID(),
        meanVelocity: Double,
        peakVelocity: Double,
        velocityLossFromFirst: Double
    ) {
        self.id = id
        self.meanVelocity = meanVelocity
        self.peakVelocity = peakVelocity
        self.velocityLossFromFirst = velocityLossFromFirst
    }
    
    // Converti in RepData per TrainingSessionData
    func toRepData() -> RepData {
        return RepData(
            meanVelocity: meanVelocity,
            peakVelocity: peakVelocity,
            velocityLossFromFirst: velocityLossFromFirst
        )
    }
}

// MARK: - TrainingZoneRaw (per Codable)

enum TrainingZoneRaw: String, Codable {
    case maxStrength = "Max Strength"
    case strength = "Strength"
    case strengthSpeed = "Strength-Speed"
    case speed = "Speed"
    case maxSpeed = "Max Speed"
    case tooSlow = "Too Slow"
    
    init(from range: ClosedRange<Double>) {
        // Determina zona dal range
        let mid = (range.lowerBound + range.upperBound) / 2
        if mid < 0.2 {
            self = .tooSlow
        } else if mid < 0.4 {
            self = .maxStrength
        } else if mid < 0.75 {
            self = .strength
        } else if mid < 1.0 {
            self = .strengthSpeed
        } else if mid < 1.3 {
            self = .speed
        } else {
            self = .maxSpeed
        }
    }
    
    var displayName: String {
        return self.rawValue
    }
    
    var color: String {
        switch self {
        case .maxStrength: return "red"
        case .strength: return "orange"
        case .strengthSpeed: return "yellow"
        case .speed: return "green"
        case .maxSpeed: return "blue"
        case .tooSlow: return "gray"
        }
    }
}
