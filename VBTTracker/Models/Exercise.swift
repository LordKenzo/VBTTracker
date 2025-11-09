//
//  Exercise.swift
//  VBTTracker
//
//  Modello per esercizi con configurazioni specifiche
//  ROM, velocità e parametri rilevamento per esercizio
//

import Foundation
import SwiftUI

// MARK: - Exercise Model

struct Exercise: Identifiable, Codable, Hashable {
    let id: UUID
    let name: String
    let category: ExerciseCategory
    let icon: String

    // ROM Configuration (per Arduino sensor)
    let defaultROM: Double              // in metri
    let romTolerance: Double            // 0.0-1.0 (es. 0.30 = ±30%)

    // Velocity Zones (specifiche per esercizio)
    let velocityRanges: VelocityRanges

    // Movement Characteristics (per WitMotion detector tuning)
    let movementProfile: MovementProfile

    init(
        id: UUID = UUID(),
        name: String,
        category: ExerciseCategory,
        icon: String,
        defaultROM: Double,
        romTolerance: Double = 0.30,
        velocityRanges: VelocityRanges,
        movementProfile: MovementProfile
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.icon = icon
        self.defaultROM = defaultROM
        self.romTolerance = romTolerance
        self.velocityRanges = velocityRanges
        self.movementProfile = movementProfile
    }
}

// MARK: - Exercise Category

enum ExerciseCategory: String, Codable, CaseIterable {
    case chest = "Petto"
    case legs = "Gambe"
    case back = "Schiena"
    case shoulders = "Spalle"
    case arms = "Braccia"

    var icon: String {
        switch self {
        case .chest: return "figure.strengthtraining.traditional"
        case .legs: return "figure.run"
        case .back: return "figure.rowing"
        case .shoulders: return "figure.arms.open"
        case .arms: return "dumbbell.fill"
        }
    }

    var color: Color {
        switch self {
        case .chest: return .blue
        case .legs: return .green
        case .back: return .orange
        case .shoulders: return .purple
        case .arms: return .red
        }
    }
}

// MARK: - Movement Profile

struct MovementProfile: Codable, Hashable {
    // Parametri per tuning detector (WitMotion)
    let minConcentricDuration: Double     // secondi
    let minAmplitude: Double              // g
    let eccentricThreshold: Double        // g
    let typicalDuration: ClosedRange<Double> // range durata tipica (s)

    init(
        minConcentricDuration: Double,
        minAmplitude: Double,
        eccentricThreshold: Double,
        typicalDuration: ClosedRange<Double>
    ) {
        self.minConcentricDuration = minConcentricDuration
        self.minAmplitude = minAmplitude
        self.eccentricThreshold = eccentricThreshold
        self.typicalDuration = typicalDuration
    }

    // Codable conformance for ClosedRange
    enum CodingKeys: String, CodingKey {
        case minConcentricDuration
        case minAmplitude
        case eccentricThreshold
        case typicalDurationMin
        case typicalDurationMax
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        minConcentricDuration = try container.decode(Double.self, forKey: .minConcentricDuration)
        minAmplitude = try container.decode(Double.self, forKey: .minAmplitude)
        eccentricThreshold = try container.decode(Double.self, forKey: .eccentricThreshold)
        let min = try container.decode(Double.self, forKey: .typicalDurationMin)
        let max = try container.decode(Double.self, forKey: .typicalDurationMax)
        typicalDuration = min...max
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(minConcentricDuration, forKey: .minConcentricDuration)
        try container.encode(minAmplitude, forKey: .minAmplitude)
        try container.encode(eccentricThreshold, forKey: .eccentricThreshold)
        try container.encode(typicalDuration.lowerBound, forKey: .typicalDurationMin)
        try container.encode(typicalDuration.upperBound, forKey: .typicalDurationMax)
    }

    // Hashable conformance (ClosedRange is not Hashable)
    func hash(into hasher: inout Hasher) {
        hasher.combine(minConcentricDuration)
        hasher.combine(minAmplitude)
        hasher.combine(eccentricThreshold)
        hasher.combine(typicalDuration.lowerBound)
        hasher.combine(typicalDuration.upperBound)
    }

    static func == (lhs: MovementProfile, rhs: MovementProfile) -> Bool {
        lhs.minConcentricDuration == rhs.minConcentricDuration &&
        lhs.minAmplitude == rhs.minAmplitude &&
        lhs.eccentricThreshold == rhs.eccentricThreshold &&
        lhs.typicalDuration.lowerBound == rhs.typicalDuration.lowerBound &&
        lhs.typicalDuration.upperBound == rhs.typicalDuration.upperBound
    }
}

// MARK: - Predefined Exercises

extension Exercise {

    // MARK: - Bench Press (Panca Piana)

    static let benchPress = Exercise(
        name: "Panca Piana",
        category: .chest,
        icon: "figure.strengthtraining.traditional",
        defaultROM: 0.50,  // 50cm ROM medio
        romTolerance: 0.30,
        velocityRanges: VelocityRanges(
            maxStrength: 0.15...0.30,    // González-Badillo & Sánchez-Medina, 2010
            strength: 0.30...0.50,        // Pareja-Blanco et al., 2017
            strengthSpeed: 0.50...0.75,   // Banyard et al., 2019
            speed: 0.75...1.00,           // Weakley et al., 2021
            maxSpeed: 1.00...2.00
        ),
        movementProfile: MovementProfile(
            minConcentricDuration: 0.3,   // Minimo 300ms
            minAmplitude: 0.45,           // 0.45g minimo
            eccentricThreshold: 0.15,     // 0.15g per rilevare discesa
            typicalDuration: 0.5...3.0    // Tipicamente 0.5-3s
        )
    )

    // MARK: - Squat

    static let squat = Exercise(
        name: "Squat",
        category: .legs,
        icon: "figure.run",
        defaultROM: 0.60,  // 60cm ROM medio (più lungo del bench)
        romTolerance: 0.25,
        velocityRanges: VelocityRanges(
            maxStrength: 0.20...0.35,    // Squat leggermente più lento del bench
            strength: 0.35...0.55,
            strengthSpeed: 0.55...0.80,
            speed: 0.80...1.10,
            maxSpeed: 1.10...2.00
        ),
        movementProfile: MovementProfile(
            minConcentricDuration: 0.4,   // Squat più lento: min 400ms
            minAmplitude: 0.60,           // Maggiore ampiezza movimento
            eccentricThreshold: 0.20,     // Soglia più alta (movimento più pesante)
            typicalDuration: 0.8...4.0    // Range più ampio
        )
    )

    // MARK: - Deadlift (Stacco da Terra)

    static let deadlift = Exercise(
        name: "Stacco da Terra",
        category: .back,
        icon: "figure.strengthtraining.traditional",
        defaultROM: 0.70,  // 70cm ROM medio (il più lungo)
        romTolerance: 0.20,
        velocityRanges: VelocityRanges(
            maxStrength: 0.10...0.25,    // Stacco più lento di tutti
            strength: 0.25...0.45,
            strengthSpeed: 0.45...0.70,
            speed: 0.70...0.95,
            maxSpeed: 0.95...1.50
        ),
        movementProfile: MovementProfile(
            minConcentricDuration: 0.5,   // Movimento più lento: min 500ms
            minAmplitude: 0.70,           // Maggiore ampiezza
            eccentricThreshold: 0.25,     // Soglia alta (carico pesante)
            typicalDuration: 1.0...5.0    // Range molto ampio
        )
    )

    // MARK: - All Exercises

    static let all: [Exercise] = [
        .benchPress,
        .squat,
        .deadlift
    ]

    static let defaultExercise: Exercise = .benchPress
}

// MARK: - Exercise Manager

class ExerciseManager: ObservableObject {
    static let shared = ExerciseManager()

    @Published var selectedExercise: Exercise {
        didSet {
            save()
            applyExerciseSettings()
        }
    }

    let availableExercises: [Exercise] = Exercise.all

    private let userDefaultsKey = "selectedExercise"

    private init() {
        // Carica esercizio salvato
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let decoded = try? JSONDecoder().decode(Exercise.self, from: data) {
            self.selectedExercise = decoded
        } else {
            self.selectedExercise = .benchPress  // Default
        }
    }

    private func save() {
        if let encoded = try? JSONEncoder().encode(selectedExercise) {
            UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
            print("💪 Esercizio salvato: \(selectedExercise.name)")
        }
    }

    /// Applica le settings dell'esercizio selezionato al SettingsManager
    private func applyExerciseSettings() {
        let settings = SettingsManager.shared

        // Applica ROM (per Arduino)
        settings.customROM = selectedExercise.defaultROM
        settings.customROMTolerance = selectedExercise.romTolerance
        settings.useCustomROM = true

        // Applica velocity ranges
        settings.velocityRanges = selectedExercise.velocityRanges

        // Applica movement profile (per WitMotion)
        settings.repMinDuration = selectedExercise.movementProfile.minConcentricDuration
        settings.repMinAmplitude = selectedExercise.movementProfile.minAmplitude
        settings.repEccentricThreshold = selectedExercise.movementProfile.eccentricThreshold

        print("⚙️ Settings applicate per: \(selectedExercise.name)")
        print("   • ROM: \(String(format: "%.2f", selectedExercise.defaultROM))m ±\(Int(selectedExercise.romTolerance * 100))%")
        print("   • Velocity range: \(String(format: "%.2f", selectedExercise.velocityRanges.strength.lowerBound))-\(String(format: "%.2f", selectedExercise.velocityRanges.strength.upperBound)) m/s (Forza)")
    }

    /// Applica manualmente le settings (da chiamare quando l'app si avvia)
    func applyCurrentExerciseSettings() {
        applyExerciseSettings()
    }
}
