//
//  SensorSettingsView.swift
//  VBTTracker
//
//  Impostazioni Sensore e Calibrazione
//

import SwiftUI

struct SensorSettingsView: View {
    @ObservedObject var bleManager: BLEManager
    @ObservedObject var calibrationManager: CalibrationManager
    @ObservedObject var settings = SettingsManager.shared
    
    @Environment(\.dismiss) var dismiss
    @State private var showCalibrationView = false
    @State private var showSensorScan = false
    
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
                            
                            Text("Data: \(calibration.timestamp, style: .date) alle \(calibration.timestamp, style: .time)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
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
                        Text("\(Int(bleManager.sampleRateHz ?? 0)) Hz")
                            .foregroundStyle(.secondary)
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
    
    private func formatSR(_ hz: Double?) -> String {
        guard let hz = hz, hz > 0 else { return "—" }
        if hz >= 100 { return "\(Int(round(hz))) Hz" }
        return String(format: "%.1f Hz", hz)
    }
    
    // MARK: - Sensor Status Row
    
    private var sensorStatusRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Prima riga: Indicatore di stato + Nome del sensore + Icona di connessione
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

                // Icona di connessione (allineata a destra)
                if bleManager.isConnected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
            }

            // Seconda riga: Frequenza stimata (allineata a sinistra, sotto il nome)
            HStack {
                Text("Frequenza stimata")
                Spacer()
                Text(formatSR(bleManager.sampleRateHz))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        SensorSettingsView(
            bleManager: BLEManager(),
            calibrationManager: CalibrationManager()
        )
    }
}
