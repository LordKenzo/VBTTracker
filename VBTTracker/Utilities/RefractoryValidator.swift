//
//  RefractoryValidator.swift
//  VBTTracker
//
//  Utility for validating refractory period between reps
//  Ensures minimum time between detected repetitions to avoid false positives
//

import Foundation

/// Validates minimum time between consecutive reps
struct RefractoryValidator {

    // MARK: - Properties

    /// Minimum time interval required between consecutive reps (seconds)
    private let minTimeBetweenReps: TimeInterval

    /// Timestamp of the last validated rep
    private(set) var lastRepTime: Date?

    // MARK: - Initialization

    /// Creates a new refractory validator
    /// - Parameter minTimeBetweenReps: Minimum time interval required between reps (default: 0.8s)
    init(minTimeBetweenReps: TimeInterval = 0.8) {
        self.minTimeBetweenReps = minTimeBetweenReps
    }

    // MARK: - Validation

    /// Checks if enough time has passed since the last rep
    /// - Parameter currentTime: The current timestamp to check against
    /// - Returns: `true` if the refractory period has passed, `false` otherwise
    func canDetectRep(at currentTime: Date = Date()) -> Bool {
        guard let lastRep = lastRepTime else {
            return true // No previous rep, allow detection
        }

        let timeSinceLastRep = currentTime.timeIntervalSince(lastRep)
        return timeSinceLastRep >= minTimeBetweenReps
    }

    /// Records a new rep detection timestamp
    /// - Parameter timestamp: The timestamp of the detected rep (default: now)
    mutating func recordRep(at timestamp: Date = Date()) {
        lastRepTime = timestamp
    }

    /// Resets the validator state (clears last rep time)
    mutating func reset() {
        lastRepTime = nil
    }

    // MARK: - Info

    /// Returns the time elapsed since the last rep (nil if no previous rep)
    func timeSinceLastRep(from currentTime: Date = Date()) -> TimeInterval? {
        guard let lastRep = lastRepTime else { return nil }
        return currentTime.timeIntervalSince(lastRep)
    }
}
