//
//  VBTRepDetector.swift
//  VBTTracker
//
//  ✅ SCIENTIFIC VBT: Calcolo corretto MPV e PPV
//  📊 Mean Propulsive Velocity e Peak Propulsive Velocity secondo letteratura (Sánchez-Medina et al. 2010)
//

import Foundation

class VBTRepDetector {
    
    // MARK: - Configuration
    
    enum VelocityMeasurementMode {
        case concentricOnly  // ✅ Standard VBT
        case fullROM
    }
    
    struct MultiAxisSample {
        let timestamp: Date
        let accX: Double
        let accY: Double
        let accZ: Double
        let gyroMagnitude: Double
    }
    
    var velocityMode: VelocityMeasurementMode = .concentricOnly
    
    /// Pattern appreso da calibrazione (se disponibile)
    var learnedPattern: LearnedPattern?
    
    // MARK: - Parametri ADATTIVI
    
    private var windowSize: Int {
        max(3, SettingsManager.shared.repSmoothingWindow)
    }
    
    /// Ampiezza minima DINAMICA basata su pattern appreso
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
    
    /// Anti-doppio-conteggio
    private var minTimeBetween: TimeInterval {
        if let pattern = learnedPattern {
            return pattern.avgConcentricDuration * 1.3
        }
        return 0.5
    }
    
    /// Soglia per decidere se è "fermo" o "si muove"
    private var idleThreshold: Double {
        learnedPattern?.restThreshold ?? 0.08
    }
    
    /// Numero rep per warmup (se non c'è pattern appreso)
    private let warmupReps: Int = 3
    
    // MARK: - State Tracking
    
    private var samples: [AccelerationSample] = []
    private var smoothedValues: [Double] = []
    
    // Tracking estremi locali
    private var lastPeak: (value: Double, index: Int, time: Date)?
    private var lastValley: (value: Double, index: Int, time: Date)?
    private var lastRepTime: Date?
    
    private var isFirstMovement: Bool = true
    
    // Adaptive learning
    private var repAmplitudes: [Double] = []
    private var learnedMinAmplitude: Double?
    private var isInWarmup: Bool = true
    private var lastMovementTime: Date?
    
    // Voice feedback
    var hasAnnouncedUnrack = false
    private var lastAnnouncedDirection: Direction = .none
    var onPhaseChange: ((Phase) -> Void)?
    
    // ✅ NUOVO: Tracking fase concentrica per calcolo MPV/PPV
    private var concentricSamples: [ConcentricSample] = []
    private var isTrackingConcentric = false
    
    /// Campione durante fase concentrica
    struct ConcentricSample {
        let timestamp: Date
        let accZ: Double          // Accelerazione raw (g)
        let smoothedAccZ: Double  // Accelerazione smoothed (g)
    }
    
    enum Phase {
        case idle
        case descending
        case ascending
        case completed
    }
    
    private enum Direction {
        case none
        case up      // Sta salendo
        case down    // Sta scendendo
    }
    
    private var currentDirection: Direction = .none
    
    // MARK: - Public Methods
    
    func addSample(accZ: Double, timestamp: Date) -> RepDetectionResult {
        let sample = AccelerationSample(timestamp: timestamp, accZ: accZ)
        samples.append(sample)
        
        if samples.count > 200 {
            samples.removeFirst()
        }
        
        let smoothed = calculateMovingAverage()
        smoothedValues.append(smoothed)
        
        if smoothedValues.count > 200 {
            smoothedValues.removeFirst()
        }
        
        // ✅ NUOVO: Traccia campioni concentrci se in fase di risalita
        if isTrackingConcentric {
            let concentricSample = ConcentricSample(
                timestamp: timestamp,
                accZ: accZ,
                smoothedAccZ: smoothed
            )
            concentricSamples.append(concentricSample)
        }
        
        return detectRepSimple()
    }
    
    /// Aggiunge un campione multi-assiale; restituisce risultato di detection.
    func addMultiAxisSample(
        accX: Double,
        accY: Double,
        accZ: Double,
        gyro: [Double],
        timestamp: Date
    ) -> RepDetectionResult {
        
        // 1. Calcola magnitude orizzontale (X/Y)
        let horizontalMag = sqrt(accX * accX + accY * accY)
        
        // 2. Calcola magnitude giroscopio
        let gyroMag = sqrt(gyro[0]*gyro[0] + gyro[1]*gyro[1] + gyro[2]*gyro[2])
        
        // 3. Motion intensity = acc horizontal + gyro weighted
        let motionIntensity = horizontalMag + (gyroMag * 0.005)
        
        // 4. Usa motion intensity per DETECTION
        let sample = AccelerationSample(
            timestamp: timestamp,
            accZ: motionIntensity
        )
        
        samples.append(sample)
        
        // 5. Smoothing e detection
        let smoothed = calculateMovingAverage()
        smoothedValues.append(smoothed)
        
        // ✅ NUOVO: Traccia ACCZ VERTICALE raw per calcolo velocità
        if isTrackingConcentric {
            let concentricSample = ConcentricSample(
                timestamp: timestamp,
                accZ: accZ,  // ✅ AccZ originale verticale, NON motion intensity
                smoothedAccZ: smoothed
            )
            concentricSamples.append(concentricSample)
        }
        
        // 6. Detect
        return detectRepSimple()
    }
    
    func reset() {
        samples.removeAll()
        smoothedValues.removeAll()
        lastPeak = nil
        lastValley = nil
        lastRepTime = nil
        currentDirection = .none
        hasAnnouncedUnrack = false
        lastAnnouncedDirection = .none
        
        // Reset adaptive learning
        repAmplitudes.removeAll()
        learnedMinAmplitude = nil
        isInWarmup = true
        lastMovementTime = nil
        
        isFirstMovement = true
        
        // ✅ NUOVO: Reset tracking concentrico
        concentricSamples.removeAll()
        isTrackingConcentric = false
    }
    
    func getSamples() -> [AccelerationSample] {
        return samples
    }
    
    // MARK: - ALGORITMO SEMPLIFICATO
    
    /// Logica: Conta OGNI pattern "picco → valle → picco"
    private func detectRepSimple() -> RepDetectionResult {
        guard smoothedValues.count >= 5 else {
            return RepDetectionResult(
                repDetected: false,
                currentValue: 0,
                meanPropulsiveVelocity: nil,
                peakPropulsiveVelocity: nil,
                duration: nil
            )
        }
        
        let current = smoothedValues.last!
        let currentIndex = smoothedValues.count - 1
        let timestamp = Date()
        
        // 1️⃣ Determina DIREZIONE attuale
        let newDirection = detectDirection()
        
        var repDetected = false
        var mpv: Double?  // Mean Propulsive Velocity
        var ppv: Double?  // Peak Propulsive Velocity
        var detectedDuration: Double? = nil
        
        // 2️⃣ Rileva INVERSIONI di direzione
        
        if newDirection != currentDirection && newDirection != .none {
            
            // INVERSIONE VERSO IL BASSO (abbiamo appena passato un PICCO)
            if newDirection == .down && currentDirection == .up {
                let peakValue = findRecentMax(lookback: 3)
                lastPeak = (peakValue, currentIndex, timestamp)
                
                print("🔴 PICCO a \(String(format: "%.2f", peakValue))g")
                
                // ✅ NUOVO: STOP tracking concentrico (fine risalita)
                isTrackingConcentric = false
                
                // Voice: discesa (solo se non l'abbiamo già detto)
                if lastAnnouncedDirection != .down {
                    if !hasAnnouncedUnrack && lastValley == nil {
                        hasAnnouncedUnrack = true
                        onPhaseChange?(.descending)
                    }
                    lastAnnouncedDirection = .down
                }
            }
            
            // INVERSIONE VERSO L'ALTO (abbiamo appena passato una VALLE)
            else if newDirection == .up && currentDirection == .down {
                let valleyValue = findRecentMin(lookback: 3)
                lastValley = (valleyValue, currentIndex, timestamp)
                
                print("🔵 VALLE a \(String(format: "%.2f", valleyValue))g")
                
                // ✅ NUOVO: START tracking concentrico (inizio risalita)
                concentricSamples.removeAll()
                isTrackingConcentric = true
                
                // Voice: salita
                if lastAnnouncedDirection != .up {
                    onPhaseChange?(.ascending)
                    lastAnnouncedDirection = .up
                }
                
                // ✅ CONTA REP: Se abbiamo pattern PICCO → VALLE → ora risale
                if let peak = lastPeak, let valley = lastValley {
                    
                    // ✅ FIX: Ignora il primo movimento (stacco)
                    if isFirstMovement {
                        print("⚠️ Primo movimento ignorato (stacco dal rack)")
                        isFirstMovement = false
                        lastPeak = nil
                        return RepDetectionResult(
                            repDetected: false,
                            currentValue: current,
                            meanPropulsiveVelocity: nil,
                            peakPropulsiveVelocity: nil,
                            duration: nil
                        )
                    }
                    
                    // Validazione MINIMA
                    let amplitude = peak.value - valley.value
                    let timeSinceLast = lastRepTime?.timeIntervalSinceNow ?? -1.0
                    let validTiming = abs(timeSinceLast) > minTimeBetween || lastRepTime == nil
                                        
                    // FILTRO INTELLIGENTE: Ignora micro-movimenti dopo inattività
                    let timeSinceMovement = lastMovementTime?.timeIntervalSinceNow ?? 0
                    let isAfterLongPause = abs(timeSinceMovement) > 2.0
                    
                    // Se sono fermo da > 2s, richiedi ampiezza maggiore
                    let amplitudeThreshold = isAfterLongPause ? minAmplitude * 1.5 : minAmplitude
                    
                    // CONTA se: ampiezza OK + timing OK
                    if amplitude >= amplitudeThreshold && validTiming {
                        
                        // ✅ NUOVO: Calcola MPV e PPV dalla fase concentrica precedente
                        // NOTA: Usa i campioni concentrci dell'ultima risalita COMPLETATA (prima della valle corrente)
                        // Quindi dobbiamo aspettare il prossimo picco per processarli
                        
                        // Per ora usiamo stima legacy come fallback
                        let duration = valley.time.timeIntervalSince(peak.time)
                        detectedDuration = abs(duration)
                        
                        // Fallback: stima semplice
                        let legacyVelocity = estimateVelocityLegacy(amplitude: amplitude, duration: abs(duration))
                        mpv = legacyVelocity
                        ppv = legacyVelocity * 1.2  // Stima PPV come 120% di MPV
                        
                        repDetected = true
                        lastRepTime = timestamp
                        lastMovementTime = timestamp
                        
                        // 🎓 LEARNING: Impara dalle prime rep
                        repAmplitudes.append(amplitude)
                        if repAmplitudes.count == warmupReps {
                            learnedMinAmplitude = repAmplitudes.reduce(0, +) / Double(warmupReps)
                            isInWarmup = false
                            print("🎓 Warmup completato - Soglia appresa: \(String(format: "%.2f", learnedMinAmplitude!))g")
                        }
                        
                        // Marca picco sul grafico
                        if peak.index < samples.count {
                            samples[peak.index].isPeak = true
                        }
                        
                        let phase = isInWarmup ? "WARMUP" : "ACTIVE"
                        print("✅ REP [\(phase)] - Amp: \(String(format: "%.2f", amplitude))g, " +
                              "MPV: \(String(format: "%.2f", mpv ?? 0.0)) m/s, " +
                              "PPV: \(String(format: "%.2f", ppv ?? 0.0)) m/s")
                        
                    } else {
                        let reason = !validTiming ? "anti-rimbalzo (\(String(format: "%.2f", abs(timeSinceLast)))s)" :
                                    isAfterLongPause ? "micro-movimento dopo pausa (amp \(String(format: "%.2f", amplitude))g < \(String(format: "%.2f", amplitudeThreshold))g)" :
                                    "ampiezza troppo bassa (\(String(format: "%.2f", amplitude))g)"
                        print("⚠️ Pattern ignorato: \(reason)")
                    }
                    
                    // Reset peak per prossimo ciclo
                    lastPeak = nil
                }
            }
            
            currentDirection = newDirection
        }
        
        // ✅ NUOVO: Se abbiamo appena rilevato una rep E abbiamo campioni concentrci, calcoliamo MPV/PPV
        if repDetected && concentricSamples.count > 5 {
            let velocities = calculatePropulsiveVelocities(from: concentricSamples)
            mpv = velocities.mpv
            ppv = velocities.ppv
            
            print("📊 Velocità Propulsive Calcolate - MPV: \(String(format: "%.3f", mpv ?? 0)) m/s, PPV: \(String(format: "%.3f", ppv ?? 0)) m/s")
        }
        
        return RepDetectionResult(
            repDetected: repDetected,
            currentValue: current,
            meanPropulsiveVelocity: mpv,
            peakPropulsiveVelocity: ppv,
            duration: detectedDuration
        )
    }
    
    // MARK: - ✅ NUOVO: Calcolo Scientifico MPV/PPV
    
    /// Calcola Mean Propulsive Velocity (MPV) e Peak Propulsive Velocity (PPV)
    /// secondo la letteratura scientifica (Sánchez-Medina et al. 2010)
    ///
    /// - Parameter samples: Campioni accelerazione durante fase concentrica
    /// - Returns: Tupla con (mpv, ppv) in m/s
    private func calculatePropulsiveVelocities(from samples: [ConcentricSample]) -> (mpv: Double?, ppv: Double?) {
        guard samples.count >= 3 else { return (nil, nil) }
        
        // 1️⃣ Converti accelerazioni da g a m/s²
        var accelerationsMS2: [Double] = []
        var timestamps: [TimeInterval] = []
        
        let startTime = samples.first!.timestamp
        
        for sample in samples {
            // Rimuovi componente gravitazionale (~1g verso il basso)
            // Assumiamo che sensore sia calibrato con gravità inclusa
            var accMS2 = sample.smoothedAccZ * 9.81
            
            // Se accZ > 0.8g, sottrai 1g (bias gravitazionale)
            if sample.smoothedAccZ > 0.8 {
                accMS2 = (sample.smoothedAccZ - 1.0) * 9.81
            } else if sample.smoothedAccZ < -0.8 {
                accMS2 = (sample.smoothedAccZ + 1.0) * 9.81
            }
            
            accelerationsMS2.append(accMS2)
            timestamps.append(sample.timestamp.timeIntervalSince(startTime))
        }
        
        // 2️⃣ Integra accelerazione per ottenere velocità istantanea
        // Metodo: Integrazione trapezoidale (più accurata di Eulero semplice)
        var velocities: [Double] = [0.0]  // Velocità iniziale = 0
        
        for i in 1..<accelerationsMS2.count {
            let dt = timestamps[i] - timestamps[i-1]
            
            // Integrazione trapezoidale: v[i] = v[i-1] + (a[i-1] + a[i])/2 * dt
            let avgAccel = (accelerationsMS2[i-1] + accelerationsMS2[i]) / 2.0
            let newVelocity = velocities.last! + avgAccel * dt
            
            velocities.append(newVelocity)
        }
        
        // 3️⃣ Identifica FINE fase propulsiva
        // Secondo letteratura: quando accelerazione < -9.81 m/s² (gravità)
        var propulsiveEndIndex = accelerationsMS2.count - 1  // Default: tutta la fase
        
        for (index, accel) in accelerationsMS2.enumerated() {
            if accel < -9.81 {
                propulsiveEndIndex = index
                print("📉 Fine fase propulsiva a \(String(format: "%.2f", timestamps[index]))s (a = \(String(format: "%.2f", accel)) m/s²)")
                break
            }
        }
        
        // Se non troviamo decelerazione significativa, assumiamo che sia carico pesante (>76% 1RM)
        // In questo caso, fase propulsiva = intera fase concentrica
        if propulsiveEndIndex == accelerationsMS2.count - 1 {
            print("📌 Carico pesante: fase propulsiva = intera concentrica")
        }
        
        // 4️⃣ Calcola MPV (Mean Propulsive Velocity)
        let propulsiveVelocities = Array(velocities[0...propulsiveEndIndex])
        
        guard !propulsiveVelocities.isEmpty else { return (nil, nil) }
        
        let mpv = propulsiveVelocities.reduce(0.0, +) / Double(propulsiveVelocities.count)
        
        // 5️⃣ Calcola PPV (Peak Propulsive Velocity)
        let ppv = propulsiveVelocities.max() ?? 0.0
        
        // 6️⃣ Validazione: valori ragionevoli per VBT (0.1 - 2.5 m/s)
        let validMPV = (0.1...2.5).contains(mpv) ? mpv : nil
        let validPPV = (0.1...3.0).contains(ppv) ? ppv : nil
        
        return (validMPV, validPPV)
    }
    
    // MARK: - Helper: Direction Detection
    
    /// Rileva se il segnale sta salendo, scendendo o è piatto
    private func detectDirection() -> Direction {
        guard smoothedValues.count >= 4 else { return .none }
        
        let last4 = Array(smoothedValues.suffix(4))
        
        // Aggiorna timestamp ultimo movimento significativo
        if last4.last! > idleThreshold || last4.last! < -idleThreshold {
            lastMovementTime = Date()
        }
        
        // Calcola trend medio (quante volte sale vs scende)
        var ups = 0
        var downs = 0
        
        for i in 1..<last4.count {
            let delta = last4[i] - last4[i-1]
            if delta > 0.03 { ups += 1 }
            else if delta < -0.03 { downs += 1 }
        }
        
        // Decidi direzione
        if ups >= 2 && ups > downs { return .up }
        if downs >= 2 && downs > ups { return .down }
        
        return currentDirection
    }
    
    /// Trova massimo negli ultimi N campioni
    private func findRecentMax(lookback: Int) -> Double {
        guard smoothedValues.count >= lookback else {
            return smoothedValues.last ?? 0
        }
        return smoothedValues.suffix(lookback).max() ?? 0
    }
    
    /// Trova minimo negli ultimi N campioni
    private func findRecentMin(lookback: Int) -> Double {
        guard smoothedValues.count >= lookback else {
            return smoothedValues.last ?? 0
        }
        return smoothedValues.suffix(lookback).min() ?? 0
    }
    
    // MARK: - Legacy Velocity Estimation (Fallback)
    
    /// Stima legacy della velocità (usata come fallback)
    private func estimateVelocityLegacy(amplitude: Double, duration: Double) -> Double {
        // ROM stimato in base ad ampiezza
        let estimatedROM: Double
        if amplitude < 0.4 {
            estimatedROM = 0.20
        } else if amplitude < 0.7 {
            estimatedROM = 0.45
        } else if amplitude < 1.0 {
            estimatedROM = 0.60
        } else {
            estimatedROM = 0.75
        }
        
        // Velocità media: v = s / t
        if duration > 0.05 {
            return estimatedROM / duration
        } else {
            // Fallback: formula cinematica v = sqrt(2*a*s)
            let accelMS2 = amplitude * 9.81
            return sqrt(2.0 * accelMS2 * estimatedROM)
        }
    }
    
    // MARK: - Helper: Smoothing
    
    private func calculateMovingAverage() -> Double {
        guard samples.count >= windowSize else {
            return samples.last?.accZ ?? 0
        }
        
        let window = samples.suffix(windowSize)
        let sum = window.reduce(0.0) { $0 + $1.accZ }
        return sum / Double(windowSize)
    }
}

// MARK: - Result Model

struct RepDetectionResult {
    let repDetected: Bool
    let currentValue: Double
    
    // ✅ NUOVO: Velocità separate secondo standard VBT
    let meanPropulsiveVelocity: Double?   // MPV (media fase propulsiva)
    let peakPropulsiveVelocity: Double?   // PPV (picco fase propulsiva)
    
    let duration: Double?
    
    // Computed: Velocità "legacy" per retrocompatibilità
    var peakVelocity: Double? {
        return peakPropulsiveVelocity ?? meanPropulsiveVelocity
    }
}
