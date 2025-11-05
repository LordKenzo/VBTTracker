//
//  SettingsManager.swift
//  VBTTracker
//
//  Gestione centralizzata impostazioni app con persistenza
//

import Foundation
import Combine
import SwiftUI

class SettingsManager: ObservableObject {
    static let shared = SettingsManager()
    
    // MARK: - Published Properties
    @Published var repLookAheadMs: Double {
        didSet { save() }
    }

    @Published var velocityMeasurementMode: VBTRepDetector.VelocityMeasurementMode {
        didSet { save() }
    }

    // Velocity Ranges (da letteratura scientifica - panca piana)
    @Published var velocityRanges: VelocityRanges {
        didSet { save() }
    }
    
    // Velocity Loss Configuration
    @Published var velocityLossThreshold: Double {
        didSet { save() }
    }
    @Published var stopOnVelocityLoss: Bool {
        didSet { save() }
    }
    
    // Audio Feedback
    @Published var voiceFeedbackEnabled: Bool {
        didSet { save() }
    }
    @Published var voiceVolume: Double {
        didSet { save() }
    }
    @Published var voiceRate: Double {
        didSet { save() }
    }
    @Published var voiceLanguage: String {
        didSet { save() }
    }
    
    // Sensor Configuration
    @Published var lastConnectedSensorMAC: String? {
        didSet { save() }
    }
    @Published var lastConnectedSensorName: String? {
        didSet { save() }
    }
    
    // Calibration (stored separately for data integrity)
    @Published var savedCalibration: CalibrationData? {
        didSet { saveCalibration() }
    }
    
    // Rep Detection Sensitivity
    @Published var repMinVelocity: Double {
        didSet { save() }
    }
    @Published var repMinPeakVelocity: Double {
        didSet { save() }
    }
    @Published var repMinAcceleration: Double {
        didSet { save() }
    }
    
    /// Tempo minimo tra due rep consecutive (secondi)
    @Published var repMinTimeBetween: Double {
        didSet { save() }
    }

    /// Durata minima fase concentrica (secondi)
    @Published var repMinDuration: Double {
        didSet { save() }
    }

    /// Ampiezza minima fase concentrica (g)
    @Published var repMinAmplitude: Double {
        didSet { save() }
    }

    /// Smoothing window size (campioni)
    @Published var repSmoothingWindow: Int {
        didSet { save() }
    }
    
    /// Soglia minima discesa per iniziare eccentrica (g, valore assoluto)
    @Published var repEccentricThreshold: Double {
        didSet { save() }
    }
    
    // MARK: - Ultimo sensore
    @Published var lastConnectedPeripheralID: String? {
        didSet { save() }
    }

    private func loadLastPeripheralID() {
        lastConnectedPeripheralID = UserDefaults.standard.string(forKey: Keys.lastPeripheralID)
    }
    
    
    // MARK: - UserDefaults Keys
    
    private enum Keys {
        static let velocityRanges = "velocityRanges"
        static let velocityLossThreshold = "velocityLossThreshold"
        static let stopOnVelocityLoss = "stopOnVelocityLoss"
        static let voiceFeedbackEnabled = "voiceFeedbackEnabled"
        static let voiceVolume = "voiceVolume"
        static let voiceRate = "voiceRate"
        static let voiceLanguage = "voiceLanguage"
        static let lastSensorMAC = "lastSensorMAC"
        static let lastSensorName = "lastSensorName"
        static let calibrationData = "calibrationData"
        static let repMinVelocity = "repMinVelocity"
        static let repMinPeakVelocity = "repMinPeakVelocity"
        static let repMinAcceleration = "repMinAcceleration"
        static let velocityMode = "velocityMode"
        static let repMinTimeBetween = "repMinTimeBetween"
        static let repMinDuration = "repMinDuration"
        static let repMinAmplitude = "repMinAmplitude"
        static let repSmoothingWindow = "repSmoothingWindow"
        static let repEccentricThreshold = "repEccentricThreshold"
        static let repLookAheadMs = "repLookAheadMs"
        static let lastPeripheralID = "lastPeripheralID"
    }
    
    // MARK: - Initialization
    
    private init() {
        // INIT senza usare self - prima assegna, POI stampa
        let loadedRanges = SettingsManager.loadVelocityRanges()
        let loadedThreshold = UserDefaults.standard.double(forKey: Keys.velocityLossThreshold)
        let loadedStopOnLoss = UserDefaults.standard.bool(forKey: Keys.stopOnVelocityLoss)
        let loadedVoiceEnabled = UserDefaults.standard.object(forKey: Keys.voiceFeedbackEnabled) as? Bool ?? true
        let loadedVolume = UserDefaults.standard.double(forKey: Keys.voiceVolume)
        let loadedRate = UserDefaults.standard.double(forKey: Keys.voiceRate)
        let loadedLanguage = UserDefaults.standard.string(forKey: Keys.voiceLanguage) ?? "it-IT"
        let loadedMAC = UserDefaults.standard.string(forKey: Keys.lastSensorMAC)
        let loadedName = UserDefaults.standard.string(forKey: Keys.lastSensorName)
        let loadedCalibration = SettingsManager.loadCalibration()
        
        // Rep Sensitivity
        let loadedMinVel = UserDefaults.standard.double(forKey: Keys.repMinVelocity)
        let loadedMinPeak = UserDefaults.standard.double(forKey: Keys.repMinPeakVelocity)
        let loadedMinAccel = UserDefaults.standard.double(forKey: Keys.repMinAcceleration)
        let loadedEccentricThreshold = UserDefaults.standard.double(forKey: Keys.repEccentricThreshold)
           repEccentricThreshold = loadedEccentricThreshold == 0 ? 0.15 : loadedEccentricThreshold  // Default 0.15g
        
        

        repMinVelocity = loadedMinVel == 0 ? 0.10 : loadedMinVel
        repMinPeakVelocity = loadedMinPeak == 0 ? 0.15 : loadedMinPeak
        repMinAcceleration = loadedMinAccel == 0 ? 2.5 : loadedMinAccel
        
        // Ora assegna tutto
        velocityRanges = loadedRanges
        velocityLossThreshold = loadedThreshold == 0 ? 20.0 : loadedThreshold
        stopOnVelocityLoss = loadedStopOnLoss
        voiceFeedbackEnabled = loadedVoiceEnabled
        voiceVolume = loadedVolume == 0 ? 0.7 : loadedVolume
        voiceRate = loadedRate == 0 ? 0.5 : loadedRate
        voiceLanguage = loadedLanguage
        lastConnectedSensorMAC = loadedMAC
        lastConnectedSensorName = loadedName
        savedCalibration = loadedCalibration
        
        let loadedTimeBetween = UserDefaults.standard.double(forKey: Keys.repMinTimeBetween)
        repMinTimeBetween = loadedTimeBetween == 0 ? 0.8 : loadedTimeBetween  // Default 0.8s
        
        let loadedDuration = UserDefaults.standard.double(forKey: Keys.repMinDuration)
        repMinDuration = loadedDuration == 0 ? 0.3 : loadedDuration  // Default 0.3s
        
        let loadedAmplitude = UserDefaults.standard.double(forKey: Keys.repMinAmplitude)
        repMinAmplitude = loadedAmplitude == 0 ? 0.45 : loadedAmplitude  // Default 0.45g
        
        let loadedWindow = UserDefaults.standard.integer(forKey: Keys.repSmoothingWindow)
        repSmoothingWindow = loadedWindow == 0 ? 10 : loadedWindow  // Default 10
        
        let loadedLookAhead = UserDefaults.standard.double(forKey: Keys.repLookAheadMs)
        repLookAheadMs = loadedLookAhead == 0 ? 200.0 : loadedLookAhead
        
        let loadedVelocityMode = UserDefaults.standard.string(forKey: Keys.velocityMode) ?? "concentricOnly"
           velocityMeasurementMode = loadedVelocityMode == "fullROM" ? .fullROM : .concentricOnly
        
        loadLastPeripheralID()

           
        print("✅ SettingsManager inizializzato")
    }
    
    // MARK: - Save/Load Methods
    
    private func save() {
        // Velocity Ranges
        if let encoded = try? JSONEncoder().encode(velocityRanges) {
            UserDefaults.standard.set(encoded, forKey: Keys.velocityRanges)
        }
        
        // Rep Sensitivity
        UserDefaults.standard.set(repMinVelocity, forKey: Keys.repMinVelocity)
        UserDefaults.standard.set(repMinPeakVelocity, forKey: Keys.repMinPeakVelocity)
        UserDefaults.standard.set(repMinAcceleration, forKey: Keys.repMinAcceleration)
        
        // Velocity Loss
        UserDefaults.standard.set(velocityLossThreshold, forKey: Keys.velocityLossThreshold)
        UserDefaults.standard.set(stopOnVelocityLoss, forKey: Keys.stopOnVelocityLoss)
        
        // Audio
        UserDefaults.standard.set(voiceFeedbackEnabled, forKey: Keys.voiceFeedbackEnabled)
        UserDefaults.standard.set(voiceVolume, forKey: Keys.voiceVolume)
        UserDefaults.standard.set(voiceRate, forKey: Keys.voiceRate)
        UserDefaults.standard.set(voiceLanguage, forKey: Keys.voiceLanguage)
        
        // Sensor
        UserDefaults.standard.set(lastConnectedSensorMAC, forKey: Keys.lastSensorMAC)
        UserDefaults.standard.set(lastConnectedSensorName, forKey: Keys.lastSensorName)
        
        // Rep Detection
        UserDefaults.standard.set(repMinTimeBetween, forKey: Keys.repMinTimeBetween)
        UserDefaults.standard.set(repMinDuration, forKey: Keys.repMinDuration)
        UserDefaults.standard.set(repMinAmplitude, forKey: Keys.repMinAmplitude)
        UserDefaults.standard.set(repSmoothingWindow, forKey: Keys.repSmoothingWindow)
        UserDefaults.standard.set(repEccentricThreshold, forKey: Keys.repEccentricThreshold)
        UserDefaults.standard.set(repLookAheadMs, forKey: Keys.repLookAheadMs)

        UserDefaults.standard.set(lastConnectedPeripheralID, forKey: Keys.lastPeripheralID)
        
        let modeString = velocityMeasurementMode == .fullROM ? "fullROM" : "concentricOnly"
          UserDefaults.standard.set(modeString, forKey: Keys.velocityMode)
        
    }
    
    private static func loadVelocityRanges() -> VelocityRanges {
        if let data = UserDefaults.standard.data(forKey: Keys.velocityRanges),
           let ranges = try? JSONDecoder().decode(VelocityRanges.self, from: data) {
            return ranges
        }
        return VelocityRanges.defaultRanges
    }
    
    private func saveCalibration() {
        if let calibration = savedCalibration,
           let encoded = try? JSONEncoder().encode(calibration) {
            UserDefaults.standard.set(encoded, forKey: Keys.calibrationData)
            print("💾 Calibrazione salvata")
        } else {
            UserDefaults.standard.removeObject(forKey: Keys.calibrationData)
            print("🗑️ Calibrazione rimossa")
        }
    }
    
    private static func loadCalibration() -> CalibrationData? {
        if let data = UserDefaults.standard.data(forKey: Keys.calibrationData),
           let calibration = try? JSONDecoder().decode(CalibrationData.self, from: data) {
            print("📥 Calibrazione caricata")
            return calibration
        }
        return nil
    }
    
    // MARK: - Helper Methods
    
    func resetToDefaults() {
        velocityRanges = VelocityRanges.defaultRanges
        velocityLossThreshold = 20.0
        stopOnVelocityLoss = false
        voiceFeedbackEnabled = true
        voiceVolume = 0.7
        voiceRate = 0.5
        repMinVelocity = 0.10
        repMinPeakVelocity = 0.15
        repMinAcceleration = 2.5
        voiceLanguage = "it-IT"
        velocityMeasurementMode = .concentricOnly
        repMinTimeBetween = 0.8
        repMinDuration = 0.45
        repMinAmplitude = 0.45
        repSmoothingWindow = 10
        repEccentricThreshold = 0.15

        print("🔄 Impostazioni resettate ai valori predefiniti")
    }
    
    func getTrainingZone(for velocity: Double) -> TrainingZone {
        if velocityRanges.maxStrength.contains(velocity) {
            return .maxStrength
        } else if velocityRanges.strength.contains(velocity) {
            return .strength
        } else if velocityRanges.strengthSpeed.contains(velocity) {
            return .strengthSpeed
        } else if velocityRanges.speed.contains(velocity) {
            return .speed
        } else if velocity >= velocityRanges.maxSpeed.lowerBound {
            return .maxSpeed
        } else {
            return .tooSlow
        }
    }
}

// MARK: - Supporting Types

struct VelocityRanges: Codable, Equatable {
    var maxStrength: ClosedRange<Double>      // Forza Massima
    var strength: ClosedRange<Double>         // Forza
    var strengthSpeed: ClosedRange<Double>    // Forza-Velocità
    var speed: ClosedRange<Double>            // Velocità
    var maxSpeed: ClosedRange<Double>         // Velocità Massima
    
    // Valori predefiniti da letteratura scientifica (panca piana)
    static let defaultRanges = VelocityRanges(
        maxStrength: 0.15...0.30,      // González-Badillo & Sánchez-Medina, 2010
        strength: 0.30...0.50,         // Pareja-Blanco et al., 2017
        strengthSpeed: 0.50...0.75,    // Banyard et al., 2019
        speed: 0.75...1.00,            // Weakley et al., 2021
        maxSpeed: 1.00...2.00
    )
    
    // Custom Codable per gestire ClosedRange
    enum CodingKeys: String, CodingKey {
        case maxStrength, strength, strengthSpeed, speed, maxSpeed
    }
    
    init(maxStrength: ClosedRange<Double>,
         strength: ClosedRange<Double>,
         strengthSpeed: ClosedRange<Double>,
         speed: ClosedRange<Double>,
         maxSpeed: ClosedRange<Double>) {
        self.maxStrength = maxStrength
        self.strength = strength
        self.strengthSpeed = strengthSpeed
        self.speed = speed
        self.maxSpeed = maxSpeed
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        let maxStrengthArray = try container.decode([Double].self, forKey: .maxStrength)
        let strengthArray = try container.decode([Double].self, forKey: .strength)
        let strengthSpeedArray = try container.decode([Double].self, forKey: .strengthSpeed)
        let speedArray = try container.decode([Double].self, forKey: .speed)
        let maxSpeedArray = try container.decode([Double].self, forKey: .maxSpeed)
        
        self.maxStrength = maxStrengthArray[0]...maxStrengthArray[1]
        self.strength = strengthArray[0]...strengthArray[1]
        self.strengthSpeed = strengthSpeedArray[0]...strengthSpeedArray[1]
        self.speed = speedArray[0]...speedArray[1]
        self.maxSpeed = maxSpeedArray[0]...maxSpeedArray[1]
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode([maxStrength.lowerBound, maxStrength.upperBound], forKey: .maxStrength)
        try container.encode([strength.lowerBound, strength.upperBound], forKey: .strength)
        try container.encode([strengthSpeed.lowerBound, strengthSpeed.upperBound], forKey: .strengthSpeed)
        try container.encode([speed.lowerBound, speed.upperBound], forKey: .speed)
        try container.encode([maxSpeed.lowerBound, maxSpeed.upperBound], forKey: .maxSpeed)
    }
}

enum TrainingZone: String, CaseIterable {
    case tooSlow = "Troppo Lento"
    case maxStrength = "Forza Massima"
    case strength = "Forza"
    case strengthSpeed = "Forza-Velocità"
    case speed = "Velocità"
    case maxSpeed = "Velocità Massima"
    
    var color: Color {
        switch self {
        case .tooSlow: return .gray
        case .maxStrength: return .red
        case .strength: return .orange
        case .strengthSpeed: return .yellow
        case .speed: return .green
        case .maxSpeed: return .blue
        }
    }
    
    var icon: String {
        switch self {
        case .tooSlow: return "tortoise.fill"
        case .maxStrength: return "hammer.fill"
        case .strength: return "dumbbell.fill"
        case .strengthSpeed: return "bolt.fill"
        case .speed: return "hare.fill"
        case .maxSpeed: return "bolt.circle.fill"
        }
    }
    
    var description: String {
        switch self {
        case .tooSlow: return "Velocità insufficiente"
        case .maxStrength: return "0.15-0.30 m/s - Carichi massimali"
        case .strength: return "0.30-0.50 m/s - Sviluppo forza"
        case .strengthSpeed: return "0.50-0.75 m/s - Potenza"
        case .speed: return "0.75-1.00 m/s - Velocità esplosiva"
        case .maxSpeed: return ">1.00 m/s - Velocità massima"
        }
    }
    
}
