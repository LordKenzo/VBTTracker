//
//  TrainingSelectionView.swift
//  VBTTracker
//
//  Selezione obiettivo di allenamento
//

import SwiftUI

struct TrainingSelectionView: View {
    @ObservedObject var bleManager: BLEManager
    @ObservedObject var calibrationManager: CalibrationManager
    @ObservedObject var settings = SettingsManager.shared
    
    @State private var selectedZone: TrainingZone = .strength
    
    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 12) {
                Image(systemName: "target")
                    .font(.system(size: 60))
                    .foregroundStyle(.blue)
                
                Text("Seleziona Obiettivo")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Scegli la zona di allenamento per la tua sessione")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top)
            
            // Training Zones
            ScrollView {
                VStack(spacing: 12) {
                    TrainingZoneCard(
                        zone: .maxStrength,
                        range: settings.velocityRanges.maxStrength,
                        isSelected: selectedZone == .maxStrength
                    ) {
                        selectedZone = .maxStrength
                    }
                    
                    TrainingZoneCard(
                        zone: .strength,
                        range: settings.velocityRanges.strength,
                        isSelected: selectedZone == .strength
                    ) {
                        selectedZone = .strength
                    }
                    
                    TrainingZoneCard(
                        zone: .strengthSpeed,
                        range: settings.velocityRanges.strengthSpeed,
                        isSelected: selectedZone == .strengthSpeed
                    ) {
                        selectedZone = .strengthSpeed
                    }
                    
                    TrainingZoneCard(
                        zone: .speed,
                        range: settings.velocityRanges.speed,
                        isSelected: selectedZone == .speed
                    ) {
                        selectedZone = .speed
                    }
                    
                    TrainingZoneCard(
                        zone: .maxSpeed,
                        range: settings.velocityRanges.maxSpeed,
                        isSelected: selectedZone == .maxSpeed
                    ) {
                        selectedZone = .maxSpeed
                    }
                }
                .padding(.horizontal)
            }
            
            // Start Button - FIXED: iOS 16+ NavigationLink
            NavigationLink(destination: TrainingSessionView(
                bleManager: bleManager,
                targetZone: selectedZone
            )) {
                Label("Inizia Allenamento", systemImage: "play.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal)
        }
        .padding()
        .navigationTitle("Nuovo Allenamento")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Training Zone Card

struct TrainingZoneCard: View {
    let zone: TrainingZone
    let range: ClosedRange<Double>
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                Image(systemName: zone.icon)
                    .font(.title)
                    .foregroundStyle(zone.color)
                    .frame(width: 50)
                
                VStack(alignment: .leading, spacing: 6) {
                    Text(zone.rawValue)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    
                    Text(zone.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    
                    Text("\(String(format: "%.2f", range.lowerBound)) - \(String(format: "%.2f", range.upperBound)) m/s")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(zone.color)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.blue)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? Color.blue.opacity(0.1) : Color(.systemGray6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack {
        TrainingSelectionView(
            bleManager: BLEManager(),
            calibrationManager: CalibrationManager()
        )
    }
}
