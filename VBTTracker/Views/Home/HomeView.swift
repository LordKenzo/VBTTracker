//
//  HomeView.swift
//  VBTTracker
//
//  Created by Lorenzo Franceschini on 17/10/25.
//


//
//  HomeView.swift
//  VBTTracker
//
//  Schermata principale dell'app
//

import SwiftUI

struct HomeView: View {
    @StateObject private var bleManager = BLEManager()
    @StateObject private var calibrationManager = CalibrationManager()
    @ObservedObject var settings = SettingsManager.shared
    
    @State private var showSettings = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background gradient
                LinearGradient(
                    colors: [Color.blue.opacity(0.1), Color.purple.opacity(0.05)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Hero Section
                        heroSection
                        
                        // Sensor Status Card
                        sensorStatusCard
                        
                        // Quick Actions
                        quickActionsSection
                        
                        // Training Zones Preview
                        trainingZonesPreview
                    }
                    .padding()
                }
            }
            .navigationTitle("VBT Tracker")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showSettings = true }) {
                        Image(systemName: "gearshape.fill")
                            .foregroundStyle(.blue)
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(
                    bleManager: bleManager,
                    calibrationManager: calibrationManager
                )
            }
            .onAppear {
                loadSavedCalibration()
                attemptAutoConnect()
            }
        }
    }
    
    // MARK: - Hero Section
    
    private var heroSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 70))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            Text("Velocity Based Training")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Allena con precisione scientifica")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical)
    }
    
    // MARK: - Sensor Status Card
    
    private var sensorStatusCard: some View {
        VStack(spacing: 16) {
            HStack {
                Circle()
                    .fill(bleManager.isConnected ? Color.green : Color.gray)
                    .frame(width: 12, height: 12)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(bleManager.sensorName)
                        .font(.headline)
                    
                    Text(bleManager.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Calibration badge
                if bleManager.isCalibrated {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.caption2)
                        Text("Calibrato")
                            .font(.caption2)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.green)
                    .cornerRadius(8)
                }
            }
            
            // Connection button if not connected
            if !bleManager.isConnected {
                Button(action: { showSettings = true }) {
                    Label("Connetti Sensore", systemImage: "sensor.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
    }
    
    // MARK: - Quick Actions
    
    private var quickActionsSection: some View {
        VStack(spacing: 16) {
            Text("Azioni Rapide")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // Start Training (main CTA)
            NavigationLink(destination: TrainingSelectionView(
                bleManager: bleManager,
                calibrationManager: calibrationManager
            )) {
                HStack {
                    Image(systemName: "play.circle.fill")
                        .font(.title2)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Inizia Allenamento")
                            .font(.headline)
                        Text("Scegli obiettivo e inizia")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(
                    LinearGradient(
                        colors: [Color.blue, Color.blue.opacity(0.8)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .foregroundStyle(.white)
                .cornerRadius(16)
                .shadow(color: .blue.opacity(0.3), radius: 8, x: 0, y: 4)
            }
            .disabled(!bleManager.isConnected || !bleManager.isCalibrated)
            
        }
    }
    
    // MARK: - Training Zones Preview
    
    private var trainingZonesPreview: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Zone di Allenamento")
                    .font(.headline)
                
                Spacer()
                
                Button(action: { showSettings = true }) {
                    Text("Modifica")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
            }
            
            VStack(spacing: 8) {
                TrainingZoneRow(
                    zone: .maxStrength,
                    range: settings.velocityRanges.maxStrength
                )
                TrainingZoneRow(
                    zone: .strength,
                    range: settings.velocityRanges.strength
                )
                TrainingZoneRow(
                    zone: .strengthSpeed,
                    range: settings.velocityRanges.strengthSpeed
                )
                TrainingZoneRow(
                    zone: .speed,
                    range: settings.velocityRanges.speed
                )
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
    }
    
    // MARK: - Helper Methods
    
    private func loadSavedCalibration() {
        if let calibration = settings.savedCalibration {
            bleManager.applyCalibration(calibration)
            print("📥 Calibrazione caricata da settings")
        }
    }
    
    private func attemptAutoConnect() {
        // TODO: Implement auto-reconnect to last sensor
        if let mac = settings.lastConnectedSensorMAC {
            print("🔄 Tentativo auto-connessione a: \(mac)")
            // bleManager.connectToMAC(mac)
        }
    }
}

// MARK: - Supporting Views

struct QuickActionCard: View {
    let icon: String
    let title: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(color.opacity(0.1))
        .cornerRadius(12)
    }
}

struct TrainingZoneRow: View {
    let zone: TrainingZone
    let range: ClosedRange<Double>
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: zone.icon)
                .font(.title3)
                .foregroundStyle(zone.color)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(zone.rawValue)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text("\(String(format: "%.2f", range.lowerBound)) - \(String(format: "%.2f", range.upperBound)) m/s")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(zone.color.opacity(0.1))
        .cornerRadius(8)
    }
}

#Preview {
    HomeView()
}
