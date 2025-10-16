//
//  SensorDataProvider.swift
//  VBTTracker
//
//  Protocollo per astrazione del sensore (reale o mock per testing futuro)
//

import Foundation

/// Definisce l'interfaccia comune per qualsiasi sensore IMU
protocol SensorDataProvider: ObservableObject {
    // Stato connessione
    var isConnected: Bool { get }
    var statusMessage: String { get }
    var sensorName: String { get }
    
    // Dati inerziali
    var acceleration: [Double] { get }      // [X, Y, Z] in g
    var angularVelocity: [Double] { get }   // [X, Y, Z] in °/s
    var angles: [Double] { get }            // [Roll, Pitch, Yaw] in °
    
    // Controlli
    func connect()
    func disconnect()
}
