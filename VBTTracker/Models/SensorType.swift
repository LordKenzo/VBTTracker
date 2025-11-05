//
//  SensorType.swift
//  VBTTracker
//
//  Enum e protocolli per supportare diversi tipi di sensori
//

import Foundation

// MARK: - Sensor Type

enum SensorType: String, CaseIterable, Codable {
    case witmotion = "WitMotion"
    case arduino = "Arduino VL53L0X"

    var displayName: String {
        switch self {
        case .witmotion:
            return "WitMotion WT901BLE (IMU)"
        case .arduino:
            return "Arduino Nano 33 BLE (Distanza)"
        }
    }

    var description: String {
        switch self {
        case .witmotion:
            return "Sensore IMU che misura accelerazione e calcola velocità tramite integrazione"
        case .arduino:
            return "Sensore laser VL53L0X che misura direttamente la distanza, più preciso per VBT"
        }
    }

    var icon: String {
        switch self {
        case .witmotion:
            return "sensor.fill"
        case .arduino:
            return "laser.burst"
        }
    }

    var serviceUUID: String {
        switch self {
        case .witmotion:
            return "0000FFE5-0000-1000-8000-00805F9A34FB"
        case .arduino:
            return "19B10000-E8F2-537E-4F6C-D104768A1214"
        }
    }

    var characteristicUUID: String {
        switch self {
        case .witmotion:
            return "0000FFE4-0000-1000-8000-00805F9A34FB"
        case .arduino:
            return "19B10001-E8F2-537E-4F6C-D104768A1214"
        }
    }
}

// MARK: - Distance Sensor Data Provider

/// Protocollo per sensori che misurano direttamente la distanza
protocol DistanceSensorDataProvider: ObservableObject {
    // Stato connessione
    var isConnected: Bool { get }
    var statusMessage: String { get }
    var sensorName: String { get }

    // Dati distanza
    var distance: Double { get }          // Distanza in millimetri
    var timestamp: UInt32 { get }         // Timestamp dal sensore
    var movementState: MovementState { get } // Stato movimento dal sensore

    // Sample rate
    var sampleRateHz: Double? { get }

    // Controlli
    func connect()
    func disconnect()
}

// MARK: - Movement State

enum MovementState: UInt8, Codable {
    case approaching = 0  // Avvicinamento (concentrica)
    case receding = 1     // Allontanamento (eccentrica)
    case idle = 2         // Fermo

    var displayName: String {
        switch self {
        case .approaching: return "Concentrica"
        case .receding: return "Eccentrica"
        case .idle: return "Fermo"
        }
    }
}
