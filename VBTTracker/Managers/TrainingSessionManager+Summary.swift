//
//  TrainingSessionManager+Summary.swift
//  VBTTracker
//
//  Extension per esporre dati sessione per summary view
//

import Foundation

extension TrainingSessionManager {
    
    /// Ottieni array di velocità picco per ogni rep
    func getRepPeakVelocities() -> [Double] {
        return repPeakVelocities
    }
    
    /// Ottieni velocità della prima rep
    func getFirstRepVelocity() -> Double? {
        return firstRepPeakVelocity
    }
    
    /// Crea TrainingSessionData per summary view
    func createSessionData() -> TrainingSessionData {
        return TrainingSessionData.from(
            manager: self,
            targetZone: targetZone,
            velocityLossThreshold: SettingsManager.shared.velocityLossThreshold
        )
    }
}
