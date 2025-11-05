//
//  VBTRepDetector.swift
//  VBTTracker
//
//  Full-cycle rep for bench press: PEAK → VALLEY → PEAK
//  Aggiunge controllo spostamento (m) sulla fase concentrica
//  Integra MPV/PPV + pattern library
//  Swift 6-compatible
//

import Foundation

final class VBTRepDetector {

    // MARK: - Debug / Thresholds

    // Metti a false per soglie realistiche
    private let DEBUG_DETECTION = false

    // Spostamento (m) minimo/massimo accettato per la fase concentrica
    // Panca piana tipicamente ~0.30–0.50 m, lasciamo un po’ di margine.
    private let MIN_CONC_DISPLACEMENT: Double = 0.20   // <— era 0.30
       private let MAX_CONC_DISPLACEMENT: Double = 0.80

    // Valori di sicurezza
    private let DEFAULT_MIN_CONCENTRIC: TimeInterval = 0.45
    private let DEFAULT_REFRACTORY: TimeInterval = 0.80
    private let MAX_MPV = 2.5
    private let MAX_PPV = 3.0
    private let warmupReps = 3
    
    private var useDisplacementGate: Bool { sampleRateHz >= 60 }
    private let MIN_CONC_SAMPLES = 8

    // MARK: - Public config

    var sampleRateHz: Double = 50.0
    var lookAheadSamples: Int = 10

    enum VelocityMeasurementMode {
        case concentricOnly
        case fullROM
    }
    var velocityMode: VelocityMeasurementMode = .concentricOnly

    var learnedPattern: LearnedPattern?

    // Callback
    enum Phase { case idle, descending, ascending, completed }
    var onPhaseChange: ((Phase) -> Void)?
    var onUnrack: (() -> Void)?

    // MARK: - Adaptive params

    private var windowSize: Int {
        max(5, SettingsManager.shared.repSmoothingWindow) // un filo più robusto
    }
    
    private func minConcentricDurationSec() -> TimeInterval {
        if DEBUG_DETECTION { return 0.30 }
        let fromPattern = learnedPattern.map { max(0.50, $0.avgConcentricDuration * 0.8) } ?? max(0.50, DEFAULT_MIN_CONCENTRIC)
        return lowSRSafeMode ? max(0.35, fromPattern * 0.85) : fromPattern  // NEW
    }

    private var minAmplitude: Double {
        let base: Double
        if let p = learnedPattern {
            base = max(0.18, p.dynamicMinAmplitude * 0.9)
        } else if isInWarmup {
            base = max(0.18, SettingsManager.shared.repMinAmplitude * 0.6)
        } else if let learned = learnedMinAmplitude {
            base = max(0.18, learned * 0.7)
        } else {
            base = 0.25
        }
        return lowSRSafeMode ? max(0.15, base * 0.8) : base  // NEW
    }

    private var idleThreshold: Double {
        if let p = learnedPattern { return max(0.06, p.restThreshold) }
        return 0.08
    }

    private var minRefractory: TimeInterval {
        let base = DEBUG_DETECTION ? 0.40 : DEFAULT_REFRACTORY
        return lowSRSafeMode ? max(0.50, base * 0.75) : base   // NEW (≈0.6s)
    }

    // MARK: - Internal state

    struct AccelMA { let timestamp: Date; let accZ: Double }

    private var samples: [AccelerationSample] = []
    private var smoothedValues: [Double] = []

    private var lastPeak: (value: Double, index: Int, time: Date)?
    private var lastValley: (value: Double, index: Int, time: Date)?
    private var lastRepTime: Date?

    private var isFirstMovement = true
    private var isInWarmup = true
    private var repAmplitudes: [Double] = []
    private var learnedMinAmplitude: Double?

    private enum Direction { case none, up, down }
    private var currentDirection: Direction = .none

    // Stato per ciclo completo (bench: peak→valley→peak)
    // 1) Attendo discesa (peak→valley)
    // 2) Attendo salita (valley→peak) -> conteggio rep
    private enum CycleState { case waitingDescent, waitingAscent }
    private var cycleState: CycleState = .waitingDescent

    // Traccia della fase concentrica corrente (valley→peak)
    private struct ConcentricSample {
        let timestamp: Date
        let accZ: Double
        let smoothedAccZ: Double
    }
    private var concentricSamples: [ConcentricSample] = []
    private var isTrackingConcentric = false

    // Unrack (stacco iniziale)
    private var hasAnnouncedUnrack = false
    private var unrackCooldownUntil: Date?
    
    private var lowSRSafeMode: Bool { sampleRateHz < 40 }

    // MARK: - Public API

    func addSample(accZ: Double, timestamp: Date) -> RepDetectionResult {
        samples.append(AccelerationSample(timestamp: timestamp, accZ: accZ))
        if samples.count > 512 { samples.removeFirst() }

        let smoothed = calculateMovingAverage()
        smoothedValues.append(smoothed)
        if smoothedValues.count > 512 { smoothedValues.removeFirst() }

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
        cycleState = .waitingDescent
        concentricSamples.removeAll()
        isTrackingConcentric = false
        hasAnnouncedUnrack = false
        unrackCooldownUntil = nil
    }

    func apply(pattern: LearnedPattern) {
        learnedPattern = pattern
        isInWarmup = false
        learnedMinAmplitude = pattern.dynamicMinAmplitude
    }

    func getSamples() -> [AccelerationSample] { samples }

    // MARK: - Core detection (peak→valley→peak)

    private func detectRep() -> RepDetectionResult {
        guard smoothedValues.count >= 5 else {
            return RepDetectionResult(repDetected: false,
                                      currentValue: smoothedValues.last ?? 0,
                                      meanPropulsiveVelocity: nil,
                                      peakPropulsiveVelocity: nil,
                                      duration: nil)
        }

        let current = smoothedValues.last!
        maybeAnnounceUnrack(current: current)

        let idx = smoothedValues.count - 1
        let now = Date()

        let newDirection = detectDirection()
        var repDetected = false
        var mpv: Double? = nil
        var ppv: Double? = nil
        var duration: Double? = nil

        // Cambi di direzione
        if newDirection != currentDirection && newDirection != .none {

            switch cycleState {

            case .waitingDescent:
                // caso "normale": abbiamo visto una discesa che si chiude in valley
                if newDirection == .up && currentDirection == .down {
                    let valleyVal = findRecentMin(lookback: 3)
                    lastValley = (valleyVal, idx, now)

                    // avvia la concentrica (valley→peak)
                    concentricSamples.removeAll()
                    isTrackingConcentric = true
                    onPhaseChange?(.ascending)
                    cycleState = .waitingAscent

                    if DEBUG_DETECTION {
                        print("⬇️→⬆️  VALLEY \(String(format: "%.3f", valleyVal)) @\(idx)")
                    }
                } else {
                    // Fallback: se non hai superato la soglia di direzione, usa un minimo locale
                    let t = localTurningPoint()
                    if let v = t.valley {
                        lastValley = (v, idx, now)
                        concentricSamples.removeAll()
                        isTrackingConcentric = true
                        onPhaseChange?(.ascending)
                        cycleState = .waitingAscent

                        if DEBUG_DETECTION {
                            print("⬇️→⬆️  VALLEY(local) \(String(format: "%.3f", v)) @\(idx)")
                        }
                    }
                }

            case .waitingAscent:
                // caso "normale": salita che si chiude in peak
                var justPeaked = false
                if newDirection == .down && currentDirection == .up {
                    let peakVal = findRecentMax(lookback: 3)
                    lastPeak = (peakVal, idx, now)
                    isTrackingConcentric = false
                    justPeaked = true
                } else {
                    // Fallback: peak locale se la soglia di direzione non scatta
                    let t = localTurningPoint()
                    if let p = t.peak {
                        lastPeak = (p, idx, now)
                        isTrackingConcentric = false
                        justPeaked = true
                        if DEBUG_DETECTION {
                            print("⬆️→⬇️  PEAK(local) \(String(format: "%.3f", p)) @\(idx)")
                        }
                    }
                }

                // Se abbiamo effettivamente un peak (normale o fallback), valida e conta la rep
                if justPeaked, let valley = lastValley, let peakT = lastPeak {
                    let amplitude = peakT.value - valley.value
                    let concDur  = peakT.time.timeIntervalSince(valley.time)

                    let refractoryOK = lastRepTime == nil || now.timeIntervalSince(lastRepTime!) >= minRefractory
                    let ampOK = amplitude >= minAmplitude
                    let durOK = concDur >= minConcentricDurationSec()

                    // ---- GATE di spostamento (attivo solo se SR≥60 Hz) ----
                    var dispOK = true
                    if useDisplacementGate, concentricSamples.count >= MIN_CONC_SAMPLES {
                        let (mpv0, ppv0, disp) = calculatePropulsiveVelocitiesAndDisplacement(from: concentricSamples)
                        let clamped = clampVBT(mpv0, ppv0)
                        mpv = clamped.0
                        ppv = clamped.1
                        if let d = disp {
                            dispOK = (MIN_CONC_DISPLACEMENT...MAX_CONC_DISPLACEMENT).contains(d)
                            if DEBUG_DETECTION {
                                print("📏 disp=\(String(format: "%.2f", d)) m  gate=\(dispOK ? "OK" : "KO")")
                            }
                        } else {
                            dispOK = false
                        }
                    } else {
                        // SR bassa: calcola MPV/PPV ma non bloccare per displacement
                        if concentricSamples.count > 5 {
                            let (mpv0, ppv0, _) = calculatePropulsiveVelocitiesAndDisplacement(from: concentricSamples)
                            let clamped = clampVBT(mpv0, ppv0)
                            mpv = clamped.0
                            ppv = clamped.1
                        }
                    }
                    // -------------------------------------------------------

                    if DEBUG_DETECTION {
                        let peakValForPrint = peakT.value
                        print("⬆️→⬇️  PEAK \(String(format: "%.3f", peakValForPrint)) @\(idx) | amp=\(String(format: "%.3f", amplitude))g  dur=\(String(format: "%.2f", concDur))s  [ampOK=\(ampOK) durOK=\(durOK) refOK=\(refractoryOK)\(useDisplacementGate ? " dispOK=\(dispOK)" : "")]  thr=\(String(format: "%.2f", minAmplitude))g")
                    }

                    if isFirstMovement {
                        isFirstMovement = false
                    } else if ampOK && refractoryOK && durOK && (!useDisplacementGate || dispOK) {
                        repDetected  = true
                        duration     = concDur
                        lastRepTime  = now

                        // warmup learning
                        repAmplitudes.append(amplitude)
                        if repAmplitudes.count == warmupReps {
                            learnedMinAmplitude = repAmplitudes.reduce(0, +) / Double(warmupReps)
                            isInWarmup = false
                        }

                        if DEBUG_DETECTION {
                            print("✅ REP DETECTED | MPV=\(mpv.map { String(format: "%.3f", $0) } ?? "nil")  PPV=\(ppv.map { String(format: "%.3f", $0) } ?? "nil")  concDur=\(String(format: "%.2f", concDur))s  amp=\(String(format: "%.3f", amplitude))g")
                        }
                    } else if DEBUG_DETECTION {
                        let dispReason = useDisplacementGate ? (dispOK ? "" : "disp ") : ""
                        print("❎ REJECTED | reason: \(ampOK ? "" : "amp ") \(durOK ? "" : "dur ") \(refractoryOK ? "" : "refractory ") \(dispReason)")
                    }

                    onPhaseChange?(.descending)
                    cycleState = .waitingDescent
                }
            }

            currentDirection = newDirection
        }

        return RepDetectionResult(repDetected: repDetected,
                                  currentValue: current,
                                  meanPropulsiveVelocity: mpv,
                                  peakPropulsiveVelocity: ppv,
                                  duration: duration)
    }

    // MARK: - Unrack (stacco)

    private func maybeAnnounceUnrack(current: Double) {
        guard !hasAnnouncedUnrack,
              lastRepTime == nil,
              abs(current) > idleThreshold * 2 else { return }
        if let until = unrackCooldownUntil, Date() < until { return }
        onUnrack?()
        hasAnnouncedUnrack = true
        unrackCooldownUntil = Date().addingTimeInterval(5)
    }

    // MARK: - MPV/PPV + Displacement

    /// Ritorna (MPV, PPV, Displacement[m] sulla finestra concentrica)
    private func calculatePropulsiveVelocitiesAndDisplacement(from src: [ConcentricSample]) -> (Double?, Double?, Double?) {
        guard src.count >= 3 else { return (nil, nil, nil) }
        let t0 = src.first!.timestamp

        // 1) Serie acc (in g) e tempi relativi
        let az = src.map { $0.smoothedAccZ }
        let tt = src.map { $0.timestamp.timeIntervalSince(t0) }

        // 2) Detrend acc (toglie media finestra)
        let meanG = az.reduce(0, +) / Double(az.count)
        let acc_ms2 = az.map { ($0 - meanG) * 9.81 }

        // 3) Integrazione trapezoidale per velocità
        var v = [0.0]
        for i in 1..<acc_ms2.count {
            let dt = max(0, tt[i] - tt[i-1])
            v.append(v.last! + 0.5 * (acc_ms2[i-1] + acc_ms2[i]) * dt)
        }

        // 4) Trova picco velocità e taglia fino allo zero-crossing successivo
        let peakIdx = v.firstIndex(of: (v.max() ?? 0.0)) ?? (v.count - 1)
        var endIdx = peakIdx
        for i in peakIdx..<acc_ms2.count where i > 0 {
            if acc_ms2[i-1] > 0 && acc_ms2[i] <= 0 { endIdx = i; break }
        }
        let vConc = Array(v[0...endIdx])
        let tConc = Array(tt[0...endIdx])
        guard !vConc.isEmpty else { return (nil, nil, nil) }

        // 5) MPV/PPV
        let mpv = vConc.reduce(0, +) / Double(vConc.count)
        let ppv = vConc.max() ?? 0

        // 6) Spostamento durante la fase concentrica: integra v
        var x = [0.0]
        for i in 1..<vConc.count {
            let dt = max(0, tConc[i] - tConc[i-1])
            x.append(x.last! + 0.5 * (vConc[i-1] + vConc[i]) * dt)
        }
        let disp = x.last ?? 0.0 // m

        return ((0.05...MAX_MPV).contains(mpv) ? mpv : nil,
                (0.05...MAX_PPV).contains(ppv) ? ppv : nil,
                abs(disp))
    }

    private func clampVBT(_ mpv: Double?, _ ppv: Double?) -> (Double?, Double?) {
        (mpv.map { min($0, MAX_MPV) }, ppv.map { min($0, MAX_PPV) })
    }

    // MARK: - Direction helpers

    private func detectDirection() -> Direction {
        guard smoothedValues.count >= 4 else { return .none }
        let last4 = Array(smoothedValues.suffix(4))
        let thr = lowSRSafeMode ? 0.01 : 0.03     // NEW: più sensibile sotto 40 Hz
        var ups = 0, downs = 0
        for i in 1..<last4.count {
            let d = last4[i] - last4[i-1]
            if d >  thr { ups  += 1 }
            if d < -thr { downs += 1 }
        }
        if ups   >= 2 && ups   > downs { return .up }
        if downs >= 2 && downs > ups   { return .down }
        return currentDirection
    }
    
    private func localTurningPoint() -> (valley: Double?, peak: Double?) {
        guard smoothedValues.count >= 3 else { return (nil, nil) }
        let a = smoothedValues[smoothedValues.count - 3]
        let b = smoothedValues[smoothedValues.count - 2]
        let c = smoothedValues[smoothedValues.count - 1]
        if b < a && b < c { return (b, nil) }   // valley locale
        if b > a && b > c { return (nil, b) }   // peak locale
        return (nil, nil)
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

// MARK: - Result

struct RepDetectionResult {
    let repDetected: Bool
    let currentValue: Double
    let meanPropulsiveVelocity: Double?
    let peakPropulsiveVelocity: Double?
    let duration: Double?
    var peakVelocity: Double? { peakPropulsiveVelocity ?? meanPropulsiveVelocity }
}

// MARK: - Pattern learning integrazione

extension VBTRepDetector {

    private static func makeFeatureVector(from samples: [AccelerationSample]) -> [Double] {
        guard samples.count > 3 else { return [] }
        let accZ = samples.map(\.accZ)
        let mean = accZ.reduce(0, +) / Double(accZ.count)
        let std = sqrt(accZ.map { pow($0 - mean, 2) }.reduce(0, +) / Double(accZ.count))
        let range = (accZ.max() ?? 0) - (accZ.min() ?? 0)
        let diffs = zip(accZ.dropFirst(), accZ).map { $0 - $1 }
        let spectralEnergy = sqrt(diffs.map { $0 * $0 }.reduce(0, +) / Double(diffs.count))
        return [mean, std, range / 2.0, spectralEnergy, Double(samples.count) / 100.0]
    }

    func recognizePatternIfPossible() {
        guard samples.count > 30 else { return }
        Task { @MainActor in
            if let match = LearnedPatternLibrary.shared.matchPattern(for: samples) {
                let features = Self.makeFeatureVector(from: samples)
                guard !features.isEmpty else { return }
                let dist = LearnedPatternLibrary.shared.distance(match.featureVector, features)
                if dist < 0.35 {
                    print("Pattern riconosciuto: \(match.label) \(match.repCount) reps")
                    learnedPattern = LearnedPattern(from: match)
                } else {
                    print("Nessun pattern simile (dist \(String(format: "%.3f", dist)))")
                }
            }
        }
    }

    func savePatternSequence(
        label: String,
        repCount: Int,
        loadPercentage: Double? = nil,
        avgMPV: Double? = nil,
        avgPPV: Double? = nil
    ) {
        guard repCount > 0 else { return }

        let amp = (samples.map { $0.accZ }.max() ?? 0) - (samples.map { $0.accZ }.min() ?? 0)
        let duration = (samples.last?.timestamp.timeIntervalSince(samples.first?.timestamp ?? Date())) ?? 0
        let features = Self.makeFeatureVector(from: samples)
        guard !features.isEmpty else { return }

        let new = PatternSequence(
            id: UUID(),
            date: Date(),
            label: label,
            repCount: repCount,
            loadPercentage: loadPercentage,
            avgDuration: duration / Double(repCount),
            avgAmplitude: amp,
            avgMPV: (avgMPV ?? 0.5),
            avgPPV: (avgPPV ?? 0.6),
            featureVector: features
        )

        Task { @MainActor in
            LearnedPatternLibrary.shared.addPattern(new)
            print("🧠 Pattern salvato: \(label) \(repCount) reps | MPV=\(String(format: "%.2f", new.avgMPV)) PPV=\(String(format: "%.2f", new.avgPPV))")

        }
    }
}

// Aggiungi questa extension in fondo a VBTRepDetector.swift

extension VBTRepDetector {
    
    /// Debug: stampa stato completo detector
    func printDebugState() {
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🔍 VBT DETECTOR STATE")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("📊 Sample Rate: \(String(format: "%.1f", sampleRateHz)) Hz")
        print("👀 Look-ahead: \(lookAheadSamples) samples (\(String(format: "%.0f", Double(lookAheadSamples)/sampleRateHz*1000))ms)")
        print("📏 Buffer: \(samples.count) samples, \(smoothedValues.count) smoothed")
        print("")
        print("🎯 SOGLIE ATTIVE:")
        print("   • Min Amplitude: \(String(format: "%.3f", minAmplitude))g")
        print("   • Idle Threshold: \(String(format: "%.3f", idleThreshold))g")
        print("   • Min Concentric: \(String(format: "%.2f", minConcentricDurationSec()))s")
        print("   • Min Refractory: \(String(format: "%.2f", minRefractory))s")
        print("   • Displacement Gate: \(useDisplacementGate ? "ON" : "OFF")")
        if useDisplacementGate {
            print("   • Range Displacement: \(MIN_CONC_DISPLACEMENT)-\(MAX_CONC_DISPLACEMENT)m")
        }
        print("")
        print("🔄 STATO CICLO:")
        print("   • Cycle State: \(cycleState)")
        print("   • Direction: \(currentDirection)")
        print("   • Is Tracking Concentric: \(isTrackingConcentric)")
        print("   • Concentric Samples: \(concentricSamples.count)")
        print("   • Is First Movement: \(isFirstMovement)")
        print("   • Is Warmup: \(isInWarmup)")
        print("")
        if let peak = lastPeak {
            print("📈 Last Peak: \(String(format: "%.3f", peak.value))g @ idx \(peak.index)")
        }
        if let valley = lastValley {
            print("📉 Last Valley: \(String(format: "%.3f", valley.value))g @ idx \(valley.index)")
        }
        if let lastRep = lastRepTime {
            let elapsed = Date().timeIntervalSince(lastRep)
            print("⏱️  Last Rep: \(String(format: "%.2f", elapsed))s ago")
        }
        print("")
        if let pattern = learnedPattern {
            print("🧠 PATTERN CARICATO:")
            print("   • ROM: \(String(format: "%.2f", pattern.estimatedROM))m")
            print("   • Avg Amplitude: \(String(format: "%.3f", pattern.dynamicMinAmplitude))g")
            print("   • Avg Duration: \(String(format: "%.2f", pattern.avgConcentricDuration))s")
            print("   • Avg Velocity: \(String(format: "%.3f", pattern.avgPeakVelocity))m/s")
        } else {
            print("🧠 Nessun pattern caricato (modalità adaptive)")
        }
        
        if !smoothedValues.isEmpty {
            let last5 = smoothedValues.suffix(5)
            print("")
            print("📊 ULTIMI 5 VALORI SMOOTHED:")
            for (i, val) in last5.enumerated() {
                let idx = smoothedValues.count - 5 + i
                print("   [\(idx)]: \(String(format: "%.4f", val))g")
            }
            
            // Controlla se c'è movimento
            let range = (last5.max() ?? 0) - (last5.min() ?? 0)
            print("   Range: \(String(format: "%.4f", range))g \(range > minAmplitude ? "✅" : "⚠️  sotto soglia")")
        }
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    }
    
    /// Debug: valida se il movimento corrente potrebbe diventare una rep
    func validateCurrentMovement() -> String {
        guard let valley = lastValley else {
            return "❌ Nessuna valley rilevata (fase discendente non completata)"
        }
        
        guard isTrackingConcentric, !concentricSamples.isEmpty else {
            return "❌ Non in fase concentrica"
        }
        
        let now = Date()
        let concDur = now.timeIntervalSince(valley.time)
        let current = smoothedValues.last ?? 0
        let amplitude = current - valley.value
        
        var issues: [String] = []
        
        if amplitude < minAmplitude {
            issues.append("Ampiezza bassa: \(String(format: "%.3f", amplitude))g < \(String(format: "%.3f", minAmplitude))g")
        }
        
        if concDur < minConcentricDurationSec() {
            issues.append("Durata breve: \(String(format: "%.2f", concDur))s < \(String(format: "%.2f", minConcentricDurationSec()))s")
        }
        
        if let lastRep = lastRepTime {
            let refractory = now.timeIntervalSince(lastRep)
            if refractory < minRefractory {
                issues.append("Refrattario: \(String(format: "%.2f", refractory))s < \(String(format: "%.2f", minRefractory))s")
            }
        }
        
        if useDisplacementGate, concentricSamples.count >= MIN_CONC_SAMPLES {
            let (_, _, disp) = calculatePropulsiveVelocitiesAndDisplacement(from: concentricSamples)
            if let d = disp {
                let inRange = (MIN_CONC_DISPLACEMENT...MAX_CONC_DISPLACEMENT).contains(d)
                if !inRange {
                    issues.append("Displacement \(String(format: "%.2f", d))m fuori range [\(MIN_CONC_DISPLACEMENT)-\(MAX_CONC_DISPLACEMENT)]m")
                }
            }
        }
        
        if issues.isEmpty {
            return "✅ Movimento valido - in attesa del peak"
        } else {
            return "⚠️  Issues:\n   • " + issues.joined(separator: "\n   • ")
        }
    }
}
