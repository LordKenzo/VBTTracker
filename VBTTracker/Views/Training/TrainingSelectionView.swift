//
//  TrainingSelectionView.swift
//  VBTTracker
//
//  STEP 2.5: Rimossa calibrazione ROM - mantiene solo selezione zona
//

import SwiftUI

struct TrainingSelectionView: View {
    @ObservedObject var sensorManager: UnifiedSensorManager

    @State private var selectedZone: TrainingZone = .strength
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
            .navigationDestination(isPresented: $navigateToSession) {
                RepTargetSelectionView(
                    sensorManager: sensorManager,
                    targetZone: selectedZone
                )
            }
        }
    }
    
    // MARK: - Sensor Status Card
    
    private var sensorStatusCard: some View {
        HStack(spacing: 16) {
            Circle()
                .fill(sensorManager.isConnected ? Color.green : Color.red)
                .frame(width: 12, height: 12)

            VStack(alignment: .leading, spacing: 4) {
                Text("Sensore")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(sensorManager.sensorName)
                    .font(.headline)
                    .foregroundStyle(.white)
            }

            Spacer()

            if sensorManager.isCalibrated {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(sensorManager.currentSensorType == .witmotion ? "Calibrato" : "Pronto")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
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
            .disabled(!sensorManager.isConnected)

            if !sensorManager.isConnected {
                Text("Connetti il sensore per continuare")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }
    
    // MARK: - Actions
    
    private func startTraining() {
        navigateToSession = true
    }
}

// MARK: - Supporting Views

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
                    
                    Text(zone.detailedDescription)
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
    
    var detailedDescription: String {
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
    TrainingSelectionView(sensorManager: UnifiedSensorManager())
}
