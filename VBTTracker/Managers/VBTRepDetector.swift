//
//  VBTRepDetector.swift
//  VBTTracker
//
//  Algoritmo VBT ULTRA-SEMPLIFICATO
//  "Vedo salita-discesa? È una REP!"
//

import Foundation

class VBTRepDetector {
    
    // MARK: - Configuration
    
    enum VelocityMeasurementMode {
        case concentricOnly
        case fullROM
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
            // Usa pattern appreso (50% della media)
            return pattern.dynamicMinAmplitude
        } else if isInWarmup {
            // Durante warmup: ultra-permissivo per imparare
            return SettingsManager.shared.repMinAmplitude * 0.4
        } else if let learned = learnedMinAmplitude {
            // Dopo warmup: usa 50% della media appresa
            return learned * 0.5
        } else {
            // Fallback
            return SettingsManager.shared.repMinAmplitude * 0.5
        }
    }
    
    /// Anti-doppio-conteggio
    private var minTimeBetween: TimeInterval {
        // Pattern appreso ha info sulla durata?
        if let pattern = learnedPattern {
            // Usa durata concentrica + buffer 30%
            return pattern.avgConcentricDuration * 1.3
        }
        
        // Fallback: 0.5s per forza, 0.3s per velocità
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
    private var repAmplitudes: [Double] = []  // Storia ampiezze rep valide
    private var learnedMinAmplitude: Double?  // Soglia appresa
    private var isInWarmup: Bool = true
    private var lastMovementTime: Date?  // Ultimo movimento significativo
    
    // Voice feedback
    var hasAnnouncedUnrack = false
    private var lastAnnouncedDirection: Direction = .none
    var onPhaseChange: ((Phase) -> Void)?
    
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
    }
    
    func getSamples() -> [AccelerationSample] {
        return samples
    }
    
    // MARK: - ALGORITMO SEMPLIFICATO
    
    /// Logica: Conta OGNI pattern "picco → valle → picco"
    private func detectRepSimple() -> RepDetectionResult {
        guard smoothedValues.count >= 5 else {
            return RepDetectionResult(repDetected: false, currentValue: 0, peakVelocity: nil)
        }
        
        let current = smoothedValues.last!
        let currentIndex = smoothedValues.count - 1
        let timestamp = Date()
        
        // 1️⃣ Determina DIREZIONE attuale
        let newDirection = detectDirection()
        
        var repDetected = false
        var peakVelocity: Double?
        
        // 2️⃣ Rileva INVERSIONI di direzione
        
        if newDirection != currentDirection && newDirection != .none {
            
            // INVERSIONE VERSO IL BASSO (abbiamo appena passato un PICCO)
            if newDirection == .down && currentDirection == .up {
                let peakValue = findRecentMax(lookback: 3)
                lastPeak = (peakValue, currentIndex, timestamp)
                
                print("🔴 PICCO a \(String(format: "%.2f", peakValue))g")
                
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
                        lastPeak = nil  // Reset per iniziare pattern pulito
                        return RepDetectionResult(
                            repDetected: false,
                            currentValue: current,
                            peakVelocity: nil
                        )
                    }
                    
                    // Validazione MINIMA
                    let amplitude = peak.value - valley.value
                    let timeSinceLast = lastRepTime?.timeIntervalSinceNow ?? -1.0
                    let validTiming = abs(timeSinceLast) > minTimeBetween || lastRepTime == nil
                                        
                    // FILTRO INTELLIGENTE: Ignora micro-movimenti dopo inattività
                    let timeSinceMovement = lastMovementTime?.timeIntervalSinceNow ?? 0
                    let isAfterLongPause = abs(timeSinceMovement) > 2.0
                    
                    // Se sono fermo da > 2s, richiedi ampiezza maggiore (anti-rumore fine serie)
                    let amplitudeThreshold = isAfterLongPause ? minAmplitude * 1.5 : minAmplitude
                    
                    // CONTA se: ampiezza OK + timing OK
                    if amplitude >= amplitudeThreshold && validTiming {
                        
                        // Calcola velocità
                        let duration = valley.time.timeIntervalSince(peak.time)
                        peakVelocity = estimateVelocity(amplitude: amplitude, duration: abs(duration))
                        
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
                              "Vel: \(String(format: "%.2f", peakVelocity!)) m/s")
                        
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
        
        return RepDetectionResult(
            repDetected: repDetected,
            currentValue: current,
            peakVelocity: peakVelocity
        )
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
            if delta > 0.03 { ups += 1 }       // Soglia rumore: 0.03g
            else if delta < -0.03 { downs += 1 }
        }
        
        // Decidi direzione
        if ups >= 2 && ups > downs { return .up }
        if downs >= 2 && downs > ups { return .down }
        
        return currentDirection  // Mantieni direzione precedente se incerto
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
    
    // MARK: - Helper: Velocity Estimation
    
    private func estimateVelocity(amplitude: Double, duration: Double) -> Double {
        // ROM stimato in base ad ampiezza
        let estimatedROM: Double
        if amplitude < 0.4 {
            estimatedROM = 0.20  // Movimento parziale
        } else if amplitude < 0.7 {
            estimatedROM = 0.45  // Panca standard
        } else if amplitude < 1.0 {
            estimatedROM = 0.60  // Movimento ampio
        } else {
            estimatedROM = 0.75  // Squat completo
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
    let peakVelocity: Double?
}
