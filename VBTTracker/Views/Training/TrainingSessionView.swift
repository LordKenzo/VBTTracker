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
            
            // TOAST NOTIFICATION
            if sessionManager.repCount > 0 && sessionManager.isRecording {
                VStack {
                    Spacer()
                    
                    RepToastView(
                        repNumber: sessionManager.repCount,
                        velocity: sessionManager.lastRepPeakVelocity,
                        isInTarget: sessionManager.lastRepInTarget
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.spring(response: 0.5, dampingFraction: 0.7), value: sessionManager.repCount)
                    .padding(.bottom, 100)
                }
            }
        }  // CHIUSURA ZSTACK
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
            // Banner Zona Corrente EVIDENTE
            HStack(spacing: 12) {
                Image(systemName: sessionManager.currentZone.icon)
                    .font(.title)
                    .foregroundStyle(.white)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("ZONA ATTUALE")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white.opacity(0.8))
                    
                    Text(sessionManager.currentZone.rawValue.uppercased())
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                }
                
                Spacer()
                
                // Indicatore animato
                Circle()
                    .fill(.white)
                    .frame(width: 12, height: 12)
                    .opacity(sessionManager.currentVelocity > 0.1 ? 1.0 : 0.3)
                    .animation(.easeInOut(duration: 0.5).repeatForever(), value: sessionManager.currentVelocity)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(sessionManager.currentZone.color)
            )
            .shadow(color: sessionManager.currentZone.color.opacity(0.5), radius: 8, x: 0, y: 4)
            
            // Velocity Display con colore dinamico
            VStack(spacing: 8) {
                Text("VELOCITÀ")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(String(format: "%.3f", sessionManager.currentVelocity))
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .foregroundStyle(sessionManager.currentZone.color)
                        .animation(.easeOut(duration: 0.2), value: sessionManager.currentVelocity)
                    
                    Text("m/s")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(sessionManager.currentZone.color.opacity(0.1))
            )
            
            // Stats Grid
            HStack(spacing: 12) {
                // Peak Velocity
                StatCard(
                    title: "PICCO",
                    value: String(format: "%.3f", sessionManager.peakVelocity),
                    unit: "m/s",
                    color: .purple
                )
                
                // Mean Velocity (if reps > 0)
                if sessionManager.repCount > 0 {
                    StatCard(
                        title: "MEDIA",
                        value: String(format: "%.3f", sessionManager.meanVelocity),
                        unit: "m/s",
                        color: .blue
                    )
                }
            }
            
            // Velocity Loss (if enabled and reps > 1)
            if settings.stopOnVelocityLoss && sessionManager.repCount > 1 {
                VStack(spacing: 8) {
                    HStack {
                        Text("VELOCITY LOSS")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                        
                        Spacer()
                        
                        Text(String(format: "%.1f%%", sessionManager.velocityLoss))
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundStyle(velocityLossColor)
                    }
                    
                    // Progress bar migliorata
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            // Background
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(.systemGray5))
                                .frame(height: 12)
                            
                            // Progress
                            RoundedRectangle(cornerRadius: 6)
                                .fill(
                                    LinearGradient(
                                        colors: [velocityLossColor, velocityLossColor.opacity(0.7)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(
                                    width: min(geometry.size.width * (sessionManager.velocityLoss / settings.velocityLossThreshold), geometry.size.width),
                                    height: 12
                                )
                                .animation(.easeOut(duration: 0.3), value: sessionManager.velocityLoss)
                            
                            // Threshold marker
                            Rectangle()
                                .fill(.white)
                                .frame(width: 2, height: 16)
                                .position(x: geometry.size.width, y: 6)
                        }
                    }
                    .frame(height: 12)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(velocityLossColor.opacity(0.1))
                )
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(radius: 2)
    }
    
    // MARK: - Reps Counter Card
    
    private var repsCounterCard: some View {
        HStack(spacing: 16) {
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 50))
                .foregroundStyle(.blue)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("RIPETIZIONI")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("\(sessionManager.repCount)")
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .foregroundStyle(.blue)
                    
                    // ⭐ NUOVO: Indicatore ultima rep
                    if sessionManager.repCount > 0 {
                        VStack(spacing: 4) {
                            Image(systemName: sessionManager.lastRepInTarget ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .font(.title)
                                .foregroundStyle(sessionManager.lastRepInTarget ? .green : .orange)
                                .symbolEffect(.bounce, value: sessionManager.repCount)
                            
                            Text(sessionManager.lastRepInTarget ? "IN TARGET" : "FUORI TARGET")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundStyle(sessionManager.lastRepInTarget ? .green : .orange)
                        }
                    }
                }
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

// MARK: - Supporting Views

struct StatCard: View {
    let title: String
    let value: String
    let unit: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(color)
                
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(color.opacity(0.1))
        )
    }
}

// MARK: - Rep Toast View

struct RepToastView: View {
    let repNumber: Int
    let velocity: Double
    let isInTarget: Bool
    
    @State private var isVisible = true
    
    var body: some View {
        if isVisible {
            HStack(spacing: 12) {
                Image(systemName: isInTarget ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("REP #\(repNumber)")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white.opacity(0.8))
                    
                    Text(String(format: "%.3f m/s", velocity))
                        .font(.headline)
                        .foregroundStyle(.white)
                }
                
                Text(isInTarget ? "✓" : "✗")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isInTarget ? Color.green : Color.orange)
                    .shadow(color: (isInTarget ? Color.green : Color.orange).opacity(0.5), radius: 10)
            )
            .onAppear {
                // Auto-hide dopo 2 secondi
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    withAnimation {
                        isVisible = false
                    }
                }
            }
        }
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
