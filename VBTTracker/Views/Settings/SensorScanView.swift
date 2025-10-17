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
    @ObservedObject var bleManager: BLEManager
    @ObservedObject var settings = SettingsManager.shared
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 12) {
                Image(systemName: "sensor.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.blue)
                
                Text("Cerca Sensori")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Accendi il sensore WitMotion e avvia la scansione")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top)
            
            // Scan Button
            if !bleManager.isScanning {
                Button(action: { bleManager.startScanning() }) {
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
                    
                    Button(action: { bleManager.stopScanning() }) {
                        Text("Ferma Scansione")
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
            }
            
            // Devices List
            if !bleManager.discoveredDevices.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Dispositivi Trovati")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(bleManager.discoveredDevices, id: \.identifier) { device in
                                DeviceRow(
                                    device: device,
                                    isLastConnected: device.address == settings.lastConnectedSensorMAC
                                ) {
                                    connectToDevice(device)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            } else if !bleManager.isScanning {
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
    
    private func connectToDevice(_ device: CBPeripheral) {
        bleManager.connect(to: device)
        
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
    let onConnect: () -> Void
    
    var body: some View {
        Button(action: onConnect) {
            HStack(spacing: 12) {
                Image(systemName: "sensor.fill")
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
        SensorScanView(bleManager: BLEManager())
    }
}