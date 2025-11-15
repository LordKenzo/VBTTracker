//
//  ArduinoBLEManager.swift
//  VBTTracker
//
//  Gestione BLE per Arduino Nano 33 BLE + VL53L0X
//  Riceve dati di distanza diretta via BLE
//

import Foundation
import CoreBluetooth
import Combine

// MARK: - ArduinoBLEManager

final class ArduinoBLEManager: NSObject, ObservableObject, DistanceSensorDataProvider {

    // MARK: - Published (UI)
    @Published var isScanning = false
    @Published var isConnected = false
    @Published var statusMessage = "Pronto per la scansione"
    @Published var sensorName = "Non connesso"
    @Published private(set) var discoveredDevices: [CBPeripheral] = []

    @Published var sampleRateHz: Double? = nil

    // Dati distanza
    @Published var distance: Double = 0.0           // in millimetri
    @Published var velocity: Double = 0.0           // in mm/s (da Arduino)
    @Published var timestamp: UInt32 = 0
    @Published var movementState: MovementState = .idle
    // configValue rimosso - non più usato in Rev3 (stato calcolato da velocità)

    // Campioni distanza per grafico real-time
    private var distanceSamples: [DistanceSample] = []
    private let maxDistanceSamples = 200 // 4 secondi a 50Hz

    // MARK: - Private
    private var central: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    private var dataCharacteristic: CBCharacteristic?
    private var seenPeripherals: [UUID: CBPeripheral] = [:]

    // UUID del sensore Arduino
    static let serviceUUID = CBUUID(string: "19B10000-E8F2-537E-4F6C-D104768A1214")
    static let characteristicUUID = CBUUID(string: "19B10001-E8F2-537E-4F6C-D104768A1214")

    // Sample rate estimation
    private var lastPacketTime: Date?
    private var packetTimestamps: [Date] = []
    private let SR_WINDOW_SIZE = 50
    private let SR_UPDATE_THRESHOLD = 10.0
    private var lastPublishedSR: Double?
    private var srStableCounter = 0

    // Flag anti-concorrenza
    private var isConnecting = false
    private var autoReconnectInProgress = false

    // MARK: - Init
    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
        print("🔵 ArduinoBLEManager inizializzato")
    }

    // MARK: - Public
    func connect() {
        guard let first = discoveredDevices.first else {
            statusMessage = "Nessun sensore trovato"
            return
        }
        connect(to: first)
    }

    func connect(to peripheral: CBPeripheral) {
        guard !isConnected, !isConnecting else { return }
        isConnecting = true

        stopScanning()
        connectedPeripheral = peripheral
        sensorName = peripheral.name ?? "VBT-Sensor"

        resetSampleRateEstimation()
        DispatchQueue.main.async {
            self.statusMessage = "Connessione a \(peripheral.name ?? "sensore")"
        }
        print("🔗 Connessione a: \(peripheral.name ?? "Unknown") [\(peripheral.identifier)]")

        central.connect(peripheral, options: nil)
    }

    func disconnect() {
        guard let p = connectedPeripheral else {
            print("⚠️ Nessun dispositivo da disconnettere")
            return
        }
        print("🔌 Disconnessione da \(p.name ?? "Unknown")")
        central.cancelPeripheralConnection(p)
    }

    @MainActor
    func attemptAutoReconnect(with idString: String) {
        guard let uuid = UUID(uuidString: idString) else {
            print("⚠️ ID dispositivo non valido")
            return
        }
        attemptAutoReconnect(to: uuid)
    }

    @MainActor
    private func attemptAutoReconnectIfPossible() {
        guard !autoReconnectInProgress else { return }
        guard let idString = SettingsManager.shared.lastConnectedPeripheralID,
              let uuid = UUID(uuidString: idString)
        else { return }
        autoReconnectInProgress = true
        attemptAutoReconnect(to: uuid)
    }

    @MainActor
    private func attemptAutoReconnect(to uuid: UUID) {
        guard !isConnected, !isConnecting else {
            autoReconnectInProgress = false
            return
        }

        DispatchQueue.main.async { self.statusMessage = "Tentativo auto-connessione" }
        print("🔄 Tentativo auto-riconnessione a peripheralID: \(uuid)")

        // 1 Cerca tra le periferiche note
        let known = central.retrievePeripherals(withIdentifiers: [uuid])
        if let p = known.first {
            print("✅ Peripheral noto via retrievePeripherals, connessione diretta")
            connect(to: p)
            autoReconnectInProgress = false
            return
        }

        // 2 Se non in cache scansiona
        print("🔍 Peripheral non in cache, avvio scansione")
        startScanning()
        autoReconnectInProgress = false
    }

    // MARK: - Scanning
    func startScanning() {
        guard central.state == .poweredOn else {
            statusMessage = "Bluetooth non disponibile"
            print("⚠️ Bluetooth non poweredOn")
            return
        }

        discoveredDevices.removeAll()
        seenPeripherals.removeAll()

        isScanning = true
        statusMessage = "Scansione in corso 🔍"
        print("📡 Inizio scansione sensori Arduino")

        central.scanForPeripherals(
            withServices: [Self.serviceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )

        // Stop automatico dopo 10 secondi
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            guard let self, self.isScanning else { return }
            self.stopScanning()
            print("Scansione auto-fermata dopo 10s")
        }
    }

    func stopScanning() {
        central.stopScan()
        isScanning = false
        statusMessage = discoveredDevices.isEmpty
            ? "Nessun sensore trovato"
            : "Seleziona un dispositivo"
        print("🔍 Scansione fermata - Trovati \(discoveredDevices.count) dispositivi")
    }

    func getDistanceSamples() -> [DistanceSample] {
        return distanceSamples
    }


    // MARK: - Sample rate estimation

    private func resetSampleRateEstimation() {
        lastPacketTime = nil
        sampleRateHz = nil
        packetTimestamps.removeAll()
        lastPublishedSR = nil
        srStableCounter = 0
        distanceSamples.removeAll()
    }

    private var lastSRNotifyTime: Date = .distantPast

    private func updateSRonPacket() {
        let now = Date()
        packetTimestamps.append(now)

        // Mantieni solo gli ultimi N pacchetti
        if packetTimestamps.count > SR_WINDOW_SIZE {
            packetTimestamps.removeFirst()
        }

        // Calcola SR solo se hai abbastanza campioni
        guard packetTimestamps.count >= 20 else { return }

        let totalTime = now.timeIntervalSince(packetTimestamps.first!)
        guard totalTime > 0 else { return }

        let instantSR = Double(packetTimestamps.count - 1) / totalTime

        // Clamp a range ragionevole (Arduino invia a 50Hz)
        let clampedSR = max(5.0, min(instantSR, 100.0))

        // Pubblicazione con hysteresis
        let shouldPublish: Bool
        if let last = lastPublishedSR {
            let delta = abs(clampedSR - last)

            if delta > SR_UPDATE_THRESHOLD {
                srStableCounter = 0
                shouldPublish = false
            } else {
                srStableCounter += 1
                shouldPublish = srStableCounter >= 10
            }
        } else {
            shouldPublish = true
            srStableCounter = 0
        }

        if shouldPublish {
            let oldSR = sampleRateHz
            sampleRateHz = clampedSR
            lastPublishedSR = clampedSR

            if oldSR == nil || abs((oldSR ?? 0) - clampedSR) > 5.0 {
                print("📊 Sample rate stabile: \(String(format: "%.1f", clampedSR)) Hz")
            }

            // Notifica cambio (throttle 1 secondo)
            if now.timeIntervalSince(lastSRNotifyTime) > 1.0 {
                lastSRNotifyTime = now
                NotificationCenter.default.post(
                    name: NSNotification.Name("BLE_SR_UPDATED"),
                    object: nil
                )
            }

            srStableCounter = 0
        }
    }


    // MARK: - Parsing pacchetto Arduino
    private func parseArduinoPacket(_ data: Data) {
        // Rev3: 11 byte (no config byte)
        guard data.count >= 11 else {
            print("⚠️ Pacchetto troppo corto: \(data.count) bytes (attesi 11)")
            return
        }

        let bytes = [UInt8](data)

        // Estrai distanza (primi 2 byte, little-endian)
        let distanceRaw = UInt16(bytes[0]) | (UInt16(bytes[1]) << 8)

        // Estrai timestamp (byte 2-5, little-endian)
        let timestampRaw = UInt32(bytes[2])
            | (UInt32(bytes[3]) << 8)
            | (UInt32(bytes[4]) << 16)
            | (UInt32(bytes[5]) << 24)

        // Estrai velocità (byte 6-9, float little-endian)
        var velocityFloat: Float = 0
        let velocityData = Data(bytes[6..<10])
        velocityFloat = velocityData.withUnsafeBytes { $0.load(as: Float.self) }

        // Estrai stato movimento (byte 10)
        // Rev5 con ORIENTATION_SIGN = +1 (sensore a terra):
        //   - CONCENTRIC (1) = fase concentrica del movimento → .approaching (displayName: "Concentrica")
        //   - ECCENTRIC (2) = fase eccentrica del movimento → .receding (displayName: "Eccentrica")
        //
        // Nota: i nomi .approaching/.receding sono semantici rispetto al MOVIMENTO del bilanciere,
        // non rispetto alla geometria del sensore. Con sensore a terra:
        //   - Concentrica: bilanciere sale (si allontana dal sensore geometricamente, ma "approaching" il completamento)
        //   - Eccentrica: bilanciere scende (si avvicina al sensore geometricamente, ma "receding" dal completamento)
        let stateByte = bytes[10]
        let state: MovementState
        switch stateByte {
        case 1:
            state = .approaching  // CONCENTRIC → "Concentrica" (mappatura semantica corretta)
        case 2:
            state = .receding     // ECCENTRIC → "Eccentrica" (mappatura semantica corretta)
        default:
            state = .idle         // 0 = IDLE
        }

        // 📊 LOG RAW dei dati Arduino (Rev5 - con filtri sofisticati)
        print("📊 ARDUINO RAW: dist=\(distanceRaw)mm, vel=\(String(format: "%.1f", velocityFloat))mm/s, state=\(stateByte)(\(state.displayName))")

        DispatchQueue.main.async {
            self.distance = Double(distanceRaw)
            self.velocity = Double(velocityFloat)
            self.timestamp = timestampRaw
            self.movementState = state

            // Aggiungi campione per grafico real-time
            let sample = DistanceSample(
                timestamp: Date(),
                distance: Double(distanceRaw),
                velocity: Double(velocityFloat)
            )
            self.distanceSamples.append(sample)

            // Limita dimensione array
            if self.distanceSamples.count > self.maxDistanceSamples {
                self.distanceSamples.removeFirst()
            }
        }

        updateSRonPacket()
    }
}

// MARK: - CBCentralManagerDelegate
extension ArduinoBLEManager: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            DispatchQueue.main.async { self.statusMessage = "Bluetooth pronto" }
            print("✅ Bluetooth powered ON")
            DispatchQueue.main.async { self.attemptAutoReconnectIfPossible() }

        case .poweredOff:
            DispatchQueue.main.async { self.statusMessage = "Bluetooth spento" }
            print("⏸️ Bluetooth powered OFF")

        case .unauthorized:
            DispatchQueue.main.async { self.statusMessage = "Permessi Bluetooth negati" }
            print("⚠️ Bluetooth unauthorized")

        case .unsupported:
            DispatchQueue.main.async { self.statusMessage = "Bluetooth non supportato" }
            print("⏸️ Bluetooth unsupported")

        default:
            DispatchQueue.main.async { self.statusMessage = "Bluetooth non disponibile" }
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String : Any],
                        rssi RSSI: NSNumber) {

        if seenPeripherals[peripheral.identifier] == nil {
            seenPeripherals[peripheral.identifier] = peripheral
            DispatchQueue.main.async { self.discoveredDevices.append(peripheral) }
            print("🔍 Trovato: \(peripheral.name ?? "Unknown") - RSSI \(RSSI)")
        }

        if !isConnected, !isConnecting,
           let savedID = SettingsManager.shared.lastConnectedPeripheralID,
           savedID == peripheral.identifier.uuidString {
            print("🔄 Auto-connect al dispositivo noto \(peripheral.name ?? "Unknown")")
            connect(to: peripheral)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("✅ Connesso a: \(peripheral.name ?? "Unknown")")
        SettingsManager.shared.lastConnectedPeripheralID = peripheral.identifier.uuidString

        DispatchQueue.main.async {
            self.isConnecting = false
            self.isConnected = true
            self.connectedPeripheral = peripheral
            self.sensorName = peripheral.name ?? "VBT-Sensor"
            self.statusMessage = "Connesso"
            self.resetSampleRateEstimation()
        }

        peripheral.delegate = self
        peripheral.discoverServices([Self.serviceUUID])
    }

    func centralManager(_ central: CBCentralManager,
                        didFailToConnect peripheral: CBPeripheral,
                        error: Error?) {
        print("🔌 Connessione fallita: \(error?.localizedDescription ?? "errore sconosciuto")")
        DispatchQueue.main.async {
            self.isConnecting = false
            self.isConnected = false
            self.statusMessage = "Connessione fallita"
            self.resetSampleRateEstimation()
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        print("🔴 Disconnesso da: \(peripheral.name ?? "Unknown")")
        DispatchQueue.main.async {
            self.isConnecting = false
            self.isConnected = false
            self.sensorName = "Non connesso"
            self.statusMessage = "Disconnesso"
            self.connectedPeripheral = nil
            self.dataCharacteristic = nil
            self.distance = 0.0
            self.timestamp = 0
            self.movementState = .idle
            self.resetSampleRateEstimation()
        }
    }
}

// MARK: - CBPeripheralDelegate
extension ArduinoBLEManager: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverServices error: Error?) {
        if let error {
            print("🔴 Errore scoperta servizi: \(error)")
            return
        }
        peripheral.services?.forEach { service in
            print("🟢 Servizio: \(service.uuid)")
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        if let error {
            print("🔴 Errore caratteristiche: \(error)")
            return
        }
        service.characteristics?.forEach { ch in
            print("🟢 Caratteristica: \(ch.uuid) props=\(ch.properties)")

            // Attiva notifiche per la caratteristica dati
            if ch.uuid == Self.characteristicUUID || ch.properties.contains(.notify) {
                dataCharacteristic = ch
                print("✅ Attivo notifiche dati su \(ch.uuid)")
                peripheral.setNotifyValue(true, for: ch)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateNotificationStateFor characteristic: CBCharacteristic,
                    error: Error?) {
        if let error {
            print("⚠️ Errore notifiche: \(error)")
            return
        }
        print(characteristic.isNotifying ? "✅ Notifiche ATTIVE" : "⚠️ Notifiche DISATTIVATE")
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        if let error {
            print("⚠️ Errore lettura valore: \(error)")
            return
        }
        guard characteristic.uuid == Self.characteristicUUID,
              let data = characteristic.value else { return }

        DispatchQueue.main.async {
            self.parseArduinoPacket(data)
        }
    }
}
