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
    private var notifyCharacteristic: CBCharacteristic?    // stream dati (notify)
    private var writeCharacteristic: CBCharacteristic?     // comandi (write / writeWithoutResponse)
    private var seenPeripherals: [UUID: CBPeripheral] = [:]

    // UUID del sensore WitMotion
    static let serviceUUID = CBUUID(string: "0000FFE5-0000-1000-8000-00805F9A34FB")
    static let characteristicUUID = CBUUID(string: "0000FFE4-0000-1000-8000-00805F9A34FB")

    // Sample rate estimation
    private var lastPacketTime: Date?
    private var intervalEMA: Double?
    private let srAlpha = 0.2
    // private var lastSRLog: Date = .distantPast

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
        connectedPeripheral = peripheral  // âœ… riferimento forte
        sensorName = peripheral.name ?? "WitMotion"

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

    func applyCalibration(_ calibration: CalibrationData) {
        currentCalibration = calibration
        isCalibrated = true
        print("✅ Calibrazione applicata al BLEManager")
    }

    func removeCalibration() {
        currentCalibration = nil
        isCalibrated = false
        print("🗑️ Calibrazione rimossa")
    }

    // MARK: - Scanning
    func startScanning() {
        guard central.state == .poweredOn else {
            statusMessage = "Bluetooth non disponibile"
            print("⚠️ Bluetooth non poweredOn")
            return
        }

        discoveredDevices.removeAll()
        seenPeripherals.removeAll()

        isScanning = true
        statusMessage = "Scansione in corso 🔍"
        print("Inizio scansione dispositivi WitMotion")

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
        print("Scansione fermata 🔍 Trovati \(discoveredDevices.count) dispositivi")
    }

    
    // MARK: - Sample rate estimation (STABILE)

    private var packetTimestamps: [Date] = []
    private let SR_WINDOW_SIZE = 50        // Calcola SR su 50 pacchetti
    private let SR_UPDATE_THRESHOLD = 10.0 // Aggiorna solo se varia >10Hz
    private var lastPublishedSR: Double?
    private var srStableCounter = 0        // Conta pacchetti consecutivi stabili

    private func resetSampleRateEstimation() {
        lastPacketTime = nil
        intervalEMA = nil
        sampleRateHz = nil
        packetTimestamps.removeAll()
        lastPublishedSR = nil
        srStableCounter = 0
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
        
        // Clamp a range ragionevole
        let clampedSR = max(5.0, min(instantSR, 500.0))
        
        // Pubblicazione con hysteresis
        let shouldPublish: Bool
        if let last = lastPublishedSR {
            // Aggiorna solo se:
            // 1. Varia più del threshold (10Hz)
            // 2. È stabile da almeno 10 pacchetti
            let delta = abs(clampedSR - last)
            
            if delta > SR_UPDATE_THRESHOLD {
                // Grande variazione -> resetta counter
                srStableCounter = 0
                shouldPublish = false
            } else {
                // Piccola variazione -> incrementa counter
                srStableCounter += 1
                shouldPublish = srStableCounter >= 10 // Stabile per 10 pacchetti
            }
        } else {
            // Prima pubblicazione
            shouldPublish = true
            srStableCounter = 0
        }
        
        if shouldPublish {
            let oldSR = sampleRateHz
            sampleRateHz = clampedSR
            lastPublishedSR = clampedSR
            
            // Log solo se cambia significativamente
            if oldSR == nil || abs((oldSR ?? 0) - clampedSR) > 5.0 {
                print("📊 Sample rate stabile: \(String(format: "%.1f", clampedSR)) Hz (finestra \(packetTimestamps.count) pacchetti)")
            }
            
            // Notifica cambio (throttle 1 secondo)
            if now.timeIntervalSince(lastSRNotifyTime) > 1.0 {
                lastSRNotifyTime = now
                NotificationCenter.default.post(
                    name: NSNotification.Name("BLE_SR_UPDATED"),
                    object: nil
                )
            }
            
            srStableCounter = 0 // Reset counter dopo pubblicazione
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
            self.sensorName = peripheral.name ?? "WitMotion"
            self.statusMessage = "Connesso"
            self.resetSampleRateEstimation()
        }
        
        peripheral.delegate = self
        peripheral.discoverServices([Self.serviceUUID])
        
        // 🆕 AUTO-CONFIGURA a 200Hz dopo 1 secondo (tempo per discovery)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.configureFor200Hz()
        }
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
            print("🔴 Errore scoperta servizi: \(error)")
            return
        }
        peripheral.services?.forEach { service in
            print("🟢 Servizio: \(service.uuid)")
            // 👇 Scopriamo TUTTE le caratteristiche (non solo FFE4)
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
            print("🟢 Caratteristica: \(ch.uuid)  props=\(ch.properties)")

            // Stream dati (notify) → tipicamente FFE4
            if ch.uuid == Self.characteristicUUID || ch.properties.contains(.notify) {
                notifyCharacteristic = ch
                dataCharacteristic = ch
                print("✅ Attivo notifiche dati su \(ch.uuid)")
                peripheral.setNotifyValue(true, for: ch)
            }

            // Comandi (write) → qualsiasi char con write* (spesso FFE9)
            if ch.properties.contains(.write) || ch.properties.contains(.writeWithoutResponse) ||
               ch.uuid == CBUUID(string: "0000FFE9-0000-1000-8000-00805F9A34FB") {
                writeCharacteristic = ch
                print("✍️  Useremo \(ch.uuid) per i comandi (write)")
            }
        }

        if writeCharacteristic == nil {
            print("⚠️ Nessuna caratteristica di WRITE disponibile (non posso configurare il rate)")
        }
    }
    
    // MARK: - Write helper
    private func writeBytes(_ bytes: [UInt8]) {
        guard let p = connectedPeripheral, let ch = writeCharacteristic else {
            print("⚠️ Nessuna caratteristica di WRITE disponibile"); return
        }
        let type: CBCharacteristicWriteType = ch.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        p.writeValue(Data(bytes), for: ch, type: type)
    }
    
    // MARK: - Read register helper (FF AA 27 XX 00)
    private func readRegister(_ addr: UInt8) {
        writeBytes([0xFF, 0xAA, 0x27, addr, 0x00])
    }

    // Convenient wrappers
    private func readRate()      { readRegister(0x03) } // RATE
    private func readBandwidth() { readRegister(0x1F) } // BANDWIDTH

    // MARK: - Comandi WitMotion (FF AA …)
    private func unlock() { writeBytes([0xFF, 0xAA, 0x69, 0x88, 0xB5]) }     // sblocco config
    private func saveConfig() { writeBytes([0xFF, 0xAA, 0x00, 0x00, 0x00]) }  // salva

    /// Bandwidth @0x1F: 0x00=256Hz, 0x01=188Hz, 0x02=98Hz, 0x03=42Hz, 0x04=20Hz, 0x05=10Hz, 0x06=5Hz
    private func setBandwidth(_ code: UInt8) {
        writeBytes([0xFF, 0xAA, 0x1F, code, 0x00])
    }

    /// Return Rate variante "codice" (più comune su WT901BLE): 0x0B = 200Hz, 0x09 = 100Hz, 0x06 = 10Hz…
    private func setReturnRateCode(_ code: UInt8) {
        writeBytes([0xFF, 0xAA, 0x03, code, 0x00])
    }

    /// Return Rate variante "valore assoluto" (alcuni firmware accettano 200=0xC8)
    private func setReturnRateValue(_ value: UInt16) {
        let lo = UInt8(value & 0xFF), hi = UInt8((value >> 8) & 0xFF)
        // se il tuo firmware usasse realmente questa forma, spesso il comando è 0x03 poi lo/hi o hi/lo.
        // Qui invio lo/hi come molti esempi; se non cambia nulla restiamo al metodo "code".
        writeBytes([0xFF, 0xAA, 0x03, lo, hi])
    }
    
    /// Imposta BW alta e Return Rate 200 Hz, poi salva.
    /// Prova prima la forma "code" (0x0B = 200Hz). In fallback usa la forma "valore" (200 = 0x00C8).
    func configureFor200Hz() {
        guard writeCharacteristic != nil else {
            print("⚠️ Impossibile configurare: nessuna caratteristica di WRITE")
            return
        }
        
        print("⚙️ Inizio configurazione 200 Hz...")
        
        // Step 1: Unlock (50ms)
        unlock()
        
        // Step 2: Set Bandwidth 256Hz (100ms)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.setBandwidth(0x00) // 256 Hz
            print("   • Bandwidth → 256Hz")
        }
        
        // Step 3: Set Return Rate 200Hz (150ms)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
            self.setReturnRateCode(0x0B) // 200 Hz
            print("   • Return Rate → 200Hz (code 0x0B)")
        }
        
        // Step 4: Save config (200ms)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            self.saveConfig()
            print("   • Config salvata")
        }
        
        // Step 5: Verifica dopo 500ms
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.50) {
            self.readBandwidth()
            self.readRate()
            print("   • Verifica configurazione...")
        }
        
        // Step 6: Check sample rate dopo 1.5s
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            let currentSR = self.sampleRateHz ?? 0
            print("   • Sample rate rilevato: \(String(format: "%.1f", currentSR)) Hz")
            
            if currentSR < 80 {
                print("⚠️ Sample rate basso, retry con 100Hz...")
                self.retryWith100Hz()
            } else if currentSR >= 150 {
                print("✅ Sensore configurato correttamente a ~200Hz")
            } else {
                print("⚠️ Sample rate intermedio (~100Hz), accettabile ma non ottimale")
            }
        }
    }

    /// Fallback: prova 100Hz se 200Hz non funziona
    private func retryWith100Hz() {
        unlock()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.setBandwidth(0x00) // 256 Hz
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
            self.setReturnRateCode(0x09) // 100 Hz
            print("   • Retry: Return Rate → 100Hz (code 0x09)")
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            self.saveConfig()
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.50) {
            self.readRate()
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            let currentSR = self.sampleRateHz ?? 0
            print("   • Sample rate dopo retry: \(String(format: "%.1f", currentSR)) Hz")
            
            if currentSR >= 50 {
                print("✅ Configurazione 100Hz accettata")
            } else {
                print("❌ Configurazione fallita, sample rate troppo basso")
                print("   Possibili cause:")
                print("   1. Sensore non supporta comandi di configurazione")
                print("   2. Caratteristica WRITE non corretta")
                print("   3. Firmware sensore non standard")
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

        let bytes = [UInt8](data)
        if bytes.count >= 6, bytes[0] == 0x55, bytes[1] == 0x71 {
            // Single-return packet: 55 71 <startReg> 00 <v0L> <v0H> <v1L> <v1H> ...
            let start = bytes[2]
            let v0L = bytes[4], _ = bytes[5]
            // let value = Int(v0H) << 8 | Int(v0L)

            switch start {
            case 0x03:
                // RATE letto
                let code = v0L // spesso basta il low-byte
                print("🔎 RATE register: 0x\(String(format: "%02X", code)) " + mapRate(code: code))

            case 0x1F:
                let code = v0L & 0x0F
                print("🔎 BANDWIDTH register: 0x\(String(format: "%02X", code)) " + mapBW(code: code))

            default:
                break
            }
            return // non è un pacchetto 0x61, quindi esco qui
        }

        // Pacchetto dati standard (0x55 0x61) → parsing normale
        DispatchQueue.main.async {
            self.parseWitMotionPacket(data)
        }
    }
    
    // MARK: - Pretty print helpers
    private func mapRate(code: UInt8) -> String {
        switch code {
        case 0x01: return "(0.2 Hz)"
        case 0x02: return "(0.5 Hz)"
        case 0x03: return "(1 Hz)"
        case 0x04: return "(2 Hz)"
        case 0x05: return "(5 Hz)"
        case 0x06: return "(10 Hz default)"
        case 0x07: return "(20 Hz)"
        case 0x08: return "(50 Hz)"
        case 0x09: return "(100 Hz)"
        case 0x0B: return "(200 Hz)"
        case 0x0C: return "(single return)"
        default:   return "(unknown)"
        }
    }

    private func mapBW(code: UInt8) -> String {
        switch code & 0x0F {
        case 0x00: return "(256 Hz)"
        case 0x01: return "(188 Hz)"
        case 0x02: return "(98 Hz)"
        case 0x03: return "(42 Hz)"
        case 0x04: return "(20 Hz default)"
        case 0x05: return "(10 Hz)"
        case 0x06: return "(5 Hz)"
        default:   return "(unknown)"
        }
    }


}
