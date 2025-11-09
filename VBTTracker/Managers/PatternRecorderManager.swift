//
//  PatternRecorderManager.swift
//  VBTTracker
//
//  🎙️ Manager per registrazione manuale pattern
//  ✅ Flusso: START → Recording → STOP → Form → Save
//

import Foundation
import Combine

@MainActor
final class PatternRecorderManager: ObservableObject {
    
    // MARK: - Published State
    
    @Published var isRecording = false
    @Published var hasRecordedData = false
    @Published var duration: TimeInterval = 0.0
    @Published var sampleCount: Int = 0
    
    // MARK: - Recording State
    
    enum RecordingState {
        case idle
        case recording
        case readyToSave
    }
    
    @Published var state: RecordingState = .idle
    
    // MARK: - Private Storage
    
    private var samples: [AccelerationSample] = []
    private var startTime: Date?
    private var timer: Timer?
    
    // Detector per analisi
    private let detector = VBTRepDetector()
    
    // MARK: - Public Methods
    
    /// Inizia la registrazione
    func startRecording() {
        samples.removeAll()
        startTime = Date()
        duration = 0.0
        sampleCount = 0
        
        state = .recording
        isRecording = true
        hasRecordedData = false
        
        detector.reset()
        
        // Timer per aggiornare durata
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor [weak self] in
                guard let self = self, let start = self.startTime else { return }
                self.duration = Date().timeIntervalSince(start)
            }
        }
        
        print("🎙️ Registrazione pattern iniziata")
    }
    
    /// Ferma la registrazione
    func stopRecording() {
        timer?.invalidate()
        timer = nil
        
        isRecording = false
        hasRecordedData = !samples.isEmpty
        
        if hasRecordedData {
            state = .readyToSave
            print("✅ Registrazione fermata: \(samples.count) campioni, \(String(format: "%.1f", duration))s")
        } else {
            state = .idle
            print("⚠️ Nessun dato registrato")
        }
    }
    
    /// Cancella la registrazione corrente
    func cancelRecording() {
        timer?.invalidate()
        timer = nil
        
        samples.removeAll()
        startTime = nil
        duration = 0.0
        sampleCount = 0
        
        isRecording = false
        hasRecordedData = false
        state = .idle
        
        detector.reset()
        
        print("🗑️ Registrazione cancellata")
    }
    
    /// Aggiunge un campione durante la registrazione
    func addSample(accZ: Double, timestamp: Date) {
        guard isRecording else { return }
        
        let sample = AccelerationSample(timestamp: timestamp, accZ: accZ)
        samples.append(sample)
        sampleCount = samples.count
        
        // Passa anche al detector per analisi
        _ = detector.addSample(accZ: accZ, timestamp: timestamp)
    }
    
    /// Salva il pattern con i dati del form
    func savePattern(
        label: String,
        repCount: Int,
        loadPercentage: Double?
    ) {
        guard !samples.isEmpty else {
            print("⚠️ Impossibile salvare: nessun dato")
            return
        }
        
        // Estrai metriche base
        let accZ = samples.map { $0.accZ }
        let amplitude = (accZ.max() ?? 0) - (accZ.min() ?? 0)
        
        // Calcola MPV/PPV medi stimati
        // Nota: in una registrazione reale queste dovrebbero venire dal detector
        let avgMPV = estimateAvgMPV(from: samples, repCount: repCount)
        let avgPPV = estimateAvgPPV(from: samples, repCount: repCount)
        
        // Crea feature vector
        let features = createFeatureVector(from: samples)

        // Crea pattern con esercizio corrente
        let pattern = PatternSequence(
            id: UUID(),
            date: Date(),
            label: label,
            exerciseId: ExerciseManager.shared.selectedExercise.id,
            repCount: repCount,
            loadPercentage: loadPercentage,
            avgDuration: duration / Double(max(repCount, 1)),
            avgAmplitude: amplitude,
            avgMPV: avgMPV,
            avgPPV: avgPPV,
            featureVector: features
        )
        
        // Salva nella libreria
        LearnedPatternLibrary.shared.addPattern(pattern)
        
        print("💾 Pattern salvato:")
        print("   • Label: \(label)")
        print("   • Reps: \(repCount)")
        if let load = loadPercentage {
            print("   • Carico: \(Int(load))%")
        }
        print("   • Durata: \(String(format: "%.1f", duration))s")
        print("   • Campioni: \(samples.count)")
        
        // Reset dopo salvataggio
        reset()
    }
    
    /// Reset completo
    func reset() {
        cancelRecording()
    }
    
    // MARK: - Private Helpers
    
    /// Stima MPV media dalle accelerazioni
    private func estimateAvgMPV(from samples: [AccelerationSample], repCount: Int) -> Double {
        guard !samples.isEmpty, repCount > 0 else { return 0.0 }
        
        let accZ = samples.map { $0.accZ * 9.81 } // g → m/s²
        let avgAcc = accZ.reduce(0, +) / Double(accZ.count)
        
        // Stima semplice: v = a * t (assumendo fase concentrica ~0.5-1s)
        let estimatedV = abs(avgAcc) * 0.7
        
        return max(0.05, min(estimatedV, 2.5)) // clamp 0.05-2.5 m/s
    }
    
    /// Stima PPV media dalle accelerazioni
    private func estimateAvgPPV(from samples: [AccelerationSample], repCount: Int) -> Double {
        guard !samples.isEmpty, repCount > 0 else { return 0.0 }
        
        // PPV tipicamente 1.2-1.5x MPV
        let mpv = estimateAvgMPV(from: samples, repCount: repCount)
        let ppv = mpv * 1.3
        
        return max(0.05, min(ppv, 3.0)) // clamp 0.05-3.0 m/s
    }
    
    /// Crea feature vector per matching
    private func createFeatureVector(from samples: [AccelerationSample]) -> [Double] {
        guard samples.count > 3 else { return [] }
        
        let accZ = samples.map { $0.accZ }
        
        let mean = accZ.reduce(0, +) / Double(accZ.count)
        let std = sqrt(accZ.map { pow($0 - mean, 2) }.reduce(0, +) / Double(accZ.count))
        let range = (accZ.max() ?? 0) - (accZ.min() ?? 0)
        
        let diffs = zip(accZ.dropFirst(), accZ).map { $0 - $1 }
        let spectralEnergy = sqrt(diffs.map { $0 * $0 }.reduce(0, +) / Double(diffs.count))
        
        return [
            mean / 1.0,
            std / 1.0,
            range / 2.0,
            spectralEnergy / 1.0,
            Double(samples.count) / 100.0
        ]
    }
}
