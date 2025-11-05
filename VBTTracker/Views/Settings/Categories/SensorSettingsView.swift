//
//  SensorSettingsView.swift
//  VBTTracker
//
//  Impostazioni Sensore e Calibrazione
//  ✅ UNIFICATO: Include funzionalità da SensorConnectionView
//

import SwiftUI

struct SensorSettingsView: View {
    @ObservedObject var bleManager: BLEManager
    @ObservedObject var calibrationManager: CalibrationManager
    @ObservedObject var settings = SettingsManager.shared
    
    @Environment(\.dismiss) var dismiss
    @State private var showCalibrationView = false
    @State private var showSensorScan = false
    
    // ✅ NUOVO: Toggle per dati real-time
    @State private var showRealTimeData = false
    
    var body: some View {
        List {
            // MARK: - Sensor Status Section
            Section {
                sensorStatusRow
                
                if bleManager.isConnected {
                    Button(action: { bleManager.disconnect() }) {
                        Label("Disconnetti", systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                } else {
                    Button(action: { showSensorScan = true }) {
                        Label("Cerca Sensori", systemImage: "magnifyingglass")
                    }
                }
            } header: {
                Text("Connessione")
            }
            
            // MARK: - Calibration Section
            if bleManager.isConnected {
                Section {
                    // Pulsante Calibrazione
                    Button(action: { showCalibrationView = true }) {
                        HStack {
                            Label("Calibrazione Sensore", systemImage: "sensor.tag.radiowaves.forward.fill")
                            
                            Spacer()
                            
                            if bleManager.isCalibrated {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            } else {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                    
                    // Dettagli calibrazione
                    if let calibration = settings.savedCalibration {
                        VStack(alignment: .leading, spacing: 8) {
                            InfoSettingRow(
                                title: "Offset X",
                                value: String(format: "%.3f g", calibration.accelerationOffset[0]),
                                icon: "arrow.left.and.right"
                            )
                            
                            InfoSettingRow(
                                title: "Offset Y",
                                value: String(format: "%.3f g", calibration.accelerationOffset[1]),
                                icon: "arrow.up.and.down"
                            )
                            
                            InfoSettingRow(
                                title: "Offset Z",
                                value: String(format: "%.3f g", calibration.accelerationOffset[2]),
                                icon: "arrow.forward.to.line"
                            )
                            
                            HStack {
                                Image(systemName: "clock")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                
                                Text("Data: \(calibration.timestamp, style: .date) alle \(calibration.timestamp, style: .time)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.top, 4)
                        }
                        .padding(.vertical, 4)
                        
                        // ✅ NUOVO: Pulsante Rimuovi Calibrazione
                        Button(action: {
                            bleManager.removeCalibration()
                            calibrationManager.resetCalibration()
                        }) {
                            HStack {
                                Image(systemName: "trash.fill")
                                    .foregroundStyle(.red)
                                Text("Rimuovi Calibrazione")
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                } header: {
                    Text("Calibrazione")
                } footer: {
                    Text("Calibra il sensore a bilanciere fermo in posizione di partenza (rack). La calibrazione rimuove offset gravitazionali e migliora l'accuratezza.")
                }
            }
            
            // MARK: - Sensor Info Section
            if bleManager.isConnected {
                Section {
                    HStack {
                        Image(systemName: "sensor.fill")
                            .foregroundStyle(.blue)
                            .frame(width: 24)
                        Text("Nome")
                        Spacer()
                        Text(bleManager.sensorName)
                            .foregroundStyle(.secondary)
                    }
                    
                    HStack {
                        Image(systemName: "waveform.path")
                            .foregroundStyle(.blue)
                            .frame(width: 24)
                        Text("Frequenza stimata")
                        Spacer()
                        Text(formatSR(bleManager.sampleRateHz))
                            .foregroundStyle(.secondary)
                    }
                    
                    // Pulsante Config 200Hz
                    Button {
                        bleManager.configureFor200Hz()
                    } label: {
                        HStack {
                            Image(systemName: "speedometer")
                                .foregroundStyle(.blue)
                            Text("Imposta 200 Hz")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    
                    HStack {
                        Image(systemName: "gauge.high")
                            .foregroundStyle(.blue)
                            .frame(width: 24)
                        Text("Range")
                        Spacer()
                        Text("±16g")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Informazioni Sensore")
                }
            }
            
            // MARK: - ✅ NUOVO: Real-Time Data Section (Debug)
            if bleManager.isConnected {
                Section {
                    Toggle("Mostra Dati Real-time", isOn: $showRealTimeData)
                        .tint(.blue)
                    
                    if showRealTimeData {
                        dataDisplaySection
                    }
                } header: {
                    Text("Debug")
                } footer: {
                    Text("Visualizza i dati grezzi dal sensore in tempo reale. Utile per diagnostica e verifica della connessione.")
                }
            }
        }
        .navigationTitle("Sensore")
        .navigationBarTitleDisplayMode(.inline)
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
        .sheet(isPresented: $showSensorScan) {
            NavigationStack {
                SensorScanView(bleManager: bleManager)
            }
        }
    }
    
    // MARK: - Helper: Format Sample Rate
    
    private func formatSR(_ hz: Double?) -> String {
        guard let hz = hz, hz > 0 else { return "—" }
        if hz >= 100 { return "\(Int(round(hz))) Hz" }
        return String(format: "%.1f Hz", hz)
    }
    
    // MARK: - Sensor Status Row
    
    private var sensorStatusRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Prima riga: Indicatore di stato + Nome del sensore
            HStack(spacing: 12) {
                // Indicatore di stato
                ZStack {
                    Circle()
                        .fill(bleManager.isConnected ? Color.green.opacity(0.2) : Color.gray.opacity(0.2))
                        .frame(width: 40, height: 40)

                    Circle()
                        .fill(bleManager.isConnected ? Color.green : Color.gray)
                        .frame(width: 12, height: 12)
                }

                // Nome del sensore
                VStack(alignment: .leading, spacing: 4) {
                    Text(bleManager.sensorName)
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Text(bleManager.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Icona di connessione
                if bleManager.isConnected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    // MARK: - ✅ NUOVO: Real-Time Data Display Section
    
    private var dataDisplaySection: some View {
        VStack(spacing: 16) {
            // Accelerazione
            dataRow(
                title: "Accelerazione (g)",
                values: bleManager.acceleration,
                colors: [.red, .green, .blue]
            )
            
            Divider()
            
            // Velocità Angolare
            dataRow(
                title: "Velocità Angolare (°/s)",
                values: bleManager.angularVelocity,
                colors: [.red, .green, .blue]
            )
            
            Divider()
            
            // Angoli
            dataRow(
                title: "Angoli (°)",
                values: bleManager.angles,
                colors: [.red, .green, .blue]
            )
        }
        .padding(.vertical, 8)
    }
    
    // MARK: - ✅ NUOVO: Data Row Component
    
    private func dataRow(title: String, values: [Double], colors: [Color]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            
            HStack(spacing: 20) {
                ForEach(0..<3) { index in
                    VStack(spacing: 4) {
                        Text(["X", "Y", "Z"][index])
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        
                        Text(String(format: "%.2f", values[index]))
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.semibold)
                            .foregroundStyle(colors[index])
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

// MARK: - Preview

#Preview("Connected & Calibrated") {
    NavigationStack {
        SensorSettingsView(
            bleManager: {
                let manager = BLEManager()
                manager.isConnected = true
                manager.isCalibrated = true
                manager.sensorName = "WT901BLE67"
                manager.sampleRateHz = 200.0
                manager.acceleration = [0.02, -0.05, 1.00]
                manager.angularVelocity = [1.2, -0.8, 0.3]
                manager.angles = [2.5, -1.2, 0.0]
                return manager
            }(),
            calibrationManager: CalibrationManager()
        )
    }
}

#Preview("Disconnected") {
    NavigationStack {
        SensorSettingsView(
            bleManager: BLEManager(),
            calibrationManager: CalibrationManager()
        )
    }
}

#Preview("Connected - Not Calibrated") {
    NavigationStack {
        SensorSettingsView(
            bleManager: {
                let manager = BLEManager()
                manager.isConnected = true
                manager.isCalibrated = false
                manager.sensorName = "WT901BLE67"
                return manager
            }(),
            calibrationManager: CalibrationManager()
        )
    }
}
