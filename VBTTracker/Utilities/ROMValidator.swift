//
//  ROMValidator.swift
//  VBTTracker
//
//  Utility for validating Range of Motion (ROM) / Displacement measurements
//  Supports both meter and millimeter units with custom ROM settings
//

import Foundation

/// Unit of measurement for ROM/displacement values
enum ROMUnit {
    case meters
    case millimeters

    /// Conversion factor to meters
    var toMeters: Double {
        switch self {
        case .meters: return 1.0
        case .millimeters: return 0.001
        }
    }
}

/// Validates displacement/ROM values against expected range
struct ROMValidator {

    // MARK: - Properties

    /// Minimum acceptable displacement/ROM
    let minDisplacement: Double

    /// Maximum acceptable displacement/ROM
    let maxDisplacement: Double

    /// Unit of measurement for the validator
    let unit: ROMUnit

    // MARK: - Initialization

    /// Creates a ROM validator with custom range
    /// - Parameters:
    ///   - min: Minimum acceptable displacement
    ///   - max: Maximum acceptable displacement
    ///   - unit: Unit of measurement (meters or millimeters)
    init(min: Double, max: Double, unit: ROMUnit = .meters) {
        self.minDisplacement = min
        self.maxDisplacement = max
        self.unit = unit
    }

    /// Creates a ROM validator from SettingsManager configuration
    /// - Parameters:
    ///   - unit: Unit of measurement for returned values
    ///   - defaultMin: Default minimum if custom ROM not enabled (in meters)
    ///   - defaultMax: Default maximum if custom ROM not enabled (in meters)
    static func fromSettings(
        unit: ROMUnit = .meters,
        defaultMin: Double = 0.20,
        defaultMax: Double = 0.80
    ) -> ROMValidator {
        let settings = SettingsManager.shared

        let (min, max): (Double, Double)
        if settings.useCustomROM {
            let rom = settings.customROM
            let tolerance = settings.customROMTolerance
            min = rom * (1.0 - tolerance)
            max = rom * (1.0 + tolerance)
        } else {
            min = defaultMin
            max = defaultMax
        }

        // Convert to target unit if needed
        switch unit {
        case .meters:
            return ROMValidator(min: min, max: max, unit: .meters)
        case .millimeters:
            return ROMValidator(min: min * 1000, max: max * 1000, unit: .millimeters)
        }
    }

    // MARK: - Validation

    /// Checks if a displacement value is within valid range
    /// - Parameter displacement: The displacement value to validate (in validator's unit)
    /// - Returns: `true` if within range, `false` otherwise
    func isValid(_ displacement: Double) -> Bool {
        return (minDisplacement...maxDisplacement).contains(displacement)
    }

    /// Validates displacement and returns detailed result
    /// - Parameter displacement: The displacement value to validate
    /// - Returns: Validation result with details
    func validate(_ displacement: Double) -> ValidationResult {
        let valid = isValid(displacement)
        return ValidationResult(
            isValid: valid,
            displacement: displacement,
            minExpected: minDisplacement,
            maxExpected: maxDisplacement,
            unit: unit
        )
    }

    // MARK: - Validation Result

    struct ValidationResult {
        let isValid: Bool
        let displacement: Double
        let minExpected: Double
        let maxExpected: Double
        let unit: ROMUnit

        var errorMessage: String? {
            guard !isValid else { return nil }

            let unitLabel = unit == .meters ? "m" : "mm"
            return "Displacement \(String(format: "%.2f", displacement))\(unitLabel) outside valid range [\(String(format: "%.2f", minExpected))-\(String(format: "%.2f", maxExpected))\(unitLabel)]"
        }
    }

    // MARK: - Unit Conversion

    /// Converts a displacement value to meters
    /// - Parameter displacement: Value in validator's unit
    /// - Returns: Value in meters
    func toMeters(_ displacement: Double) -> Double {
        return displacement * unit.toMeters
    }
}
