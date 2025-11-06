//
//  DistanceBasedRepDetector.swift
//  VBTTracker
//
//  Rilevatore di ripetizioni basato su distanza diretta
//  Usa dati da sensore laser VL53L0X (Arduino Nano 33 BLE)
//  Più semplice e preciso rispetto all'integrazione dell'accelerazione
//

import Foundation
import Combine

final class DistanceBasedRepDetector: ObservableObject {

    // MARK: - Configuration

    var sampleRateHz: Double = 50.0
    var lookAheadSamples: Int = 10

    // ROM expected (in mm)
    var expectedROM: Double {
        if SettingsManager.shared.useCustomROM {
            return SettingsManager.shared.customROM * 1000.0 // converti m -> mm
        }
        return 500.0 // default 500mm per bench press
    }

    private var minROM: Double {
        let tolerance = SettingsManager.shared.customROMTolerance
        return expectedROM * (1.0 - tolerance)
    }

    private var maxROM: Double {
        let tolerance = SettingsManager.shared.customROMTolerance
        return expectedROM * (1.0 + tolerance)
    }

    // Soglie
    private let MIN_VELOCITY_THRESHOLD = 50.0  // mm/s minimo per rilevare movimento
    private let MIN_CONCENTRIC_DURATION: TimeInterval = 0.3
    private let MIN_TIME_BETWEEN_REPS: TimeInterval = 0.8

    // MARK: - Callbacks

    enum Phase { case idle, descending, ascending, completed }
    var onPhaseChange: ((Phase) -> Void)?
    var onUnrack: (() -> Void)?

    // Metriche VBT per la rep completata
    struct RepMetrics {
        let meanPropulsiveVelocity: Double  // MPV (m/s)
        let peakPropulsiveVelocity: Double  // PPV (m/s)
        let displacement: Double            // ROM (m)
        let concentricDuration: TimeInterval
        let eccentricDuration: TimeInterval
        let totalDuration: TimeInterval
    }

    var onRepDetected: ((RepMetrics) -> Void)?

    // MARK: - Internal State

    private struct DistanceSample {
        let timestamp: Date
        let distance: Double  // mm
        let velocity: Double  // mm/s (calcolata)
    }

    private var samples: [DistanceSample] = []
    private var smoothedDistances: [Double] = []

    private enum CycleState {
        case waitingDescent    // Attende inizio eccentrica
        case descending        // In fase eccentrica
        case waitingAscent     // Attende inizio concentrica
        case ascending         // In fase concentrica
    }

    private var state: CycleState = .waitingDescent
    private var lastRepTime: Date?

    // Tracking fase eccentrica
    private var eccentricStartTime: Date?
    private var eccentricStartDistance: Double?

    // Tracking fase concentrica
    private var concentricSamples: [DistanceSample] = []
    private var concentricStartTime: Date?
    private var concentricStartDistance: Double?
    private var concentricPeakDistance: Double?

    // Baseline (distanza a riposo)
    private var baselineDistance: Double?
    private let BASELINE_SAMPLES = 20

    // Smoothing window
    private var windowSize: Int {
        max(5, SettingsManager.shared.repSmoothingWindow)
    }

    // MARK: - Public API

    func reset() {
        samples.removeAll()
        smoothedDistances.removeAll()
        state = .waitingDescent
        lastRepTime = nil
        eccentricStartTime = nil
        eccentricStartDistance = nil
        concentricSamples.removeAll()
        concentricStartTime = nil
        concentricStartDistance = nil
        concentricPeakDistance = nil
        baselineDistance = nil
        print("🔄 DistanceBasedRepDetector reset")
    }

    /// Processa un nuovo campione di distanza
    /// - Parameters:
    ///   - distance: Distanza in millimetri dal sensore
    ///   - velocity: Velocità in mm/s calcolata dall'Arduino
    ///   - movementState: Stato movimento rilevato dall'Arduino
    ///   - timestamp: Timestamp del campione
    func processSample(distance: Double, velocity: Double, movementState: MovementState, timestamp: Date) {
        // Spike filtering: scarta letture improbabili
        if let lastSample = samples.last {
            let distanceDelta = abs(distance - lastSample.distance)
            // Se la distanza cambia più di 1000mm in un campione (~20ms), è uno spike
            if distanceDelta > 1000 {
                print("⚠️ Spike rilevato: \(String(format: "%.1f", lastSample.distance))mm → \(String(format: "%.1f", distance))mm, scartato")
                return
            }
        }

        let sample = DistanceSample(timestamp: timestamp, distance: distance, velocity: velocity)
        samples.append(sample)

        // Mantieni solo ultimi N secondi (es. 10s @50Hz = 500 campioni)
        let maxSamples = Int(sampleRateHz * 10)
        if samples.count > maxSamples {
            samples.removeFirst(samples.count - maxSamples)
        }

        // Smoothing
        updateSmoothedValues()

        // Stabilisci baseline (prime 20 letture)
        if baselineDistance == nil, samples.count >= BASELINE_SAMPLES {
            baselineDistance = samples.prefix(BASELINE_SAMPLES).map(\.distance).reduce(0, +) / Double(BASELINE_SAMPLES)
            print("📏 Baseline stabilita: \(String(format: "%.1f", baselineDistance!)) mm")
            onUnrack?()
        }

        // Processa stato usando lo stato movimento dall'Arduino
        guard baselineDistance != nil, samples.count >= windowSize else { return }
        processStateFromArduino(currentSample: sample, arduinoState: movementState)
    }

    // MARK: - Private Methods

    private func calculateVelocity(distance: Double, timestamp: Date) -> Double {
        guard let lastSample = samples.last else { return 0.0 }

        let dt = timestamp.timeIntervalSince(lastSample.timestamp)
        guard dt > 0 else { return 0.0 }

        let dd = distance - lastSample.distance
        return dd / dt  // mm/s
    }

    private func updateSmoothedValues() {
        guard samples.count >= windowSize else { return }

        let recentDistances = samples.suffix(windowSize).map(\.distance)
        let smoothed = recentDistances.reduce(0, +) / Double(recentDistances.count)
        smoothedDistances.append(smoothed)

        // Mantieni solo ultimi 1000 valori smoothed
        if smoothedDistances.count > 1000 {
            smoothedDistances.removeFirst(smoothedDistances.count - 1000)
        }
    }

    /// Processa lo stato usando il movimento state dall'Arduino (più affidabile)
    private func processStateFromArduino(currentSample: DistanceSample, arduinoState: MovementState) {
        let smoothedDist = smoothedDistances.last ?? currentSample.distance

        switch state {
        case .waitingDescent:
            // Attende che Arduino rilevi approaching (eccentrica)
            if arduinoState == .approaching {
                state = .descending
                eccentricStartTime = currentSample.timestamp
                eccentricStartDistance = smoothedDist
                onPhaseChange?(.descending)
                print("⬇️ Inizio eccentrica a \(String(format: "%.1f", smoothedDist)) mm")
            }

        case .descending:
            // In eccentrica, attende che Arduino rilevi receding (concentrica)
            if arduinoState == .receding {
                state = .waitingAscent
                concentricStartTime = currentSample.timestamp
                concentricStartDistance = smoothedDist
                concentricPeakDistance = smoothedDist
                concentricSamples = [currentSample]
                print("🔄 Transizione a concentrica a \(String(format: "%.1f", smoothedDist)) mm")
            }

        case .waitingAscent:
            // Conferma l'inizio della concentrica con 3 campioni consecutivi receding
            concentricSamples.append(currentSample)

            if arduinoState == .receding, concentricSamples.count >= 3 {
                state = .ascending
                onPhaseChange?(.ascending)
                print("⬆️ Inizio concentrica confermata")
            } else if arduinoState == .approaching {
                // Falso positivo, torna a descending
                state = .descending
                concentricSamples.removeAll()
                print("🔄 Falso positivo, torna a eccentrica")
            }

        case .ascending:
            concentricSamples.append(currentSample)

            // Traccia picco massimo
            if smoothedDist > (concentricPeakDistance ?? 0) {
                concentricPeakDistance = smoothedDist
            }

            // Rileva fine concentrica quando Arduino rileva idle (fermo al top)
            if arduinoState == .idle, concentricSamples.count >= lookAheadSamples {
                tryCompleteRep(currentSample: currentSample)
            }
        }
    }

    // Metodo legacy che calcola lo stato dalla velocità (mantenuto per riferimento)
    private func processState(currentSample: DistanceSample) {
        let smoothedDist = smoothedDistances.last ?? currentSample.distance
        let velocity = currentSample.velocity

        switch state {
        case .waitingDescent:
            // Attende che la distanza inizi a diminuire (avvicinamento sensore)
            if velocity < -MIN_VELOCITY_THRESHOLD {  // Negativo = si avvicina
                state = .descending
                eccentricStartTime = currentSample.timestamp
                eccentricStartDistance = smoothedDist
                onPhaseChange?(.descending)
                print("⬇️ Inizio eccentrica a \(String(format: "%.1f", smoothedDist)) mm")
            }

        case .descending:
            // In eccentrica, attende che la velocità si inverta
            if velocity > MIN_VELOCITY_THRESHOLD {  // Positivo = si allontana
                state = .waitingAscent
                concentricStartTime = currentSample.timestamp
                concentricStartDistance = smoothedDist
                concentricPeakDistance = smoothedDist
                concentricSamples = [currentSample]
                print("🔄 Transizione a concentrica a \(String(format: "%.1f", smoothedDist)) mm")
            }

        case .waitingAscent:
            // Conferma l'inizio della concentrica
            concentricSamples.append(currentSample)

            if velocity > MIN_VELOCITY_THRESHOLD, concentricSamples.count >= 3 {
                state = .ascending
                onPhaseChange?(.ascending)
                print("⬆️ Inizio concentrica confermata")
            } else if velocity < -MIN_VELOCITY_THRESHOLD {
                // Falso positivo, torna a descending
                state = .descending
                concentricSamples.removeAll()
            }

        case .ascending:
            concentricSamples.append(currentSample)

            // Traccia picco massimo
            if smoothedDist > (concentricPeakDistance ?? 0) {
                concentricPeakDistance = smoothedDist
            }

            // Rileva fine concentrica (picco raggiunto + velocità quasi nulla)
            let isNearPeak = abs(smoothedDist - (concentricPeakDistance ?? 0)) < 10.0  // mm
            let isVelocityLow = abs(velocity) < MIN_VELOCITY_THRESHOLD

            if isNearPeak, isVelocityLow, concentricSamples.count >= lookAheadSamples {
                tryCompleteRep(currentSample: currentSample)
            }
        }
    }

    private func tryCompleteRep(currentSample: DistanceSample) {
        guard let startTime = concentricStartTime,
              let startDist = concentricStartDistance,
              let peakDist = concentricPeakDistance,
              let eccentricStart = eccentricStartTime,
              let eccentricStartDist = eccentricStartDistance
        else { return }

        let concentricDuration = currentSample.timestamp.timeIntervalSince(startTime)
        let eccentricDuration = startTime.timeIntervalSince(eccentricStart)
        let totalDuration = concentricDuration + eccentricDuration

        // Displacement (ROM) in mm
        let displacementMM = abs(peakDist - startDist)

        // Validazioni
        guard concentricDuration >= MIN_CONCENTRIC_DURATION else {
            print("❌ Rep scartata: durata concentrica troppo breve (\(String(format: "%.2f", concentricDuration))s)")
            resetCycle()
            return
        }

        guard displacementMM >= minROM, displacementMM <= maxROM else {
            print("❌ Rep scartata: ROM fuori range (\(String(format: "%.1f", displacementMM)) mm, atteso \(String(format: "%.1f", minROM))-\(String(format: "%.1f", maxROM)) mm)")
            resetCycle()
            return
        }

        // Controllo refractory period
        if let lastRep = lastRepTime, currentSample.timestamp.timeIntervalSince(lastRep) < MIN_TIME_BETWEEN_REPS {
            print("❌ Rep scartata: troppo vicina all'ultima (\(String(format: "%.2f", currentSample.timestamp.timeIntervalSince(lastRep)))s)")
            resetCycle()
            return
        }

        // Calcola velocità media e picco (solo fase propulsiva)
        let (mpv, ppv) = calculateVelocityMetrics()

        let metrics = RepMetrics(
            meanPropulsiveVelocity: mpv,
            peakPropulsiveVelocity: ppv,
            displacement: displacementMM / 1000.0,  // converti mm -> m
            concentricDuration: concentricDuration,
            eccentricDuration: eccentricDuration,
            totalDuration: totalDuration
        )

        print("✅ REP RILEVATA - ROM: \(String(format: "%.3f", metrics.displacement))m, MPV: \(String(format: "%.3f", mpv))m/s, PPV: \(String(format: "%.3f", ppv))m/s")

        lastRepTime = currentSample.timestamp
        onRepDetected?(metrics)
        onPhaseChange?(.completed)

        resetCycle()
    }

    private func calculateVelocityMetrics() -> (mpv: Double, ppv: Double) {
        guard !concentricSamples.isEmpty else { return (0.0, 0.0) }

        // Converti velocità da mm/s a m/s
        let velocities = concentricSamples.map { $0.velocity / 1000.0 }

        // PPV (Peak Propulsive Velocity) = massima velocità durante concentrica
        let ppv = velocities.max() ?? 0.0

        // MPV (Mean Propulsive Velocity) = media delle velocità positive
        let propulsiveVelocities = velocities.filter { $0 > 0 }
        let mpv = propulsiveVelocities.isEmpty ? 0.0 : propulsiveVelocities.reduce(0, +) / Double(propulsiveVelocities.count)

        return (mpv, ppv)
    }

    private func resetCycle() {
        state = .waitingDescent
        eccentricStartTime = nil
        eccentricStartDistance = nil
        concentricSamples.removeAll()
        concentricStartTime = nil
        concentricStartDistance = nil
        concentricPeakDistance = nil
        onPhaseChange?(.idle)
    }
}
