//
//  TrainingHistoryManager.swift
//  VBTTracker
//
//  Created by Lorenzo Franceschini on 01/11/25.
//


//
//  TrainingHistoryManager.swift
//  VBTTracker
//
//  Gestisce salvataggio e recupero storico sessioni
//

import Foundation
import Combine

class TrainingHistoryManager: ObservableObject {
    static let shared = TrainingHistoryManager()
    
    @Published var sessions: [TrainingSession] = []
    
    private let storageKey = "saved_training_sessions"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    private init() {
        loadSessions()
    }
    
    // MARK: - Public Methods
    
    /// Salva una nuova sessione
    func saveSession(_ session: TrainingSession) {
        sessions.insert(session, at: 0) // Più recente in cima
        persistSessions()
        print("💾 Sessione salvata: \(session.completedReps) reps, \(session.formattedDate)")
    }
    
    /// Elimina una sessione
    func deleteSession(_ session: TrainingSession) {
        sessions.removeAll { $0.id == session.id }
        persistSessions()
        print("🗑️ Sessione eliminata: \(session.id)")
    }
    
    /// Elimina tutte le sessioni
    func deleteAllSessions() {
        sessions.removeAll()
        persistSessions()
        print("🗑️ Tutte le sessioni eliminate")
    }
    
    /// Ottieni statistiche aggregate
    func getStats() -> TrainingStats {
        let totalSessions = sessions.count
        let totalReps = sessions.reduce(0) { $0 + $1.completedReps }
        let avgVelocityLoss = sessions.isEmpty ? 0 : sessions.reduce(0) { $0 + $1.velocityLoss } / Double(sessions.count)
        let avgMeanVelocity = sessions.isEmpty ? 0 : sessions.reduce(0) { $0 + $1.meanVelocity } / Double(sessions.count)
        
        return TrainingStats(
            totalSessions: totalSessions,
            totalReps: totalReps,
            avgVelocityLoss: avgVelocityLoss,
            avgMeanVelocity: avgMeanVelocity
        )
    }
    
    // MARK: - Private Methods
    
    private func loadSessions() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            print("📂 Nessuna sessione salvata trovata")
            return
        }
        
        do {
            sessions = try decoder.decode([TrainingSession].self, from: data)
            print("📂 Caricate \(sessions.count) sessioni salvate")
        } catch {
            print("❌ Errore caricamento sessioni: \(error.localizedDescription)")
            sessions = []
        }
    }
    
    private func persistSessions() {
        do {
            let data = try encoder.encode(sessions)
            UserDefaults.standard.set(data, forKey: storageKey)
            print("💾 Sessioni persistite: \(sessions.count)")
        } catch {
            print("❌ Errore salvataggio sessioni: \(error.localizedDescription)")
        }
    }
}

// MARK: - Stats Model

struct TrainingStats {
    let totalSessions: Int
    let totalReps: Int
    let avgVelocityLoss: Double
    let avgMeanVelocity: Double
}