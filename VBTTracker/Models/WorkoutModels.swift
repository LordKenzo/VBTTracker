//
//  WorkoutModels.swift
//  VBTTracker
//
//  Modelli SwiftData per tracking workout VBT
//

import Foundation
import SwiftData

// MARK: - Trajectory Point

struct TrajectoryPoint: Codable, Identifiable {
    let id = UUID()
    let timestamp: Double      // Tempo relativo alla rep (secondi)
    let x: Double             // Posizione X (angolo roll)
    let y: Double             // Posizione Y (angolo yaw)
    let z: Double             // Posizione Z (angolo pitch - verticale)
    let velocity: Double      // Velocità istantanea (m/s)
    
    enum CodingKeys: String, CodingKey {
        case timestamp, x, y, z, velocity
    }
}

// MARK: - Rep Feedback

enum RepFeedback: String, Codable {
    case optimal = "optimal"        // Velocità perfetta per la zona
    case tooSlow = "too_slow"      // Troppo lento
    case tooFast = "too_fast"      // Troppo veloce
    case unknown = "unknown"        // Non determinabile
    
    var displayName: String {
        switch self {
        case .optimal: return "Ottimale"
        case .tooSlow: return "Troppo Lento"
        case .tooFast: return "Troppo Veloce"
        case .unknown: return "N/D"
        }
    }
    
    var icon: String {
        switch self {
        case .optimal: return "checkmark.circle.fill"
        case .tooSlow: return "arrow.down.circle.fill"
        case .tooFast: return "arrow.up.circle.fill"
        case .unknown: return "questionmark.circle.fill"
        }
    }
}

// MARK: - Rep Data

@Model
class RepData {
    var id: UUID
    var repNumber: Int
    var peakVelocity: Double           // Velocità di picco (m/s)
    var avgVelocity: Double            // Mean Propulsive Velocity (m/s)
    var rom: Double                    // Range of Motion (gradi)
    var duration: Double               // Durata ripetizione (secondi)
    var trajectoryData: Data?          // Traiettoria codificata
    var feedbackRaw: String            // RepFeedback as String
    var velocityLoss: Double?          // Velocity Loss % rispetto a prima rep
    
    // Computed property per feedback
    var feedback: RepFeedback {
        get { RepFeedback(rawValue: feedbackRaw) ?? .unknown }
        set { feedbackRaw = newValue.rawValue }
    }
    
    // Computed property per trajectory
    var trajectory: [TrajectoryPoint] {
        get {
            guard let data = trajectoryData,
                  let decoded = try? JSONDecoder().decode([TrajectoryPoint].self, from: data) else {
                return []
            }
            return decoded
        }
        set {
            trajectoryData = try? JSONEncoder().encode(newValue)
        }
    }
    
    init(repNumber: Int, peakVelocity: Double = 0, avgVelocity: Double = 0,
         rom: Double = 0, duration: Double = 0, trajectory: [TrajectoryPoint] = [],
         feedback: RepFeedback = .unknown, velocityLoss: Double? = nil) {
        self.id = UUID()
        self.repNumber = repNumber
        self.peakVelocity = peakVelocity
        self.avgVelocity = avgVelocity
        self.rom = rom
        self.duration = duration
        self.feedbackRaw = feedback.rawValue
        self.velocityLoss = velocityLoss
        self.trajectory = trajectory
    }
}

// MARK: - Set Data

@Model
class SetData {
    var id: UUID
    var setNumber: Int
    var targetReps: Int
    var actualReps: Int
    var restTime: TimeInterval?        // Secondi di riposo
    
    @Relationship(deleteRule: .cascade)
    var reps: [RepData] = []
    
    // Computed properties
    var avgVelocity: Double {
        guard !reps.isEmpty else { return 0 }
        return reps.map { $0.avgVelocity }.reduce(0, +) / Double(reps.count)
    }
    
    var peakVelocity: Double {
        reps.map { $0.peakVelocity }.max() ?? 0
    }
    
    var totalVolume: Double {
        // Sarà calcolato dalla session usando il carico
        0
    }
    
    init(setNumber: Int, targetReps: Int = 0, actualReps: Int = 0, restTime: TimeInterval? = nil) {
        self.id = UUID()
        self.setNumber = setNumber
        self.targetReps = targetReps
        self.actualReps = actualReps
        self.restTime = restTime
    }
}

// MARK: - Workout Session

@Model
class WorkoutSession {
    var id: UUID
    var date: Date
    
    // Esercizio e configurazione
    var exerciseTypeRaw: String        // ExerciseType as String
    var loadKg: Double
    var targetZoneRaw: String          // LoadZone as String
    
    // Atleta (opzionale)
    var athleteName: String?
    
    // Note
    var notes: String?
    
    @Relationship(deleteRule: .cascade)
    var sets: [SetData] = []
    
    // Computed properties
    var exerciseType: ExerciseType {
        get { ExerciseType(rawValue: exerciseTypeRaw) ?? .benchPress }
        set { exerciseTypeRaw = newValue.rawValue }
    }
    
    var targetZone: LoadZone {
        get { LoadZone(rawValue: targetZoneRaw) ?? .maxStrength }
        set { targetZoneRaw = newValue.rawValue }
    }
    
    var totalReps: Int {
        sets.reduce(0) { $0 + $1.actualReps }
    }
    
    var totalVolume: Double {
        loadKg * Double(totalReps)
    }
    
    var avgVelocity: Double {
        let allReps = sets.flatMap { $0.reps }
        guard !allReps.isEmpty else { return 0 }
        return allReps.map { $0.avgVelocity }.reduce(0, +) / Double(allReps.count)
    }
    
    var peakVelocity: Double {
        sets.map { $0.peakVelocity }.max() ?? 0
    }
    
    // Stima % 1RM dalla velocità media
    var estimatedRMPercentage: Int? {
        VBTReferenceData.estimateRM(velocity: avgVelocity, exercise: exerciseType)
    }
    
    init(exerciseType: ExerciseType, loadKg: Double, targetZone: LoadZone,
         athleteName: String? = nil, notes: String? = nil) {
        self.id = UUID()
        self.date = Date()
        self.exerciseTypeRaw = exerciseType.rawValue
        self.loadKg = loadKg
        self.targetZoneRaw = targetZone.rawValue
        self.athleteName = athleteName
        self.notes = notes
    }
}

// MARK: - Recorded Rep (per uso in-memory durante workout)

struct RecordedRep: Identifiable {
    let id = UUID()
    let repNumber: Int
    let peakVelocity: Double
    let avgVelocity: Double
    let rom: Double
    let duration: Double
    let trajectory: [TrajectoryPoint]
    let feedback: RepFeedback
    let velocityLoss: Double?
    
    // Converte in RepData per salvataggio
    func toRepData() -> RepData {
        RepData(
            repNumber: repNumber,
            peakVelocity: peakVelocity,
            avgVelocity: avgVelocity,
            rom: rom,
            duration: duration,
            trajectory: trajectory,
            feedback: feedback,
            velocityLoss: velocityLoss
        )
    }
}
