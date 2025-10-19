//
//  CalibrationModeSelectionView.swift
//  VBTTracker
//
//  Created by Lorenzo Franceschini on 19/10/25.
//


//
//  CalibrationModeSelectionView.swift
//  VBTTracker
//
//  Schermata di selezione modalità calibrazione
//

import SwiftUI

struct CalibrationModeSelectionView: View {
    @ObservedObject var calibrationManager: ROMCalibrationManager
    @ObservedObject var bleManager: BLEManager
    @Environment(\.dismiss) var dismiss
    
    @State private var selectedMode: CalibrationMode = .automatic
    @State private var showCalibrationView = false
    
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
                        // Header
                        headerSection
                        
                        // Saved Pattern Info (if exists)
                        if calibrationManager.isCalibrated,
                           let pattern = calibrationManager.learnedPattern {
                            savedPatternCard(pattern)
                        }
                        
                        // Mode Selection Cards
                        VStack(spacing: 16) {
                            Text("Scegli Modalità Calibrazione")
                                .font(.headline)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            
                            // Automatic Mode Card
                            ModeCard(
                                mode: .automatic,
                                isSelected: selectedMode == .automatic
                            ) {
                                selectedMode = .automatic
                            }
                            
                            // Manual Mode Card
                            ModeCard(
                                mode: .manual,
                                isSelected: selectedMode == .manual
                            ) {
                                selectedMode = .manual
                            }
                        }
                        
                        // Action Buttons
                        actionButtons
                    }
                    .padding()
                }
            }
            .navigationTitle("Calibrazione ROM")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Chiudi") {
                        dismiss()
                    }
                }
            }
            .fullScreenCover(isPresented: $showCalibrationView) {
                if selectedMode == .automatic {
                    AutomaticCalibrationView(
                        calibrationManager: calibrationManager,
                        bleManager: bleManager
                    )
                } else {
                    ManualCalibrationView(
                        calibrationManager: calibrationManager,
                        bleManager: bleManager
                    )
                }
            }
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "figure.mind.and.body")
                .font(.system(size: 60))
                .foregroundStyle(.blue)
            
            Text("Calibrazione Range of Motion")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(.white)
            
            Text("Impara il pattern del tuo movimento per un rilevamento più accurato delle ripetizioni")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(16)
    }
    
    // MARK: - Saved Pattern Card
    
    private func savedPatternCard(_ pattern: LearnedPattern) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                
                Text("Calibrazione Salvata")
                    .font(.headline)
                    .foregroundStyle(.white)
                
                Spacer()
                
                Button(action: {
                    calibrationManager.deletePattern()
                }) {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
            }
            
            Divider()
                .background(.white.opacity(0.3))
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Modalità:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(pattern.calibrationMode.displayName)
                        .font(.caption)
                        .fontWeight(.medium)
                }
                
                HStack {
                    Text("Data:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(pattern.shortDescription)
                        .font(.caption)
                        .fontWeight(.medium)
                }
                
                HStack {
                    Text("ROM:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.0f cm", pattern.estimatedROM * 100))
                        .font(.caption)
                        .fontWeight(.medium)
                }
            }
            
            Button(action: {
                // Usa pattern esistente
                dismiss()
            }) {
                Text("Usa Questa Calibrazione")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.bordered)
            .tint(.green)
        }
        .padding()
        .background(Color.green.opacity(0.1))
        .cornerRadius(12)
    }
    
    // MARK: - Action Buttons
    
    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button(action: {
                calibrationManager.selectMode(selectedMode)
                showCalibrationView = true
            }) {
                HStack {
                    Image(systemName: "play.circle.fill")
                    Text("Inizia Calibrazione \(selectedMode.displayName)")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            
            if !calibrationManager.isCalibrated {
                Button(action: {
                    calibrationManager.skipCalibration()
                    dismiss()
                }) {
                    Text("Salta Calibrazione (usa default)")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
    }
}

// MARK: - Mode Card

struct ModeCard: View {
    let mode: CalibrationMode
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(mode.color.opacity(0.2))
                            .frame(width: 50, height: 50)
                        
                        Image(systemName: mode.icon)
                            .font(.title2)
                            .foregroundStyle(mode.color)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(mode.displayName)
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                        
                        Text(featuresSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    // Selection indicator
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.green)
                    } else {
                        Image(systemName: "circle")
                            .font(.title2)
                            .foregroundStyle(.gray)
                    }
                }
                
                // Description
                Text(mode.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                
                // Features
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(features, id: \.self) { feature in
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(mode.color)
                            
                            Text(feature)
                                .font(.caption)
                                .foregroundStyle(.white)
                        }
                    }
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? mode.color.opacity(0.15) : Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(isSelected ? mode.color : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
    
    private var featuresSummary: String {
        switch mode {
        case .automatic: return "Veloce e semplice"
        case .manual: return "Precisa e dettagliata"
        }
    }
    
    private var features: [String] {
        switch mode {
        case .automatic:
            return [
                "2 ripetizioni complete",
                "Rilevamento automatico",
                "~30 secondi"
            ]
        case .manual:
            return [
                "5 step guidati",
                "Controllo assistente",
                "Massima precisione"
            ]
        }
    }
}

// MARK: - Preview

#Preview("With Saved Pattern") {
    CalibrationModeSelectionView(
        calibrationManager: .previewCompleted,
        bleManager: BLEManager()
    )
}

#Preview("No Pattern") {
    CalibrationModeSelectionView(
        calibrationManager: ROMCalibrationManager(),
        bleManager: BLEManager()
    )
}