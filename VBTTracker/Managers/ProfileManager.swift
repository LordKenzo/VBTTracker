//
//  ProfileManager.swift
//  VBTTracker
//
//  Manager per la gestione del profilo utente e persistenza
//

import Foundation
import UIKit
import Combine

class ProfileManager: ObservableObject {

    // MARK: - Singleton

    static let shared = ProfileManager()

    // MARK: - Published Properties

    @Published var profile: UserProfile {
        didSet {
            saveProfile()
        }
    }

    @Published var profilePhoto: UIImage? {
        didSet {
            saveProfilePhoto()
        }
    }

    // MARK: - Private Properties

    private let profileKey = "userProfile"
    private let photoKey = "userProfilePhoto"

    // MARK: - Initialization

    private init() {
        self.profile = ProfileManager.loadProfile()
        self.profilePhoto = ProfileManager.loadProfilePhoto()
    }

    // MARK: - Profile Persistence

    private func saveProfile() {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(profile)
            UserDefaults.standard.set(data, forKey: profileKey)
            print("✅ Profile saved successfully")
        } catch {
            print("❌ Error saving profile: \(error.localizedDescription)")
        }
    }

    private static func loadProfile() -> UserProfile {
        guard let data = UserDefaults.standard.data(forKey: "userProfile") else {
            print("ℹ️ No saved profile found, creating default")
            return UserProfile()
        }

        do {
            let decoder = JSONDecoder()
            let profile = try decoder.decode(UserProfile.self, from: data)
            print("✅ Profile loaded successfully")
            return profile
        } catch {
            print("❌ Error loading profile: \(error.localizedDescription)")
            return UserProfile()
        }
    }

    // MARK: - Photo Persistence

    private func saveProfilePhoto() {
        guard let photo = profilePhoto else {
            // Remove photo if nil
            UserDefaults.standard.removeObject(forKey: photoKey)
            return
        }

        // Compress to JPEG (0.8 quality) to reduce size
        guard let imageData = photo.jpegData(compressionQuality: 0.8) else {
            print("❌ Error converting image to data")
            return
        }

        UserDefaults.standard.set(imageData, forKey: photoKey)
        print("✅ Profile photo saved successfully (\(imageData.count) bytes)")
    }

    private static func loadProfilePhoto() -> UIImage? {
        guard let imageData = UserDefaults.standard.data(forKey: "userProfilePhoto") else {
            return nil
        }

        guard let image = UIImage(data: imageData) else {
            print("❌ Error loading profile photo from data")
            return nil
        }

        print("✅ Profile photo loaded successfully")
        return image
    }

    // MARK: - Public Methods

    /// Updates profile and validates before saving
    func updateProfile(_ newProfile: UserProfile) throws {
        try newProfile.validate()
        self.profile = newProfile
    }

    /// Clears all profile data
    func clearProfile() {
        profile = UserProfile()
        profilePhoto = nil
        UserDefaults.standard.removeObject(forKey: profileKey)
        UserDefaults.standard.removeObject(forKey: photoKey)
        print("🗑️ Profile cleared")
    }

    /// Exports profile as JSON string
    func exportProfileJSON() -> String? {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(profile)
            return String(data: data, encoding: .utf8)
        } catch {
            print("❌ Error exporting profile: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Fatigue Index Helpers

    /// Calculates a personalized fatigue modifier based on user profile
    /// Used for adjusting velocity loss thresholds and training recommendations
    func calculateFatigueModifier() -> Double {
        var modifier = 1.0

        // Age factor
        modifier *= profile.ageIntensityModifier

        // Gender factor
        modifier *= profile.genderRecoveryModifier

        // BMI factor (optional - can affect recovery)
        if let bmi = profile.bmi {
            switch bmi {
            case ..<18.5: modifier *= 0.95  // Underweight - conservative
            case 18.5..<25: modifier *= 1.0  // Normal - optimal
            case 25..<30: modifier *= 0.95  // Overweight - slightly reduced
            default: modifier *= 0.90  // Obese - more conservative
            }
        }

        return modifier
    }

    /// Returns a recommended velocity loss threshold based on profile
    func recommendedVelocityLossThreshold() -> Double {
        let baseThreshold = 20.0  // Standard 20% VL threshold
        let modifier = calculateFatigueModifier()

        return baseThreshold * modifier
    }
}
