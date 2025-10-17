//
//  SettingsView.swift
//  VBTTracker
//
//  Pannello impostazioni completo
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var bleManager: BLEManager
    @ObservedObject var calibrationManager: CalibrationManager
    @ObservedObject var settings = SettingsManager.shared
    
    @Environment(\.dismiss) var dismiss
    @State private var showCalibrationView = false
    @State private var showVelocityRangesEditor = false
    @State private var showResetAlert = false
    
    var body: some View {
        NavigationStack {
            List {
                // MARK: - Sensor Section
                Section("Sensore") {
                    sensorStatusRow
                    
                    if bleManager.isConnected {
                        Button(action: { bleManager.disconnect() }) {
                            Label("Disconnetti", systemImage: "xmark.circle.fill")
                                .foregroundStyle(.red)
                        }
                        
                        Button(action: { showCalibrationView = true }) {
                            HStack {
                                Label("Calibrazione", systemImage: "sensor.tag.radiowaves.forward.fill")
                                
                                Spacer()
                                
                                if bleManager.isCalibrated {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                }
                            }
                        }
                    } else {
                        NavigationLink(destination: SensorScanView(bleManager: bleManager)) {
                            Label("Cerca Sensori", systemImage: "magnifyingglass")
                        }
                    }
                }
                
                // MARK: - Velocity Ranges Section
                Section {
                    Button(action: { showVelocityRangesEditor = true }) {
                        HStack {
                            Label("Zone di Velocità", systemImage: "speedometer")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Range di Velocità")
                } footer: {
                    Text("Valori predefiniti da letteratura scientifica (panca piana)")
                }
                
                // MARK: - Velocity Measurement Mode Section

                Section {
                    Picker("Modalità Misurazione", selection: $settings.velocityMeasurementMode) {
                        Text("Solo Concentrica").tag(VBTRepDetector.VelocityMeasurementMode.concentricOnly)
                        Text("ROM Completo").tag(VBTRepDetector.VelocityMeasurementMode.fullROM)
                    }
                    .pickerStyle(.segmented)
                    
                } header: {
                    Text("Misurazione Velocità")
                } footer: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(footerText)
                        
                        Divider()
                        
                        Text("📚 Letteratura Scientifica:")
                            .font(.caption2)
                            .fontWeight(.semibold)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("• González-Badillo & Sánchez-Medina (2010): MPV solo concentrica")
                            Text("• Pareja-Blanco et al. (2017): Velocity loss su fase propulsiva")
                            Text("• Banyard et al. (2019): Standard VBT = concentrica only")
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                }

                // MARK: - Computed Property per Footer

                var footerText: String {
                    switch settings.velocityMeasurementMode {
                    case .concentricOnly:
                        return """
                        Standard VBT: Misura velocità SOLO nella fase concentrica (salita/spinta).
                        Più accurato per valutare la potenza esplosiva.
                        
                        Esempio: Panca piana
                        • Eccentrica (discesa): ignora
                        • Concentrica (salita): misura velocità ✅
                        """
                    case .fullROM:
                        return """
                        ROM Completo: Misura velocità su tutto il movimento (discesa + salita).
                        Utile per esercizi controllati o powerlifting.
                        
                        Esempio: Panca piana
                        • Eccentrica + Concentrica: misura velocità totale ✅
                        """
                    }
                }
                
                // MARK: - Velocity Loss Section
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Soglia Velocity Loss")
                            Spacer()
                            Text("\(Int(settings.velocityLossThreshold))%")
                                .foregroundStyle(.secondary)
                        }
                        
                        Slider(value: $settings.velocityLossThreshold, in: 10...40, step: 5)
                            .tint(.blue)
                    }
                    
                    Toggle(isOn: $settings.stopOnVelocityLoss) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Blocco automatico")
                            Text("Ferma serie al raggiungimento soglia")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Velocity Loss")
                } footer: {
                    Text("10-20%: ottimale per forza\n20-40%: ipertrofia")
                }
                
                // MARK: - Rep Detection Section
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Velocità Minima Movimento")
                            Spacer()
                            Text(String(format: "%.2f m/s", settings.repMinVelocity))
                                .foregroundStyle(.secondary)
                        }
                        
                        Slider(value: $settings.repMinVelocity, in: 0.05...0.20, step: 0.01)
                            .tint(.blue)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Velocità Minima Picco")
                            Spacer()
                            Text(String(format: "%.2f m/s", settings.repMinPeakVelocity))
                                .foregroundStyle(.secondary)
                        }
                        
                        Slider(value: $settings.repMinPeakVelocity, in: 0.10...0.30, step: 0.01)
                            .tint(.blue)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Accelerazione Minima")
                            Spacer()
                            Text(String(format: "%.1f m/s²", settings.repMinAcceleration))
                                .foregroundStyle(.secondary)
                        }
                        
                        Slider(value: $settings.repMinAcceleration, in: 1.0...5.0, step: 0.5)
                            .tint(.blue)
                    }
                } header: {
                    Text("Sensibilità Rilevamento")
                } footer: {
                    Text("Valori più bassi = più sensibile (conta anche reps lente)\nValori più alti = meno sensibile (solo reps veloci)")
                }
                
                // MARK: - Audio Feedback Section
                Section {
                    Toggle(isOn: $settings.voiceFeedbackEnabled) {
                        Label("Feedback Vocale", systemImage: "speaker.wave.2.fill")
                    }
                    
                    if settings.voiceFeedbackEnabled {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Volume")
                                Spacer()
                                Text("\(Int(settings.voiceVolume * 100))%")
                                    .foregroundStyle(.secondary)
                            }
                            
                            Slider(value: $settings.voiceVolume, in: 0...1, step: 0.1)
                                .tint(.blue)
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Velocità Voce")
                                Spacer()
                                Text(voiceRateLabel)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Slider(value: $settings.voiceRate, in: 0...1, step: 0.1)
                                .tint(.blue)
                        }
                        
                        Picker("Lingua", selection: $settings.voiceLanguage) {
                            Text("Italiano").tag("it-IT")
                            Text("English").tag("en-US")
                        }
                        
                        Button(action: testVoiceFeedback) {
                            Label("Test Audio", systemImage: "play.circle.fill")
                        }
                    }
                } header: {
                    Text("Audio")
                } footer: {
                    Text("Feedback vocale durante l'allenamento")
                }
                
                // MARK: - About Section
                Section("Info") {
                    HStack {
                        Text("Versione")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }
                    
                    Button(action: { showResetAlert = true }) {
                        Label("Reset Impostazioni", systemImage: "arrow.counterclockwise")
                            .foregroundStyle(.red)
                    }
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
            .sheet(isPresented: $showCalibrationView) {
                CalibrationView(
                    calibrationManager: calibrationManager,
                    sensorManager: bleManager
                )
                .onDisappear {
                    if let calibration = calibrationManager.currentCalibration {
                        settings.savedCalibration = calibration
                        bleManager.applyCalibration(calibration)
                    }
                }
            }
            .sheet(isPresented: $showVelocityRangesEditor) {
                VelocityRangesEditorView()
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
    
    // MARK: - Sensor Status Row
    
    private var sensorStatusRow: some View {
        HStack {
            Circle()
                .fill(bleManager.isConnected ? Color.green : Color.gray)
                .frame(width: 12, height: 12)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(bleManager.sensorName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(bleManager.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
    }
    
    private var voiceRateLabel: String {
        if settings.voiceRate < 0.3 {
            return "Lenta"
        } else if settings.voiceRate > 0.7 {
            return "Veloce"
        } else {
            return "Normale"
        }
    }
    
    private func testVoiceFeedback() {
        // TODO: Implement voice feedback test
        print("🔊 Test feedback vocale")
    }
}

#Preview {
    SettingsView(
        bleManager: BLEManager(),
        calibrationManager: CalibrationManager()
    )
}
