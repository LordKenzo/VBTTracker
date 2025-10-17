//
//  TrainingSessionView.swift
//  VBTTracker
//
//  UI COMPATTA con scroll
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
            // Background gradient
            LinearGradient(
                colors: [
                    sessionManager.currentZone.color.opacity(0.15),
                    Color.clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            // ⭐ SCROLL VIEW per tutto il contenuto
            ScrollView {
                VStack(spacing: 16) {
                    
                    // Zona Corrente + Target (compatta)
                    compactZoneCard
                    
                    // Velocità (3 valori in 1 riga)
                    if sessionManager.isRecording {
                        compactVelocityCard
                    }
                    
                    // Grafico Accelerazione
                    if sessionManager.isRecording {
                        compactGraphCard
                    }
                    
                    // Reps Counter
                    compactRepsCard
                    
                    // Velocity Loss (se attivo)
                    if settings.stopOnVelocityLoss && sessionManager.repCount > 1 {
                        velocityLossCard
                    }
                    
                    // Control Buttons
                    controlButtons
                        .padding(.top, 8)
                }
                .padding()
            }
            
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
        }
        .navigationTitle("Allenamento")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(sessionManager.isRecording)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                if sessionManager.isRecording {
                    Button("Termina") {
                        showEndSessionAlert = true
                    }
                    .foregroundStyle(.red)
                    .fontWeight(.semibold)
                } else {
                    // Mostra back button normale
                    EmptyView()
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
    
    // MARK: - Compact Zone Card
    
    private var compactZoneCard: some View {
        HStack(spacing: 12) {
            // Zona Corrente
            HStack(spacing: 8) {
                Image(systemName: sessionManager.currentZone.icon)
                    .foregroundStyle(sessionManager.currentZone.color)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("ZONA")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    
                    Text(sessionManager.currentZone.rawValue)
                        .font(.subheadline)
                        .fontWeight(.bold)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(sessionManager.currentZone.color.opacity(0.15))
            .cornerRadius(10)
            
            // Target
            HStack(spacing: 8) {
                Image(systemName: "target")
                    .foregroundStyle(targetZone.color)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("TARGET")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    
                    Text(targetZone.rawValue)
                        .font(.subheadline)
                        .fontWeight(.bold)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color(.systemGray6))
            .cornerRadius(10)
        }
    }
    
    // MARK: - Compact Velocity Card (3 valori in 1 riga)
    
    private var compactVelocityCard: some View {
        VStack(spacing: 8) {
            HStack {
                Text("VELOCITÀ")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                
                Spacer()
            }
            
            HStack(spacing: 8) {
                // Corrente
                VStack(spacing: 4) {
                    Text("Corrente")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    
                    Text(String(format: "%.2f", sessionManager.currentVelocity))
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundStyle(sessionManager.currentZone.color)
                    
                    Text("m/s")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(sessionManager.currentZone.color.opacity(0.1))
                .cornerRadius(8)
                
                // Picco
                VStack(spacing: 4) {
                    Text("Picco")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    
                    Text(String(format: "%.2f", sessionManager.peakVelocity))
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundStyle(.purple)
                    
                    Text("m/s")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Color.purple.opacity(0.1))
                .cornerRadius(8)
                
                // Media
                if sessionManager.repCount > 0 {
                    VStack(spacing: 4) {
                        Text("Media")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        
                        Text(String(format: "%.2f", sessionManager.meanVelocity))
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundStyle(.blue)
                        
                        Text("m/s")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }
    
    // MARK: - Compact Graph Card
    
    private var compactGraphCard: some View {
        VStack(spacing: 8) {
            HStack {
                Text("SEGNALE ACCELERAZIONE")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                // Indicatore REC
                HStack(spacing: 4) {
                    Circle()
                        .fill(.red)
                        .frame(width: 6, height: 6)
                    
                    Text("REC")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(.red)
                }
            }
            
            RealTimeAccelerationGraph(data: sessionManager.getAccelerationSamples())
                .frame(height: 120) // ⭐ Ridotto da 200 a 120
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }
    
    // MARK: - Compact Reps Card
    
    private var compactRepsCard: some View {
        HStack(spacing: 16) {
            // Icona e numero reps
            HStack(spacing: 12) {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(size: 36))
                    .foregroundStyle(.blue)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("RIPETIZIONI")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Text("\(sessionManager.repCount)")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(.blue)
                }
            }
            
            Spacer()
            
            // Indicatore target ultima rep
            if sessionManager.repCount > 0 {
                VStack(spacing: 6) {
                    Image(systemName: sessionManager.lastRepInTarget ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.title)
                        .foregroundStyle(sessionManager.lastRepInTarget ? .green : .orange)
                    
                    Text(sessionManager.lastRepInTarget ? "IN TARGET" : "FUORI")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(sessionManager.lastRepInTarget ? .green : .orange)
                    
                    Text(String(format: "%.2f m/s", sessionManager.lastRepPeakVelocity))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(
            LinearGradient(
                colors: [Color.blue.opacity(0.1), Color.clear],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .cornerRadius(12)
    }
    
    // MARK: - Velocity Loss Card
    
    private var velocityLossCard: some View {
        VStack(spacing: 8) {
            HStack {
                Text("VELOCITY LOSS")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Text(String(format: "%.1f%%", sessionManager.velocityLoss))
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundStyle(velocityLossColor)
            }
            
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(velocityLossColor)
                        .frame(
                            width: min(
                                geometry.size.width * (sessionManager.velocityLoss / settings.velocityLossThreshold),
                                geometry.size.width
                            )
                        )
                }
            }
            .frame(height: 8)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }
    
    // MARK: - Control Buttons
    
    private var controlButtons: some View {
        VStack(spacing: 12) {
            if sessionManager.isRecording {
                Button(action: {
                    showEndSessionAlert = true
                }) {
                    Label("TERMINA ALLENAMENTO", systemImage: "stop.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            } else {
                Button(action: {
                    sessionManager.startRecording()
                }) {
                    Label("INIZIA", systemImage: "play.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                }
                .buttonStyle(.borderedProminent)
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
    
    // MARK: - Data Stream
    
    private func startDataStream() {
        dataStreamTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            sessionManager.processSensorData(
                acceleration: bleManager.acceleration,
                angularVelocity: bleManager.angularVelocity,
                angles: bleManager.angles,
                isCalibrated: bleManager.isCalibrated
            )
            
            if settings.stopOnVelocityLoss &&
               sessionManager.isRecording &&
               sessionManager.velocityLoss >= settings.velocityLossThreshold {
                sessionManager.stopRecording()
            }
        }
    }
    
    private func stopDataStream() {
        dataStreamTimer?.invalidate()
        dataStreamTimer = nil
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
                    
                    Text(String(format: "%.2f m/s", velocity))
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
