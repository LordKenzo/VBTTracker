//
//  RepDetectionSettingsView.swift
//  VBTTracker
//
//  Created by Lorenzo Franceschini on 19/10/25.
//


//
//  RepDetectionSettingsView.swift
//  VBTTracker
//
//  Impostazioni Avanzate - Algoritmo Rilevamento Rep
//

import SwiftUI

struct RepDetectionSettingsView: View {
    @ObservedObject var settings = SettingsManager.shared
    @State private var showResetAlert = false
    
    var body: some View {
        List {
            // MARK: - Warning Section
            Section {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.title2)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Impostazioni Avanzate")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        
                        Text("Modifica questi parametri solo se hai esperienza con VBT. I valori predefiniti sono ottimizzati per la maggior parte degli atleti.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 4)
            }

            // MARK: - Detection Profile
            Section {
                Picker("Profilo", selection: $settings.detectionProfile) {
                    ForEach(DetectionProfile.allCases, id: \.self) { profile in
                        HStack {
                            Image(systemName: profile.icon)
                            Text(profile.displayName)
                        }
                        .tag(profile)
                    }
                }
                .pickerStyle(.navigationLink)

                // Descrizione profilo selezionato
                HStack(spacing: 8) {
                    Image(systemName: settings.detectionProfile.icon)
                        .foregroundStyle(settings.detectionProfile.color)
                        .font(.title3)
                    Text(settings.detectionProfile.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)

                // Toggle correzioni avanzate
                if settings.detectionProfile != .generic {
                    Toggle(isOn: $settings.enableVelocityCorrection) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Correzione Velocità")
                                .font(.body)
                            Text("Applica fattore ×\(String(format: "%.1f", settings.detectionProfile.velocityCorrectionFactor)) a MPV/PPV")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Toggle(isOn: $settings.forceDisplacementGate) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Forza Displacement Gate")
                                .font(.body)
                            Text("Abilita validazione ROM anche sotto 60Hz")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Warning per SR bassi
                    if settings.forceDisplacementGate {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .font(.caption)
                            Text("Con sample rate <40Hz la validazione ROM può bloccare ripetizioni valide (doppia integrazione inaccurata).")
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(8)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(6)
                    }
                }
            } header: {
                Text("Profilo Rilevamento")
            } footer: {
                if settings.detectionProfile == .generic {
                    Text("Il profilo Generico usa le impostazioni attuali senza modifiche automatiche. Seleziona un profilo specifico per ottimizzazioni automatiche.")
                } else {
                    Text("Profilo ottimizzato per \(settings.detectionProfile.velocityRange.lowerBound.formatted())-\(settings.detectionProfile.velocityRange.upperBound.formatted()) m/s. Le correzioni compensano limitazioni di sample rate bassi.")
                }
            }

            // MARK: - Timing Parameters
            Section {
                SliderSettingRow(
                    title: "Tempo tra Rep",
                    value: $settings.repMinTimeBetween,
                    range: 0.5...2.0,
                    step: 0.1,
                    unit: "s",
                    description: timeBetweenDescription
                )
                
                SliderSettingRow(
                    title: "Durata Minima",
                    value: $settings.repMinDuration,
                    range: 0.2...1.0,
                    step: 0.1,
                    unit: "s",
                    description: durationDescription
                )
            } header: {
                Text("Parametri Temporali")
            } footer: {
                Text("Tempo tra Rep: intervallo minimo tra due ripetizioni consecutive. Durata Minima: tempo minimo della fase concentrica.")
            }
            
            // MARK: - Amplitude Parameters
            Section {
                SliderSettingRow(
                    title: "Ampiezza Minima",
                    value: $settings.repMinAmplitude,
                    range: 0.3...1.0,
                    step: 0.05,
                    unit: "g",
                    description: amplitudeDescription
                )
                
                SliderSettingRow(
                    title: "Soglia Eccentrica",
                    value: $settings.repEccentricThreshold,
                    range: 0.05...0.30,
                    step: 0.05,
                    unit: "g",
                    description: eccentricThresholdDescription
                )
            } header: {
                Text("Parametri Ampiezza")
            } footer: {
                Text("Ampiezza Minima: differenza minima accelerazione picco-valle per rilevare una rep. Soglia Eccentrica: accelerazione minima per rilevare inizio discesa.")
            }
            
            // MARK: - Signal Processing

            Section {
                // 1️⃣ Stepper smoothing window
                Stepper(
                    value: $settings.repSmoothingWindow,
                    in: 5...20,
                    step: 1
                ) {
                    HStack {
                        Text("Finestra Smoothing")
                        Spacer()
                        Text("\(settings.repSmoothingWindow)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }

                Text(smoothingDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 4)

                Divider().padding(.vertical, 4)

                // 2️⃣ 🔹 Nuovo Slider Look-ahead
                SliderSettingRow(
                    title: "Look-ahead",
                    value: $settings.repLookAheadMs,
                    range: 50...400,
                    step: 10,
                    unit: "ms",
                    description: lookAheadDescription
                )

            } header: {
                Text("Elaborazione Segnale")
            } footer: {
                Text("Numero di campioni per la media mobile e finestra di look-ahead (ritardo in ms per confermare la rep).")
            }

            // MARK: - ROM Personalizzato
            Section {
                Toggle(isOn: $settings.useCustomROM) {
                    HStack(spacing: 8) {
                        Image(systemName: "ruler")
                            .foregroundStyle(settings.useCustomROM ? .blue : .secondary)
                        Text("ROM Personalizzato")
                    }
                }

                if settings.useCustomROM {
                    SliderSettingRow(
                        title: "ROM (petto-braccio)",
                        value: $settings.customROM,
                        range: 0.30...0.80,
                        step: 0.05,
                        unit: "m",
                        description: romDescription
                    )

                    SliderSettingRow(
                        title: "Tolleranza",
                        value: $settings.customROMTolerance,
                        range: 0.10...0.50,
                        step: 0.05,
                        unit: "",
                        description: toleranceDescription
                    )

                    // Range calcolato in tempo reale
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "ruler.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                            Text("Range Accettato:")
                                .font(.caption)
                                .fontWeight(.medium)
                        }

                        HStack {
                            Text(String(format: "%.2f m", settings.customROM * (1.0 - settings.customROMTolerance)))
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.green)

                            Image(systemName: "arrow.left.and.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text(String(format: "%.2f m", settings.customROM * (1.0 + settings.customROMTolerance)))
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.green)
                        }
                        .padding(.leading, 28)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(8)
                }
            } header: {
                Text("Validazione ROM")
            } footer: {
                if settings.useCustomROM {
                    Text("Distanza petto-braccio durante bench press. Le ripetizioni verranno conteggiate solo se il displacement rientra nel range ±tolleranza. Attivo solo con frequenza campionamento ≥60Hz.")
                } else {
                    Text("Abilita per usare un ROM personalizzato invece del range standard (0.20-0.80m). Utile per adattare la rilevazione alla tua anatomia.")
                }
            }

            // MARK: - Velocity Thresholds (Legacy - kept for compatibility)
            Section {
                SliderSettingRow(
                    title: "Velocità Minima",
                    value: $settings.repMinVelocity,
                    range: 0.05...0.30,
                    step: 0.05,
                    unit: " m/s",
                    description: "Velocità media minima per validare una rep"
                )
                
                SliderSettingRow(
                    title: "Velocità Picco Minima",
                    value: $settings.repMinPeakVelocity,
                    range: 0.10...0.50,
                    step: 0.05,
                    unit: " m/s",
                    description: "Velocità massima minima durante la fase concentrica"
                )
                
                SliderSettingRow(
                    title: "Accelerazione Minima",
                    value: $settings.repMinAcceleration,
                    range: 1.0...5.0,
                    step: 0.5,
                    unit: " m/s²",
                    description: "Accelerazione minima per rilevare movimento esplosivo"
                )
            } header: {
                Text("Soglie Velocità (Legacy)")
            } footer: {
                Text("Parametri utilizzati in modalità avanzata per validazione aggiuntiva delle rep rilevate.")
            }
            
            // MARK: - Algorithm Info
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: "brain.head.profile")
                            .foregroundStyle(.blue)
                        Text("Algoritmo Pattern-Based")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        algorithmFeatureRow(icon: "waveform.path.ecg", text: "Riconoscimento pattern Valle → Picco → Valle")
                        algorithmFeatureRow(icon: "chart.line.uptrend.xyaxis", text: "Adaptive learning dalle prime 3 rep (warmup)")
                        algorithmFeatureRow(icon: "timer", text: "Context-aware: distingue pause da movimento")
                        algorithmFeatureRow(icon: "checkmark.shield.fill", text: "Filtri anti-rimbalzo e anti-rumore")
                    }
                    .padding(.leading, 36)
                }
                .padding(.vertical, 4)
            } header: {
                Text("Info Algoritmo")
            }
            
            // MARK: - Reset Section
            Section {
                Button(action: { showResetAlert = true }) {
                    HStack {
                        Spacer()
                        Label("Ripristina Valori Predefiniti", systemImage: "arrow.counterclockwise")
                            .foregroundStyle(.red)
                        Spacer()
                    }
                }
            } footer: {
                Text("Ripristina tutti i parametri di rilevamento ai valori raccomandati dalla letteratura scientifica.")
            }
        }
        .navigationTitle("Rilevamento Rep")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Ripristina Parametri", isPresented: $showResetAlert) {
            Button("Annulla", role: .cancel) { }
            Button("Ripristina", role: .destructive) {
                resetToDefaults()
            }
        } message: {
            Text("Tutti i parametri di rilevamento verranno ripristinati ai valori predefiniti. Le altre impostazioni non verranno modificate.")
        }
    }
    
    // MARK: - Helper Views
    
    private func algorithmFeatureRow(icon: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    
    // MARK: - Computed Properties
    
    private var timeBetweenDescription: String {
        if settings.repMinTimeBetween < 0.6 {
            return "⚡ Ottimo per movimenti veloci/esplosivi"
        } else if settings.repMinTimeBetween < 1.0 {
            return "✅ Bilanciato (consigliato)"
        } else {
            return "🐢 Per movimenti lenti (forza massima)"
        }
    }
    
    private var durationDescription: String {
        if settings.repMinDuration < 0.3 {
            return "⚡ Per movimenti molto veloci"
        } else if settings.repMinDuration < 0.6 {
            return "✅ Standard (consigliato)"
        } else {
            return "🐢 Per movimenti controllati"
        }
    }
    
    private var amplitudeDescription: String {
        if settings.repMinAmplitude < 0.40 {
            return "⚠️ Sensibile: rischio falsi positivi su ROM corti"
        } else if settings.repMinAmplitude <= 0.50 {
            return "✅ Bilanciato (consigliato)"
        } else {
            return "🎯 Conservativo: solo ROM completi"
        }
    }
    
    private var eccentricThresholdDescription: String {
        if settings.repEccentricThreshold < 0.10 {
            return "⚡ Rileva anche ROM molto corti (rischio falsi positivi)"
        } else if settings.repEccentricThreshold <= 0.20 {
            return "✅ Bilanciato (ROM standard)"
        } else {
            return "🎯 Solo ROM completi (fino al petto)"
        }
    }
    
    private var smoothingDescription: String {
        if settings.repSmoothingWindow < 8 {
            return "⚡ Più reattivo, meno filtrato"
        } else if settings.repSmoothingWindow <= 12 {
            return "✅ Bilanciato (consigliato)"
        } else {
            return "🎯 Più filtrato, meno rumore"
        }
    }
    
    private var lookAheadDescription: String {
        switch settings.repLookAheadMs {
        case ..<100: return "⚡ Molto reattivo"
        case ..<200: return "✅ Bilanciato (consigliato)"
        default:     return "🎯 Stabile, ma più lento a reagire"
        }
    }

    private var romDescription: String {
        if settings.customROM < 0.40 {
            return "📏 ROM corto - adatto per braccia corte"
        } else if settings.customROM <= 0.55 {
            return "✅ ROM medio (bench press standard)"
        } else {
            return "📏 ROM lungo - adatto per braccia lunghe"
        }
    }

    private var toleranceDescription: String {
        let percentage = Int(settings.customROMTolerance * 100)
        if settings.customROMTolerance < 0.20 {
            return "🎯 Stretta (±\(percentage)%) - solo ROM molto precisi"
        } else if settings.customROMTolerance <= 0.35 {
            return "✅ Bilanciata (±\(percentage)%) - consigliata"
        } else {
            return "⚠️ Ampia (±\(percentage)%) - accetta variazioni maggiori"
        }
    }

    // MARK: - Actions
    
    private func resetToDefaults() {
        settings.repMinTimeBetween = 0.8
        settings.repMinDuration = 0.3
        settings.repMinAmplitude = 0.45
        settings.repSmoothingWindow = 10
        settings.repEccentricThreshold = 0.15
        settings.repMinVelocity = 0.10
        settings.repMinPeakVelocity = 0.15
        settings.repMinAcceleration = 2.5
        settings.repLookAheadMs = 200
        settings.customROM = 0.50
        settings.customROMTolerance = 0.30
        settings.useCustomROM = false

        print("🔄 Parametri rilevamento ripristinati ai valori predefiniti")
    }
}

#Preview {
    NavigationStack {
        RepDetectionSettingsView()
    }
}
