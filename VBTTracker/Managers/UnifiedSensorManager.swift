//
//  UnifiedSensorManager.swift
//  VBTTracker
//
//  Manager unificato che gestisce entrambi i tipi di sensore
//  (WitMotion IMU e Arduino VL53L0X)
//

import Foundation
import Combine

final class UnifiedSensorManager: ObservableObject {

    // MARK: - Published Properties

    @Published var isConnected = false
    @Published var statusMessage = "Pronto per la scansione"
    @Published var sensorName = "Non connesso"
    @Published var sampleRateHz: Double? = nil

    // Stato comune
    @Published var currentSensorType: SensorType {
        didSet {
            // Quando cambia il tipo, disconnetti il sensore attuale
            if oldValue != currentSensorType {
                disconnectCurrentSensor()
                refreshAggregatedState()
            }
        }
    }

    // MARK: - Sub-Managers

    let bleManager: BLEManager
    let arduinoManager: ArduinoBLEManager

    // MARK: - Private

    private var cancellables = Set<AnyCancellable>()
    private let settings = SettingsManager.shared

    // MARK: - Init

    init() {
        bleManager = BLEManager()
        arduinoManager = ArduinoBLEManager()
        currentSensorType = settings.selectedSensorType

        setupBindings()
    }

    // MARK: - Setup

    private func setupBindings() {
        // Observe changes to settings
        settings.$selectedSensorType
            .sink { [weak self] newType in
                self?.currentSensorType = newType
            }
            .store(in: &cancellables)

        // Bind WitMotion manager
        bleManager.$isConnected
            .sink { [weak self] connected in
                guard let self, self.currentSensorType == .witmotion else { return }
                self.isConnected = connected
            }
            .store(in: &cancellables)

        bleManager.$statusMessage
            .sink { [weak self] message in
                guard let self, self.currentSensorType == .witmotion else { return }
                self.statusMessage = message
            }
            .store(in: &cancellables)

        bleManager.$sensorName
            .sink { [weak self] name in
                guard let self, self.currentSensorType == .witmotion else { return }
                self.sensorName = name
            }
            .store(in: &cancellables)

        bleManager.$sampleRateHz
            .sink { [weak self] rate in
                guard let self, self.currentSensorType == .witmotion else { return }
                self.sampleRateHz = rate
            }
            .store(in: &cancellables)

        // Bind Arduino manager
        arduinoManager.$isConnected
            .sink { [weak self] connected in
                guard let self, self.currentSensorType == .arduino else { return }
                self.isConnected = connected
            }
            .store(in: &cancellables)

        arduinoManager.$statusMessage
            .sink { [weak self] message in
                guard let self, self.currentSensorType == .arduino else { return }
                self.statusMessage = message
            }
            .store(in: &cancellables)

        arduinoManager.$sensorName
            .sink { [weak self] name in
                guard let self, self.currentSensorType == .arduino else { return }
                self.sensorName = name
            }
            .store(in: &cancellables)

        arduinoManager.$sampleRateHz
            .sink { [weak self] rate in
                guard let self, self.currentSensorType == .arduino else { return }
                self.sampleRateHz = rate
            }
            .store(in: &cancellables)
    }

    // MARK: - Public Methods

    func connect() {
        switch currentSensorType {
        case .witmotion:
            bleManager.connect()
        case .arduino:
            arduinoManager.connect()
        }
    }

    func disconnect() {
        switch currentSensorType {
        case .witmotion:
            bleManager.disconnect()
        case .arduino:
            arduinoManager.disconnect()
        }
    }

    func startScanning() {
        switch currentSensorType {
        case .witmotion:
            bleManager.startScanning()
        case .arduino:
            arduinoManager.startScanning()
        }
    }

    func stopScanning() {
        switch currentSensorType {
        case .witmotion:
            bleManager.stopScanning()
        case .arduino:
            arduinoManager.stopScanning()
        }
    }

    private func disconnectCurrentSensor() {
        bleManager.disconnect()
        arduinoManager.disconnect()
    }

    // MARK: - Calibration (solo per WitMotion)

    var isCalibrated: Bool {
        currentSensorType == .witmotion ? bleManager.isCalibrated : true  // Arduino non richiede calibrazione
    }

    var currentCalibration: CalibrationData? {
        currentSensorType == .witmotion ? bleManager.currentCalibration : nil
    }

    func applyCalibration(_ calibration: CalibrationData) {
        guard currentSensorType == .witmotion else { return }
        bleManager.applyCalibration(calibration)
    }

    func removeCalibration() {
        guard currentSensorType == .witmotion else { return }
        bleManager.removeCalibration()
    }

    // MARK: - State Management

    private func refreshAggregatedState() {
        switch currentSensorType {
        case .witmotion:
            isConnected = bleManager.isConnected
            statusMessage = bleManager.statusMessage
            sensorName = bleManager.sensorName
            sampleRateHz = bleManager.sampleRateHz
        case .arduino:
            isConnected = arduinoManager.isConnected
            statusMessage = arduinoManager.statusMessage
            sensorName = arduinoManager.sensorName
            sampleRateHz = arduinoManager.sampleRateHz
        }
    }
}
