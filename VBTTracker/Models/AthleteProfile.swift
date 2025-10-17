//
//  AthleteProfile.swift
//  VBTTracker
//
//  Created by Lorenzo Franceschini on 17/10/25.
//


//
//  AthleteProfile.swift
//  VBTTracker
//
//  Modello SwiftData per profilo atleta
//

import Foundation
import SwiftData
import UIKit

@Model
class AthleteProfile {
    var id: UUID
    var name: String
    var createdDate: Date
    
    // Dati personali opzionali
    var age: Int?
    var weight: Double?              // kg
    var height: Double?              // cm
    
    // 1RM per ogni esercizio (kg)
    var benchPress1RM: Double?
    var squat1RM: Double?
    var deadlift1RM: Double?
    
    // Immagine profilo
    var profileImageData: Data?
    
    // Computed property per immagine
    var profileImage: UIImage? {
        guard let data = profileImageData else { return nil }
        return UIImage(data: data)
    }
    
    init(name: String, age: Int? = nil, weight: Double? = nil, height: Double? = nil) {
        self.id = UUID()
        self.name = name
        self.age = age
        self.weight = weight
        self.height = height
        self.createdDate = Date()
    }
    
    // MARK: - 1RM Helpers
    
    /// Ottiene il 1RM per un esercizio specifico
    func get1RM(for exercise: ExerciseType) -> Double? {
        switch exercise {
        case .benchPress: return benchPress1RM
        case .squat: return squat1RM
        case .deadlift: return deadlift1RM
        }
    }
    
    /// Imposta il 1RM per un esercizio specifico
    func set1RM(_ value: Double?, for exercise: ExerciseType) {
        switch exercise {
        case .benchPress: benchPress1RM = value
        case .squat: squat1RM = value
        case .deadlift: deadlift1RM = value
        }
    }
    
    /// Calcola la % 1RM dato un carico
    func calculateRMPercentage(load: Double, for exercise: ExerciseType) -> Int? {
        guard let oneRM = get1RM(for: exercise), oneRM > 0 else {
            return nil
        }
        return Int((load / oneRM) * 100)
    }
    
    /// Calcola il carico per una % 1RM target
    func calculateLoad(rmPercentage: Int, for exercise: ExerciseType) -> Double? {
        guard let oneRM = get1RM(for: exercise), oneRM > 0 else {
            return nil
        }
        return oneRM * (Double(rmPercentage) / 100.0)
    }
    
    /// Verifica se ha 1RM impostato per un esercizio
    func has1RM(for exercise: ExerciseType) -> Bool {
        get1RM(for: exercise) != nil
    }
}

// MARK: - Workout Defaults (per memorizzare ultimi carichi usati)

struct WorkoutDefaults {
    private static let defaults = UserDefaults.standard
    private static let lastLoadKey = "lastLoad_"
    
    /// Salva ultimo carico usato per un esercizio
    static func saveLastLoad(_ load: Double, for exercise: ExerciseType) {
        let key = lastLoadKey + exercise.rawValue
        defaults.set(load, forKey: key)
    }
    
    /// Recupera ultimo carico usato per un esercizio
    static func getLastLoad(for exercise: ExerciseType) -> Double? {
        let key = lastLoadKey + exercise.rawValue
        let value = defaults.double(forKey: key)
        return value > 0 ? value : nil
    }
    
    /// Suggerisce un carico iniziale per un esercizio
    static func suggestLoad(for exercise: ExerciseType, athlete: AthleteProfile?, targetZone: LoadZone) -> Double {
        // 1. Prova con 1RM dell'atleta
        if let athlete = athlete,
           let oneRM = athlete.get1RM(for: exercise) {
            // Usa il punto medio del range della zona
            let midPercentage = (targetZone.rmRange.lowerBound + targetZone.rmRange.upperBound) / 2
            return oneRM * (Double(midPercentage) / 100.0)
        }
        
        // 2. Usa ultimo carico se disponibile
        if let lastLoad = getLastLoad(for: exercise) {
            return lastLoad
        }
        
        // 3. Usa valori default ragionevoli
        switch exercise {
        case .benchPress:
            return targetZone == .maxStrength ? 80 : 60
        case .squat:
            return targetZone == .maxStrength ? 120 : 80
        case .deadlift:
            return targetZone == .maxStrength ? 140 : 100
        }
    }
}