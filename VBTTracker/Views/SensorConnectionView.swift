//
//  SensorConnectionView.swift
//  VBTTracker
//
//  Interfaccia per connessione e visualizzazione dati sensore
//

import SwiftUI

struct SensorConnectionView: View {
    @StateObject private var bleManager = BLEManager()
    @StateObject private var calibrationManager = CalibrationManager() // ⭐ NUOVO
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Status Card
                statusCard
                
                // Dati Real-time (solo se connesso)
                if bleManager.isConnected {
                    dataDisplaySection
                }
                
                Spacer()
                
                // Controlli
                controlSection
            }
            .padding()
            .navigationTitle("VBT Tracker")
        }
    }
    
    // MARK: - Status Card
    
    private var statusCard: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(bleManager.isConnected ? Color.green : Color.red)
                .frame(width: 12, height: 12)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(bleManager.sensorName)
                        .font(.headline)
                    
                    // ⭐ NUOVO: Badge calibrazione
                    if bleManager.isCalibrated {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.caption2)
                            Text("Calibrato")
                                .font(.caption2)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green)
                        .cornerRadius(8)
                    }
                }
                
                Text(bleManager.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }
    
    // MARK: - Data Display Section
    
    private var dataDisplaySection: some View {
        VStack(spacing: 16) {
            Text("Dati Sensore")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            
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
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 3, x: 0, y: 2)
    }
    
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
    
    // MARK: - Control Section
    
    private var controlSection: some View {
            VStack(spacing: 12) {
                if bleManager.isConnected {
                    // Pulsante Disconnetti
                    Button(action: { bleManager.disconnect() }) {
                        Label("Disconnetti Sensore", systemImage: "xmark.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .controlSize(.large)
                    
                    // ⭐ MODIFICATO: Usa il calibrationManager condiviso
                    NavigationLink(destination: CalibrationView(
                        calibrationManager: calibrationManager,  // ← Usa @StateObject
                        sensorManager: bleManager
                    )) {
                        Label("Calibra Sensore", systemImage: "sensor.tag.radiowaves.forward.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    if bleManager.isCalibrated {
                    Button(action: {
                        bleManager.removeCalibration()
                        calibrationManager.resetCalibration()
                    }) {
                        Label("Rimuovi Calibrazione", systemImage: "trash.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                    // Test Velocità
                    NavigationLink(destination: VelocityTestView(sensorManager: bleManager)) {
                        Label("Test Calcolo Velocità", systemImage: "gauge.high")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.purple)
                }
                    
                } else {
                // Pulsante Scansione
                Button(action: { bleManager.startScanning() }) {
                    HStack {
                        if bleManager.isScanning {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        }
                        Text(bleManager.isScanning ? "Scansione..." : "Cerca Sensori")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(bleManager.isScanning)
                
                // Lista Dispositivi Trovati
                if !bleManager.discoveredDevices.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Dispositivi trovati:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                        
                        ForEach(bleManager.discoveredDevices, id: \.identifier) { device in
                            Button(action: { bleManager.connect(to: device) }) {
                                HStack {
                                    Image(systemName: "sensor.fill")
                                        .foregroundStyle(.blue)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(device.name ?? "Sensore sconosciuto")
                                            .fontWeight(.medium)
                                        
                                        Text(device.identifier.uuidString)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding()
                                .background(Color(.systemGray6))
                                .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    SensorConnectionView()
}
