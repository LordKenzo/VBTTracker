//
//  VBTRepDetector.swift
//  VBTTracker
//
//  Algoritmo VBT CORRETTO basato su letteratura scientifica
//  Conta SOLO fase concentrica (salita/spinta)
//

import Foundation

class VBTRepDetector {
    
    // MARK: - Configuration
    
    /// Modalità misurazione velocità
    enum VelocityMeasurementMode {
        case concentricOnly    // Standard VBT (solo fase concentrica)
        case fullROM          // ROM completo (eccentrica + concentrica)
    }
    
    var velocityMode: VelocityMeasurementMode = .concentricOnly
    
    /// Smoothing
    private let windowSize: Int = 10  // ⭐ Aumentato da 7 a 10 (più smoothing)
    
    /// Soglia accelerazione per rilevare movimento attivo (m/s²)
    private let activeMovementThreshold: Double = 3.0
    
    /// Ampiezza minima fase concentrica (g)
    private let minConcentricAmplitude: Double = 0.45  // ⭐ Aumentato da 0.4 a 0.45
    
    /// Tempo minimo tra rep (s)
    private let minTimeBetweenReps: TimeInterval = 1.2  // ⭐ Aumentato da 0.6 a 1.2
    
    /// Durata minima fase concentrica (s) - evita micro-movimenti
    private let minConcentricDuration: TimeInterval = 0.3  // ⭐ NUOVO
    
    // MARK: - State
    
    private var samples: [AccelerationSample] = []
    private var smoothedValues: [Double] = []
    
    private var currentPhase: Phase = .idle
    private var lastRepTime: Date?
    
    private var concentricStartValue: Double?
    private var concentricStartTime: Date?
    private var concentricPeakValue: Double = 0
    private var concentricPeakTime: Date?
    
    // ⭐ Per modalità Full ROM
    private var eccentricStartValue: Double?
    private var eccentricStartTime: Date?
    private var totalROMStartValue: Double?
    private var totalROMStartTime: Date?
    
    enum Phase {
        case idle              // Fermo (su rack o inizio)
        case eccentric         // Discesa (al petto)
        case concentric        // Salita (spinta) ⭐ QUESTA È LA REP
        case returnToRack      // Ritorno a rack (dopo completamento)
    }
    
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
        
        return detectConcentricPhase()
    }
    
    func reset() {
        samples.removeAll()
        smoothedValues.removeAll()
        currentPhase = .idle
        lastRepTime = nil
        concentricStartValue = nil
        concentricPeakValue = 0
        eccentricStartValue = nil
        eccentricStartTime = nil
        totalROMStartValue = nil
        totalROMStartTime = nil
    }
    
    func getSamples() -> [AccelerationSample] {
        return samples
    }
    
    // MARK: - Private Methods
    
    private func calculateMovingAverage() -> Double {
        guard samples.count >= windowSize else {
            return samples.last?.accZ ?? 0
        }
        
        let window = samples.suffix(windowSize)
        let sum = window.reduce(0.0) { $0 + $1.accZ }
        return sum / Double(windowSize)
    }
    
    /// ⭐ ALGORITMO VBT CORRETTO
    private func detectConcentricPhase() -> RepDetectionResult {
        guard smoothedValues.count >= 3 else {
            return RepDetectionResult(
                repDetected: false,
                currentValue: samples.last?.accZ ?? 0,
                peakVelocity: nil
            )
        }
        
        let current = smoothedValues[smoothedValues.count - 1]
        let previous = smoothedValues[smoothedValues.count - 2]
        let beforePrevious = smoothedValues[smoothedValues.count - 3]
        
        var repDetected = false
        var peakVelocity: Double = 0
        
        // 1️⃣ RILEVA INIZIO ECCENTRICA (discesa significativa)
        if currentPhase == .idle || currentPhase == .returnToRack {
            // Rileva discesa: valore diventa negativo e scende
            if current < -0.2 && current < previous {
                currentPhase = .eccentric
                
                // ⭐ Per Full ROM: registra inizio movimento totale
                if velocityMode == .fullROM {
                    eccentricStartValue = current
                    eccentricStartTime = Date()
                    totalROMStartValue = current
                    totalROMStartTime = Date()
                }
                
                print("📉 ECCENTRICA iniziata (discesa al petto)")
            }
        }
        
        // 2️⃣ RILEVA INIZIO CONCENTRICA (inversione del movimento)
        if currentPhase == .eccentric {
            // Rileva valle (punto più basso = petto)
            if previous < beforePrevious && previous < current {
                // Valle trovata = INIZIO CONCENTRICA
                currentPhase = .concentric
                concentricStartValue = previous
                concentricStartTime = Date()
                concentricPeakValue = previous
                
                print("🟢 CONCENTRICA iniziata - Start: \(String(format: "%.2f", previous))g")
            }
        }
        
        // 3️⃣ MONITORA FASE CONCENTRICA (salita)
        if currentPhase == .concentric {
            // Aggiorna picco se stiamo salendo
            if current > concentricPeakValue {
                concentricPeakValue = current
                concentricPeakTime = Date()
            }
            
            // Rileva FINE CONCENTRICA (picco raggiunto e inizia discesa)
            if previous > beforePrevious && previous > current {
                // Picco trovato = FINE CONCENTRICA = ✅ CONTA REP
                
                guard let startValue = concentricStartValue else {
                    currentPhase = .returnToRack
                    return RepDetectionResult(
                        repDetected: false,
                        currentValue: current,
                        peakVelocity: nil
                    )
                }
                
                let amplitude = concentricPeakValue - startValue
                let duration = concentricPeakTime?.timeIntervalSince(concentricStartTime ?? Date()) ?? 0
                
                // ⭐ Calcola velocità in base alla modalità
                let velocity: Double
                let velocityLabel: String
                
                switch velocityMode {
                case .concentricOnly:
                    // Standard VBT: solo fase concentrica
                    velocity = calculateVelocity(
                        amplitude: amplitude,
                        duration: duration
                    )
                    velocityLabel = "Concentrica"
                    
                case .fullROM:
                    // Full ROM: da inizio eccentrica a fine concentrica
                    if let totalStart = totalROMStartValue,
                       let totalStartTime = totalROMStartTime {
                        let totalAmplitude = concentricPeakValue - totalStart
                        let totalDuration = Date().timeIntervalSince(totalStartTime)
                        velocity = calculateVelocity(
                            amplitude: abs(totalAmplitude),
                            duration: totalDuration
                        )
                        velocityLabel = "Full ROM"
                    } else {
                        // Fallback
                        velocity = calculateVelocity(amplitude: amplitude, duration: duration)
                        velocityLabel = "Concentrica (fallback)"
                    }
                }
                
                // Validazione
                let timeSinceLastRep = lastRepTime?.timeIntervalSinceNow ?? -1.0
                let validTiming = abs(timeSinceLastRep) > minTimeBetweenReps || lastRepTime == nil
                let validAmplitude = amplitude >= minConcentricAmplitude
                
                if validAmplitude && validTiming {
                    // ✅ REP VALIDA
                    peakVelocity = velocity
                    
                    repDetected = true
                    lastRepTime = Date()
                    
                    // Marca picco
                    if samples.count >= 2 {
                        samples[samples.count - 2].isPeak = true
                    }
                    
                    print("✅ REP [\(velocityLabel)] - Ampiezza: \(String(format: "%.2f", amplitude))g, Durata: \(String(format: "%.2f", duration))s, Velocità: \(String(format: "%.2f", velocity)) m/s")
                    
                    // Passa a fase eccentrica (o ritorno rack)
                    currentPhase = .eccentric
                } else {
                    print("⚠️ Rep ignorata - Ampiezza: \(String(format: "%.2f", amplitude))g, Timing: \(validTiming)")
                    currentPhase = .returnToRack
                }
                
                // Reset per prossima rep
                concentricStartValue = nil
                concentricPeakValue = 0
                totalROMStartValue = nil  // ⭐ Reset anche per Full ROM
            }
        }
        
        // 4️⃣ RILEVA RITORNO A IDLE (bilanciere fermo su rack)
        if abs(current) < 0.1 && abs(previous) < 0.1 {
            if currentPhase != .idle {
                print("⏸️  Ritorno a IDLE (rack)")
            }
            currentPhase = .idle
        }
        
        return RepDetectionResult(
            repDetected: repDetected,
            currentValue: current,
            peakVelocity: repDetected ? peakVelocity : nil
        )
    }
    
    /// Calcola velocità media propulsiva (MPV)
    /// Basato su v = sqrt(2 * a * s) e considerando durata
    private func calculateVelocity(amplitude: Double, duration: Double) -> Double {
        // Converti ampiezza da g a m/s²
        let accelMS2 = amplitude * 9.81
        
        // Stima distanza ROM (Range of Motion)
        // Panca piana: ~50cm, Squat: ~70cm
        let estimatedROM: Double
        if amplitude < 0.6 {
            estimatedROM = 0.3  // Movimento corto
        } else if amplitude < 1.0 {
            estimatedROM = 0.5  // Movimento medio (panca)
        } else {
            estimatedROM = 0.7  // Movimento lungo (squat)
        }
        
        // Velocità media: v_avg = distance / time
        if duration > 0.1 {
            return estimatedROM / duration
        } else {
            // Fallback: formula cinematica
            return sqrt(2.0 * abs(accelMS2) * estimatedROM)
        }
    }
}

// MARK: - Result Model

struct RepDetectionResult {
    let repDetected: Bool
    let currentValue: Double
    let peakVelocity: Double?
}
