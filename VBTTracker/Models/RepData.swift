
//
//  RepData.swift
//  VBTTracker
//
//  Modello dati per una singola ripetizione VBT
//

import Foundation

struct RepData: Identifiable, Codable {
    let id: UUID
    let repNumber: Int
    let timestamp: Date
    
    // Metriche velocità
    let peakVelocity: Double        // m/s - Velocità massima nella fase concentrica
    let meanVelocity: Double        // m/s - Velocità media propulsiva (MPV)
    
    // Durata fasi
    let concentricDuration: Double  // secondi - Durata fase concentrica
    let eccentricDuration: Double   // secondi - Durata fase eccentrica
    let totalDuration: Double       // secondi - Durata totale ripetizione
    
    // Dati aggiuntivi
    let peakAcceleration: Double    // m/s² - Accelerazione massima
    let rom: Double?                // cm - Range of Motion (opzionale)
    
    // Metadata
    let isValid: Bool               // Flag validità ripetizione
    
    init(
        id: UUID = UUID(),
        repNumber: Int,
        timestamp: Date = Date(),
        peakVelocity: Double,
        meanVelocity: Double,
        concentricDuration: Double,
        eccentricDuration: Double,
        peakAcceleration: Double,
        rom: Double? = nil,
        isValid: Bool = true
    ) {
        self.id = id
        self.repNumber = repNumber
        self.timestamp = timestamp
        self.peakVelocity = peakVelocity
        self.meanVelocity = meanVelocity
        self.concentricDuration = concentricDuration
        self.eccentricDuration = eccentricDuration
        self.totalDuration = concentricDuration + eccentricDuration
        self.peakAcceleration = peakAcceleration
        self.rom = rom
        self.isValid = isValid
    }
    
    /// Calcola la percentuale di 1RM stimata dalla velocità (González-Badillo 2010)
    /// Valido solo per bench press
    func estimatedRM() -> Int? {
        guard peakVelocity > 0 else { return nil }
        
        // Relazione velocità-%RM per bench press (approssimativa)
        // Fonte: González-Badillo & Sánchez-Medina (2010)
        switch peakVelocity {
        case 0...0.20: return 100  // 1RM
        case 0.20...0.25: return 95
        case 0.25...0.35: return 90
        case 0.35...0.42: return 85
        case 0.42...0.50: return 80
        case 0.50...0.58: return 75
        case 0.58...0.66: return 70
        default: return nil
        }
    }
}
