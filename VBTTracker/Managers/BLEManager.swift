//
//  BLEManager.swift
//  VBTTracker
//
//  Gestione BLE per WitMotion WT901BLE
//

import Foundation
import CoreBluetooth
import Combine

// MARK: - BLEManager

final class BLEManager: NSObject, ObservableObject, SensorDataProvider {

    // MARK: - Published (UI)
    @Published var isScanning = false
    @Published var isConnected = false
    @Published var statusMessage = "Pronto per la scansione"
    @Published var sensorName = "Non connesso"
    @Published private(set) var discoveredDevices: [CBPeripheral] = []

    @Published var currentCalibration: CalibrationData?
    @Published var isCalibrated = false
    @Published var sampleRateHz: Double? = nil

    @Published var acceleration: [Double] = [0,0,0]
    @Published var angularVelocity: [Double] = [0,0,0]
    @Published var angles: [Double] = [0,0,0]

    // MARK: - Private
    private var central: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    private var dataCharacteristic: CBCharacteristic?
    private var seenPeripherals: [UUID: CBPeripheral] = [:]

    // UUID del sensore WitMotion
    static let serviceUUID = CBUUID(string: "0000FFE5-0000-1000-8000-00805F9A34FB")
    static let characteristicUUID = CBUUID(string: "0000FFE4-0000-1000-8000-00805F9A34FB")

    // Sample rate estimation
    private var lastPacketTime: Date?
    private var intervalEMA: Double?
    private let srAlpha = 0.2
    private var lastSRLog: Date = .distantPast

    // Flag anti-concorrenza
    private var isConnecting = false
    private var autoReconnectInProgress = false

    // MARK: - Init
    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
        print("🔵 BLEManager inizializzato")
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
        connectedPeripheral = peripheral  // ✅ riferimento forte
        sensorName = peripheral.name ?? "WitMotion"

        resetSampleRateEstimation()
        DispatchQueue.main.async {
            self.statusMessage = "Connessione a \(peripheral.name ?? "sensore")…"
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

        DispatchQueue.main.async { self.statusMessage = "Tentativo auto-connessione…" }
        print("🔄 Tentativo auto-riconnessione a peripheralID: \(uuid)")

        // 1️⃣ Cerca tra le periferiche note
        let known = central.retrievePeripherals(withIdentifiers: [uuid])
        if let p = known.first {
            print("✅ Peripheral noto via retrievePeripherals, connessione diretta…")
            connect(to: p)
            autoReconnectInProgress = false
            return
        }

        // 2️⃣ Se non in cache → scansiona
        print("🔎 Peripheral non in cache, avvio scansione")
        startScanning()
        autoReconnectInProgress = false
    }

    func applyCalibration(_ calibration: CalibrationData) {
        currentCalibration = calibration
        isCalibrated = true
        print("✅ Calibrazione applicata al BLEManager")
    }

    func removeCalibration() {
        currentCalibration = nil
        isCalibrated = false
        print("🔄 Calibrazione rimossa")
    }

    // MARK: - Scanning
    func startScanning() {
        guard central.state == .poweredOn else {
            statusMessage = "Bluetooth non disponibile"
            print("❌ Bluetooth non poweredOn")
            return
        }

        discoveredDevices.removeAll()
        seenPeripherals.removeAll()

        isScanning = true
        statusMessage = "Scansione in corso…"
        print("🔍 Inizio scansione dispositivi WitMotion…")

        central.scanForPeripherals(
            withServices: [Self.serviceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )

        // Stop automatico dopo 10 secondi
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            guard let self, self.isScanning else { return }
            self.stopScanning()
            print("⏱️ Scansione auto-fermata dopo 10s")
        }
    }

    func stopScanning() {
        central.stopScan()
        isScanning = false
        statusMessage = discoveredDevices.isEmpty
            ? "Nessun sensore trovato"
            : "Seleziona un dispositivo"
        print("ℹ️ Scansione fermata — Trovati \(discoveredDevices.count) dispositivi")
    }

    // MARK: - Sample rate
    private func resetSampleRateEstimation() {
        lastPacketTime = nil
        intervalEMA = nil
        sampleRateHz = nil
        lastSRLog = .distantPast
    }

    private func updateSRonPacket() {
        let now = Date()
        defer { lastPacketTime = now }

        guard let last = lastPacketTime else { return }
        let dt = now.timeIntervalSince(last)
        guard dt > 0 else { return }

        intervalEMA = (intervalEMA == nil) ? dt : ((1 - srAlpha) * intervalEMA! + srAlpha * dt)
        guard let meanDt = intervalEMA, meanDt > 0 else { return }

        let sr = 1.0 / meanDt
        if sampleRateHz == nil || abs((sampleRateHz ?? 0) - sr) > 0.5 {
            sampleRateHz = sr
        }

        if now.timeIntervalSince(lastSRLog) > 1.0 {
            lastSRLog = now
            print("⏱️ SR stimata: \(String(format: "%.1f", sr)) Hz")
        }
    }

    // MARK: - Parsing pacchetto
    private func parseWitMotionPacket(_ data: Data) {
        guard data.count >= 20 else { return }
        let bytes = [UInt8](data)
        guard bytes[0] == 0x55, bytes[1] == 0x61 else { return }

        func i16(_ hi: UInt8, _ lo: UInt8) -> Int16 { (Int16(hi) << 8) | Int16(lo) }

        let ax = i16(bytes[3], bytes[2]), ay = i16(bytes[5], bytes[4]), az = i16(bytes[7], bytes[6])
        let gx = i16(bytes[9], bytes[8]), gy = i16(bytes[11], bytes[10]), gz = i16(bytes[13], bytes[12])
        let r  = i16(bytes[15], bytes[14]), p  = i16(bytes[17], bytes[16]), y  = i16(bytes[19], bytes[18])

        var acc = [Double(ax)/32768*16, Double(ay)/32768*16, Double(az)/32768*16]
        var gyr = [Double(gx)/32768*2000, Double(gy)/32768*2000, Double(gz)/32768*2000]
        var ang = [Double(r)/32768*180, Double(p)/32768*180, Double(y)/32768*180]

        if let cal = currentCalibration {
            let out = cal.applyCalibration(acceleration: acc, angularVelocity: gyr, angles: ang)
            acc = out.acceleration; gyr = out.angularVelocity; ang = out.angles
        }

        DispatchQueue.main.async {
            self.acceleration = acc
            self.angularVelocity = gyr
            self.angles = ang
        }
        updateSRonPacket()
    }
}

// MARK: - CBCentralManagerDelegate
extension BLEManager: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            DispatchQueue.main.async { self.statusMessage = "Bluetooth pronto" }
            print("✅ Bluetooth powered ON")
            DispatchQueue.main.async { self.attemptAutoReconnectIfPossible() }

        case .poweredOff:
            DispatchQueue.main.async { self.statusMessage = "Bluetooth spento" }
            print("❌ Bluetooth powered OFF")

        case .unauthorized:
            DispatchQueue.main.async { self.statusMessage = "Permessi Bluetooth negati" }
            print("⚠️ Bluetooth unauthorized")

        case .unsupported:
            DispatchQueue.main.async { self.statusMessage = "Bluetooth non supportato" }
            print("❌ Bluetooth unsupported")

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
            print("📡 Trovato: \(peripheral.name ?? "Unknown") - RSSI \(RSSI)")
        }

        if !isConnected, !isConnecting,
           let savedID = SettingsManager.shared.lastConnectedPeripheralID,
           savedID == peripheral.identifier.uuidString {
            print("🔁 Auto-connect al dispositivo noto \(peripheral.name ?? "Unknown")")
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
            self.sensorName = peripheral.name ?? "WitMotion"
            self.statusMessage = "Connesso"
            self.resetSampleRateEstimation()
        }

        peripheral.delegate = self
        peripheral.discoverServices([Self.serviceUUID])
    }

    func centralManager(_ central: CBCentralManager,
                        didFailToConnect peripheral: CBPeripheral,
                        error: Error?) {
        print("❌ Connessione fallita: \(error?.localizedDescription ?? "errore sconosciuto")")
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
        print("🔌 Disconnesso da: \(peripheral.name ?? "Unknown")")
        DispatchQueue.main.async {
            self.isConnecting = false
            self.isConnected = false
            self.sensorName = "Non connesso"
            self.statusMessage = "Disconnesso"
            self.connectedPeripheral = nil
            self.dataCharacteristic = nil
            self.acceleration = [0,0,0]
            self.angularVelocity = [0,0,0]
            self.angles = [0,0,0]
            self.resetSampleRateEstimation()
        }
    }
}

// MARK: - CBPeripheralDelegate
extension BLEManager: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverServices error: Error?) {
        if let error {
            print("❌ Errore scoperta servizi: \(error)")
            return
        }
        peripheral.services?.forEach { service in
            print("🔍 Servizio: \(service.uuid)")
            peripheral.discoverCharacteristics([Self.characteristicUUID], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        if let error {
            print("❌ Errore caratteristiche: \(error)")
            return
        }
        service.characteristics?.forEach { ch in
            print("🔍 Caratteristica: \(ch.uuid)")
            if ch.uuid == Self.characteristicUUID {
                DispatchQueue.main.async { self.dataCharacteristic = ch }
                print("✅ Attivo notifiche dati")
                peripheral.setNotifyValue(true, for: ch)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateNotificationStateFor characteristic: CBCharacteristic,
                    error: Error?) {
        if let error {
            print("❌ Errore notifiche: \(error)")
            return
        }
        print(characteristic.isNotifying ? "✅ Notifiche ATTIVE" : "ℹ️ Notifiche DISATTIVATE")
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        if let error {
            print("❌ Errore lettura valore: \(error)")
            return
        }
        guard characteristic.uuid == Self.characteristicUUID,
              let data = characteristic.value else { return }

        DispatchQueue.main.async {
            self.parseWitMotionPacket(data)
        }
    }
}
