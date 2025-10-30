//
//  BLEManager.swift
//  VBTTracker
//
//  Gestisce connessione Bluetooth e parsing dati WitMotion WT901BLE
//

import Foundation
import CoreBluetooth
import Combine

class BLEManager: NSObject, ObservableObject, SensorDataProvider {

    // MARK: - Published Properties
    @Published var isScanning = false
    @Published var isConnected = false
    @Published var discoveredDevices: [CBPeripheral] = []
    @Published var statusMessage = "Pronto per la scansione"
    @Published var sensorName = "Non connesso"
    
    // Calibrazione
    @Published var currentCalibration: CalibrationData?
    @Published var isCalibrated = false
   
    // Dati raw (prima della calibrazione)
    private var rawAcceleration: [Double] = [0.0, 0.0, 0.0]
    private var rawAngularVelocity: [Double] = [0.0, 0.0, 0.0]
    private var rawAngles: [Double] = [0.0, 0.0, 0.0]
    
    @Published var acceleration: [Double] = [0.0, 0.0, 0.0]
    @Published var angularVelocity: [Double] = [0.0, 0.0, 0.0]
    @Published var angles: [Double] = [0.0, 0.0, 0.0]
    
    // MARK: - Private Properties
    private var centralManager: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    
    // UUID WitMotion WT901BLE
    private let serviceUUID = CBUUID(string: "0000FFE5-0000-1000-8000-00805F9A34FB")
    private let characteristicUUID = CBUUID(string: "0000FFE4-0000-1000-8000-00805F9A34FB")
    
    // MARK: - Initialization
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
        print("🔵 BLEManager inizializzato")
    }
    
    // MARK: - Public Methods (SensorDataProvider)
    
    /// Connetti al primo dispositivo trovato
    func connect() {
        guard let device = discoveredDevices.first else {
            statusMessage = "Nessun sensore trovato"
            return
        }
        connect(to: device)
    }
    
    /// Connetti a un dispositivo specifico
    func connect(to peripheral: CBPeripheral) {
        stopScanning()
        statusMessage = "Connessione a \(peripheral.name ?? "sensore")..."
        print("🔗 Connessione a: \(peripheral.name ?? "Unknown") [\(peripheral.identifier)]")
        centralManager.connect(peripheral, options: nil)
    }
    
    /// Disconnetti dal dispositivo corrente
    func disconnect() {
        guard let peripheral = connectedPeripheral else {
            print("⚠️ Nessun dispositivo da disconnettere")
            return
        }
        print("🔌 Disconnessione da \(peripheral.name ?? "Unknown")")
        centralManager.cancelPeripheralConnection(peripheral)
    }
    
    // MARK: - Scanning Methods
    
    func startScanning() {
        guard centralManager.state == .poweredOn else {
            statusMessage = "Bluetooth non disponibile"
            print("❌ Bluetooth non poweredOn")
            return
        }
        
        discoveredDevices.removeAll()
        isScanning = true
        statusMessage = "Scansione in corso..."
        
        print("🔍 Inizio scansione dispositivi WitMotion...")
        centralManager.scanForPeripherals(
            withServices: [serviceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        
        // Auto-stop dopo 10 secondi
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            if self?.isScanning == true {
                self?.stopScanning()
                print("⏱️ Scansione auto-fermata dopo 10s")
            }
        }
    }
    
    func stopScanning() {
        centralManager.stopScan()
        isScanning = false
        statusMessage = discoveredDevices.isEmpty ?
            "Nessun sensore trovato" : "Seleziona un dispositivo"
        print("ℹ️ Scansione fermata - Trovati \(discoveredDevices.count) dispositivi")
    }
    
    func applyCalibration(_ calibration: CalibrationData) {
        self.currentCalibration = calibration
        self.isCalibrated = true
        print("✅ Calibrazione applicata al BLEManager")
    }
    
    func removeCalibration() {
        self.currentCalibration = nil
        self.isCalibrated = false
        print("🔄 Calibrazione rimossa")
    }
    
    // MARK: - Data Parsing
    
    private func parseWitMotionPacket(_ data: Data) {
        guard data.count >= 20 else {
            print("⚠️ Pacchetto troppo corto: \(data.count) bytes")
            return
        }
        
        let bytes = [UInt8](data)
        
        // Verifica header 0x55 0x61
        guard bytes[0] == 0x55 && bytes[1] == 0x61 else {
            print("⚠️ Header non valido: 0x\(String(format: "%02X", bytes[0])) 0x\(String(format: "%02X", bytes[1]))")
            return
        }
        
        // Estrai accelerazione (byte 2-7, signed int16, scala ±16g)
        let axRaw = Int16(bytes[3]) << 8 | Int16(bytes[2])
        let ayRaw = Int16(bytes[5]) << 8 | Int16(bytes[4])
        let azRaw = Int16(bytes[7]) << 8 | Int16(bytes[6])
        
        // Estrai velocità angolare (byte 8-13, signed int16, scala ±2000°/s)
        let gxRaw = Int16(bytes[9]) << 8 | Int16(bytes[8])
        let gyRaw = Int16(bytes[11]) << 8 | Int16(bytes[10])
        let gzRaw = Int16(bytes[13]) << 8 | Int16(bytes[12])
        
        // Estrai angoli (byte 14-19, signed int16, scala ±180°)
        let rollRaw = Int16(bytes[15]) << 8 | Int16(bytes[14])
        let pitchRaw = Int16(bytes[17]) << 8 | Int16(bytes[16])
        let yawRaw = Int16(bytes[19]) << 8 | Int16(bytes[18])
        
        // Converti con scale corrette (dati RAW)
        rawAcceleration = [
            Double(axRaw) / 32768.0 * 16.0,
            Double(ayRaw) / 32768.0 * 16.0,
            Double(azRaw) / 32768.0 * 16.0
        ]
        
        rawAngularVelocity = [
            Double(gxRaw) / 32768.0 * 2000.0,
            Double(gyRaw) / 32768.0 * 2000.0,
            Double(gzRaw) / 32768.0 * 2000.0
        ]
        
        rawAngles = [
            Double(rollRaw) / 32768.0 * 180.0,
            Double(pitchRaw) / 32768.0 * 180.0,
            Double(yawRaw) / 32768.0 * 180.0
        ]
        
        // Applica calibrazione se presente
        var finalAcceleration = rawAcceleration
        var finalAngularVelocity = rawAngularVelocity
        var finalAngles = rawAngles
        
        if let calibration = currentCalibration {
            let calibrated = calibration.applyCalibration(
                acceleration: rawAcceleration,
                angularVelocity: rawAngularVelocity,
                angles: rawAngles
            )
            finalAcceleration = calibrated.acceleration
            finalAngularVelocity = calibrated.angularVelocity
            finalAngles = calibrated.angles
            
        }
        
        DispatchQueue.main.async {
            self.acceleration = finalAcceleration
            self.angularVelocity = finalAngularVelocity
            self.angles = finalAngles
        }
        if self.isCalibrated && Int.random(in: 0...49) == 0 {
            print("📊 CALIBRATO: X=\(String(format: "%.3f", finalAcceleration[0]))g, " +
                  "Y=\(String(format: "%.3f", finalAcceleration[1]))g, " +
                  "Z=\(String(format: "%.3f", finalAcceleration[2]))g")
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension BLEManager: CBCentralManagerDelegate {
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            statusMessage = "Bluetooth pronto"
            print("✅ Bluetooth powered ON")
        case .poweredOff:
            statusMessage = "Bluetooth spento"
            print("❌ Bluetooth powered OFF")
        case .unauthorized:
            statusMessage = "Permessi Bluetooth negati"
            print("⚠️ Bluetooth unauthorized")
        case .unsupported:
            statusMessage = "Bluetooth non supportato"
            print("❌ Bluetooth unsupported")
        default:
            statusMessage = "Bluetooth non disponibile"
        }
    }
    
    func centralManager(_ central: CBCentralManager,
                       didDiscover peripheral: CBPeripheral,
                       advertisementData: [String : Any],
                       rssi RSSI: NSNumber) {
        
        // Evita duplicati
        guard !discoveredDevices.contains(where: { $0.identifier == peripheral.identifier }) else {
            return
        }
        
        print("📡 Trovato: \(peripheral.name ?? "Unknown") - RSSI: \(RSSI)")
        
        DispatchQueue.main.async {
            self.discoveredDevices.append(peripheral)
        }
    }
    
    func centralManager(_ central: CBCentralManager,
                       didConnect peripheral: CBPeripheral) {
        print("✅ Connesso a: \(peripheral.name ?? "Unknown")")
        
        DispatchQueue.main.async {
            self.isConnected = true
            self.connectedPeripheral = peripheral
            self.sensorName = peripheral.name ?? "WitMotion"
            self.statusMessage = "Connesso"
        }
        
        peripheral.delegate = self
        peripheral.discoverServices([serviceUUID])
    }
    
    func centralManager(_ central: CBCentralManager,
                       didDisconnectPeripheral peripheral: CBPeripheral,
                       error: Error?) {
        print("🔌 Disconnesso da: \(peripheral.name ?? "Unknown")")
        
        DispatchQueue.main.async {
            self.isConnected = false
            self.sensorName = "Non connesso"
            self.statusMessage = "Disconnesso"
            self.connectedPeripheral = nil
            
            // Reset dati
            self.acceleration = [0.0, 0.0, 0.0]
            self.angularVelocity = [0.0, 0.0, 0.0]
            self.angles = [0.0, 0.0, 0.0]
        }
    }
    
    func centralManager(_ central: CBCentralManager,
                       didFailToConnect peripheral: CBPeripheral,
                       error: Error?) {
        print("❌ Connessione fallita: \(error?.localizedDescription ?? "Unknown error")")
        
        DispatchQueue.main.async {
            self.statusMessage = "Connessione fallita"
            self.isConnected = false
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BLEManager: CBPeripheralDelegate {
    
    func peripheral(_ peripheral: CBPeripheral,
                   didDiscoverServices error: Error?) {
        if let error = error {
            print("❌ Errore scoperta servizi: \(error)")
            return
        }
        
        guard let services = peripheral.services else { return }
        
        for service in services {
            print("🔍 Servizio trovato: \(service.uuid)")
            peripheral.discoverCharacteristics([characteristicUUID], for: service)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral,
                   didDiscoverCharacteristicsFor service: CBService,
                   error: Error?) {
        if let error = error {
            print("❌ Errore scoperta caratteristiche: \(error)")
            return
        }
        
        guard let characteristics = service.characteristics else { return }
        
        for characteristic in characteristics {
            print("🔍 Caratteristica trovata: \(characteristic.uuid)")
            
            if characteristic.uuid == characteristicUUID {
                print("✅ Attivazione notifiche per caratteristica dati")
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral,
                   didUpdateValueFor characteristic: CBCharacteristic,
                   error: Error?) {
        if let error = error {
            print("❌ Errore lettura valore: \(error)")
            return
        }
        
        guard let data = characteristic.value else { return }
        parseWitMotionPacket(data)
    }
    
    func peripheral(_ peripheral: CBPeripheral,
                   didUpdateNotificationStateFor characteristic: CBCharacteristic,
                   error: Error?) {
        if let error = error {
            print("❌ Errore notifiche: \(error)")
            return
        }
        
        if characteristic.isNotifying {
            print("✅ Notifiche ATTIVE - streaming dati iniziato")
        } else {
            print("ℹ️ Notifiche DISATTIVATE")
        }
    }
}

