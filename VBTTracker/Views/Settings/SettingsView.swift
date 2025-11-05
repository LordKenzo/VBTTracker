//
//  SettingsView.swift
//  VBTTracker
//
//  Hub principale impostazioni - Architettura modulare
//  ✅ AGGIORNATO con @ObservedObject per patternLibrary
//

import SwiftUI

// MARK: - Detection Algorithm Enum
enum RepDetectionAlgorithm: String, CaseIterable, Identifiable {
    case zAxisSimple = "Asse Z (Semplice)"
    
    var id: String { self.rawValue }
    
    var description: String {
        switch self {
        case .zAxisSimple:
            return "Pattern picco-valle-picco su asse verticale"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var bleManager: BLEManager
    @ObservedObject var calibrationManager: CalibrationManager
    @ObservedObject var settings = SettingsManager.shared
    
    // ✅ CORREZIONE: @ObservedObject per aggiornamento real-time
    @ObservedObject private var patternLibrary = LearnedPatternLibrary.shared
    
    @Environment(\.dismiss) var dismiss
    @State private var showResetAlert = false
    
    @AppStorage("selectedDetectionAlgorithm") private var selectedAlgorithmRaw = RepDetectionAlgorithm.zAxisSimple.rawValue
    
    private var selectedAlgorithm: RepDetectionAlgorithm {
        get {
            RepDetectionAlgorithm(rawValue: selectedAlgorithmRaw) ?? .zAxisSimple
        }
        nonmutating set {
            selectedAlgorithmRaw = newValue.rawValue
        }
    }

    var body: some View {
        NavigationStack {
            List {
                // MARK: - Detection Algorithm Section
                Section {
                    Picker("Algoritmo", selection: Binding(
                        get: { selectedAlgorithm },
                        set: { newValue in
                            selectedAlgorithm = newValue
                            NotificationCenter.default.post(
                                name: .detectionAlgorithmChanged,
                                object: newValue.rawValue
                            )
                        }
                    )) {
                        ForEach(RepDetectionAlgorithm.allCases) { algorithm in
                            Text(algorithm.rawValue).tag(algorithm)
                        }
                    }
                    .pickerStyle(.menu)
                    
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        
                        Text(selectedAlgorithm.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    
                } header: {
                    Text("Algoritmo Detection")
                } footer: {
                    Text("L'algoritmo Asse Z utilizza un pattern semplice basato su picchi e valli dell'accelerazione verticale. Ottimizzato per movimenti balistici come panca, squat e stacchi.")
                }
                
                // MARK: - Categories Section
                Section {
                    NavigationLink(destination: SensorSettingsView(
                        bleManager: bleManager,
                        calibrationManager: calibrationManager
                    )) {
                        NavigationSettingRow(
                            title: "Sensore",
                            subtitle: sensorSubtitle,
                            icon: "sensor.fill",
                            iconColor: bleManager.isConnected ? .green : .gray
                        )
                    }
                    
                    NavigationLink(destination: LearnedPatternsView()) {
                        NavigationSettingRow(
                            title: "Pattern Appresi",
                            subtitle: patternSubtitle,
                            icon: "brain.head.profile",
                            iconColor: .purple
                        )
                    }
                    
                    NavigationLink(destination: RecordPatternView(bleManager: bleManager)) {
                        NavigationSettingRow(
                            title: "Registra Pattern",
                            subtitle: "Registra manualmente un nuovo pattern",
                            icon: "waveform.badge.plus",
                            iconColor: .red,
                            badge: "Nuovo"
                        )
                    }
                    
                    NavigationLink(destination: VelocitySettingsView()) {
                        NavigationSettingRow(
                            title: "Velocità",
                            subtitle: "Zone VBT e Velocity Loss",
                            icon: "speedometer",
                            iconColor: .blue
                        )
                    }
                    
                    NavigationLink(destination: RepDetectionSettingsView()) {
                        NavigationSettingRow(
                            title: "Rilevamento Rep",
                            subtitle: "Parametri algoritmo",
                            icon: "waveform.path.ecg",
                            iconColor: .purple,
                            badge: "Avanzato"
                        )
                    }
                    
                    NavigationLink(destination: AudioSettingsView()) {
                        NavigationSettingRow(
                            title: "Audio",
                            subtitle: audioSubtitle,
                            icon: "speaker.wave.2.fill",
                            iconColor: settings.voiceFeedbackEnabled ? .orange : .gray
                        )
                    }
                } header: {
                    Text("Categorie")
                }
                
                // MARK: - About Section
                Section {
                    InfoSettingRow(
                        title: "Versione",
                        value: "1.1.0",
                        icon: "info.circle"
                    )
                    
                    InfoSettingRow(
                        title: "Build",
                        value: "2024.11.02",
                        icon: "hammer"
                    )
                    
                    HStack {
                        Image(systemName: "heart.fill")
                            .foregroundStyle(.red)
                            .frame(width: 24)
                        
                        Text("Sviluppato per Scienze Motorie")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    
                } header: {
                    Text("Informazioni")
                }
                
                // MARK: - Reset Section
                Section {
                    Button(action: { showResetAlert = true }) {
                        HStack {
                            Spacer()
                            Label("Reset Completo Impostazioni", systemImage: "arrow.counterclockwise.circle.fill")
                                .foregroundStyle(.red)
                            Spacer()
                        }
                    }
                } footer: {
                    Text("Ripristina tutte le impostazioni ai valori predefiniti. Le sessioni di allenamento salvate non verranno eliminate.")
                }
            }
            .navigationTitle("Impostazioni")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Fine") {
                        dismiss()
                    }
                }
            }
            .alert("Reset Impostazioni", isPresented: $showResetAlert) {
                Button("Annulla", role: .cancel) { }
                Button("Reset", role: .destructive) {
                    settings.resetToDefaults()
                }
            } message: {
                Text("Tutte le impostazioni verranno ripristinate ai valori predefiniti. Le sessioni salvate non verranno eliminate.")
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var sensorSubtitle: String {
        if bleManager.isConnected {
            return "\(bleManager.sensorName) Connesso"
        } else {
            return "Nessun sensore connesso"
        }
    }
    
    private var audioSubtitle: String {
        if settings.voiceFeedbackEnabled {
            let language = settings.voiceLanguage == "it-IT" ? "Italiano" : "English"
            return "Attivo \(language)"
        } else {
            return "Disattivato"
        }
    }
    
    // ✅ CORREZIONE: Ora si aggiorna in tempo reale
    private var patternSubtitle: String {
        let count = patternLibrary.patterns.count
        if count == 0 {
            return "Nessun pattern salvato"
        } else if count == 1 {
            return "1 pattern salvato"
        } else {
            return "\(count) pattern salvati"
        }
    }
}

// MARK: - NotificationCenter Extension
extension Notification.Name {
    static let detectionAlgorithmChanged = Notification.Name("detectionAlgorithmChanged")
}

// MARK: - Previews
#Preview("Connected") {
    let bleManager = BLEManager()
    bleManager.isConnected = true
    bleManager.sensorName = "WT901BLE67"
    
    return SettingsView(
        bleManager: bleManager,
        calibrationManager: CalibrationManager()
    )
}

#Preview("Disconnected") {
    SettingsView(
        bleManager: BLEManager(),
        calibrationManager: CalibrationManager()
    )
}
