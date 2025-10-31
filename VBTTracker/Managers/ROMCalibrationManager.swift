//
//  ROMCalibrationManager.swift
//  VBTTracker
//
//  Versione semplificata: SOLO calibrazione automatica
//

import Foundation
import Combine

final class ROMCalibrationManager: ObservableObject {

    // MARK: - Stato pubblico (usato dalle View)

    @Published var automaticState: AutomaticCalibrationState = .idle
    @Published var statusMessage: String = "Pronto per calibrazione"
    @Published var calibrationProgress: Double = 0.0          // [0, 1]
    @Published var isCalibrated: Bool = false
    @Published var learnedPattern: LearnedPattern?

    // MARK: - Tipi interni

    /// Finestra minima che racchiude una ripetizione rilevata
    private struct RepWindow {
        let start: Date
        let end: Date
        let min: Double
        let max: Double
    }

    // MARK: - Buffer e parametri

    /// Campioni Z (in g) usati durante la calibrazione automatica
    private var samples: [AccelerationSample] = []

    /// Parametri minimi per validare la rep (coerenti con Settings)
    private var minAmplitudeG: Double { SettingsManager.shared.repMinAmplitude }
    private var smoothingWin: Int { max(3, SettingsManager.shared.repSmoothingWindow) }
    private let minConcentricDuration: TimeInterval = 0.30
    
    // Frequenza di campionamento del flusso durante la calibrazione (Hz)
    var sampleRateHz: Double = 200   // puoi aggiornarla da fuori (es. dal BLEManager)

    // Durata del look-ahead in secondi (quanto "oltre" il picco guardiamo)
    var lookAheadSeconds: Double = 0.1  // 0.1s di default

    private var lookAheadSamples: Int {
        // converti ms in secondi
        let seconds = SettingsManager.shared.repLookAheadMs / 1000.0
        let n = Int(round(seconds * sampleRateHz))
        return min(max(n, 10), 80)
    }

    // MARK: - API compatibili (la manuale Ã¨ stata rimossa)

    /// Manteniamo la firma per compatibilitÃ  con le view; ora non fa nulla
    func selectMode(_ mode: CalibrationMode) { /* solo .automatic, no-op */ }

    func startAutomaticCalibration() {
        resetEphemeral()
        isCalibrated = false
        learnedPattern = nil
        automaticState = .waitingForFirstRep
        statusMessage = "Esegui 2 ripetizioni ROM completo"
        calibrationProgress = 0.0
    }

    func cancelCalibration() {
        resetEphemeral()
        automaticState = .idle
        statusMessage = "Calibrazione annullata"
        calibrationProgress = 0.0
    }

    func reset() {
        cancelCalibration()
        learnedPattern = nil
        isCalibrated = false
        statusMessage = "Pattern cancellato"
    }

    func deletePattern() {
        reset()
        UserDefaults.standard.removeObject(forKey: "learnedPattern")
    }

    func savePattern() {
        guard let pattern = learnedPattern,
              let data = try? JSONEncoder().encode(pattern) else { return }
        UserDefaults.standard.set(data, forKey: "learnedPattern")
    }

    /// Opzionale: consenti di saltare la calibrazione usando un pattern di default
    func skipCalibration() {
        learnedPattern = .defaultPattern
        isCalibrated = true
        automaticState = .completed
        statusMessage = "Usato pattern di default"
        calibrationProgress = 1.0
    }

    /// Facoltativo: chiamalo quando vuoi segnare la fine del flusso â€œwaitingForLoadâ€
    func finishCalibration() {
        guard isCalibrated else { return }
        automaticState = .completed
        statusMessage = "Calibrazione completata!"
    }

    // MARK: - Ingresso dati (chiamato dal flusso BLE)

    /// Passa i campioni Z (asse verticale) dal sensore durante la calibrazione
    func ingestSample(accZ: Double, timestamp: Date) {
        switch automaticState {
        case .waitingForFirstRep, .detectingReps:
            samples.append(AccelerationSample(timestamp: timestamp, accZ: accZ))
            // Mantieni ~4 secondi a 200 Hz (800 campioni)
            if samples.count > 800 { samples.removeFirst(samples.count - 800) }

            automaticState = .detectingReps
            statusMessage = "Riconoscimento ripetizioniâ€¦"
            detectRepsIfPossible()

        default:
            break
        }
    }

    // MARK: - Logica di detection (compatta)

    private func detectRepsIfPossible() {
        guard samples.count >= smoothingWin + 2 else { return }

        let z = samples.map { $0.accZ }
        let smoothed = movingAverage(values: z, win: smoothingWin)

        var repWindows: [RepWindow] = []
        var lastValley: (idx: Int, val: Double)?
        // var lastPeak: (idx: Int, val: Double)?

        var i = 1
        while i < smoothed.count - 1 {
            let prev = smoothed[i - 1], cur = smoothed[i], next = smoothed[i + 1]

            // Valle
            if cur < prev && cur < next {
                lastValley = (i, cur)
            }

            // Picco
            if cur > prev && cur > next {
                if let v = lastValley {
                    let peak = (i, cur)
                    let endIdx = min(i + lookAheadSamples, smoothed.count - 1)


                    let amp = (peak.1 - v.val) // picco - valle
                    if amp >= minAmplitudeG {
                        let startT = samples[v.idx].timestamp
                        let endT   = samples[endIdx].timestamp
                        let dur    = endT.timeIntervalSince(startT)

                        if dur >= minConcentricDuration {
                            repWindows.append(.init(
                                start: startT, end: endT,
                                min: v.val, max: peak.1
                            ))
                        }
                    }
                }
            }
            i += 1
        }

        // Prendi al massimo le prime 2 rep valide in ordine temporale
        let firstTwo = Array(repWindows.sorted { $0.start < $1.start }.prefix(2))

        // Aggiorna progresso
        calibrationProgress = min(Double(firstTwo.count) / 2.0, 1.0)

        if firstTwo.count == 2 {
            automaticState = .analyzing
            statusMessage = "Analisi patternâ€¦"
            computeLearnedPattern(from: firstTwo)
        } else if firstTwo.count == 1 {
            statusMessage = "1/2 ripetizioni rilevataâ€¦"
        } else {
            automaticState = .waitingForFirstRep
            statusMessage = "Esegui 2 ripetizioni ROM completo"
        }
    }

    private func computeLearnedPattern(from reps: [RepWindow]) {
        guard reps.count == 2 else { return }

        let amps = reps.map { $0.max - $0.min }
        let durs = reps.map { $0.end.timeIntervalSince($0.start) }

        let avgAmp = max(0.0, amps.reduce(0, +) / Double(amps.count))
        let avgConcentric = max(minConcentricDuration, durs.reduce(0, +) / Double(durs.count))

        // Stime robuste e conservative per i campi richiesti
        let estROM = max(0.15, avgAmp * 0.5)             // m, dipende dal setup
        let estPeakV = max(0.1, estROM / max(0.3, avgConcentric))

        let pattern = LearnedPattern(
            rom: estROM,                         // ROM stimata (m)
            minThreshold: avgAmp * 0.5,          // soglia dinamica basata su ampiezza
            avgVelocity: estPeakV,               // velocitÃ  media (m/s)
            avgConcentricDuration: avgConcentric,
            restThreshold: avgAmp * 0.1          // soglia "fermo"
        )


        learnedPattern = pattern
        isCalibrated = true
        calibrationProgress = 1.0
        automaticState = .waitingForLoad
        statusMessage = "Carica il bilanciere: pronto!"
    }

    // MARK: - Helpers

    private func resetEphemeral() {
        samples.removeAll()
    }

    private func movingAverage(values: [Double], win: Int) -> [Double] {
        guard win > 1, values.count >= win else { return values }
        var res: [Double] = []
        var sum = 0.0
        for i in 0..<values.count {
            sum += values[i]
            if i >= win { sum -= values[i - win] }
            if i >= win - 1 { res.append(sum / Double(win)) }
        }
        // riallinea con padding iniziale per mantenere la stessa lunghezza
        let padCount = max(0, values.count - res.count)
        if padCount > 0 {
            return Array(repeating: res.first ?? 0.0, count: padCount) + res
        }
        return res
    }
}
