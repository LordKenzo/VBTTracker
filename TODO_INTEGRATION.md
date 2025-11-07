# TODO: Completamento Integrazione Arduino Sensor

## ✅ Completato

### Strutture Base
- [x] SensorType enum e protocolli
- [x] ArduinoBLEManager
- [x] DistanceBasedRepDetector
- [x] UnifiedSensorManager
- [x] SettingsManager integration

### Viste Principali Aggiornate
- [x] HomeView → UnifiedSensorManager
- [x] SettingsView → UnifiedSensorManager
- [x] SensorSettingsView → Supporto entrambi i sensori
- [x] SensorScanView → Supporto entrambi i sensori
- [x] TrainingSelectionView → UnifiedSensorManager

## 📋 Passi Rimanenti

### 1. RepTargetSelectionView
**File:** `/VBTTracker/Views/Training/RepTargetSelectionView.swift`

```swift
// Cambia da:
@ObservedObject var bleManager: BLEManager

// A:
@ObservedObject var sensorManager: UnifiedSensorManager

// E aggiorna:
- bleManager.isConnected → sensorManager.isConnected
- bleManager.sensorName → sensorManager.sensorName
```

### 2. TrainingSessionView (CRITICO)
**File:** `/VBTTracker/Views/Training/TrainingSessionView.swift`

Questo è il file più importante dove avviene il rilevamento delle rep.

**Modifiche necessarie:**

```swift
struct TrainingSessionView: View {
    @ObservedObject var sensorManager: UnifiedSensorManager

    // Aggiungere:
    @StateObject private var distanceDetector = DistanceBasedRepDetector()
    @StateObject private var sessionManager = TrainingSessionManager()

    // Nel body, sottoscrivere ai dati del sensore appropriato:
    .onReceive(sensorManager.bleManager.$acceleration) { acc in
        if settings.selectedSensorType == .witmotion {
            // Usa accelerazione (esistente)
        }
    }
    .onReceive(sensorManager.arduinoManager.$distance) { distance in
        if settings.selectedSensorType == .arduino {
            // Processa con distanceDetector
            distanceDetector.processSample(
                distance: distance,
                timestamp: Date()
            )
        }
    }

    // Setup detector callbacks:
    distanceDetector.onRepDetected = { metrics in
        // Aggiorna sessionManager con MPV/PPV
        sessionManager.addRepetition(
            mpv: metrics.meanPropulsiveVelocity,
            ppv: metrics.peakPropulsiveVelocity,
            displacement: metrics.displacement
        )
    }
}
```

### 3. RecordPatternView
**File:** `/VBTTracker/Views/Training/RecordPatternView.swift`

```swift
// Cambia da:
@ObservedObject var bleManager: BLEManager

// A:
@ObservedObject var sensorManager: UnifiedSensorManager

// Solo per WitMotion - Arduino non usa pattern
if settings.selectedSensorType == .witmotion {
    // Mostra UI registrazione pattern
}
```

### 4. SensorConnectionView (Deprecato?)
**File:** `/VBTTracker/Views/Sensor/SensorConnectionView.swift`

Questa vista sembra duplicata con SensorSettingsView. Verificare se è ancora usata.
Se sì, aggiornare come SensorSettingsView, altrimenti rimuovere.

### 5. TrainingSessionManager Enhancements
**File:** `/VBTTracker/Managers/TrainingSessionManager.swift`

Aggiungere metodi per gestire metriche da Arduino:

```swift
// Aggiungere:
func addRepetitionFromDistance(
    mpv: Double,
    ppv: Double,
    displacement: Double,
    concentricDuration: TimeInterval
) {
    // Simile a addRepetition esistente ma con dati diretti
    repMeanPropulsiveVelocities.append(mpv)
    repPeakPropulsiveVelocities.append(ppv)

    // Calcola velocity loss
    if firstRepMPV == nil {
        firstRepMPV = mpv
    }

    let loss = calculateVelocityLoss(current: mpv, first: firstRepMPV!)
    velocityLoss = loss

    // Voice feedback
    if voiceFeedbackEnabled {
        voiceFeedback.announceRep(number: repCount + 1, velocity: mpv)
    }

    repCount += 1
}
```

## 🔧 Testing Checklist

### WitMotion (Regressione)
- [ ] Connessione funziona
- [ ] Calibrazione funziona
- [ ] Rilevamento rep funziona
- [ ] Pattern library funziona
- [ ] Voice feedback funziona

### Arduino VL53L0X (Nuovo)
- [ ] Scansione trova sensore
- [ ] Connessione funziona
- [ ] Dati distanza in real-time
- [ ] Rilevamento rep da distanza
- [ ] MPV/PPV calcolati correttamente
- [ ] ROM validazione funziona

## 📝 Note Implementazione

### Strategia Rilevamento
- **WitMotion**: Usa `VBTRepDetector` esistente con accelerazione
- **Arduino**: Usa `DistanceBasedRepDetector` con distanza diretta

### Vantaggi Arduino
- Zero drift (misura diretta vs integrazione doppia)
- ROM preciso (mm vs approssimazione)
- Nessuna calibrazione necessaria
- Calcolo velocità più affidabile

### Limitazioni Arduino
- Non supporta pattern learning (solo WitMotion)
- Richiede sensore laser a vista (line-of-sight)
- Range limitato a 30-2000mm

## 🚀 Deploy

1. Testare build in Xcode
2. Verificare che entrambi i sensori funzionino
3. Testare switch tra sensori
4. Creare PR con descrizione dettagliata
5. Aggiornare documentazione utente

## 📚 Documentazione Utente

Creare guida per:
- Setup sensore Arduino
- Caricamento firmware
- Primo collegamento
- Confronto WitMotion vs Arduino
- Quando usare quale sensore
