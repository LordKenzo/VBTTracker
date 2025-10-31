//
//  VBTRepDetector.swift
//  VBTTracker
//
//  âœ… Scientific VBT: MPV/PPV corretti (SÃ¡nchez-Medina et al. 2010)
//  âœ… Integrato con LearnedPatternLibrary
//  âœ… Compatibile con Swift 6
//

import Foundation

final class VBTRepDetector {

    // MARK: - Config

    enum VelocityMeasurementMode {
        case concentricOnly
        case fullROM
    }

    var velocityMode: VelocityMeasurementMode = .concentricOnly
    var learnedPattern: LearnedPattern?
    var onPhaseChange: ((Phase) -> Void)?

    // MARK: - Parametri adattivi

    private var windowSize: Int {
        max(3, SettingsManager.shared.repSmoothingWindow)
    }

    private var minAmplitude: Double {
        if let pattern = learnedPattern {
            return pattern.dynamicMinAmplitude
        } else if isInWarmup {
            return SettingsManager.shared.repMinAmplitude * 0.4
        } else if let learned = learnedMinAmplitude {
            return learned * 0.5
        } else {
            return SettingsManager.shared.repMinAmplitude * 0.5
        }
    }

    private var idleThreshold: Double {
        learnedPattern?.restThreshold ?? 0.08
    }

    private let warmupReps = 3
    private let DEFAULT_MIN_CONCENTRIC: TimeInterval = 0.40
    private let DEFAULT_REFRACTORY: TimeInterval = 0.80
    private let MAX_MPV = 2.5
    private let MAX_PPV = 3.0

    private func minConcentricDurationSec() -> TimeInterval {
        let safety = DEFAULT_MIN_CONCENTRIC
        if let rom = learnedPattern?.estimatedROM, rom > 0 {
            let vmax = 2.5
            return max(safety, rom / vmax)
        }
        return safety
    }

    private var minRefractory: TimeInterval { DEFAULT_REFRACTORY }

    // MARK: - Stato

    struct AccelMA { let timestamp: Date; let accZ: Double }

    private var samples: [AccelerationSample] = []
    private var smoothedValues: [Double] = []
    private var lastPeak: (value: Double, index: Int, time: Date)?
    private var lastValley: (value: Double, index: Int, time: Date)?
    private var lastRepTime: Date?
    private var lastMovementTime: Date?
    private var isFirstMovement = true
    private var isInWarmup = true
    private var repAmplitudes: [Double] = []
    private var learnedMinAmplitude: Double?

    private enum Direction { case none, up, down }
    private var currentDirection: Direction = .none
    private var lastAnnouncedDirection: Direction = .none
    var hasAnnouncedUnrack = false

    // MARK: - Fase concentrica

    private struct ConcentricSample {
        let timestamp: Date
        let accZ: Double
        let smoothedAccZ: Double
    }

    private var concentricSamples: [ConcentricSample] = []
    private var isTrackingConcentric = false

    enum Phase { case idle, descending, ascending, completed }

    // MARK: - API

    func addSample(accZ: Double, timestamp: Date) -> RepDetectionResult {
        samples.append(AccelerationSample(timestamp: timestamp, accZ: accZ))
        if samples.count > 200 { samples.removeFirst() }

        let smoothed = calculateMovingAverage()
        smoothedValues.append(smoothed)
        if smoothedValues.count > 200 { smoothedValues.removeFirst() }

        if isTrackingConcentric {
            concentricSamples.append(.init(timestamp: timestamp, accZ: accZ, smoothedAccZ: smoothed))
        }

        return detectRep()
    }

    func reset() {
        samples.removeAll()
        smoothedValues.removeAll()
        lastPeak = nil
        lastValley = nil
        lastRepTime = nil
        isFirstMovement = true
        isInWarmup = true
        repAmplitudes.removeAll()
        learnedMinAmplitude = nil
        currentDirection = .none
        hasAnnouncedUnrack = false
        lastAnnouncedDirection = .none
        concentricSamples.removeAll()
        isTrackingConcentric = false
    }

    func getSamples() -> [AccelerationSample] { samples }

    // MARK: - Detection principale

    private func detectRep() -> RepDetectionResult {
        guard smoothedValues.count >= 5 else {
            return RepDetectionResult(repDetected: false, currentValue: smoothedValues.last ?? 0,
                                      meanPropulsiveVelocity: nil, peakPropulsiveVelocity: nil, duration: nil)
        }

        let current = smoothedValues.last!
        let idx = smoothedValues.count - 1
        let now = Date()

        let newDirection = detectDirection()
        var repDetected = false
        var mpv: Double? = nil
        var ppv: Double? = nil
        var duration: Double? = nil

        if newDirection != currentDirection && newDirection != .none {

            // Inversione â†’ VALLE
            if newDirection == .up && currentDirection == .down {
                let valley = findRecentMin(lookback: 3)
                lastValley = (valley, idx, now)
                concentricSamples.removeAll()
                isTrackingConcentric = true
                onPhaseChange?(.ascending)
            }

            // Inversione â†’ PICCO
            if newDirection == .down && currentDirection == .up {
                let peak = findRecentMax(lookback: 3)
                lastPeak = (peak, idx, now)
                isTrackingConcentric = false

                if let valley = lastValley, let peakT = lastPeak {
                    let amplitude = peakT.value - valley.value
                    let concDur = peakT.time.timeIntervalSince(valley.time)

                    let refractoryOK = lastRepTime == nil || now.timeIntervalSince(lastRepTime!) >= minRefractory
                    let ampOK = amplitude >= minAmplitude
                    let durOK = concDur >= minConcentricDurationSec()

                    if isFirstMovement {
                        isFirstMovement = false
                    } else if ampOK && refractoryOK && durOK {
                        if concentricSamples.count > 5 {
                            (mpv, ppv) = calculatePropulsiveVelocities(from: concentricSamples)
                            (mpv, ppv) = clampVBT(mpv, ppv)
                        }
                        repDetected = true
                        duration = concDur
                        lastRepTime = now

                        repAmplitudes.append(amplitude)
                        if repAmplitudes.count == warmupReps {
                            learnedMinAmplitude = repAmplitudes.reduce(0, +) / Double(warmupReps)
                            isInWarmup = false
                        }
                    }
                }
                onPhaseChange?(.descending)
            }
            currentDirection = newDirection
        }

        return RepDetectionResult(repDetected: repDetected, currentValue: current,
                                  meanPropulsiveVelocity: mpv, peakPropulsiveVelocity: ppv,
                                  duration: duration)
    }

    // MARK: - MPV/PPV

    private func calculatePropulsiveVelocities(from src: [ConcentricSample]) -> (Double?, Double?) {
        guard src.count >= 3 else { return (nil, nil) }
        var a: [Double] = []
        var t: [TimeInterval] = []
        let t0 = src.first!.timestamp

        for s in src {
            var acc = s.smoothedAccZ * 9.81
            if s.smoothedAccZ > 0.8 { acc = (s.smoothedAccZ - 1.0) * 9.81 }
            else if s.smoothedAccZ < -0.8 { acc = (s.smoothedAccZ + 1.0) * 9.81 }
            a.append(acc)
            t.append(s.timestamp.timeIntervalSince(t0))
        }

        var v: [Double] = [0.0]
        for i in 1..<a.count {
            let dt = max(0, t[i] - t[i-1])
            v.append(v.last! + ((a[i-1] + a[i]) * 0.5 * dt))
        }

        let end = a.firstIndex(where: { $0 < -9.81 }) ?? a.count - 1
        let pv = Array(v[0...end])
        guard !pv.isEmpty else { return (nil, nil) }

        let mpv = pv.reduce(0, +) / Double(pv.count)
        let ppv = pv.max() ?? 0
        return ((0.05...MAX_MPV).contains(mpv) ? mpv : nil,
                (0.05...MAX_PPV).contains(ppv) ? ppv : nil)
    }

    private func clampVBT(_ mpv: Double?, _ ppv: Double?) -> (Double?, Double?) {
        (mpv.map { min($0, MAX_MPV) }, ppv.map { min($0, MAX_PPV) })
    }

    // MARK: - Direzione

    private func detectDirection() -> Direction {
        guard smoothedValues.count >= 4 else { return .none }
        let last4 = Array(smoothedValues.suffix(4))
        if abs(last4.last!) > idleThreshold { lastMovementTime = Date() }

        var ups = 0, downs = 0
        for i in 1..<last4.count {
            let d = last4[i] - last4[i-1]
            if d > 0.03 { ups += 1 } else if d < -0.03 { downs += 1 }
        }
        if ups >= 2 && ups > downs { return .up }
        if downs >= 2 && downs > ups { return .down }
        return currentDirection
    }

    private func findRecentMax(lookback: Int) -> Double {
        smoothedValues.suffix(lookback).max() ?? (smoothedValues.last ?? 0)
    }
    private func findRecentMin(lookback: Int) -> Double {
        smoothedValues.suffix(lookback).min() ?? (smoothedValues.last ?? 0)
    }

    private func calculateMovingAverage() -> Double {
        guard samples.count >= windowSize else { return samples.last?.accZ ?? 0 }
        return samples.suffix(windowSize).map(\.accZ).reduce(0, +) / Double(windowSize)
    }
}

// MARK: - Risultato

struct RepDetectionResult {
    let repDetected: Bool
    let currentValue: Double
    let meanPropulsiveVelocity: Double?
    let peakPropulsiveVelocity: Double?
    let duration: Double?
    var peakVelocity: Double? { peakPropulsiveVelocity ?? meanPropulsiveVelocity }
}

// MARK: - Pattern Learning Integration

extension VBTRepDetector {
    func recognizePatternIfPossible() {
        guard samples.count > 30 else { return }

        Task { @MainActor in
            if let match = LearnedPatternLibrary.shared.matchPattern(for: samples) {
                let dist = LearnedPatternLibrary.shared.distance(match.featureVector, match.featureVector)
                if dist < 0.35 {
                    print("ðŸ¤– Pattern riconosciuto: \(match.label) â€” \(match.repCount) reps")
                    learnedPattern = LearnedPattern(from: match)
                } else {
                    print("â„¹ï¸ Nessun pattern simile (dist \(String(format: "%.3f", dist)))")
                }
            }
        }
    }

    func savePatternSequence(label: String, repCount: Int, loadPercentage: Double? = nil) {
        guard repCount > 0 else { return }

        let amp = (samples.map { $0.accZ }.max() ?? 0) - (samples.map { $0.accZ }.min() ?? 0)
        let duration = (samples.last?.timestamp.timeIntervalSince(samples.first?.timestamp ?? Date())) ?? 0
        let features = samples.isEmpty ? [] : samples.suffix(100).map { $0.accZ }

        let new = PatternSequence(
            id: UUID(),
            date: Date(),
            label: label,
            repCount: repCount,
            loadPercentage: loadPercentage,
            avgDuration: duration / Double(repCount),
            avgAmplitude: amp,
            avgMPV: 0.5,
            avgPPV: 0.6,
            featureVector: features
        )

        Task { @MainActor in
            LearnedPatternLibrary.shared.addPattern(new)
            print("ðŸ’¾ Pattern salvato: \(label) â€” \(repCount) reps")
        }
    }
}
