//
//  TrainingSessionView.swift
//  VBTTracker
//
//  Created by Lorenzo Franceschini on 17/10/25.
//


//
//  TrainingSessionView.swift
//  VBTTracker
//
//  View principale della sessione di allenamento con feedback real-time
//

import SwiftUI

struct TrainingSessionView: View {
    @ObservedObject var bleManager: BLEManager
    let targetZone: TrainingZone
    @ObservedObject var settings = SettingsManager.shared
    
    @StateObject private var sessionManager = TrainingSessionManager()
    @Environment(\.dismiss) var dismiss
    
    @State private var dataStreamTimer: Timer?
    @State private var showEndSessionAlert = false
    
    var body: some View {
        ZStack {
            // Background gradient based on current zone
            LinearGradient(
                colors: [
                    sessionManager.currentZone.color.opacity(0.2),

                    sessionManager.currentZone.color.opacity(0.05),

                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 20) {
                // Target Zone Info
                targetZoneCard
                
                // Real-time Metrics
                if sessionManager.isRecording {
                    currentMetricsCard
                }
                
                // Reps Counter
                repsCounterCard
                
                Spacer()
                
                // Control Buttons
                controlButtons
            }
            .padding()
        }
        .navigationTitle("Allenamento")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(sessionManager.isRecording)
        .toolbar {
            if sessionManager.isRecording {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Termina") {
                        showEndSessionAlert = true
                    }
                    .foregroundStyle(.red)
                }
            }
        }
        .onAppear {
            sessionManager.targetZone = targetZone
            startDataStream()
        }
        .onDisappear {
            stopDataStream()
        }
        .alert("Terminare Sessione?", isPresented: $showEndSessionAlert) {
            Button("Annulla", role: .cancel) { }
            Button("Termina", role: .destructive) {
                sessionManager.stopRecording()
                dismiss()
            }
        } message: {
            Text("La sessione verrà salvata. Ripetizioni: \(sessionManager.repCount)")
        }
    }
    
    // MARK: - Target Zone Card
    
    private var targetZoneCard: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: targetZone.icon)
                    .font(.title)
                    .foregroundStyle(targetZone.color)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Obiettivo: \(targetZone.rawValue)")
                        .font(.headline)
                    
                    Text(targetZone.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
            }
            
            // Target Range
            let range = getRangeForZone(targetZone)
            HStack {
                Text("Range Obiettivo")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Text("\(String(format: "%.2f", range.lowerBound)) - \(String(format: "%.2f", range.upperBound)) m/s")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(targetZone.color)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(radius: 2)
    }
    
    // MARK: - Current Metrics Card
    
    private var currentMetricsCard: some View {
        VStack(spacing: 16) {
            // Current Zone Indicator
            HStack {
                Circle()
                    .fill(sessionManager.currentZone.color)
                    .frame(width: 12, height: 12)
                
                Text("Zona Attuale: \(sessionManager.currentZone.rawValue)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Spacer()
            }
            
            // Velocity Display
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(String(format: "%.3f", sessionManager.currentVelocity))
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(sessionManager.currentZone.color)
                
                Text("m/s")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            
            // Peak Velocity
            HStack {
                Text("Velocità Picco")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Text(String(format: "%.3f m/s", sessionManager.peakVelocity))
                    .font(.headline)
                    .foregroundStyle(.purple)
            }
            
            // Mean Velocity (if reps > 0)
            if sessionManager.repCount > 0 {
                HStack {
                    Text("Velocità Media")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    Text(String(format: "%.3f m/s", sessionManager.meanVelocity))
                        .font(.headline)
                        .foregroundStyle(.blue)
                }
            }
            
            // Velocity Loss (if enabled and reps > 1)
            if settings.stopOnVelocityLoss && sessionManager.repCount > 1 {
                VStack(spacing: 8) {
                    HStack {
                        Text("Velocity Loss")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Spacer()
                        
                        Text(String(format: "%.1f%%", sessionManager.velocityLoss))
                            .font(.headline)
                            .foregroundStyle(velocityLossColor)
                    }
                    
                    // Progress bar
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(Color(.systemGray5))
                                .frame(height: 8)
                                .cornerRadius(4)
                            
                            Rectangle()
                                .fill(velocityLossColor)
                                .frame(
                                    width: min(geometry.size.width * (sessionManager.velocityLoss / settings.velocityLossThreshold), geometry.size.width),
                                    height: 8
                                )
                                .cornerRadius(4)
                        }
                    }
                    .frame(height: 8)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(radius: 2)
    }
    
    // MARK: - Reps Counter Card
    
    private var repsCounterCard: some View {
        HStack {
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 50))
                .foregroundStyle(.blue)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Ripetizioni")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Text("\(sessionManager.repCount)")
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .foregroundStyle(.blue)
            }
            
            Spacer()
        }
        .padding()
        .background(
            LinearGradient(
                colors: [Color.blue.opacity(0.15), Color.blue.opacity(0.05)],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .cornerRadius(16)
    }
    
    // MARK: - Control Buttons
    
    private var controlButtons: some View {
        VStack(spacing: 12) {
            if sessionManager.isRecording {
                Button(action: {
                    sessionManager.stopRecording()
                    // TODO: Save session and show summary
                    dismiss()
                }) {
                    Label("Stop Allenamento", systemImage: "stop.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.large)
            } else {
                Button(action: {
                    sessionManager.startRecording()
                }) {
                    Label("Inizia", systemImage: "play.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
    }
    
    // MARK: - Helpers
    
    private var velocityLossColor: Color {
        let loss = sessionManager.velocityLoss
        let threshold = settings.velocityLossThreshold
        
        if loss < threshold * 0.5 {
            return .green
        } else if loss < threshold * 0.8 {
            return .orange
        } else {
            return .red
        }
    }
    
    private func getRangeForZone(_ zone: TrainingZone) -> ClosedRange<Double> {
        switch zone {
        case .maxStrength:
            return settings.velocityRanges.maxStrength
        case .strength:
            return settings.velocityRanges.strength
        case .strengthSpeed:
            return settings.velocityRanges.strengthSpeed
        case .speed:
            return settings.velocityRanges.speed
        case .maxSpeed:
            return settings.velocityRanges.maxSpeed
        case .tooSlow:
            return 0.0...0.15
        }
    }
    
    // MARK: - Data Stream
    
    private func startDataStream() {
        dataStreamTimer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { _ in
            sessionManager.processSensorData(
                acceleration: bleManager.acceleration,
                angularVelocity: bleManager.angularVelocity,
                angles: bleManager.angles,
                isCalibrated: bleManager.isCalibrated
            )
            
            // Check velocity loss threshold
            if settings.stopOnVelocityLoss &&
               sessionManager.isRecording &&
               sessionManager.velocityLoss >= settings.velocityLossThreshold {
                sessionManager.stopRecording()
                // TODO: Voice feedback "Velocity loss raggiunta"
            }
        }
    }
    
    private func stopDataStream() {
        dataStreamTimer?.invalidate()
        dataStreamTimer = nil
    }
}

#Preview {
    NavigationStack {
        TrainingSessionView(
            bleManager: BLEManager(),
            targetZone: .strength
        )
    }
}
