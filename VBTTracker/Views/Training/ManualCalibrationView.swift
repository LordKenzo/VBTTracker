//
//  ManualCalibrationView.swift
//  VBTTracker
//
//  UI per calibrazione manuale (5 step guidati)
//

import SwiftUI

struct ManualCalibrationView: View {
    @ObservedObject var calibrationManager: ROMCalibrationManager
    @ObservedObject var bleManager: BLEManager
    @Environment(\.dismiss) var dismiss
    
    @State private var dataStreamTimer: Timer?
    
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
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Progress Header
                        progressHeader
                        
                        // State-based content
                        switch calibrationManager.manualState {
                        case .idle:
                            welcomeView
                        case .instructionsShown(let step):
                            instructionsView(for: step)
                        case .recording(let step):
                            recordingView(for: step)
                        case .stepCompleted(let step):
                            stepCompletedView(for: step)
                        case .analyzing:
                            analyzingView
                        case .completed:
                            completedView
                        case .failed(let error):
                            errorView(error)
                        }
                    }
                    .padding()
                }
                
                // MARK: - Floating Recording Button
                if case .instructionsShown = calibrationManager.manualState {
                    VStack {
                        Spacer()
                        
                        startRecordingButton
                            .padding(.bottom, 40)
                    }
                }
                
                // MARK: - Floating Stop Button
                if case .recording = calibrationManager.manualState {
                    VStack {
                        Spacer()
                        
                        stopRecordingButton
                            .padding(.bottom, 40)
                    }
                }
            }
            .navigationTitle("Calibrazione Manuale")
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
    
    // MARK: - Progress Header
    
    private var progressHeader: some View {
        VStack(spacing: 12) {
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.1))
                        .frame(height: 8)
                    
                    // Progress
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * calibrationManager.calibrationProgress, height: 8)
                }
            }
            .frame(height: 8)
            
            // Step indicator
            HStack {
                Text(calibrationManager.currentStepProgress)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                
                Spacer()
                
                Text("\(Int(calibrationManager.calibrationProgress * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
    }
    
    // MARK: - Welcome View
    
    private var welcomeView: some View {
        VStack(spacing: 20) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 60))
                .foregroundStyle(.purple)
            
            Text("Calibrazione Manuale")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Verrai guidato attraverso 5 step per registrare il pattern del movimento con massima precisione.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            Divider()
                .background(.white.opacity(0.3))
            
            VStack(alignment: .leading, spacing: 12) {
                Text("⚠️ Richiede Assistente")
                    .font(.headline)
                
                Text("Per questa calibrazione avrai bisogno di un'altra persona che tenga premuto il pulsante REGISTRA durante le fasi di movimento.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding()
            .background(Color.orange.opacity(0.1))
            .cornerRadius(12)
            
            Button(action: {
                calibrationManager.startManualCalibration()
            }) {
                Label("Inizia Calibrazione", systemImage: "play.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            
            Button(action: {
                dismiss()
            }) {
                Text("Annulla")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
        .padding()
    }
    
    // MARK: - Instructions View
    
    private func instructionsView(for step: ManualCalibrationStep) -> some View {
        VStack(spacing: 20) {
            // Step icon and title
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(step.color.opacity(0.2))
                        .frame(width: 80, height: 80)
                    
                    Image(systemName: step.icon)
                        .font(.system(size: 40))
                        .foregroundStyle(step.color)
                }
                
                Text(step.title)
                    .font(.title2)
                    .fontWeight(.bold)
            }
            
            // Instructions
            VStack(alignment: .leading, spacing: 16) {
                Text("Istruzioni:")
                    .font(.headline)
                
                Text(step.instructions)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding()
            .background(Color.white.opacity(0.05))
            .cornerRadius(12)
        }
    }
    
    // MARK: - Recording View
    
    private func recordingView(for step: ManualCalibrationStep) -> some View {
        VStack(spacing: 24) {
            // Recording indicator
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.2))
                    .frame(width: 120, height: 120)
                
                Circle()
                    .fill(Color.red)
                    .frame(width: 80, height: 80)
                    .overlay {
                        Image(systemName: "record.circle")
                            .font(.system(size: 50))
                            .foregroundStyle(.white)
                    }
            }
            .scaleEffect(calibrationManager.isRecordingStep ? 1.1 : 1.0)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: calibrationManager.isRecordingStep)
            
            VStack(spacing: 8) {
                Text("🔴 REGISTRAZIONE")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundStyle(.red)
                
                Text(step.shortTitle)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                
                Text("Premi STOP quando il movimento è completato")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }
    
    // MARK: - Step Completed View
    
    private func stepCompletedView(for step: ManualCalibrationStep) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.green)
            
            Text("Step Completato!")
                .font(.title2)
                .fontWeight(.bold)
            
            if let recording = calibrationManager.manualStepData[step] {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Dati Registrati:")
                        .font(.headline)
                    
                    Divider()
                    
                    HStack {
                        Text("Durata:")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "%.2f s", recording.duration))
                            .fontWeight(.medium)
                    }
                    
                    HStack {
                        Text("Campioni:")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(recording.sampleCount)")
                            .fontWeight(.medium)
                    }
                    
                    HStack {
                        Text("Ampiezza:")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "%.2f g", recording.amplitude))
                            .fontWeight(.medium)
                    }
                }
                .padding()
                .background(Color.green.opacity(0.1))
                .cornerRadius(12)
            }
            
            if !step.isLastStep {
                Button(action: {
                    calibrationManager.nextManualStep()
                }) {
                    Label("Prossimo Step", systemImage: "arrow.right.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
    }
    
    // MARK: - Analyzing View
    
    private var analyzingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            
            Text("Analisi Dati in Corso...")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Elaborazione pattern da 5 step")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            VStack(alignment: .leading, spacing: 8) {
                ForEach(ManualCalibrationStep.allCases, id: \.self) { step in
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        
                        Text(step.shortTitle)
                            .font(.caption)
                        
                        Spacer()
                        
                        if let recording = calibrationManager.manualStepData[step] {
                            Text("\(recording.sampleCount) campioni")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding()
            .background(Color.white.opacity(0.05))
            .cornerRadius(12)
        }
        .padding()
    }
    
    // MARK: - Completed View
    
    private var completedView: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 80))
                .foregroundStyle(.green)
            
            Text("Calibrazione Completata!")
                .font(.title)
                .fontWeight(.bold)
            
            if let pattern = calibrationManager.learnedPattern {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Pattern Manuale Appreso:")
                        .font(.headline)
                    
                    Divider()
                    
                    PatternRow(label: "Ampiezza concentrica", value: String(format: "%.2f g", pattern.avgAmplitude))
                    PatternRow(label: "Durata concentrica", value: String(format: "%.2f s", pattern.avgConcentricDuration))
                    PatternRow(label: "Durata eccentrica", value: String(format: "%.2f s", pattern.avgEccentricDuration))
                    PatternRow(label: "Velocità media", value: String(format: "%.2f m/s", pattern.avgPeakVelocity))
                    PatternRow(label: "ROM stimato", value: String(format: "%.0f cm", pattern.estimatedROM * 100))
                }
                .padding()
                .background(Color.green.opacity(0.1))
                .cornerRadius(12)
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
            
            Button(action: {
                calibrationManager.reset()
                calibrationManager.startManualCalibration()
            }) {
                Label("Riprova", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding()
        .background(Color.red.opacity(0.1))
        .cornerRadius(12)
    }
    
    // MARK: - Recording Buttons
    
    private var startRecordingButton: some View {
        Button(action: {
            calibrationManager.startRecordingStep()
        }) {
            ZStack {
                Circle()
                    .fill(Color.green)
                    .frame(width: 100, height: 100)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.white.opacity(0.5), lineWidth: 3)
                    )
                
                VStack(spacing: 4) {
                    Image(systemName: "record.circle")
                        .font(.system(size: 50))
                        .foregroundStyle(.white)
                    
                    Text("START")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                }
            }
            .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
        }
        .buttonStyle(.plain)
    }
    
    private var stopRecordingButton: some View {
        Button(action: {
            calibrationManager.stopRecordingStep()
        }) {
            ZStack {
                Circle()
                    .fill(Color.red)
                    .frame(width: 100, height: 100)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.white.opacity(0.5), lineWidth: 3)
                    )
                
                VStack(spacing: 4) {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 50))
                        .foregroundStyle(.white)
                    
                    Text("STOP")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                }
            }
            .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Data Stream
    
    private func startDataStream() {
        guard bleManager.isConnected else { return }
        
        dataStreamTimer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { _ in
            let accZ = bleManager.acceleration[2]
            let timestamp = Date()
            calibrationManager.processManualSample(accZ: accZ, timestamp: timestamp)
        }
    }
    
    private func stopDataStream() {
        dataStreamTimer?.invalidate()
        dataStreamTimer = nil
    }
}

#Preview("Instructions") {
    ManualCalibrationView(
        calibrationManager: .previewManualStep2,
        bleManager: BLEManager()
    )
}

#Preview("Recording") {
    ManualCalibrationView(
        calibrationManager: .previewManualRecording,
        bleManager: BLEManager()
    )
}
