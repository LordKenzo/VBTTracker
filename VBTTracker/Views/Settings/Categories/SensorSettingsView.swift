//
//  SensorSettingsView.swift
//  VBTTracker
//
//  Impostazioni Sensore e Calibrazione
//  ✅ UNIFICATO: Include funzionalità da SensorConnectionView
//

import SwiftUI

struct SensorSettingsView: View {
    @ObservedObject var sensorManager: UnifiedSensorManager
    @ObservedObject var calibrationManager: CalibrationManager
    @ObservedObject var settings = SettingsManager.shared

    @Environment(\.dismiss) var dismiss
    @State private var showCalibrationView = false
    @State private var showSensorScan = false

    // ✅ NUOVO: Toggle per dati real-time
    @State private var showRealTimeData = false

    // Helper per accedere al manager corrente
    private var currentManager: Any {
        switch settings.selectedSensorType {
        case .witmotion:
            return sensorManager.bleManager
        case .arduino:
            return sensorManager.arduinoManager
        }
    }

    private var isConnected: Bool {
        sensorManager.isConnected
    }
    
    var body: some View {
        List {
            // MARK: - Sensor Type Selection
            Section {
                Picker("Tipo Sensore", selection: $settings.selectedSensorType) {
                    ForEach(SensorType.allCases, id: \.self) { type in
                        HStack {
                            Image(systemName: type.icon)
                            Text(type.displayName)
                        }
                        .tag(type)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(settings.selectedSensorType.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Tipo di Sensore")
            } footer: {
                Text("Seleziona il tipo di sensore che stai utilizzando. Il sensore Arduino con VL53L0X misura direttamente la distanza ed è più preciso per VBT.")
            }

            // MARK: - Sensor Status Section
            Section {
                sensorStatusRow

                if isConnected {
                    Button(action: { sensorManager.disconnect() }) {
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
            
            // MARK: - Calibration Section (solo WitMotion)
            if isConnected && settings.selectedSensorType == .witmotion {
                Section {
                    // Pulsante Calibrazione
                    Button(action: { showCalibrationView = true }) {
                        HStack {
                            Label("Calibrazione Sensore", systemImage: "sensor.tag.radiowaves.forward.fill")

                            Spacer()

                            if sensorManager.bleManager.isCalibrated {
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
                            sensorManager.removeCalibration()
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
            if isConnected {
                Section {
                    HStack {
                        Image(systemName: "sensor.fill")
                            .foregroundStyle(.blue)
                            .frame(width: 24)
                        Text("Nome")
                        Spacer()
                        Text(sensorManager.sensorName)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Image(systemName: "waveform.path")
                            .foregroundStyle(.blue)
                            .frame(width: 24)
                        Text("Frequenza stimata")
                        Spacer()
                        Text(formatSR(sensorManager.sampleRateHz))
                            .foregroundStyle(.secondary)
                    }

                    // Pulsante Config 200Hz (solo WitMotion)
                    if settings.selectedSensorType == .witmotion {
                        Button {
                            sensorManager.bleManager.configureFor200Hz()
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
                    }

                    // Info Arduino
                    if settings.selectedSensorType == .arduino {
                        HStack {
                            Image(systemName: "ruler")
                                .foregroundStyle(.blue)
                                .frame(width: 24)
                            Text("Distanza Attuale")
                            Spacer()
                            Text(String(format: "%.0f mm", sensorManager.arduinoManager.distance))
                                .foregroundStyle(.secondary)
                        }

                        HStack {
                            Image(systemName: "gauge.high")
                                .foregroundStyle(.blue)
                                .frame(width: 24)
                            Text("Range")
                            Spacer()
                            Text("30-2000 mm")
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Informazioni Sensore")
                }
            }
            
            // MARK: - ✅ NUOVO: Real-Time Data Section (Debug)
            if isConnected {
                Section {
                    Toggle("Mostra Dati Real-time", isOn: $showRealTimeData)
                        .tint(.blue)

                    if showRealTimeData {
                        if settings.selectedSensorType == .witmotion {
                            dataDisplaySectionWitMotion
                        } else {
                            dataDisplaySectionArduino
                        }
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
                sensorManager: sensorManager.bleManager
            )
            .onDisappear {
                if let calibration = calibrationManager.currentCalibration {
                    settings.savedCalibration = calibration
                    sensorManager.applyCalibration(calibration)
                }
            }
        }
        .sheet(isPresented: $showSensorScan) {
            NavigationStack {
                SensorScanView(sensorManager: sensorManager)
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
                        .fill(isConnected ? Color.green.opacity(0.2) : Color.gray.opacity(0.2))
                        .frame(width: 40, height: 40)

                    Circle()
                        .fill(isConnected ? Color.green : Color.gray)
                        .frame(width: 12, height: 12)
                }

                // Nome del sensore
                VStack(alignment: .leading, spacing: 4) {
                    Text(sensorManager.sensorName)
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Text(sensorManager.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Icona di connessione
                if isConnected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    // MARK: - ✅ NUOVO: Real-Time Data Display Sections

    private var dataDisplaySectionWitMotion: some View {
        VStack(spacing: 16) {
            // Accelerazione
            dataRow(
                title: "Accelerazione (g)",
                values: sensorManager.bleManager.acceleration,
                colors: [.red, .green, .blue]
            )

            Divider()

            // Velocità Angolare
            dataRow(
                title: "Velocità Angolare (°/s)",
                values: sensorManager.bleManager.angularVelocity,
                colors: [.red, .green, .blue]
            )

            Divider()

            // Angoli
            dataRow(
                title: "Angoli (°)",
                values: sensorManager.bleManager.angles,
                colors: [.red, .green, .blue]
            )
        }
        .padding(.vertical, 8)
    }

    private var dataDisplaySectionArduino: some View {
        VStack(spacing: 16) {
            // Distanza
            VStack(alignment: .leading, spacing: 8) {
                Text("Distanza (mm)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(String(format: "%.1f", sensorManager.arduinoManager.distance))
                    .font(.system(.title, design: .monospaced))
                    .fontWeight(.semibold)
                    .foregroundStyle(.blue)
            }

            Divider()

            // Velocità
            VStack(alignment: .leading, spacing: 8) {
                Text("Velocità (mm/s)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(String(format: "%.1f", sensorManager.arduinoManager.velocity))
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.semibold)
                    .foregroundStyle(sensorManager.arduinoManager.velocity > 0 ? .green : sensorManager.arduinoManager.velocity < 0 ? .orange : .secondary)
            }

            Divider()

            // Stato Movimento
            VStack(alignment: .leading, spacing: 8) {
                Text("Stato Movimento")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Circle()
                        .fill(stateColor(sensorManager.arduinoManager.movementState))
                        .frame(width: 12, height: 12)

                    Text(sensorManager.arduinoManager.movementState.displayName)
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.semibold)
                }
            }

            Divider()

            // Timestamp
            VStack(alignment: .leading, spacing: 8) {
                Text("Timestamp (ms)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(String(format: "%d", sensorManager.arduinoManager.timestamp))
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
    }

    private func stateColor(_ state: MovementState) -> Color {
        switch state {
        case .approaching: return .red
        case .receding: return .blue
        case .idle: return .gray
        }
    }
    
    // MARK: - ✅ NUOVO: Data Row Component
    
    private func dataRow(title: String, values: [Double], colors: [Color]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 20) {
                // Assi fissi: X, Y, Z
                let axes = ["X", "Y", "Z"]
                ForEach(0..<3, id: \.self) { index in
                    VStack(spacing: 4) {
                        // Nome dell'asse (sempre presente)
                        Text(axes[index])
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        // Valore con fallback a 0.0 se l'indice non esiste
                        let value = index < values.count ? values[index] : 0.0
                        Text(String(format: "%.2f", value))
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.semibold)
                            .foregroundStyle(index < colors.count ? colors[index] : .primary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

}

// MARK: - Preview

#Preview("WitMotion Connected") {
    NavigationStack {
        SensorSettingsView(
            sensorManager: UnifiedSensorManager(),
            calibrationManager: CalibrationManager()
        )
    }
}

#Preview("Arduino Connected") {
    NavigationStack {
        SensorSettingsView(
            sensorManager: UnifiedSensorManager(),
            calibrationManager: CalibrationManager()
        )
    }
}

#Preview("Disconnected") {
    NavigationStack {
        SensorSettingsView(
            sensorManager: UnifiedSensorManager(),
            calibrationManager: CalibrationManager()
        )
    }
}
