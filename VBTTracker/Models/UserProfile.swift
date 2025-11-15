//
//  UserProfile.swift
//  VBTTracker
//
//  Modello dati per il profilo utente
//  Utilizzato per personalizzazione e calcolo indice di fatica
//

import Foundation
import UIKit

// MARK: - User Profile Model

struct UserProfile: Codable {

    // MARK: - Properties

    var name: String
    var age: Int?
    var gender: Gender?
    var height: Double?  // cm
    var weight: Double?  // kg

    // Photo is stored separately as Data (not in Codable struct)
    // Use ProfileManager to access profile photo

    // MARK: - Gender Enum

    enum Gender: String, Codable, CaseIterable {
        case male = "Maschio"
        case female = "Femmina"
        case other = "Altro"

        var systemImage: String {
            switch self {
            case .male: return "person.fill"
            case .female: return "person.fill"
            case .other: return "person.fill"
            }
        }
    }

    // MARK: - Initialization

    init(
        name: String = "",
        age: Int? = nil,
        gender: Gender? = nil,
        height: Double? = nil,
        weight: Double? = nil
    ) {
        self.name = name
        self.age = age
        self.gender = gender
        self.height = height
        self.weight = weight
    }

    // MARK: - Validation

    var isComplete: Bool {
        !name.isEmpty && age != nil && gender != nil && height != nil && weight != nil
    }

    var completionPercentage: Double {
        var filledFields = 0
        let totalFields = 5

        if !name.isEmpty { filledFields += 1 }
        if age != nil { filledFields += 1 }
        if gender != nil { filledFields += 1 }
        if height != nil { filledFields += 1 }
        if weight != nil { filledFields += 1 }

        return Double(filledFields) / Double(totalFields)
    }

    // MARK: - Computed Properties

    /// Body Mass Index (BMI)
    var bmi: Double? {
        guard let height = height, let weight = weight, height > 0 else { return nil }
        let heightInMeters = height / 100.0
        return weight / (heightInMeters * heightInMeters)
    }

    /// BMI Category
    var bmiCategory: String? {
        guard let bmi = bmi else { return nil }

        switch bmi {
        case ..<18.5: return "Sottopeso"
        case 18.5..<25: return "Normopeso"
        case 25..<30: return "Sovrappeso"
        default: return "Obesità"
        }
    }

    /// Age-based training intensity modifier
    /// Used for fatigue index calculation
    var ageIntensityModifier: Double {
        guard let age = age else { return 1.0 }

        switch age {
        case ..<18: return 0.85  // Youth - conservative
        case 18..<30: return 1.0  // Peak performance
        case 30..<40: return 0.95
        case 40..<50: return 0.90
        case 50..<60: return 0.85
        default: return 0.80  // 60+
        }
    }

    /// Gender-based recovery modifier
    /// Research suggests females may have different recovery patterns
    var genderRecoveryModifier: Double {
        switch gender {
        case .male: return 1.0
        case .female: return 1.05  // Slightly faster recovery in some studies
        case .other, .none: return 1.0
        }
    }

    /// Estimated relative strength based on body weight
    /// Used for fatigue index normalization
    func relativeStrength(velocity: Double) -> Double {
        guard let weight = weight, weight > 0 else { return velocity }
        return velocity / weight
    }
}

// MARK: - Validation Errors

enum UserProfileValidationError: LocalizedError {
    case emptyName
    case invalidAge
    case invalidHeight
    case invalidWeight

    var errorDescription: String? {
        switch self {
        case .emptyName:
            return "Il nome è obbligatorio"
        case .invalidAge:
            return "L'età deve essere compresa tra 10 e 120 anni"
        case .invalidHeight:
            return "L'altezza deve essere compresa tra 100 e 250 cm"
        case .invalidWeight:
            return "Il peso deve essere compreso tra 30 e 300 kg"
        }
    }
}

// MARK: - Profile Validation

extension UserProfile {

    /// Validates the profile and returns errors if any
    func validate() throws {
        if name.trimmingCharacters(in: .whitespaces).isEmpty {
            throw UserProfileValidationError.emptyName
        }

        if let age = age, !(10...120).contains(age) {
            throw UserProfileValidationError.invalidAge
        }

        if let height = height, !(100...250).contains(height) {
            throw UserProfileValidationError.invalidHeight
        }

        if let weight = weight, !(30...300).contains(weight) {
            throw UserProfileValidationError.invalidWeight
        }
    }
}
