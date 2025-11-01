//
//  LearnedPatternLibrary.swift
//  VBTTracker
//
//  Libreria di pattern appresi (mini-ML locale)
//

import Foundation

struct PatternSequence: Identifiable, Codable {
    let id: UUID
    let date: Date
    let label: String              // es. "Squat 60kg"
    let repCount: Int
    let loadPercentage: Double?    // % carico rispetto al massimale (es. 70.0)
    let avgDuration: Double
    let avgAmplitude: Double
    let avgMPV: Double
    let avgPPV: Double
    let featureVector: [Double]
}

@MainActor
final class LearnedPatternLibrary: ObservableObject {
    static let shared = LearnedPatternLibrary()

    @Published private(set) var patterns: [PatternSequence] = []
    private let maxPatterns = 10
    private let saveURL: URL = FileManager.default
        .urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("LearnedPatternLibrary.json")

    private init() { load() }

    // MARK: - Gestione libreria

    func addPattern(_ pattern: PatternSequence) {
        patterns.append(pattern)
        if patterns.count > maxPatterns { patterns.removeFirst() }
        save()
    }

    func removeAll() {
        patterns.removeAll()
        save()
    }
    
    /// Rimuove un singolo pattern per ID
    func removePattern(id: UUID) {
        patterns.removeAll { $0.id == id }
        save()
    }

    func matchPattern(for sequence: [AccelerationSample]) -> PatternSequence? {
        guard !patterns.isEmpty else { return nil }
        let features = featureVector(for: sequence)
        return patterns.min(by: { distance($0.featureVector, features) < distance($1.featureVector, features) })
    }
    
    /// Match intelligente considerando sia feature vector che % carico
    /// Se fornisci loadPercentage, i pattern con carico simile avranno priorità
    func matchPatternWeighted(for sequence: [AccelerationSample], loadPercentage: Double? = nil) -> PatternSequence? {
        guard !patterns.isEmpty else { return nil }
        let features = featureVector(for: sequence)
        
        // Se non abbiamo info sul carico, usa matching standard
        guard let targetLoad = loadPercentage else {
            return matchPattern(for: sequence)
        }
        
        // Calcola score pesato: 70% similarità pattern + 30% vicinanza carico
        let scored = patterns.map { pattern -> (pattern: PatternSequence, score: Double) in
            let featureDist = distance(pattern.featureVector, features)
            
            // Calcola distanza carico (normalizzata 0-1)
            let loadDist: Double
            if let patternLoad = pattern.loadPercentage {
                // Differenza percentuale normalizzata (max 100% diff = 1.0)
                loadDist = abs(patternLoad - targetLoad) / 100.0
            } else {
                // Se il pattern non ha carico, penalizza leggermente
                loadDist = 0.3
            }
            
            // Score combinato (più basso = migliore)
            let combinedScore = (featureDist * 0.7) + (loadDist * 0.3)
            return (pattern, combinedScore)
        }
        
        return scored.min(by: { $0.score < $1.score })?.pattern
    }

    // MARK: - Feature Extraction & Distance

    func distance(_ a: [Double], _ b: [Double]) -> Double {
        let n = min(a.count, b.count)
        guard n > 0 else { return .infinity }
        return zip(a, b).reduce(0) { $0 + pow($1.0 - $1.1, 2) }.squareRoot()
    }

    private func featureVector(for seq: [AccelerationSample]) -> [Double] {
        guard seq.count > 3 else { return [] }
        let accZ = seq.map { $0.accZ }

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
            Double(seq.count) / 100.0
        ]
    }

    // MARK: - Salvataggio e caricamento

    private func save() {
        do {
            let data = try JSONEncoder().encode(patterns)
            try data.write(to: saveURL)
            print("Libreria pattern salvata (\(patterns.count))")
        } catch {
            print("Errore salvataggio libreria pattern: \(error)")
        }
    }

    private func load() {
        do {
            let data = try Data(contentsOf: saveURL)
            patterns = try JSONDecoder().decode([PatternSequence].self, from: data)
            print("Libreria pattern caricata (\(patterns.count))")
        } catch {
            patterns = []
            print("Nessuna libreria pattern trovata (prima esecuzione)")
        }
    }
}
