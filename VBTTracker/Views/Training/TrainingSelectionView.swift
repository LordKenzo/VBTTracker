//
//  TrainingSelectionView.swift
//  VBTTracker
//
//  AGGIORNATO con integrazione calibrazione ROM
//

import SwiftUI

struct TrainingSelectionView: View {
    @ObservedObject var bleManager: BLEManager
    @StateObject private var calibrationManager = ROMCalibrationManager()
    
    @State private var selectedZone: TrainingZone = .strength
    @State private var showCalibration = false
    @State private var navigateToSession = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                LinearGradient(
                    colors: [Color.black, Color(white: 0.1)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Sensor Status
                        sensorStatusCard
                        
                        // Calibration Card
                        calibrationCard
                        
                        // Zone Selection
                        zoneSelectionCard
                        
                        // Start Button
                        startButton
                    }
                    .padding()
                }
            }
            .navigationTitle("Setup Allenamento")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showCalibration) {
                ROMCalibrationView(
                    calibrationManager: calibrationManager,
                    bleManager: bleManager
                )
            }
            .navigationDestination(isPresented: $navigateToSession) {
                RepTargetSelectionView(
                    bleManager: bleManager,
                    targetZone: selectedZone
                )
            }
        }
    }
    
    // MARK: - Sensor Status Card
    
    private var sensorStatusCard: some View {
        HStack(spacing: 16) {
            Circle()
                .fill(bleManager.isConnected ? Color.green : Color.red)
                .frame(width: 12, height: 12)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Sensore")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Text(bleManager.sensorName)
                    .font(.headline)
                    .foregroundStyle(.white)
            }
            
            Spacer()
            
            if bleManager.isCalibrated {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Calibrato")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
    }
    
    // MARK: - Calibration Card
    
    private var calibrationCard: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Calibrazione Movimento")
                        .font(.headline)
                        .foregroundStyle(.white)
                    
                    if calibrationManager.isCalibrated {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Pattern appreso")
                                .font(.subheadline)
                                .foregroundStyle(.green)
                        }
                    } else {
                        Text("Consigliata per nuovi esercizi")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                Image(systemName: calibrationManager.isCalibrated ?
                      "brain.filled.head.profile" : "brain.head.profile")
                    .font(.system(size: 40))
                    .foregroundStyle(calibrationManager.isCalibrated ? .green : .blue)
            }
            
            if let pattern = calibrationManager.learnedPattern {
                Divider()
                    .background(.white.opacity(0.2))
                
                HStack(spacing: 20) {
                    CalibrationStat(
                        icon: "ruler",
                        label: "ROM",
                        value: String(format: "%.0fcm", pattern.estimatedROM * 100)
                    )
                    
                    CalibrationStat(
                        icon: "gauge.with.dots.needle.67percent",
                        label: "Velocità",
                        value: String(format: "%.2fm/s", pattern.avgPeakVelocity)
                    )
                    
                    CalibrationStat(
                        icon: "timer",
                        label: "Durata",
                        value: String(format: "%.1fs", pattern.avgConcentricDuration)
                    )
                }
            }
            
            HStack(spacing: 12) {
                Button(action: {
                    if calibrationManager.isCalibrated {
                        calibrationManager.reset()
                    }
                    showCalibration = true
                }) {
                    Label(
                        calibrationManager.isCalibrated ? "Ricalibra" : "Calibra Movimento",
                        systemImage: calibrationManager.isCalibrated ? "arrow.clockwise" : "play.circle"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.blue)
                
                if calibrationManager.isCalibrated {
                    Button(action: {
                        calibrationManager.reset()
                    }) {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(calibrationManager.isCalibrated ? Color.green.opacity(0.5) : Color.blue.opacity(0.3), lineWidth: 2)
                )
        )
    }
    
    // MARK: - Zone Selection Card
    
    private var zoneSelectionCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Zona Target")
                .font(.headline)
                .foregroundStyle(.white)
            
            ForEach(TrainingZone.allCases.filter { $0 != .tooSlow }, id: \.self) { zone in
                ZoneRow(
                    zone: zone,
                    isSelected: selectedZone == zone,
                    action: { selectedZone = zone }
                )
            }
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
    }
    
    // MARK: - Start Button
    
    private var startButton: some View {
        VStack(spacing: 12) {
            Button(action: startTraining) {
                Label("Inizia Allenamento", systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .disabled(!bleManager.isConnected)
            
            if !bleManager.isConnected {
                Text("Connetti il sensore per continuare")
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if !calibrationManager.isCalibrated {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.yellow)
                    Text("Calibrazione consigliata ma non obbligatoria")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
    
    // MARK: - Actions
    
    private func startTraining() {
        // 💾 Salva pattern per la prossima sessione
        if calibrationManager.isCalibrated {
            calibrationManager.savePattern()
        }
        
        navigateToSession = true
    }
}

// MARK: - Supporting Views

struct CalibrationStat: View {
    let icon: String
    let label: String
    let value: String
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.blue)
            
            Text(value)
                .font(.headline)
                .foregroundStyle(.white)
            
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct ZoneRow: View {
    let zone: TrainingZone
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(zone.rawValue)
                        .font(.headline)
                        .foregroundStyle(.white)
                    
                    Text(zone.detailedDescription)  // ✅ Aggiornato
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? zone.color.opacity(0.2) : Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? zone.color : Color.clear, lineWidth: 2)
            )
        }
    }
}

// MARK: - TrainingZone Extension

extension TrainingZone {
    static var allCases: [TrainingZone] {
        [.maxStrength, .strength, .strengthSpeed, .speed, .maxSpeed, .tooSlow]
    }
    
    var detailedDescription: String {  // ✅ Cambiato nome
        switch self {
        case .maxStrength:
            return "Forza massimale (0.15-0.40 m/s)"
        case .strength:
            return "Forza (0.40-0.75 m/s)"
        case .strengthSpeed:
            return "Forza-Velocità (0.75-1.00 m/s)"
        case .speed:
            return "Velocità (1.00-1.30 m/s)"
        case .maxSpeed:
            return "Velocità massima (>1.30 m/s)"
        case .tooSlow:
            return "Troppo lento"
        }
    }
}

// MARK: - Preview

#Preview {
    TrainingSelectionView(bleManager: BLEManager())
}
