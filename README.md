# Velocity Based Training: VBTTracker

## 🎯 Obiettivo
Il progetto si pone l'obiettivo di creare un'applicazione mobile per iOS utilizzando come linguaggio Swift ed il framework dichiarativo SwiftUI per la creazione delle interfacce utente (UI) che permetta di analizzare il proprio allenamento tramite il paradigma della VBT: Velocity Based Training. In pratica l'allenamento della Forza non si basa sul classico 1RM bensì sulla velocità di spostamento del carico. In questo modo il focus non si sposta sul volume utilizzato ma sulla velocità. In questo modo è possibile capire lo stato attuale dell'atleta e innalzare (o abbassare) il carico in base alla stato di forma del soggetto.



## 💂‍♂️ Separazione di responsabilità
SwiftUI integra il pattern architetturale MVVM, che sta a significare Model-View ViewModel, in cui:
1. Model: rappresentano le strutture dati, i modelli
2. Views: sono le interfacce costrutite con il framework SwiftUI
3. ViewModels: sono le classi che implementano @ObservedObject e @StateObject necessarie per il collegamento tra logica di business e UI
La struttura del progetto prevede una chiara separazione delle responsabilità, per un'architettura pulita by-design. L'organizzazione delle folder sarà:

```
La struttura a cartelle che state usando è organizzata così:
VBTTracker/
├── Models/           # Dati e strutture
├── Views/            # Interfacce SwiftUI
├── Managers/         # Logica di business e coordinamento
├── Services/         # Servizi esterni (sensori, persistenza)
└── Utilities/        # Helper e estensioni
```

## ✨ Funzionalità primarie
- ✅ Scansione dispositivi Bluetooth LE
- ✅ Supporto alla connessione e scambio dati del sensore WitMotion WT9011DCL reperibile in commercio
- ✅ Parsing pacchetti IMU (formato 0x55 0x61 come da specifiche del produttore WitMotion)
- ✅ Visualizzazione real-time: accelerazione, velocità angolare, angoli
- ✅ Architettura modulare con protocollo `SensorDataProvider`
- ✅ Possibilità di impostare i range delle velocità rispetto ai default basati su studi scientifici
- ✅ Impostazione dell'1RM e degli obiettivi di allenamento della specifica Forza
- ✅ Feedback in tempo reale
- ✅ Salvataggio della sessione di lavoro

## 📊 Specifiche Tecniche
- **Service UUID**: `0000FFE5-0000-1000-8000-00805F9A34FB`
- **Characteristic UUID**: `0000FFE4-0000-1000-8000-00805F9A34FB`
- **Formato pacchetto**: 
  - Header: `0x55 0x61`
  - Accelerazione: byte 2-7 (±16g)
  - Giroscopio: byte 8-13 (±2000°/s)
  - Angoli: byte 14-19 (±180°)

## ⚠️ Note
- Richiede dispositivo fisico iOS (WitMotion)
- Impostare i permessi bluetooth attrerso la creazione di 2 chiavi in Targets -> VBTTracker -> Info

```
Privacy - Bluetooth Always Usage Description
VBT Tracker richiede Bluetooth per connettersi al sensore WitMotion

Privacy - Bluetooth Peripheral Usage Description
Connessione al sensore inerziale per misurare velocità e accelerazione
```
