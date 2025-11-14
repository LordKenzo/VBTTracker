# VBT Tracker - Documentazione Tecnica Tesi

## Indice

### 1. [Architettura del Sistema](./01-architettura.md)
- Pattern architetturali (MVVM, Manager, Protocol-Oriented)
- Struttura modulare del codice
- Gestione dello stato con SwiftUI
- Integrazione hardware (BLE, USB)
- Persistenza dati

### 2. [Algoritmi di Rilevamento Ripetizioni](./02-algoritmi-rep-detection.md)
- **Distance-Based Detection** (Arduino + VL53L0X)
  - State Machine con look-ahead
  - Parametri adattivi per movimenti veloci
  - Calibrazione ROM
- **DTW-Based Detection** (WitMotion IMU)
  - Dynamic Time Warping
  - Pattern matching
  - Learned patterns library
- Signal Processing
  - Smoothing e filtering
  - Velocity calculation
  - Peak detection

### 3. [Sfide Tecniche e Soluzioni](./03-sfide-tecniche.md)
- Touch-and-go rep detection
- Movimenti veloci vs lenti
- Dual-sensor support
- BLE configuration issues
- Real-time performance
- Exercise-specific calibration

### 4. [Implementazione e Dettagli](./04-implementazione.md)
- Thread safety e concorrenza
- Performance optimization
- Error handling
- Testing strategy

### 5. [Metriche e Risultati](./05-metriche.md)
- Accuratezza rilevamento reps
- Latency e performance
- Confronto con sistemi esistenti
- User study results
- Cost-benefit analysis

### 6. [Conclusioni e Lavoro Futuro](./06-conclusioni.md)
- Sintesi risultati
- Contributi scientifici
- Limitazioni
- Roadmap sviluppo futuro
- Riflessioni personali

---

## Abstract

VBT Tracker è un'applicazione iOS per il Velocity-Based Training che utilizza sensori hardware (Arduino con laser VL53L0X e WitMotion IMU) per rilevare automaticamente ripetizioni e calcolare metriche di performance in tempo reale.

Il sistema implementa algoritmi avanzati di rilevamento basati su:
- **Distance-Based Detection** per sensori laser con state machine adattiva
- **DTW (Dynamic Time Warping)** per sensori inerziali con pattern recognition

L'architettura modulare basata su MVVM e Protocol-Oriented Programming garantisce estensibilità e manutenibilità del codice.

## Tecnologie Utilizzate

- **Swift 5.9** / **SwiftUI**
- **CoreBluetooth** (BLE communication)
- **ORSSerial** (USB communication)
- **CoreML** (pattern matching)
- **Combine** (reactive programming)

## Repository Structure

```
VBTTracker/
├── Models/              # Data models (Exercise, Rep, Session)
├── Managers/            # Business logic (SessionManager, BLEManager, etc.)
├── Views/               # SwiftUI views
├── RepDetection/        # Rep detection algorithms
├── Utils/               # Utilities and extensions
└── tesi/                # Thesis documentation (this folder)
    ├── 01-architettura.md
    ├── 02-algoritmi-rep-detection.md
    ├── 03-sfide-tecniche.md
    ├── 04-implementazione.md
    └── 05-metriche.md
```

## Come Usare Questa Documentazione

Questa documentazione è strutturata per essere:
1. **Letta sequenzialmente** per una comprensione completa del sistema
2. **Consultata come riferimento** per sezioni specifiche
3. **Esportata** in LaTeX/Word per la stesura finale della tesi

Ogni file Markdown contiene:
- Diagrammi (in Mermaid format)
- Code snippets con spiegazioni
- Before/After examples
- Riferimenti a file sorgente specifici

---

**Autore**: Lorenzo
**Anno Accademico**: 2024/2025
**Corso**: [Nome Corso]
**Università**: [Nome Università]
