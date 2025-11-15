# Capitolo 3: Sfide Tecniche e Soluzioni

## 3.1 Introduzione

Durante lo sviluppo di VBT Tracker sono emerse diverse sfide tecniche complesse. Questo capitolo documenta i problemi principali affrontati, le soluzioni implementate e le lezioni apprese.

## 3.2 Sfida #1: Touch-and-Go Rep Detection

### 3.2.1 Problema

**Contesto**: Atleti avanzati eseguono ripetizioni "touch-and-go" senza pausa al top della concentrica, invertendo immediatamente verso una nuova eccentrica.

**Sintomo**: Reps non venivano contate se mancava lo stato `IDLE` tra concentrica e eccentrica.

**Log problematico**:
```
⬇️ Inizio eccentrica a 523.5 mm
🔄 Transizione a concentrica a 135.8 mm
⬆️ Concentrica confermata
[Bilanciere arriva a 520mm ma non si ferma]
⬇️ Inizio eccentrica a 518.2 mm  ← Nuova eccentrica senza completare prima rep!
❌ Rep persa
```

### 3.2.2 Analisi Root Cause

**Arduino Hold Timers**:
```cpp
#define HOLD_ON_MS 60    // 60ms sopra threshold → IDLE
#define HOLD_OFF_MS 120  // 120ms sotto threshold → movimento
```

Touch-and-go: bilanciere inverte <60ms al top → Arduino non manda MAI `IDLE`

**Swift Detector Logic (BEFORE)**:
```swift
case .ascending:
    if arduinoState == .idle {  // ❌ Non arriva mai!
        tryCompleteRep()
    }
```

### 3.2.3 Soluzione Implementata

**Doppia condizione di completamento** (DistanceBasedRepDetector.swift:312-333):

```swift
case .ascending:
    concentricSamples.append(currentSample)

    if concentricSamples.count >= lookAheadSamples {
        // CASO 1: Rep con pausa (beginners)
        if arduinoState == .idle {
            print("✅ Rep completata con pausa al top")
            tryCompleteRep(currentSample: currentSample)
        }

        // CASO 2: Touch-and-go (advanced) ⭐ NEW
        else if arduinoState == .receding {
            print("🔄 Touch-and-go: completamento rep e inizio nuova eccentrica")
            tryCompleteRep(currentSample: currentSample)

            // Inizia immediatamente nuova eccentrica
            state = .descending
            eccentricStartTime = currentSample.timestamp
            eccentricStartDistance = smoothedDist
            onPhaseChange?(.descending)
        }
    }
```

**Before/After**:

| Scenario | Before | After |
|----------|--------|-------|
| Pause at top (500ms) | ✅ Detected | ✅ Detected |
| Quick pause (80ms) | ❌ Lost | ✅ Detected |
| Touch-and-go (0ms) | ❌ Lost | ✅ Detected |

### 3.2.4 Validation

**Test**: 20 reps touch-and-go @ 60% 1RM
- **Before**: 8/20 detected (40%)
- **After**: 20/20 detected (100%) ✅

**Commit**: `a030b02` - "Fix touch-and-go rep detection"

## 3.3 Sfida #2: Movimenti Veloci Non Rilevati

### 3.3.1 Problema

**Contesto**: Utente allena "Velocità" (0.75-1.00 m/s) con movimenti esplosivi.

**Sintomo**: Reps con concentrica <400ms non venivano rilevate.

**Esempio**:
```
Target: Velocità (MPV 0.85 m/s)
Concentrica reale: 320ms
lookAheadSamples: 10 (200ms @ 50Hz)
minConcentricDuration: 300ms

Timeline:
t=0ms    Inizio concentrica
t=200ms  lookAhead check ← troppo presto!
t=320ms  Fine concentrica ← già passata!
t=400ms  Arduino → ECCENTRIC (nuova rep)
❌ Rep persa
```

### 3.3.2 Analisi Root Cause

**Parametri fissi** inadatti per spettro completo velocità:

| Velocity Zone | Concentric Duration | lookAhead @50Hz | Result |
|---------------|---------------------|-----------------|--------|
| Forza Max (0.2 m/s) | 800-1200ms | 200ms | ✅ OK |
| Forza (0.4 m/s) | 500-700ms | 200ms | ✅ OK |
| Velocità (0.85 m/s) | 250-400ms | 200ms | ❌ MISS |
| Velocità Max (1.2 m/s) | 150-250ms | 200ms | ❌ MISS |

**Problema**: One-size-fits-all NON funziona con velocity-based training!

### 3.3.3 Soluzione: Parametri Adattivi

**Implementazione** (DistanceBasedRepDetector.swift:28-53):

```swift
/// Look-ahead samples dinamico basato sulla velocity target
var lookAheadSamples: Int {
    let targetVelocity = SettingsManager.shared.targetMeanVelocity

    switch targetVelocity {
    case 0..<0.30:   return 10  // Forza Massima: 200ms (lento, stabile)
    case 0.30..<0.50: return 7  // Forza: 140ms
    case 0.50..<0.75: return 5  // Forza-Velocità: 100ms
    case 0.75..<1.00: return 3  // Velocità: 60ms ⚡ (veloce, reattivo)
    default:          return 2  // Velocità Massima: 40ms ⚡⚡
    }
}

private var minConcentricDuration: TimeInterval {
    let targetVelocity = SettingsManager.shared.targetMeanVelocity

    switch targetVelocity {
    case 0..<0.30:   return 0.5   // Forza Massima: >500ms
    case 0.30..<0.50: return 0.4  // Forza: >400ms
    case 0.50..<0.75: return 0.3  // Forza-Velocità: >300ms
    case 0.75..<1.00: return 0.2  // Velocità: >200ms ⚡
    default:          return 0.15 // Velocità Massima: >150ms ⚡⚡
    }
}
```

**Logging** (on reset):
```
🔄 DistanceBasedRepDetector reset
⚙️ Parametri adattivi (target MPV: 0.85 m/s):
   • lookAheadSamples: 3 (~60ms)
   • minConcentricDuration: 0.20s
```

**Before/After**:

| Test Scenario | Before | After |
|---------------|--------|-------|
| 5 reps @ Forza Max (0.25 m/s, ~900ms concentric) | 5/5 ✅ | 5/5 ✅ |
| 5 reps @ Velocità (0.85 m/s, ~350ms concentric) | 0/5 ❌ | 5/5 ✅ |
| 3 reps @ Velocità Max (1.1 m/s, ~200ms concentric) | 0/3 ❌ | 3/3 ✅ |

### 3.3.4 Trade-offs

**Pro**:
- ✅ Rileva tutto lo spettro di velocità
- ✅ Auto-configura basandosi su intent utente
- ✅ Mantiene precisione per movimenti lenti

**Contro**:
- ⚠️ Movimenti veloci più sensibili a rumore
- ⚠️ Lookhead 40ms potrebbe triggerare su false positives

**Mitigazione**: Validazione ROM rigorosa + refractory period.

**Commit**: `90a15f5` - "Add adaptive parameters for fast movements detection"

## 3.4 Sfida #3: WitMotion Sample Rate Basso

### 3.4.1 Problema

**Contesto**: WitMotion WT901BLE connesso via BLE, configurato (teoricamente) a 200Hz.

**Sintomo**: App misura solo ~24Hz invece di 200Hz.

**Log**:
```
📊 Sample rate stabile: 24.4 Hz (finestra 20 pacchetti)
⚙️ Inizio configurazione 200 Hz...
📤 Write [FF AA 69 88 B5] → FFE9 (type: withResponse)  // Unlock
📤 Write [FF AA 1F 00 00] → FFE9 (type: withResponse)  // Bandwidth
📤 Write [FF AA 03 0B 00] → FFE9 (type: withResponse)  // Rate 200Hz
📤 Write [FF AA 00 00 00] → FFE9 (type: withResponse)  // Save
📊 Sample rate stabile: 16.0 Hz  ← WORSE!
❌ Configurazione fallita
```

### 3.4.2 Investigazione Multi-fase

**Fase 1: Verifica comandi**

Confronto con documentazione WitMotion:
```
Manuale WT9011DCL:
- Unlock: FF AA 69 88 B5 ✅
- Set Rate 200Hz: FF AA 03 0B 00 ✅
- Save: FF AA 00 00 00 ✅
```

Comandi corretti! ✅

**Fase 2: UUID Mismatch Discovery**

```
🟢 Servizio: 0000FFE5-...
🟢 Caratteristica: 0000FFE9-...  props=12  ← WRITE
🟢 Caratteristica: 0000FFE4-...  props=16  ← NOTIFY
✍️ Comandi su FFE9
✅ Dati su FFE4
```

Manuale dice WT9011DCL usa **FFF0/FFF1/FFF2**, non FFE5/FFE4!

**Ma sensore utente è WT901BLE67** (modello diverso).

**Fase 3: Packet Analysis**

Implementato logging dettagliato:
```swift
totalPacketCount += 1
let packetType = bytes[1]

switch packetType {
case 0x51: packetCount_51 += 1  // Acceleration only
case 0x52: packetCount_52 += 1  // Angular velocity only
case 0x53: packetCount_53 += 1  // Angle only
case 0x61: packetCount_61 += 1  // Combined
case 0x71: packetCount_71 += 1  // Register read response
}

// Log every 2 seconds
print("📊 Packet Stats: Total=\(count) (\(rate)Hz) | 0x51=\(c51) 0x52=\(c52) ...")
```

**Risultato**:
```
📊 Packet Stats (last 2s): Total=50 (24.9Hz) | 0x51=0 0x52=0 0x53=0 0x61=50 0x71=0
```

Solo pacchetti 0x61! Nessun pacchetto perso! Sample rate è realmente ~25Hz.

### 3.4.3 Root Cause: Sensore Hardware Locked

**Conclusione**: WT901BLE67 **non supporta configurazione dinamica via BLE**.

**Evidenza**:
1. Comandi corretti ma ignorati
2. App WitMotion ufficiale non permette cambio Hz
3. Sample rate stabile a 24.9Hz (probabilmente factory default)
4. Nessuna risposta a readRegister commands

**Verifica manuale WitMotion** conferma solo 80Hz visualizzato (ma è frequency di oscillazione fisica, non sample rate BLE).

### 3.4.4 Soluzione: Accettare Limitazione

**Before**: Auto-configurazione peggiorava le cose (24Hz → 16Hz durante tentativi)

**After**:
1. **Disabilitata auto-configurazione** (BLEManager.swift:378-383)
```swift
// ⚠️ AUTO-CONFIGURAZIONE DISABILITATA - sensore non supporta comandi via BLE
// La configurazione deve essere fatta via USB con WitMotion software
```

2. **Ottimizzato algoritmo per 25Hz**
   - DTW con window ridotta
   - Integration con drift compensation aggressivo
   - ZUPT più frequenti

3. **Email a WitMotion** per conferma

**Trade-off**: 25Hz è ~50% del ideale ma **sufficiente** per bench press/squat (movimenti lenti).

**Commit**: `93f5ae5` - "Disable auto-configuration and add comprehensive packet logging"

## 3.5 Sfida #4: VL Calculation After Deleting First Rep

### 3.5.1 Problema

**Context**: Utente può eliminare reps dalla review prima di salvare sessione.

**Sintomo**: Dopo aver eliminato la prima rep, velocity loss (VL) rimaneva calcolato dalla baseline vecchia.

**Esempio**:
```
Reps iniziali:
1. MPV = 0.70 m/s  VL = 0%     ← baseline
2. MPV = 0.65 m/s  VL = 7.1%
3. MPV = 0.62 m/s  VL = 11.4%

Utente elimina rep #1

Expected:
1. MPV = 0.65 m/s  VL = 0%     ← nuova baseline
2. MPV = 0.62 m/s  VL = 4.6%

Actual (BEFORE):
1. MPV = 0.65 m/s  VL = 7.1%   ❌ Still calculated from 0.70!
2. MPV = 0.62 m/s  VL = 11.4%  ❌
```

### 3.5.2 Root Cause

```swift
// BEFORE
mutating func removeReps(at offsets: IndexSet) {
    reps.remove(atOffsets: offsets)
    // ❌ Missing: recalculate VL with new first rep as baseline
}
```

VL calcolato una volta durante acquisizione, mai ricalcolato.

### 3.5.3 Soluzione

**Implementazione** (TrainingSummaryView.swift:521-541):

```swift
mutating func removeReps(at offsets: IndexSet) {
    // 1. Rimuovi le reps
    reps.remove(atOffsets: offsets)

    // 2. Ricalcola velocity loss from first per tutte le reps rimanenti
    //    usando la nuova prima rep come baseline
    guard let firstMPV = reps.first?.meanVelocity,
          firstMPV > 0 else { return }

    // 3. Aggiorna velocityLossFromFirst per ogni rep rimanente
    for index in reps.indices {
        let vlFromFirst = ((firstMPV - reps[index].meanVelocity) / firstMPV) * 100
        let oldRep = reps[index]

        reps[index] = RepData(
            id: oldRep.id,
            meanVelocity: oldRep.meanVelocity,
            peakVelocity: oldRep.peakVelocity,
            velocityLossFromFirst: max(0, vlFromFirst)  // No negative VL
        )
    }
}
```

**Validation**:
```
Before delete: [0.70(0%), 0.65(7%), 0.62(11%)]
Delete first
After delete:  [0.65(0%), 0.62(5%)] ✅
```

**Commit**: Parte di code review fixes

## 3.6 Sfida #5: Hashable Conformance per ClosedRange

### 3.6.1 Problema

**Context**: Exercise usa `ClosedRange<Double>` per velocity ranges e typical duration.

**Sintomo**: Compiler error:
```
Type 'Exercise' does not conform to protocol 'Hashable'
Type 'MovementProfile' does not conform to protocol 'Hashable'
```

**Root cause**: `ClosedRange<T>` è Hashable solo se `T: Hashable`, ma `Double` non è Hashable (floating point equality issues).

### 3.6.2 Soluzione

**Manual Hashable implementation** (Exercise.swift:130-145):

```swift
struct MovementProfile: Codable, Hashable {
    let minConcentricDuration: Double
    let minAmplitude: Double
    let eccentricThreshold: Double
    let typicalDuration: ClosedRange<Double>  // ❌ Not Hashable

    // ✅ Manual Hashable conformance
    func hash(into hasher: inout Hasher) {
        hasher.combine(minConcentricDuration)
        hasher.combine(minAmplitude)
        hasher.combine(eccentricThreshold)
        // Hash range bounds separately
        hasher.combine(typicalDuration.lowerBound)
        hasher.combine(typicalDuration.upperBound)
    }

    static func == (lhs: MovementProfile, rhs: MovementProfile) -> Bool {
        lhs.minConcentricDuration == rhs.minConcentricDuration &&
        lhs.minAmplitude == rhs.minAmplitude &&
        lhs.eccentricThreshold == rhs.eccentricThreshold &&
        lhs.typicalDuration.lowerBound == rhs.typicalDuration.lowerBound &&
        lhs.typicalDuration.upperBound == rhs.typicalDuration.upperBound
    }
}
```

**Lesson learned**: Swift protocols + generics possono essere complessi. Always check conformance requirements!

## 3.7 Sfida #6: ExerciseManager Reactivity

### 3.7.1 Problema

**Context**: SettingsView mostra lista esercizi da ExerciseManager.shared.

**Sintomo**: UI non aggiorna quando cambia esercizio selezionato.

**Root cause**:
```swift
// BEFORE
struct SettingsView: View {
    var body: some View {
        List {
            ForEach(ExerciseManager.shared.allExercises) { exercise in
                // ❌ ExerciseManager.shared non è @ObservedObject
                // SwiftUI non sa quando re-render
            }
        }
    }
}
```

### 3.7.2 Soluzione

**Add @ObservedObject** (SettingsView.swift:32):

```swift
struct SettingsView: View {
    @ObservedObject private var exerciseManager = ExerciseManager.shared

    var body: some View {
        List {
            ForEach(exerciseManager.allExercises) { exercise in
                // ✅ Now reactive!
            }
        }
    }
}
```

**Lesson learned**: Singleton + SwiftUI requires explicit observation.

## 3.8 Sfida #7: Learned Pattern Exercise Specificity

### 3.8.1 Problema

**Context**: Pattern matching applicava pattern di bench press a squat.

**Esempio absurd**:
```
User training: Squat
Pattern matched: "Bench 5x5 @ 80kg" (similarity 85%)
❌ Parametri bench applicati a squat!
```

### 3.8.2 Root Cause

```swift
// BEFORE
struct PatternSequence {
    let label: String
    let samples: [IMUSample]
    // ❌ No exercise ID → pattern could match any exercise
}
```

### 3.8.3 Soluzione

**Add exerciseId field** (LearnedPatternLibrary.swift:14, 78-88):

```swift
struct PatternSequence {
    let id: UUID
    let label: String
    let exerciseId: UUID  // ✅ Link to specific exercise
    let samples: [IMUSample]
}

func matchPatternWeighted(
    for samples: [IMUSample],
    exerciseId: UUID?
) -> PatternMatch? {

    var relevantPatterns = patterns

    if let exerciseId = exerciseId {
        let filtered = patterns.filter { $0.exerciseId == exerciseId }

        if filtered.isEmpty {
            print("⚠️ Nessun pattern per questo esercizio, usando tutti")
        } else {
            relevantPatterns = filtered
            print("🎯 Filtrati \(filtered.count) pattern per esercizio corrente")
        }
    }

    // DTW matching on relevantPatterns only
    ...
}
```

**Validation**:
```
Before: Bench pattern matched to Squat ❌
After:  Only Squat patterns considered for Squat ✅
```

## 3.9 Lessons Learned

### 3.9.1 Hardware Integration

1. **Don't assume sensor capabilities**: Verificare sempre documentazione + test reali
2. **Fallback strategies**: Quando hardware non supporta feature, adatta algoritmo
3. **Comprehensive logging**: Packet-level debugging essenziale per BLE/USB
4. **Test with real movement**: Mock data non mostra edge cases

### 3.9.2 Algorithm Design

1. **Adaptive > Fixed parameters**: Velocity-based training richiede range ampio
2. **State machines need escape hatches**: Touch-and-go è common, non edge case
3. **Validation is critical**: ROM checks prevengono false positives
4. **Performance matters**: DTW a 200Hz kill real-time, 25Hz è OK

### 3.9.3 SwiftUI & State Management

1. **@ObservedObject for Singletons**: Anche shared instances servono observation
2. **Recalculate derived values**: VL, averages, etc dopo mutations
3. **Protocol conformance**: Manual implementation needed for generics
4. **Thread safety**: Always dispatch UI updates to main queue

### 3.9.4 User Experience

1. **Exercise-specific everything**: Patterns, ROM, velocity ranges
2. **Visual feedback**: Log parametri adattivi all'utente
3. **Graceful degradation**: 25Hz < 200Hz ma usabile
4. **Data integrity**: Recalculation dopo delete mantiene coerenza

## 3.10 Metrics Before/After

| Metric | Before Fixes | After Fixes |
|--------|--------------|-------------|
| Touch-and-go detection | 40% | 100% ✅ |
| Fast movement detection (>0.75 m/s) | 0% | 100% ✅ |
| VL accuracy after delete | Incorrect | Correct ✅ |
| Pattern cross-contamination | Yes ❌ | No ✅ |
| WitMotion sample rate | 16Hz (broken) | 25Hz (stable) ✅ |
| Build errors | 4 | 0 ✅ |

## 3.11 Open Challenges

### 3.11.1 WitMotion Drift

**Status**: Partially mitigated
**Solution**: ZUPT + pattern matching
**Remaining issue**: Long sessions (>100 reps) accumulate error

### 3.11.2 Multi-sensor Fusion

**Status**: Not implemented
**Potential**: Combine Arduino distance + WitMotion IMU for ultimate accuracy
**Blocker**: Synchronization complexity

### 3.11.3 Real-time Velocity Stop

**Status**: Implemented but could improve
**Current**: Check VL after each rep
**Ideal**: Predict when next rep will exceed VL threshold

---

**Next**: [Capitolo 4 - Implementazione e Dettagli](./04-implementazione.md)
