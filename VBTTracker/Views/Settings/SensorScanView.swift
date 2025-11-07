//
//  SensorScanView.swift
//  VBTTracker
//
//  Created by Lorenzo Franceschini on 17/10/25.
//


//
//  SensorScanView.swift
//  VBTTracker
//
//  View per scansione e connessione sensori BLE
//

import SwiftUI
import CoreBluetooth

struct SensorScanView: View {
    @ObservedObject var sensorManager: UnifiedSensorManager
    @ObservedObject var settings = SettingsManager.shared
    @Environment(\.dismiss) var dismiss

    // Helper per accedere al manager corrente
    private var discoveredDevices: [CBPeripheral] {
        switch settings.selectedSensorType {
        case .witmotion:
            return sensorManager.bleManager.discoveredDevices
        case .arduino:
            return sensorManager.arduinoManager.discoveredDevices
        }
    }

    private var isScanning: Bool {
        switch settings.selectedSensorType {
        case .witmotion:
            return sensorManager.bleManager.isScanning
        case .arduino:
            return sensorManager.arduinoManager.isScanning
        }
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 12) {
                Image(systemName: settings.selectedSensorType.icon)
                    .font(.system(size: 60))
                    .foregroundStyle(.blue)

                Text("Cerca Sensori")
                    .font(.title2)
                    .fontWeight(.bold)

                Text(sensorTypeDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top)

            // Scan Button
            if !isScanning {
                Button(action: { sensorManager.startScanning() }) {
                    Label("Avvia Scansione", systemImage: "magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.5)

                    Text("Scansione in corso...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Button(action: { sensorManager.stopScanning() }) {
                        Text("Ferma Scansione")
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
            }

            // Devices List
            if !discoveredDevices.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Dispositivi Trovati")
                        .font(.headline)
                        .padding(.horizontal)

                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(discoveredDevices, id: \.identifier) { device in
                                DeviceRow(
                                    device: device,
                                    isLastConnected: device.address == settings.lastConnectedSensorMAC,
                                    sensorType: settings.selectedSensorType
                                ) {
                                    connectToDevice(device)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            } else if !isScanning {
                VStack(spacing: 12) {
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 40))
                        .foregroundStyle(.gray)

                    Text("Nessun sensore trovato")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
            
            Spacer()
        }
        .padding()
        .navigationTitle("Scansione Sensori")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private var sensorTypeDescription: String {
        switch settings.selectedSensorType {
        case .witmotion:
            return "Accendi il sensore WitMotion e avvia la scansione"
        case .arduino:
            return "Accendi il sensore Arduino VBT e avvia la scansione"
        }
    }

    private func connectToDevice(_ device: CBPeripheral) {
        switch settings.selectedSensorType {
        case .witmotion:
            sensorManager.bleManager.connect(to: device)
        case .arduino:
            sensorManager.arduinoManager.connect(to: device)
        }

        // Save last connected device
        settings.lastConnectedSensorMAC = device.address
        settings.lastConnectedSensorName = device.name

        // Dismiss after short delay to show connection feedback
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            dismiss()
        }
    }
}

// MARK: - Device Row

struct DeviceRow: View {
    let device: CBPeripheral
    let isLastConnected: Bool
    let sensorType: SensorType
    let onConnect: () -> Void

    var body: some View {
        Button(action: onConnect) {
            HStack(spacing: 12) {
                Image(systemName: sensorType.icon)
                    .font(.title2)
                    .foregroundStyle(.blue)
                    .frame(width: 40)
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(device.name ?? "Sensore Sconosciuto")
                            .font(.headline)
                        
                        if isLastConnected {
                            Text("Ultimo")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.2))
                                .foregroundStyle(.blue)
                                .cornerRadius(4)
                        }
                    }
                    
                    Text(device.identifier.uuidString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - CBPeripheral Extension for Address

extension CBPeripheral {
    var address: String {
        // On iOS, we use identifier as address since MAC is not accessible
        return identifier.uuidString
    }
}

#Preview {
    NavigationStack {
        SensorScanView(sensorManager: UnifiedSensorManager())
    }
}