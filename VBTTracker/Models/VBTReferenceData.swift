//
//  VBTReferenceData.swift
//  VBTTracker
//
//  Modelli per dati di riferimento VBT basati su letteratura scientifica
//  Riferimenti: González-Badillo & Sánchez-Medina (2010), Conceição et al. (2016)
//

import Foundation
import SwiftUI

// MARK: - Exercise Type

enum ExerciseType: String, Codable, CaseIterable {
    case benchPress = "bench_press"
    case squat = "squat"
    case deadlift = "deadlift"
    
    var displayName: String {
        switch self {
        case .benchPress: return "Panca Piana"
        case .squat: return "Squat"
        case .deadlift: return "Stacco"
        }
    }
    
    var icon: String {
        switch self {
        case .benchPress: return "figure.strengthtraining.traditional"
        case .squat: return "figure.squat"
        case .deadlift: return "figure.flexibility"
        }
    }
}

// MARK: - Load Zone

enum LoadZone: String, Codable, CaseIterable {
    case maxStrength = "max_strength"        // 90-100% 1RM
    case strengthSpeed = "strength_speed"    // 80-89% 1RM
    case speed = "speed"                     // 70-79% 1RM
    case speedStrength = "speed_strength"    // 60-69% 1RM
    case explosive = "explosive"             // <60% 1RM
    
    var displayName: String {
        switch self {
        case .maxStrength: return "Forza Massimale"
        case .strengthSpeed: return "Forza-Velocità"
        case .speed: return "Velocità"
        case .speedStrength: return "Velocità-Forza"
        case .explosive: return "Esplosiva"
        }
    }
    
    var shortName: String {
        switch self {
        case .maxStrength: return "Max"
        case .strengthSpeed: return "F-V"
        case .speed: return "Vel"
        case .speedStrength: return "V-F"
        case .explosive: return "Exp"
        }
    }
    
    var color: Color {
        switch self {
        case .maxStrength: return .red
        case .strengthSpeed: return .orange
        case .speed: return .yellow
        case .speedStrength: return .green
        case .explosive: return .blue
        }
    }
    
    var rmRange: ClosedRange<Int> {
        switch self {
        case .maxStrength: return 90...100
        case .strengthSpeed: return 80...89
        case .speed: return 70...79
        case .speedStrength: return 60...69
        case .explosive: return 30...59
        }
    }
}

// MARK: - VBT Zone Reference

struct VBTZoneReference: Identifiable, Codable {
    let id = UUID()
    let exerciseType: ExerciseType
    let loadZone: LoadZone
    let rmPercentage: Int           // % 1RM
    let minVelocity: Double         // m/s
    let maxVelocity: Double         // m/s
    
    var avgVelocity: Double {
        (minVelocity + maxVelocity) / 2
    }
    
    enum CodingKeys: String, CodingKey {
        case exerciseType, loadZone, rmPercentage, minVelocity, maxVelocity
    }
}

// MARK: - VBT Reference Data Manager

struct VBTReferenceData {
    
    // MARK: - Bench Press References
    // Fonte: González-Badillo & Sánchez-Medina (2010)
    
    private static let benchPressReferences: [VBTZoneReference] = [
        // Forza Massimale (90-100% 1RM)
        VBTZoneReference(exerciseType: .benchPress, loadZone: .maxStrength, rmPercentage: 100, minVelocity: 0.15, maxVelocity: 0.20),
        VBTZoneReference(exerciseType: .benchPress, loadZone: .maxStrength, rmPercentage: 95, minVelocity: 0.20, maxVelocity: 0.25),
        VBTZoneReference(exerciseType: .benchPress, loadZone: .maxStrength, rmPercentage: 90, minVelocity: 0.25, maxVelocity: 0.30),
        
        // Forza-Velocità (80-89% 1RM)
        VBTZoneReference(exerciseType: .benchPress, loadZone: .strengthSpeed, rmPercentage: 85, minVelocity: 0.35, maxVelocity: 0.40),
        VBTZoneReference(exerciseType: .benchPress, loadZone: .strengthSpeed, rmPercentage: 80, minVelocity: 0.40, maxVelocity: 0.50),
        
        // Velocità (70-79% 1RM)
        VBTZoneReference(exerciseType: .benchPress, loadZone: .speed, rmPercentage: 75, minVelocity: 0.50, maxVelocity: 0.60),
        VBTZoneReference(exerciseType: .benchPress, loadZone: .speed, rmPercentage: 70, minVelocity: 0.60, maxVelocity: 0.70),
        
        // Velocità-Forza (60-69% 1RM)
        VBTZoneReference(exerciseType: .benchPress, loadZone: .speedStrength, rmPercentage: 65, minVelocity: 0.70, maxVelocity: 0.80),
        VBTZoneReference(exerciseType: .benchPress, loadZone: .speedStrength, rmPercentage: 60, minVelocity: 0.80, maxVelocity: 0.90),
        
        // Esplosiva (<60% 1RM)
        VBTZoneReference(exerciseType: .benchPress, loadZone: .explosive, rmPercentage: 50, minVelocity: 0.90, maxVelocity: 1.00),
        VBTZoneReference(exerciseType: .benchPress, loadZone: .explosive, rmPercentage: 40, minVelocity: 1.00, maxVelocity: 1.10),
        VBTZoneReference(exerciseType: .benchPress, loadZone: .explosive, rmPercentage: 30, minVelocity: 1.10, maxVelocity: 1.30)
    ]
    
    // MARK: - Squat References
    // Fonte: Conceição et al. (2016)
    
    private static let squatReferences: [VBTZoneReference] = [
        // Forza Massimale (90-100% 1RM)
        VBTZoneReference(exerciseType: .squat, loadZone: .maxStrength, rmPercentage: 100, minVelocity: 0.20, maxVelocity: 0.25),
        VBTZoneReference(exerciseType: .squat, loadZone: .maxStrength, rmPercentage: 95, minVelocity: 0.30, maxVelocity: 0.35),
        VBTZoneReference(exerciseType: .squat, loadZone: .maxStrength, rmPercentage: 90, minVelocity: 0.40, maxVelocity: 0.45),
        
        // Forza-Velocità (80-89% 1RM)
        VBTZoneReference(exerciseType: .squat, loadZone: .strengthSpeed, rmPercentage: 85, minVelocity: 0.50, maxVelocity: 0.60),
        VBTZoneReference(exerciseType: .squat, loadZone: .strengthSpeed, rmPercentage: 80, minVelocity: 0.60, maxVelocity: 0.70),
        
        // Velocità (70-79% 1RM)
        VBTZoneReference(exerciseType: .squat, loadZone: .speed, rmPercentage: 75, minVelocity: 0.70, maxVelocity: 0.80),
        VBTZoneReference(exerciseType: .squat, loadZone: .speed, rmPercentage: 70, minVelocity: 0.80, maxVelocity: 0.90),
        
        // Velocità-Forza (60-69% 1RM)
        VBTZoneReference(exerciseType: .squat, loadZone: .speedStrength, rmPercentage: 65, minVelocity: 0.90, maxVelocity: 1.00),
        VBTZoneReference(exerciseType: .squat, loadZone: .speedStrength, rmPercentage: 60, minVelocity: 1.00, maxVelocity: 1.10),
        
        // Esplosiva (<60% 1RM)
        VBTZoneReference(exerciseType: .squat, loadZone: .explosive, rmPercentage: 50, minVelocity: 1.10, maxVelocity: 1.20),
        VBTZoneReference(exerciseType: .squat, loadZone: .explosive, rmPercentage: 40, minVelocity: 1.20, maxVelocity: 1.30),
        VBTZoneReference(exerciseType: .squat, loadZone: .explosive, rmPercentage: 30, minVelocity: 1.30, maxVelocity: 1.50)
    ]
    
    // MARK: - Public API
    
    /// Ottiene tutti i riferimenti per un esercizio
    static func getReferences(for exercise: ExerciseType) -> [VBTZoneReference] {
        switch exercise {
        case .benchPress: return benchPressReferences
        case .squat: return squatReferences
        case .deadlift: return [] // TODO: Implementare
        }
    }
    
    /// Ottiene i riferimenti per una zona specifica
    static func getZones(for exercise: ExerciseType) -> [VBTZoneReference] {
        getReferences(for: exercise)
    }
    
    /// Stima la % 1RM dalla velocità media
    static func estimateRM(velocity: Double, exercise: ExerciseType) -> Int? {
        let references = getReferences(for: exercise)
        
        // Trova il riferimento più vicino
        let closest = references.min { ref1, ref2 in
            let dist1 = abs(ref1.avgVelocity - velocity)
            let dist2 = abs(ref2.avgVelocity - velocity)
            return dist1 < dist2
        }
        
        return closest?.rmPercentage
    }
    
    /// Determina la zona di allenamento dalla velocità
    static func getLoadZone(velocity: Double, exercise: ExerciseType) -> LoadZone? {
        let references = getReferences(for: exercise)
        
        // Trova zona che contiene questa velocità
        let match = references.first { ref in
            velocity >= ref.minVelocity && velocity <= ref.maxVelocity
        }
        
        return match?.loadZone
    }
    
    /// Verifica se la velocità è nel range target per una zona
    static func isVelocityInZone(velocity: Double, zone: LoadZone, exercise: ExerciseType) -> Bool {
        let references = getReferences(for: exercise).filter { $0.loadZone == zone }
        
        guard let minVel = references.map({ $0.minVelocity }).min(),
              let maxVel = references.map({ $0.maxVelocity }).max() else {
            return false
        }
        
        return velocity >= minVel && velocity <= maxVel
    }
    
    /// Ottiene il range di velocità per una zona
    static func getVelocityRange(zone: LoadZone, exercise: ExerciseType) -> (min: Double, max: Double)? {
        let references = getReferences(for: exercise).filter { $0.loadZone == zone }
        
        guard let minVel = references.map({ $0.minVelocity }).min(),
              let maxVel = references.map({ $0.maxVelocity }).max() else {
            return nil
        }
        
        return (minVel, maxVel)
    }
}
