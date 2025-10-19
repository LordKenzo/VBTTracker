//
//  ROMCalibrationManager.swift
//  VBTTracker
//
//  Calibrazione ROM - DUAL MODE (Automatic + Manual)
//

import Foundation
import Combine

class ROMCalibrationManager: ObservableObject {
    
    // MARK: - Mode Selection
    
    @Published var calibrationMode: CalibrationMode = .automatic
    
    // MARK: - Automatic Mode State
    
    @Published var automaticState: AutomaticCalibrationState = .idle
    private var automaticCalibrationReps: [AutomaticCalibrationRep] = []
    private let requiredAutomaticReps: Int = 2
    
    // MARK: - Manual Mode State
    
    @Published var manualState: ManualCalibrationState = .idle
    @Published var currentManualStep: ManualCalibrationStep = .step1_unrackAndLockout
    @Published var isRecordingStep: Bool = false
    @Published var manualStepData: [ManualCalibrationStep: StepRecording] = [:]
    
    private var recordingStartTime: Date?
    private var recordingSamples: [AccelerationSample] = []
    
    // MARK: - Common State
    
    @Published var calibrationProgress: Double = 0.0
    @Published var statusMessage: String = "Pronto per calibrazione"
    @Published var learnedPattern: LearnedPattern?
    @Published var isCalibrated: Bool = false
    
    // MARK: - Internal Components
    
    private var samples: [AccelerationSample] = []
    private var detector: VBTRepDetector
    private var lastSignificantMovement: Date?
    private var restStartTime: Date?
    private let restDetectionTime: TimeInterval = 3.0
    
    // MARK: - Initialization
    
    init() {
        self.detector = VBTRepDetector()
        self.detector.velocityMode = .concentricOnly
        loadPattern()
    }
    
    // MARK: - Public Methods - Mode Selection
    
    func selectMode(_ mode: CalibrationMode) {
        reset()
        calibrationMode = mode
        statusMessage = mode == .automatic ?
            "Pronto per calibrazione automatica" :
            "Pronto per calibrazione manuale"
    }
    
    // MARK: - Automatic Mode Methods
    
    func startAutomaticCalibration() {
        reset()
        calibrationMode = .automatic
        automaticState = .waitingForFirstRep
        statusMessage = "Esegui 2 ripetizioni lente e controllate"
        print("🎯 Calibrazione AUTOMATICA iniziata")
    }
    
    func processAutomaticSample(accZ: Double, timestamp: Date) {
        guard automaticState == .waitingForFirstRep ||
              automaticState == .detectingReps ||
              automaticState == .waitingForLoad else {
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
            
            if automaticState == .waitingForFirstRep {
                automaticState = .detectingReps
                statusMessage = "Rep 1/\(requiredAutomaticReps)..."
            }
        }
        
        // 2️⃣ Durante rilevamento rep
        if automaticState == .detectingReps {
            let result = detector.addSample(accZ: accZ, timestamp: timestamp)
            
            if result.repDetected, let peakVel = result.peakVelocity {
                recordAutomaticRep(
                    samples: detector.getSamples(),
                    peakVelocity: peakVel,
                    timestamp: timestamp
                )
                
                calibrationProgress = Double(automaticCalibrationReps.count) / Double(requiredAutomaticReps)
                
                if automaticCalibrationReps.count < requiredAutomaticReps {
                    statusMessage = "Rep \(automaticCalibrationReps.count)/\(requiredAutomaticReps) completata. Fai la prossima..."
                } else {
                    analyzeAutomaticData()
                }
            }
        }
        
        // 3️⃣ Rileva periodo di rest dopo analisi
        if automaticState == .waitingForLoad {
            if abs(accZ) < 0.08 {
                if restStartTime == nil {
                    restStartTime = timestamp
                }
                
                if let restStart = restStartTime {
                    let restDuration = timestamp.timeIntervalSince(restStart)
                    if restDuration >= restDetectionTime {
                        automaticState = .completed
                        statusMessage = "✅ Calibrazione completata! Inizia serie"
                        print("✅ Calibrazione AUTOMATICA completata")
                    }
                }
            } else {
                restStartTime = nil
            }
        }
    }
    
    private func recordAutomaticRep(samples: [AccelerationSample],
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
        
        let rep = AutomaticCalibrationRep(
            amplitude: amplitude,
            concentricDuration: concentricDuration,
            eccentricDuration: eccentricDuration,
            peakVelocity: peakVelocity,
            samples: samples
        )
        
        automaticCalibrationReps.append(rep)
        
        print("📊 Rep AUTO \(automaticCalibrationReps.count) - " +
              "Amp: \(String(format: "%.2f", amplitude))g, " +
              "Vel: \(String(format: "%.2f", peakVelocity)) m/s")
    }
    
    private func analyzeAutomaticData() {
        guard automaticCalibrationReps.count >= requiredAutomaticReps else {
            automaticState = .failed("Dati insufficienti")
            return
        }
        
        automaticState = .analyzing
        statusMessage = "Analisi pattern..."
        
        let avgAmp = automaticCalibrationReps.map { $0.amplitude }.reduce(0, +) / Double(automaticCalibrationReps.count)
        let avgConcentric = automaticCalibrationReps.map { $0.concentricDuration }.reduce(0, +) / Double(automaticCalibrationReps.count)
        let avgEccentric = automaticCalibrationReps.map { $0.eccentricDuration }.reduce(0, +) / Double(automaticCalibrationReps.count)
        let avgVel = automaticCalibrationReps.map { $0.peakVelocity }.reduce(0, +) / Double(automaticCalibrationReps.count)
        
        let estimatedROM = estimateROM(amplitude: avgAmp, velocity: avgVel, duration: avgConcentric)
        
        learnedPattern = LearnedPattern.fromAutomaticCalibration(
            amplitude: avgAmp,
            concentricDuration: avgConcentric,
            eccentricDuration: avgEccentric,
            peakVelocity: avgVel,
            rom: estimatedROM
        )
        
        isCalibrated = true
        automaticState = .waitingForLoad
        statusMessage = "✅ Pattern appreso! Carica bilanciere e aspetta 3s"
        
        savePattern()
        
        print("🎓 Pattern AUTOMATICO appreso:")
        print("   • Ampiezza: \(String(format: "%.2f", avgAmp))g")
        print("   • Durata concentrica: \(String(format: "%.2f", avgConcentric))s")
        print("   • Velocità media: \(String(format: "%.2f", avgVel)) m/s")
        print("   • ROM stimato: \(String(format: "%.0f", estimatedROM * 100))cm")
    }
    
    // MARK: - Manual Mode Methods
    
    func startManualCalibration() {
        reset()
        calibrationMode = .manual
        currentManualStep = .step1_unrackAndLockout
        manualState = .instructionsShown(.step1_unrackAndLockout)
        statusMessage = "Step 1/5: Leggi le istruzioni"
        calibrationProgress = 0.0
        print("🎯 Calibrazione MANUALE iniziata")
    }
    
    func startRecordingStep() {
        guard case .instructionsShown(let step) = manualState else {
            print("⚠️ Non è possibile registrare: stato non corretto")
            return
        }
        
        isRecordingStep = true
        recordingStartTime = Date()
        recordingSamples.removeAll()
        manualState = .recording(step)
        statusMessage = "🔴 REGISTRAZIONE in corso..."
        
        print("🔴 Inizio registrazione step: \(step.title)")
    }
    
    func processManualSample(accZ: Double, timestamp: Date) {
        guard isRecordingStep,
              case .recording = manualState else {
            return
        }
        
        let sample = AccelerationSample(timestamp: timestamp, accZ: accZ)
        recordingSamples.append(sample)
    }
    
    func stopRecordingStep() {
        guard isRecordingStep,
              case .recording(let step) = manualState,
              let startTime = recordingStartTime else {
            print("⚠️ Nessuna registrazione in corso")
            return
        }
        
        isRecordingStep = false
        let endTime = Date()
        
        // Crea StepRecording
        let recording = StepRecording(
            step: step,
            samples: recordingSamples,
            startTime: startTime,
            endTime: endTime
        )
        
        // Salva dati step
        manualStepData[step] = recording
        manualState = .stepCompleted(step)
        
        print("✅ Step completato: \(step.title)")
        print("   • Durata: \(String(format: "%.2f", recording.duration))s")
        print("   • Campioni: \(recording.sampleCount)")
        print("   • Ampiezza: \(String(format: "%.2f", recording.amplitude))g")
        
        // Aggiorna progress
        calibrationProgress = step.progressValue
        
        // Verifica se è l'ultimo step
        if step.isLastStep {
            analyzeManualData()
        } else {
            statusMessage = "✅ Step completato! Pronto per il prossimo"
        }
    }
    
    func nextManualStep() {
        guard case .stepCompleted(let currentStep) = manualState,
              let nextStep = currentStep.next() else {
            print("⚠️ Nessuno step successivo disponibile")
            return
        }
        
        currentManualStep = nextStep
        manualState = .instructionsShown(nextStep)
        statusMessage = "Step \(nextStep.rawValue + 1)/5: Leggi le istruzioni"
        
        print("➡️ Avanzamento a step: \(nextStep.title)")
    }
    
    private func analyzeManualData() {
        guard manualStepData.count == 5 else {
            manualState = .failed("Dati incompleti: \(manualStepData.count)/5 step")
            return
        }
        
        manualState = .analyzing
        statusMessage = "Analisi dati..."
        
        // Estrai dati per fase
        guard let step1 = manualStepData[.step1_unrackAndLockout],
              let step2 = manualStepData[.step2_eccentricDown],
              let step3 = manualStepData[.step3_concentricUp],
              let step4 = manualStepData[.step4_eccentricDown2],
              let step5 = manualStepData[.step5_concentricUp2] else {
            manualState = .failed("Dati step mancanti")
            return
        }
        
        let eccentricData = [step2, step4]
        let concentricData = [step3, step5]
        
        // Crea pattern usando factory method
        learnedPattern = LearnedPattern.fromManualCalibration(
            unrackData: step1,
            eccentricData: eccentricData,
            concentricData: concentricData
        )
        
        isCalibrated = true
        manualState = .completed
        calibrationProgress = 1.0
        statusMessage = "✅ Calibrazione MANUALE completata!"
        
        savePattern()
        
        print("🎓 Pattern MANUALE appreso:")
        if let pattern = learnedPattern {
            print("   • Ampiezza: \(String(format: "%.2f", pattern.avgAmplitude))g")
            print("   • Durata concentrica: \(String(format: "%.2f", pattern.avgConcentricDuration))s")
            print("   • Durata eccentrica: \(String(format: "%.2f", pattern.avgEccentricDuration))s")
            print("   • Velocità media: \(String(format: "%.2f", pattern.avgPeakVelocity)) m/s")
            print("   • ROM stimato: \(String(format: "%.0f", pattern.estimatedROM * 100))cm")
        }
    }
    
    // MARK: - Common Methods
    
    func skipCalibration() {
        learnedPattern = LearnedPattern.defaultPattern
        isCalibrated = true
        
        if calibrationMode == .automatic {
            automaticState = .completed
        } else {
            manualState = .completed
        }
        
        statusMessage = "Pattern default caricato"
        savePattern()
        print("⚠️ Calibrazione saltata - Usando defaults")
    }
    
    func savePattern() {
        guard let pattern = learnedPattern else { return }
        
        if let encoded = try? JSONEncoder().encode(pattern) {
            UserDefaults.standard.set(encoded, forKey: "learnedPattern")
            print("💾 Pattern salvato (\(pattern.calibrationMode.displayName))")
        }
    }
    
    func loadPattern() {
        if let data = UserDefaults.standard.data(forKey: "learnedPattern"),
           let pattern = try? JSONDecoder().decode(LearnedPattern.self, from: data) {
            learnedPattern = pattern
            isCalibrated = true
            
            if calibrationMode == .automatic {
                automaticState = .completed
            } else {
                manualState = .completed
            }
            
            statusMessage = "Pattern caricato: \(pattern.shortDescription)"
            print("📂 Pattern caricato: \(pattern.description)")
        }
    }
    
    func deletePattern() {
        UserDefaults.standard.removeObject(forKey: "learnedPattern")
        learnedPattern = nil
        isCalibrated = false
        reset()
        print("🗑️ Pattern eliminato")
    }
    
    func reset() {
        // Reset automatic state
        automaticState = .idle
        automaticCalibrationReps.removeAll()
        
        // Reset manual state
        manualState = .idle
        currentManualStep = .step1_unrackAndLockout
        isRecordingStep = false
        manualStepData.removeAll()
        recordingStartTime = nil
        recordingSamples.removeAll()
        
        // Reset common state
        calibrationProgress = 0.0
        samples.removeAll()
        detector.reset()
        lastSignificantMovement = nil
        restStartTime = nil
        learnedPattern = nil
        isCalibrated = false
        
        statusMessage = "Pronto per calibrazione"
    }
    
    // MARK: - Helper Methods
    
    private func estimateROM(amplitude: Double, velocity: Double, duration: Double) -> Double {
        let romFromAmplitude = amplitude * 0.30
        let estimated = min(max(romFromAmplitude, 0.20), 0.80)
        return estimated
    }
    
    // MARK: - Computed Properties
    
    var isInProgress: Bool {
        switch calibrationMode {
        case .automatic:
            return automaticState != .idle && automaticState != .completed
        case .manual:
            return manualState != .idle && manualState != .completed
        }
    }
    
    var canStartRecording: Bool {
        if case .instructionsShown = manualState {
            return true
        }
        return false
    }
    
    var currentStepProgress: String {
        guard calibrationMode == .manual else { return "" }
        return "\(currentManualStep.rawValue + 1)/5"
    }
}

// MARK: - Private Data Models

private struct AutomaticCalibrationRep {
    let amplitude: Double
    let concentricDuration: Double
    let eccentricDuration: Double
    let peakVelocity: Double
    let samples: [AccelerationSample]
}
