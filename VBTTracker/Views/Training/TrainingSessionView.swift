//
//  TrainingSessionView.swift
//  VBTTracker
//
//  UI FINALE con layout: Reps+Target in alto, Zona in basso
//

import SwiftUI

struct TrainingSessionView: View {
    @ObservedObject var bleManager: BLEManager
    let targetZone: TrainingZone
    let targetReps: Int
    @ObservedObject var settings = SettingsManager.shared

    
    @StateObject private var sessionManager = TrainingSessionManager()
    @Environment(\.dismiss) var dismiss
    
    @State private var dataStreamTimer: Timer?
    @State private var showEndSessionAlert = false
    
    @State private var showSummary = false
    @State private var sessionData: TrainingSessionData?
    
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
            
            ScrollView {
                VStack(spacing: 16) {
                    
                    // 1. REPS + TARGET (in alto)
                    repsAndTargetCard
                    
                    // 2. VELOCITÀ
                    if sessionManager.isRecording {
                        compactVelocityCard
                    }
                    
                    // 3. GRAFICO
                    if sessionManager.isRecording {
                        compactGraphCard
                    }
                    
                    // 4. FEEDBACK ULTIMA REP (solo se ha fatto almeno 1 rep)
                    if sessionManager.isRecording && sessionManager.repCount > 0 {
                        lastRepFeedbackCard
                    }
                    
                    // 5. VELOCITY LOSS
                    if settings.stopOnVelocityLoss && sessionManager.repCount > 1 {
                        velocityLossCard
                    }
                    
                    // 6. PULSANTI
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
        .navigationBarItems(leading:
            sessionManager.isRecording ?
            AnyView(
                Button("Termina") {
                    showEndSessionAlert = true
                }
                .foregroundColor(.red)
                .fontWeight(.semibold)
            ) : AnyView(EmptyView())
        )
        .onAppear {
            sessionManager.targetZone = targetZone
            
            // Carica pattern ROM
            if let data = UserDefaults.standard.data(forKey: "learnedPattern"),
               let pattern = try? JSONDecoder().decode(LearnedPattern.self, from: data) {
                sessionManager.repDetector.learnedPattern = pattern
                print("📂 Pattern ROM caricato: \(String(format: "%.0fcm", pattern.estimatedROM * 100))")
            }
            
            startDataStream()
            
            // ✅ AGGIUNGI: Avvia automaticamente la sessione
            sessionManager.startRecording()
        }
        .onDisappear {
            stopDataStream()
        }
        .alert("Terminare Sessione?", isPresented: $showEndSessionAlert) {
            Button("Annulla", role: .cancel) { }
            Button("Termina", role: .destructive) {
                // Crea session data PRIMA di stoppare
                sessionData = sessionManager.createSessionData()
                sessionManager.stopRecording()
                showSummary = true
            }
        } message: {
            Text("Ripetizioni completate: \(sessionManager.repCount)/\(targetReps)")
        }
        .sheet(isPresented: $showSummary) {
            if let data = sessionData {
                TrainingSummaryView(sessionData: data)
            }
        }
    }
    
    // MARK: - 1. Reps + Target Card
    private var progress: Double {
        guard targetReps > 0 else { return 0 }
        return min(Double(sessionManager.repCount) / Double(targetReps), 1.0)
    }

    private var progressColor: Color {
        if progress < 0.3 {
            return .orange
        } else if progress < 0.7 {
            return .yellow
        } else if progress >= 1.0 {
            return .green
        } else {
            return .blue
        }
    }
    
    private var repsAndTargetCard: some View {
        HStack(spacing: 20) {
            // REPS
            VStack(spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.title3)
                        .foregroundStyle(.blue)
                    Text("REPS")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                }
                
                // ✅ MOSTRA PROGRESSO
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(sessionManager.repCount)")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    
                    Text("/ \(targetReps)")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                
                // Progress bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color.white.opacity(0.1))
                            .frame(height: 4)
                            .cornerRadius(2)
                        
                        Rectangle()
                            .fill(progressColor)
                            .frame(width: geometry.size.width * progress, height: 4)
                            .cornerRadius(2)
                            .animation(.easeInOut, value: sessionManager.repCount)
                    }
                }
                .frame(height: 4)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.white.opacity(0.05))
            .cornerRadius(16)
            
            // TARGET ZONE
            VStack(spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Image(systemName: "target")
                        .font(.title3)
                        .foregroundStyle(sessionManager.targetZone.color)
                    Text("TARGET")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                }
                
                Text(sessionManager.targetZone.rawValue)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.white.opacity(0.05))
            .cornerRadius(16)
        }
    }
    
    // MARK: - 2. Velocità Card
    
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
    
    // MARK: - 3. Grafico Card
    
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
                .frame(height: 120)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }
    
    // MARK: - 4. Feedback Ultima Rep Card
    
    private var lastRepFeedbackCard: some View {
        HStack(spacing: 16) {
            // Info Rep
            VStack(alignment: .leading, spacing: 6) {
                Text("ULTIMA RIPETIZIONE")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(String(format: "%.2f", sessionManager.lastRepPeakVelocity))
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    
                    Text("m/s")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                
                // Zona della rep
                Text(getZoneForVelocity(sessionManager.lastRepPeakVelocity))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Badge Target (GRANDE e CHIARO)
            VStack(spacing: 8) {
                Image(systemName: sessionManager.lastRepInTarget ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(sessionManager.lastRepInTarget ? .green : .orange)
                
                Text(sessionManager.lastRepInTarget ? "IN TARGET" : "FUORI TARGET")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(sessionManager.lastRepInTarget ? .green : .orange)
            }
            .padding(.horizontal, 12)
        }
        .padding()
        .background(
            (sessionManager.lastRepInTarget ? Color.green : Color.orange).opacity(0.1)
        )
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(sessionManager.lastRepInTarget ? Color.green : Color.orange, lineWidth: 2)
        )
    }
    
    // Helper per ottenere zona dalla velocità
    private func getZoneForVelocity(_ velocity: Double) -> String {
        let zone = SettingsManager.shared.getTrainingZone(for: velocity)
        return zone.rawValue
    }
    
    // MARK: - 5. Velocity Loss Card
    
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
    
    // MARK: - 6. Control Buttons
    
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
        dataStreamTimer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { _ in
            sessionManager.processSensorData(
                acceleration: bleManager.acceleration,
                angularVelocity: bleManager.angularVelocity,
                angles: bleManager.angles,
                isCalibrated: bleManager.isCalibrated
            )
            
            // Check velocity loss
            if settings.stopOnVelocityLoss &&
               sessionManager.isRecording &&
               sessionManager.velocityLoss >= settings.velocityLossThreshold {
                sessionManager.stopRecording()
            }
            
            // Auto-stop al raggiungimento target
            /*
            if sessionManager.isRecording &&
               sessionManager.repCount >= self.targetReps {
                sessionManager.stopRecording()
                
                // Vibrazione + feedback
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
            }
             */
            // Notifica visiva al raggiungimento target
            if sessionManager.isRecording &&
               sessionManager.repCount == self.targetReps {
                
                // Haptic feedback
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
                
                // Voice feedback opzionale
                // voiceFeedback.announce("Target raggiunto")
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
            targetZone: .strength,
            targetReps: 5
        )
    }
}
