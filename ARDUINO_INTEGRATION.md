# Integrazione Sensore Arduino Nano 33 BLE + VL53L0X

## 📋 Stato Implementazione

### ✅ Completato

1. **Strutture Base**
   - `SensorType` enum per gestire WitMotion e Arduino
   - `MovementState` enum per stati movimento dal sensore
   - `DistanceSensorDataProvider` protocol

2. **Manager Sensore Arduino**
   - `ArduinoBLEManager`: Gestisce connessione BLE con Arduino
   - Parsing pacchetti (8 byte): distanza + timestamp + stato movimento
   - Sample rate estimation
   - Auto-reconnect

3. **Rilevatore Basato su Distanza**
   - `DistanceBasedRepDetector`: Rileva ripetizioni da dati di distanza diretta
   - Calcolo MPV/PPV da velocità derivata (più preciso dell'integrazione)
   - Validazione ROM personalizzabile
   - Rilevamento fasi eccentrica/concentrica

4. **Manager Unificato**
   - `UnifiedSensorManager`: Wrapper per entrambi i sensori
   - Switching automatico basato su `SettingsManager.selectedSensorType`
   - Interfaccia unificata per l'app

5. **Impostazioni**
   - Aggiunto `selectedSensorType` in `SettingsManager`
   - UI per selezione tipo sensore in `SensorSettingsView`

## 🔧 Prossimi Passi di Integrazione

### 1. Aggiungere File al Progetto Xcode

In Xcode, aggiungi questi nuovi file al progetto:
- `Models/SensorType.swift`
- `Managers/ArduinoBLEManager.swift`
- `Managers/DistanceBasedRepDetector.swift`
- `Managers/UnifiedSensorManager.swift`

### 2. Modificare HomeView

```swift
// Da:
@StateObject private var bleManager = BLEManager()

// A:
@StateObject private var sensorManager = UnifiedSensorManager()
```

Poi passare `sensorManager` invece di `bleManager` alle viste che lo richiedono.

### 3. Aggiornare TrainingSessionManager

Modificare per accettare sia dati da accelerometro che da distanza:

```swift
// Aggiungere proprietà per distanza
@Published var currentDistance: Double = 0.0

// Modificare startRecording per usare detector appropriato
func startRecording(with sensorManager: UnifiedSensorManager) {
    switch sensorManager.currentSensorType {
    case .witmotion:
        // Usa VBTRepDetector (esistente)
    case .arduino:
        // Usa DistanceBasedRepDetector (nuovo)
    }
}
```

### 4. Creare Vista Test Arduino (Opzionale)

Per testare rapidamente il sensore Arduino senza modificare il flusso principale:

```swift
struct ArduinoTestView: View {
    @StateObject private var arduino = ArduinoBLEManager()
    @StateObject private var detector = DistanceBasedRepDetector()

    var body: some View {
        VStack {
            Text("Distanza: \(arduino.distance) mm")
            Text("Stato: \(arduino.movementState.displayName)")
            // ... visualizza metriche
        }
        .onReceive(arduino.$distance) { distance in
            detector.processSample(
                distance: distance,
                timestamp: Date()
            )
        }
    }
}
```

### 5. Aggiornare SensorScanView

Modificare per supportare scansione di entrambi i tipi:

```swift
struct SensorScanView: View {
    @ObservedObject var sensorManager: UnifiedSensorManager

    var body: some View {
        // Mostra dispositivi dal manager appropriato
        switch sensorManager.currentSensorType {
        case .witmotion:
            // Lista da sensorManager.bleManager.discoveredDevices
        case .arduino:
            // Lista da sensorManager.arduinoManager.discoveredDevices
        }
    }
}
```

## 🎯 Vantaggi del Sensore Arduino

1. **Precisione Superiore**: Misura diretta della distanza invece di integrazione doppia dell'accelerazione
2. **Meno Drift**: Nessun accumulo di errore da integrazione
3. **Calcolo Diretto Velocità**: Derivata semplice invece di integrazione complessa
4. **ROM Preciso**: Misura esatta dello spostamento
5. **Minore Latenza**: Meno elaborazione necessaria

## 📊 Formato Pacchetto Arduino

```
Byte 0-1: Distanza (uint16, little-endian, mm)
Byte 2-5: Timestamp (uint32, little-endian, ms)
Byte 6:   Stato movimento (0=approaching, 1=receding, 2=idle)
Byte 7:   Riservato
```

## 🔌 UUID Bluetooth

```
Service:        19B10000-E8F2-537E-4F6C-D104768A1214
Characteristic: 19B10001-E8F2-537E-4F6C-D104768A1214
```

## ⚙️ Configurazione Consigliata

- **Sample Rate**: 50Hz (SAMPLE_INTERVAL = 20ms in Arduino)
- **ROM Default**: 500mm (bench press tipica)
- **Tolleranza ROM**: ±30%
- **Velocità Minima**: 50 mm/s per rilevare movimento

## 🧪 Testing

1. Flashare codice Arduino sul Nano 33 BLE
2. Aprire app e andare in Settings → Sensore
3. Selezionare "Arduino Nano 33 BLE (Distanza)"
4. Cercare sensori (dovrebbe apparire "VBT-Sensor-Rev2")
5. Connettere e testare

## 📝 Note

- Il sensore Arduino **non richiede calibrazione** (a differenza del WitMotion)
- La distanza è misurata in millimetri dall'Arduino e convertita in metri internamente
- Il rilevamento delle fasi usa la variazione di distanza invece dell'accelerazione
- Supporta profili di rilevamento adattivi come il WitMotion

## 🐛 Debug

Usa i log per verificare:
```
📡 Inizio scansione sensori Arduino
🔍 Trovato: VBT-Sensor-Rev2
✅ Connesso a: VBT-Sensor-Rev2
📊 Sample rate stabile: 50.0 Hz
📏 Baseline stabilita: XXX.X mm
⬇️ Inizio eccentrica
⬆️ Inizio concentrica
✅ REP RILEVATA - ROM: X.XXXm, MPV: X.XXXm/s, PPV: X.XXXm/s
```
