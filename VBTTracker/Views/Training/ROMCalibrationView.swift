//
//  ROMCalibrationView.swift
//  VBTTracker
//
//  UI per calibrazione ROM e pattern learning
//

import SwiftUI

struct ROMCalibrationView: View {
    @ObservedObject var calibrationManager: ROMCalibrationManager
    @ObservedObject var bleManager: BLEManager
    @Environment(\.dismiss) var dismiss
    
    @State private var dataStreamTimer: Timer?
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background gradient
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
                        
                        // State-based content
                        switch calibrationManager.calibrationState {
                        case .idle:
                            setupInstructions
                        case .waitingForFirstRep, .detectingReps:
                            executionView
                        case .analyzing:
                            analyzingView
                        case .waitingForLoad:
                            loadBarbellView
                        case .completed:
                            completedView
                        case .failed(let error):
                            errorView(error)
                        }
                        
                        // Actions
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
                        stopDataStream()
                        dismiss()
                    }
                }
            }
            .onAppear {
                startDataStream()
            }
            .onDisappear {
                stopDataStream()
            }
        }
    }
    
    // MARK: - Header
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: calibrationIcon)
                .font(.system(size: 60))
                .foregroundStyle(calibrationColor)
            
            Text(calibrationManager.statusMessage)
                .font(.headline)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            
            if calibrationManager.calibrationProgress > 0 &&
               calibrationManager.calibrationProgress < 1.0 {
                ProgressView(value: calibrationManager.calibrationProgress)
                    .progressViewStyle(.linear)
                    .tint(.blue)
            }
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(16)
    }
    
    // MARK: - Setup Instructions
    
    private var setupInstructions: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("📋 Preparazione")
                .font(.title3)
                .fontWeight(.bold)
            
            InstructionRow(
                number: "1",
                text: "Carica bilanciere LEGGERO",
                detail: "Usa solo il bilanciere o carico minimo"
            )
            
            InstructionRow(
                number: "2",
                text: "Posizionati correttamente",
                detail: "Come faresti normalmente nell'esercizio"
            )
            
            InstructionRow(
                number: "3",
                text: "Esegui 2 ripetizioni",
                detail: "Lente e controllate, ROM completo"
            )
            
            Divider()
                .background(.white.opacity(0.3))
            
            HStack(spacing: 8) {
                Image(systemName: "lightbulb.fill")
                    .foregroundStyle(.yellow)
                Text("Tip: Queste rep servono solo per imparare il tuo movimento, non affaticarti!")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
    }
    
    // MARK: - Execution View
    
    private var executionView: some View {
        VStack(spacing: 16) {
            // Rep Counter
            HStack(spacing: 20) {
                ForEach(0..<2, id: \.self) { index in
                    let isCompleted = Double(index) < calibrationManager.calibrationProgress * 2
                    
                    Circle()
                        .fill(isCompleted ? Color.green : Color.white.opacity(0.2))
                        .frame(width: 60, height: 60)
                        .overlay {
                            Text("\(index + 1)")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundStyle(.white)
                        }
                }
            }
            
            // Live acceleration graph (mini version)
            if bleManager.isConnected {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Accelerazione Live")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Text("\(String(format: "%.2f", bleManager.acceleration[2])) g")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundStyle(accelColor(bleManager.acceleration[2]))
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.white.opacity(0.05))
                .cornerRadius(12)
            }
            
            Text("Esegui le ripetizioni con calma")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
    }
    
    // MARK: - Analyzing View
    
    private var analyzingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            
            Text("Analisi pattern in corso...")
                .font(.headline)
            
            Text("Calcolo ROM e parametri ottimali")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
    }
    
    // MARK: - Load Barbell View
    
    private var loadBarbellView: some View {
        VStack(spacing: 20) {
            if let pattern = calibrationManager.learnedPattern {
                // Risultati calibrazione
                VStack(alignment: .leading, spacing: 12) {
                    Text("✅ Pattern Appreso")
                        .font(.title3)
                        .fontWeight(.bold)
                    
                    Divider()
                    
                    PatternRow(label: "Ampiezza", value: String(format: "%.2f g", pattern.avgAmplitude))
                    PatternRow(label: "Durata concentrica", value: String(format: "%.2f s", pattern.avgConcentricDuration))
                    PatternRow(label: "Velocità media", value: String(format: "%.2f m/s", pattern.avgPeakVelocity))
                    PatternRow(label: "ROM stimato", value: String(format: "%.0f cm", pattern.estimatedROM * 100))
                }
                .padding()
                .background(Color.green.opacity(0.1))
                .cornerRadius(12)
            }
            
            // Istruzioni caricamento
            VStack(spacing: 12) {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(size: 50))
                    .foregroundStyle(.blue)
                
                Text("Ora carica il bilanciere")
                    .font(.headline)
                
                Text("Rileverò automaticamente quando sei pronto")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .background(Color.white.opacity(0.05))
            .cornerRadius(12)
        }
    }
    
    // MARK: - Completed View
    
    private var completedView: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.green)
            
            Text("Calibrazione Completata!")
                .font(.title2)
                .fontWeight(.bold)
            
            if let pattern = calibrationManager.learnedPattern {
                VStack(spacing: 8) {
                    Text("Il sistema userà questi parametri:")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    HStack(spacing: 20) {
                        StatBadge(label: "ROM", value: String(format: "%.0fcm", pattern.estimatedROM * 100))
                        StatBadge(label: "Soglia", value: String(format: "%.2fg", pattern.dynamicMinAmplitude))
                    }
                }
            }
            
            Button(action: {
                dismiss()
            }) {
                Label("Inizia Allenamento", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding()
    }
    
    // MARK: - Error View
    
    private func errorView(_ error: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.red)
            
            Text("Errore")
                .font(.title2)
                .fontWeight(.bold)
            
            Text(error)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .background(Color.red.opacity(0.1))
        .cornerRadius(12)
    }
    
    // MARK: - Action Buttons
    
    private var actionButtons: some View {
        VStack(spacing: 12) {
            if calibrationManager.calibrationState == .idle {
                Button(action: {
                    calibrationManager.startCalibration()
                }) {
                    Label("Inizia Calibrazione", systemImage: "play.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                
                Button(action: {
                    calibrationManager.skipCalibration()
                }) {
                    Text("Salta (usa impostazioni default)")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            
            if calibrationManager.calibrationState == .detectingReps ||
               calibrationManager.calibrationState == .waitingForFirstRep {
                Button(action: {
                    calibrationManager.reset()
                }) {
                    Label("Ricomincia", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            
            if case .failed = calibrationManager.calibrationState {
                Button(action: {
                    calibrationManager.reset()
                    calibrationManager.startCalibration()
                }) {
                    Label("Riprova", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
    }
    
    // MARK: - Helpers
    
    private var calibrationIcon: String {
        switch calibrationManager.calibrationState {
        case .idle:
            return "figure.mind.and.body"
        case .waitingForFirstRep, .detectingReps:
            return "figure.strengthtraining.traditional"
        case .analyzing:
            return "brain.head.profile"
        case .waitingForLoad:
            return "figure.cooldown"
        case .completed:
            return "checkmark.circle.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        }
    }
    
    private var calibrationColor: Color {
        switch calibrationManager.calibrationState {
        case .idle:
            return .blue
        case .waitingForFirstRep, .detectingReps:
            return .orange
        case .analyzing:
            return .purple
        case .waitingForLoad:
            return .cyan
        case .completed:
            return .green
        case .failed:
            return .red
        }
    }
    
    private func accelColor(_ value: Double) -> Color {
        if abs(value) < 0.2 {
            return .gray
        } else if value > 0 {
            return .green
        } else {
            return .red
        }
    }
    
    // MARK: - Data Stream
    
    private func startDataStream() {
        guard bleManager.isConnected else { return }
        
        dataStreamTimer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { _ in
            let accZ = bleManager.acceleration[2]
            let timestamp = Date()
            
            calibrationManager.processSample(accZ: accZ, timestamp: timestamp)
        }
    }
    
    private func stopDataStream() {
        dataStreamTimer?.invalidate()
        dataStreamTimer = nil
    }
}

// MARK: - Supporting Views

struct PatternRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Spacer()
            
            Text(value)
                .font(.headline)
                .foregroundStyle(.white)
        }
    }
}

struct StatBadge: View {
    let label: String
    let value: String
    
    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(.white)
            
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color.white.opacity(0.1))
        .cornerRadius(12)
    }
}

// MARK: - Preview

#Preview {
    ROMCalibrationView(
        calibrationManager: ROMCalibrationManager(),
        bleManager: BLEManager()
    )
}
