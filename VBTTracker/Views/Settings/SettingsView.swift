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
    @ObservedObject var sensorManager: UnifiedSensorManager
    @ObservedObject var calibrationManager: CalibrationManager
    @ObservedObject var settings = SettingsManager.shared

    // ✅ CORREZIONE: @ObservedObject per aggiornamento real-time
    @ObservedObject private var patternLibrary = LearnedPatternLibrary.shared
    @ObservedObject private var exerciseManager = ExerciseManager.shared
    @ObservedObject private var profileManager = ProfileManager.shared

    @Environment(\.dismiss) var dismiss
    @State private var showResetAlert = false
    @State private var showProfileEdit = false
    
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

                // MARK: - User Profile Section
                Section {
                    Button(action: {
                        showProfileEdit = true
                    }) {
                        HStack(spacing: 12) {
                            // Profile Photo or Placeholder
                            if let photo = profileManager.profilePhoto {
                                Image(uiImage: photo)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 50, height: 50)
                                    .clipShape(Circle())
                            } else {
                                Image(systemName: "person.circle.fill")
                                    .resizable()
                                    .frame(width: 50, height: 50)
                                    .foregroundColor(.gray)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text(profileManager.profile.name.isEmpty ? "Configura Profilo" : profileManager.profile.name)
                                    .font(.headline)
                                    .foregroundColor(.primary)

                                if profileManager.profile.isComplete {
                                    HStack(spacing: 4) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.caption)
                                            .foregroundColor(.green)
                                        Text("Profilo Completo")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                } else {
                                    HStack(spacing: 4) {
                                        Image(systemName: "exclamationmark.circle.fill")
                                            .font(.caption)
                                            .foregroundColor(.orange)
                                        Text("Completa il profilo (\(Int(profileManager.profile.completionPercentage * 100))%)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                } header: {
                    Text("Profilo Utente")
                } footer: {
                    Text("Il tuo profilo viene utilizzato per personalizzare l'esperienza e calcolare l'indice di fatica basato sui tuoi dati VBT.")
                }
                .sheet(isPresented: $showProfileEdit) {
                    ProfileEditView()
                }

                // MARK: - Categories Section
                Section {
                    // ✅ NUOVO: Esercizio (in cima per importanza)
                    NavigationLink(destination: ExerciseSelectionView()) {
                        NavigationSettingRow(
                            title: "Esercizio",
                            subtitle: exerciseManager.selectedExercise.name,
                            icon: exerciseManager.selectedExercise.icon,
                            iconColor: exerciseManager.selectedExercise.category.color,
                            badge: "★"
                        )
                    }

                    NavigationLink(destination: SensorSettingsView(
                        sensorManager: sensorManager,
                        calibrationManager: calibrationManager
                    )) {
                        NavigationSettingRow(
                            title: "Sensore",
                            subtitle: sensorSubtitle,
                            icon: "sensor.fill",
                            iconColor: sensorManager.isConnected ? .green : .gray
                        )
                    }

                    // ✅ Pattern Appresi - SOLO WitMotion (nascosto completamente per Arduino)
                    if settings.selectedSensorType == .witmotion {
                        NavigationLink(destination: LearnedPatternsView()) {
                            NavigationSettingRow(
                                title: "Pattern Appresi",
                                subtitle: patternSubtitle,
                                icon: "brain.head.profile",
                                iconColor: .purple
                            )
                        }

                        // ✅ Registra Pattern - SOLO WitMotion
                        NavigationLink(destination: RecordPatternView(sensorManager: sensorManager)) {
                            NavigationSettingRow(
                                title: "Registra Pattern",
                                subtitle: "Registra manualmente un nuovo pattern",
                                icon: "waveform.badge.plus",
                                iconColor: .red,
                                badge: "Nuovo"
                            )
                        }
                    }

                    NavigationLink(destination: VelocitySettingsView()) {
                        NavigationSettingRow(
                            title: "Velocità",
                            subtitle: "Zone VBT e Velocity Loss",
                            icon: "speedometer",
                            iconColor: .blue
                        )
                    }

                    // ✅ Rilevamento Rep - Badge "WitMotion" quando applicabile
                    NavigationLink(destination: RepDetectionSettingsView()) {
                        NavigationSettingRow(
                            title: "Rilevamento Rep",
                            subtitle: repDetectionSubtitle,
                            icon: "waveform.path.ecg",
                            iconColor: .purple,
                            badge: repDetectionBadge
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
                        
                        Text("Sviluppo Tesi Ing. Informatica")
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
        if sensorManager.isConnected {
            return "\(sensorManager.sensorName) Connesso"
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

    // ✅ NUOVO: Subtitle per Rep Detection
    private var repDetectionSubtitle: String {
        switch settings.selectedSensorType {
        case .witmotion:
            return "Parametri algoritmo WitMotion"
        case .arduino:
            return "Parametri algoritmo Arduino"
        }
    }

    // ✅ NUOVO: Badge per Rep Detection
    private var repDetectionBadge: String? {
        switch settings.selectedSensorType {
        case .witmotion:
            return "Avanzato"
        case .arduino:
            return nil  // Nessun badge per Arduino (più semplice)
        }
    }
}

// MARK: - NotificationCenter Extension
extension Notification.Name {
    static let detectionAlgorithmChanged = Notification.Name("detectionAlgorithmChanged")
}

// MARK: - Previews
#Preview("Connected") {
    SettingsView(
        sensorManager: UnifiedSensorManager(),
        calibrationManager: CalibrationManager()
    )
}

#Preview("Disconnected") {
    SettingsView(
        sensorManager: UnifiedSensorManager(),
        calibrationManager: CalibrationManager()
    )
}
