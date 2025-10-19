//
//  ROMCalibrationManager.swift
//  VBTTracker
//
//  Calibrazione ROM e Pattern Learning per VBT
//

import Foundation
import Combine

/// Gestisce la calibrazione del Range of Motion e pattern dell'atleta
class ROMCalibrationManager: ObservableObject {
    
    // MARK: - Published State
    
    @Published var calibrationState: CalibrationState = .idle
    @Published var calibrationProgress: Double = 0.0  // 0.0 - 1.0
    @Published var statusMessage: String = "Pronto per calibrazione"
    
    @Published var learnedPattern: LearnedPattern?
    @Published var isCalibrated: Bool = false
    
    // ✅ AGGIUNTO Equatable
    enum CalibrationState: Equatable {
        case idle
        case waitingForFirstRep
        case detectingReps
        case analyzing
        case waitingForLoad
        case completed
        case failed(String)
    }
    
    // MARK: - Configuration
    
    private let requiredReps: Int = 2
    private let restDetectionTime: TimeInterval = 3.0
    
    // MARK: - Internal State
    
    private var calibrationReps: [CalibrationRep] = []
    private var samples: [AccelerationSample] = []
    private var detector: VBTRepDetector
    
    private var lastSignificantMovement: Date?
    private var restStartTime: Date?
    
    // MARK: - Initialization
    
    init() {
        self.detector = VBTRepDetector()
        self.detector.velocityMode = .concentricOnly
        loadPattern()
    }
    
    // MARK: - Public Methods
    
    func startCalibration() {
        reset()
        calibrationState = .waitingForFirstRep
        statusMessage = "Esegui 2 ripetizioni lente e controllate"
        print("🎯 Calibrazione ROM iniziata")
    }
    
    func processSample(accZ: Double, timestamp: Date) {
        guard calibrationState == .waitingForFirstRep ||
              calibrationState == .detectingReps ||
              calibrationState == .waitingForLoad else {
            return
        }
        
        let sample = AccelerationSample(timestamp: timestamp, accZ: accZ)
        samples.append(sample)
        
        if samples.count > 500 {
            samples.removeFirst()
        }
        
        // 1️⃣ Rileva movimento significativo
        if abs(accZ) > 0.15 {
            lastSignificantMovement = timestamp
            restStartTime = nil
            
            if calibrationState == .waitingForFirstRep {
                calibrationState = .detectingReps
                statusMessage = "Rep 1/\(requiredReps)..."
            }
        }
        
        // 2️⃣ Durante rilevamento rep
        if calibrationState == .detectingReps {
            let result = detector.addSample(accZ: accZ, timestamp: timestamp)
            
            if result.repDetected, let peakVel = result.peakVelocity {
                recordCalibrationRep(
                    samples: detector.getSamples(),
                    peakVelocity: peakVel,
                    timestamp: timestamp
                )
                
                calibrationProgress = Double(calibrationReps.count) / Double(requiredReps)
                
                DispatchQueue.main.async {
                    if self.calibrationReps.count < self.requiredReps {
                        self.statusMessage = "Rep \(self.calibrationReps.count)/\(self.requiredReps) completata. Fai la prossima..."
                        print("📊 Rep \(self.calibrationReps.count)/\(self.requiredReps) - Aspetto la prossima")
                    } else {
                        // Solo DOPO la seconda rep → analizza
                        self.analyzeCalibrationData()
                        print("🔍 DEBUG: calibrationReps.count = \(self.calibrationReps.count), requiredReps = \(self.requiredReps)")

                    }
                    
                }
            }
        }
        
        // 3️⃣ Rileva periodo di rest
        if calibrationState == .waitingForLoad {
            if abs(accZ) < 0.08 {
                if restStartTime == nil {
                    restStartTime = timestamp
                }
                
                let restDuration = timestamp.timeIntervalSince(restStartTime!)
                if restDuration >= restDetectionTime {
                    calibrationState = .completed
                    statusMessage = "✅ Calibrazione completata! Inizia serie"
                    print("✅ Calibrazione completata - Pattern appreso")
                }
            } else {
                restStartTime = nil
            }
        }
    }
    
    func skipCalibration() {
        learnedPattern = LearnedPattern(
            avgAmplitude: 0.7,
            avgConcentricDuration: 0.8,
            avgEccentricDuration: 1.0,
            avgPeakVelocity: 1.0,
            unrackThreshold: 0.15,
            restThreshold: 0.08,
            estimatedROM: 0.45
        )
        
        isCalibrated = true
        calibrationState = .completed
        statusMessage = "Pattern default caricato"
        savePattern()
        print("⚠️ Calibrazione saltata - Usando defaults")
    }
    
    func savePattern() {
        guard let pattern = learnedPattern else { return }
        
        if let encoded = try? JSONEncoder().encode(pattern) {
            UserDefaults.standard.set(encoded, forKey: "learnedPattern")
            print("💾 Pattern salvato in UserDefaults")
        }
    }
    
    func loadPattern() {
        if let data = UserDefaults.standard.data(forKey: "learnedPattern"),
           let pattern = try? JSONDecoder().decode(LearnedPattern.self, from: data) {
            learnedPattern = pattern
            isCalibrated = true
            calibrationState = .completed
            print("📂 Pattern caricato da storage")
        }
    }
    
    func reset() {
        calibrationState = .idle
        calibrationProgress = 0.0
        calibrationReps.removeAll()
        samples.removeAll()
        detector.reset()
        lastSignificantMovement = nil
        restStartTime = nil
        learnedPattern = nil
        isCalibrated = false
    }
    
    // MARK: - Private Methods
    
    private func recordCalibrationRep(samples: [AccelerationSample],
                                     peakVelocity: Double,
                                     timestamp: Date) {
        let values = samples.map { $0.accZ }
        
        guard let maxVal = values.max(),
              let minVal = values.min() else {
            return
        }
        
        let amplitude = maxVal - minVal
        let concentricSamples = samples.filter { $0.accZ > 0 }
        let eccentricSamples = samples.filter { $0.accZ < 0 }
        
        let concentricDuration = Double(concentricSamples.count) * 0.02
        let eccentricDuration = Double(eccentricSamples.count) * 0.02
        
        let rep = CalibrationRep(
            amplitude: amplitude,
            concentricDuration: concentricDuration,
            eccentricDuration: eccentricDuration,
            peakVelocity: peakVelocity,
            samples: samples
        )
        
        calibrationReps.append(rep)
        
        print("📊 Rep \(calibrationReps.count) registrata - " +
              "Amp: \(String(format: "%.2f", amplitude))g, " +
              "Vel: \(String(format: "%.2f", peakVelocity)) m/s")
    }
    
    private func analyzeCalibrationData() {
        guard calibrationReps.count >= requiredReps else {
            calibrationState = .failed("Dati insufficienti")
            return
        }
        
        calibrationState = .analyzing
        statusMessage = "Analisi pattern..."
        
        let avgAmp = calibrationReps.map { $0.amplitude }.reduce(0, +) / Double(calibrationReps.count)
        let avgConcentric = calibrationReps.map { $0.concentricDuration }.reduce(0, +) / Double(calibrationReps.count)
        let avgEccentric = calibrationReps.map { $0.eccentricDuration }.reduce(0, +) / Double(calibrationReps.count)
        let avgVel = calibrationReps.map { $0.peakVelocity }.reduce(0, +) / Double(calibrationReps.count)
        
        let estimatedROM = estimateROM(amplitude: avgAmp, velocity: avgVel, duration: avgConcentric)
        
        learnedPattern = LearnedPattern(
            avgAmplitude: avgAmp,
            avgConcentricDuration: avgConcentric,
            avgEccentricDuration: avgEccentric,
            avgPeakVelocity: avgVel,
            unrackThreshold: avgAmp * 0.2,
            restThreshold: avgAmp * 0.1,
            estimatedROM: estimatedROM
        )
        
        isCalibrated = true
        calibrationState = .waitingForLoad
        statusMessage = "✅ Pattern appreso! Carica bilanciere e aspetta 3s"
        
        savePattern()
        
        print("🎓 Pattern appreso:")
        print("   • Ampiezza: \(String(format: "%.2f", avgAmp))g")
        print("   • Durata concentrica: \(String(format: "%.2f", avgConcentric))s")
        print("   • Velocità media: \(String(format: "%.2f", avgVel)) m/s")
        print("   • ROM stimato: \(String(format: "%.0f", estimatedROM * 100))cm")
    }
    
    private func estimateROM(amplitude: Double, velocity: Double, duration: Double) -> Double {
        let romFromAmplitude = amplitude * 0.30
        
        // Solo per debug/logging
        let accelMS2 = amplitude * 9.81
        let _ = 0.5 * accelMS2 * pow(duration, 2)  // ✅ Assegna a _ per silenzio warning
        
        let estimated = min(max(romFromAmplitude, 0.20), 0.80)
        return estimated
    }
}

// MARK: - Private Data Models

private struct CalibrationRep {
    let amplitude: Double
    let concentricDuration: Double
    let eccentricDuration: Double
    let peakVelocity: Double
    let samples: [AccelerationSample]
}
