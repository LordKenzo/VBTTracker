//
//  HomeView.swift
//  VBTTracker
//
//  Vista principale con accesso a storico allenamenti
//

import SwiftUI

struct HomeView: View {
    @StateObject private var bleManager = BLEManager()
    @StateObject private var calibrationManager = CalibrationManager()
    
    @State private var showSettings = false
    @State private var showHistory = false
    @State private var showConnectionView = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background gradient
                LinearGradient(
                    colors: [Color.black, Color(white: 0.1)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                VStack(spacing: 30) {
                    Spacer()
                    
                    // Logo & Title
                    VStack(spacing: 12) {
                        Image(systemName: "figure.strengthtraining.traditional")
                            .font(.system(size: 80))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.blue, .cyan],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        
                        Text("VBT Tracker")
                            .font(.system(size: 42, weight: .bold, design: .rounded))
                        
                        Text("Velocity-Based Training")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        
                        Text("by Lorenzo Franceschini")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    // Connection Status
                    connectionStatusCard
                    
                    // Main Actions
                    VStack(spacing: 16) {
                        // Start Training Button
                        NavigationLink(destination: TrainingSelectionView(
                            bleManager: bleManager
                        )) {
                            Label("Inizia Allenamento", systemImage: "play.circle.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!bleManager.isConnected || !bleManager.isCalibrated)
                        
                        // Connect Sensor Button (if not connected)
                        /*if !bleManager.isConnected {
                            Button(action: {
                                showConnectionView = true
                            }) {
                                Label("Connetti Sensore", systemImage: "sensor.fill")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 56)
                            }
                            .buttonStyle(.bordered)
                        }*/
                    }
                    .padding(.horizontal)
                    
                    Spacer()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        showHistory = true
                    }) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.title3)
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showSettings = true
                    }) {
                        Image(systemName: "gearshape.fill")
                            .font(.title3)
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(
                    bleManager: bleManager,
                    calibrationManager: calibrationManager
                )
            }
            .sheet(isPresented: $showHistory) {
                TrainingHistoryView()
            }
            .sheet(isPresented: $showConnectionView) {
                SensorConnectionView()
            }
        }
    }
    
    // MARK: - Connection Status Card
    
    private var connectionStatusCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                // Sensor Status
                StatusIndicator(
                    icon: "sensor.fill",
                    label: "Sensore",
                    isActive: bleManager.isConnected,
                    activeText: bleManager.sensorName,
                    inactiveText: "Non connesso"
                )
                
                // Calibration Status
                StatusIndicator(
                    icon: "scope",
                    label: "Calibrazione",
                    isActive: bleManager.isCalibrated,
                    activeText: "Calibrato",
                    inactiveText: "Non calibrato"
                )
            }
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(16)
        .padding(.horizontal)
    }
}

// MARK: - Status Indicator

struct StatusIndicator: View {
    let icon: String
    let label: String
    let isActive: Bool
    let activeText: String
    let inactiveText: String
    
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(isActive ? Color.green.opacity(0.2) : Color.gray.opacity(0.2))
                    .frame(width: 50, height: 50)
                
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(isActive ? .green : .gray)
            }
            
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            
            Text(isActive ? activeText : inactiveText)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(isActive ? .green : .gray)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Preview

#Preview("Connected") {
    HomeView()
}

#Preview("Disconnected") {
    HomeView()
}
