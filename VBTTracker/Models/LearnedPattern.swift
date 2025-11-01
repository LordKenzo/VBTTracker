import Foundation

struct LearnedPattern: Codable, Equatable, Sendable {
    /// ROM stimata in metri (es. 0.52 = 52 cm)
    let estimatedROM: Double
    /// Soglia dinamica di ampiezza in g per contare una rep
    let dynamicMinAmplitude: Double
    /// Velocità  media/picco tipica (m/s) usata come riferimento
    let avgPeakVelocity: Double
    /// Durata media della fase concentrica (s)
    let avgConcentricDuration: Double
    /// Soglia in g
    let restThreshold: Double

    /// Inizializzatore canonico (usalo ovunque)
    init(
        rom: Double,
        minThreshold: Double,
        avgVelocity: Double,
        avgConcentricDuration: Double,
        restThreshold: Double
    ) {
        self.estimatedROM = rom
        self.dynamicMinAmplitude = minThreshold
        self.avgPeakVelocity = avgVelocity
        self.avgConcentricDuration = avgConcentricDuration
        self.restThreshold = restThreshold
    }
}

extension LearnedPattern {
    /// Inizializzatore da PatternSequence
    init(from pattern: PatternSequence) {
        self.estimatedROM = pattern.avgAmplitude
        self.dynamicMinAmplitude = pattern.avgAmplitude * 0.5
        self.avgPeakVelocity = pattern.avgPPV
        self.avgConcentricDuration = pattern.avgDuration
        self.restThreshold = 0.08
    }
    
    static let defaultPattern: LearnedPattern = .init(
        rom: 0.45,                     // 45 cm ROM media
        minThreshold: 0.40,            // ampiezza minima 0.4g
        avgVelocity: 0.80,             // 0.8 m/s tipica (forza)
        avgConcentricDuration: 0.9,    // ~0.9 s concentrico
        restThreshold: 0.10            // 0.1g per considerare
    )
}
