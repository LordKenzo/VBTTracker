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

    // MARK: - Thread Safety

    private let queue = DispatchQueue(label: "com.vbttracker.repdetector", qos: .userInitiated)

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
        let calculated = expectedROM * (1.0 - tolerance)
        // Aggiungi buffer di 10mm per evitare scarti per pochi millimetri
        return max(calculated - 10.0, 50.0)  // Minimo assoluto 50mm
    }

    private var maxROM: Double {
        let tolerance = SettingsManager.shared.customROMTolerance
        return expectedROM * (1.0 + tolerance) + 10.0  // Aggiungi buffer di 10mm
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
    private var idleStartTime: Date?
    private let BASELINE_RECALIBRATION_IDLE_TIME: TimeInterval = 3.0

    // State debouncing rimosso - Arduino lo fa già hardware-side

    // Smoothing window
    private var windowSize: Int {
        max(5, SettingsManager.shared.repSmoothingWindow)
    }

    // MARK: - Public API

    func reset() {
        queue.sync {
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
            idleStartTime = nil
            print("🔄 DistanceBasedRepDetector reset")
        }
    }

    /// Processa un nuovo campione di distanza
    /// - Parameters:
    ///   - distance: Distanza in millimetri dal sensore
    ///   - velocity: Velocità in mm/s calcolata dall'Arduino
    ///   - movementState: Stato movimento rilevato dall'Arduino
    ///   - timestamp: Timestamp del campione
    func processSample(distance: Double, velocity: Double, movementState: MovementState, timestamp: Date) {
        queue.sync {
            processSampleUnsafe(distance: distance, velocity: velocity, movementState: movementState, timestamp: timestamp)
        }
    }

    private func processSampleUnsafe(distance: Double, velocity: Double, movementState: MovementState, timestamp: Date) {
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

        guard baselineDistance != nil, samples.count >= windowSize else { return }

        // Ricalibra baseline se idle per >3s E la distanza è stabile
        if state == .waitingDescent {
            if idleStartTime == nil {
                idleStartTime = timestamp
            } else if let idleStart = idleStartTime,
                      timestamp.timeIntervalSince(idleStart) > BASELINE_RECALIBRATION_IDLE_TIME {
                let recentSamples = samples.suffix(BASELINE_SAMPLES)
                if recentSamples.count == BASELINE_SAMPLES {
                    let distances = recentSamples.map(\.distance)
                    let mean = distances.reduce(0, +) / Double(distances.count)

                    // Calcola varianza per verificare stabilità
                    let variance = distances.map { pow($0 - mean, 2) }.reduce(0, +) / Double(distances.count)
                    let stdDev = sqrt(variance)

                    // Ricalibra solo se STABILE (std dev < 10mm) E cambio significativo (>20mm)
                    if stdDev < 10.0 && abs(mean - (baselineDistance ?? 0)) > 20.0 {
                        baselineDistance = mean
                        print("📏 Baseline ricalibrata: \(String(format: "%.1f", mean)) mm (σ=\(String(format: "%.1f", stdDev)))")
                    }
                }
                idleStartTime = nil // Reset timer
            }
        } else {
            idleStartTime = nil // Reset se non idle
        }

        // ⚡ Rev5: FIDATI dello stato Arduino (ha median filter, EMA, hold timers, isteresi!)
        // Lo stato è ora molto più affidabile grazie ai filtri sofisticati
        processStateFromArduino(currentSample: sample, arduinoState: movementState)
    }

    // MARK: - Private Methods

    /// [DEPRECATO per Rev5+] Calcola lo stato di movimento dalla velocità
    /// Rev5 Arduino ha filtri sofisticati (median, EMA, hold), quindi si usa lo stato hardware.
    /// Questo metodo resta per backward compatibility con firmware più vecchi.
    /// - Parameter velocity: Velocità in mm/s
    /// - Returns: Stato movimento calcolato
    private func calculateStateFromVelocity(_ velocity: Double) -> MovementState {
        let VELOCITY_THRESHOLD = 100.0  // mm/s threshold per rilevare movimento

        if velocity < -VELOCITY_THRESHOLD {
            // Velocità negativa = si avvicina al sensore = concentrica (approaching)
            return .approaching
        } else if velocity > VELOCITY_THRESHOLD {
            // Velocità positiva = si allontana dal sensore = eccentrica (receding)
            return .receding
        } else {
            // Velocità bassa = fermo
            return .idle
        }
    }

    private func calculateVelocity(distance: Double, timestamp: Date) -> Double {
        guard let lastSample = samples.last else { return 0.0 }

        let dt = timestamp.timeIntervalSince(lastSample.timestamp)
        let minDt = 1.0 / (sampleRateHz * 2.0)  // metà del periodo atteso

        // Se dt troppo piccolo, mantieni velocità precedente
        guard dt > minDt else { return lastSample.velocity }

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
            // Attende che Arduino rilevi receding (eccentrica = allontanamento dal sensore)
            if arduinoState == .receding {
                state = .descending
                eccentricStartTime = currentSample.timestamp
                eccentricStartDistance = smoothedDist
                onPhaseChange?(.descending)
                print("⬇️ Inizio eccentrica a \(String(format: "%.1f", smoothedDist)) mm")
            } else {
                // Debug: log quando non iniziamo eccentrica
                if arduinoState != .idle {
                    print("🔍 waitingDescent: ricevuto \(arduinoState.displayName) (aspettavo receding)")
                }
            }

        case .descending:
            // In eccentrica, attende che Arduino rilevi approaching (concentrica = avvicinamento al sensore)
            if arduinoState == .approaching {
                state = .waitingAscent
                concentricStartTime = currentSample.timestamp
                concentricStartDistance = smoothedDist
                concentricPeakDistance = smoothedDist
                concentricSamples = [currentSample]
                print("🔄 Transizione a concentrica a \(String(format: "%.1f", smoothedDist)) mm")
            }

        case .waitingAscent:
            // Conferma l'inizio della concentrica con 3 campioni consecutivi approaching
            concentricSamples.append(currentSample)

            if arduinoState == .approaching, concentricSamples.count >= 3 {
                state = .ascending
                onPhaseChange?(.ascending)
                print("⬆️ Inizio concentrica confermata")
            } else if arduinoState == .receding {
                // Falso positivo, torna a descending
                state = .descending
                concentricSamples.removeAll()
                print("🔄 Falso positivo, torna a eccentrica")
            }

        case .ascending:
            concentricSamples.append(currentSample)

            // Traccia picco massimo (distanza minima = bilanciere più vicino al sensore)
            if smoothedDist < (concentricPeakDistance ?? Double.infinity) {
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

        // Displacement (ROM) in mm: dal fondo (inizio concentrica) al top (picco concentrica)
        // startDist = dove inizia concentrica (fondo, distanza massima)
        // peakDist = picco concentrica (top, distanza minima)
        let displacementMM = abs(startDist - peakDist)

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
        if idleStartTime == nil {
            idleStartTime = Date()
        }
        onPhaseChange?(.idle)
    }
}
