//
//  RepDetectorProtocol.swift
//  VBTTracker
//
//  Protocol defining the common interface for rep detection systems
//  Supports both accelerometer-based and distance-based detection
//

import Foundation

// MARK: - Shared Phase Enum

/// Common phases for rep detection across all detector types
enum DetectorPhase {
    case idle
    case descending
    case ascending
    case completed
}

// MARK: - Rep Detection Protocol

/// Common interface for all rep detection implementations
protocol RepDetectorProtocol: AnyObject {

    // MARK: - Configuration

    /// Sample rate in Hz (e.g., 50, 100, 200)
    var sampleRateHz: Double { get set }

    /// Number of samples to look ahead for direction detection
    var lookAheadSamples: Int { get }

    // MARK: - Callbacks

    /// Called when movement phase changes (descending, ascending, etc.)
    var onPhaseChange: ((DetectorPhase) -> Void)? { get set }

    /// Called when bar is unracked (first significant movement detected)
    var onUnrack: (() -> Void)? { get set }

    // MARK: - State

    /// Timestamp of the last detected rep (for refractory period validation)
    var lastRepTime: Date? { get }

    // MARK: - Methods

    /// Reset all internal state (samples, phase tracking, etc.)
    func reset()
}

// MARK: - Default Implementations

extension RepDetectorProtocol {

    /// Default implementation for smoothing window size
    /// Can be overridden by conforming types
    var windowSize: Int {
        max(5, SettingsManager.shared.repSmoothingWindow)
    }
}
