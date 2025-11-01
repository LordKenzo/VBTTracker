//
//  RecordPatternView.swift
//  VBTTracker
//
//  🎙️ View per registrazione manuale pattern
//  Flusso: START → Recording → STOP → Form → Save
//

import SwiftUI

struct RecordPatternView: View {
    @ObservedObject var bleManager: BLEManager
    @StateObject private var recorder = PatternRecorderManager()
    
    @Environment(\.dismiss) var dismiss
    
    // Form state
    @State private var showForm = false
    @State private var patternLabel = ""
    @State private var repCount = 5
    @State private var loadPercentage = ""
    @State private var useLoadPercentage = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background gradient
                LinearGradient(
                    colors: [Color.purple.opacity(0.1), Color.blue.opacity(0.05)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Status Card
                        statusCard
                        
                        // Recording Controls
                        if !showForm {
                            recordingControls
                        }
                        
                        // Instructions
                        if recorder.state == .idle {
                            instructionsCard
                        }
                        
                        // Real-time graph (optional)
                        if recorder.isRecording {
                            realTimeStatsCard
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Registra Pattern")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if !recorder.isRecording {
                        Button("Annulla") {
                            dismiss()
                        }
                    }
                }
            }
            .sheet(isPresented: $showForm) {
                patternFormSheet
            }
            .onChange(of: recorder.state) { _, newState in
                if newState == .readyToSave {
                    showForm = true
                }
            }
            .onReceive(bleManager.$acceleration) { acceleration in
                if recorder.isRecording, acceleration.count >= 3 {
                    // Estrai componente Z (indice 2) dall'array
                    let accZ = acceleration[2]
                    recorder.addSample(accZ: accZ, timestamp: Date())
                }
            }
        }
    }
    
    // MARK: - Status Card
    
    private var statusCard: some View {
        VStack(spacing: 16) {
            // Connection Status
            HStack {
                Circle()
                    .fill(bleManager.isConnected ? Color.green : Color.gray)
                    .frame(width: 12, height: 12)
                
                Text(bleManager.isConnected ? "Sensore Connesso" : "Sensore Non Connesso")
                    .font(.subheadline)
                    .foregroundStyle(bleManager.isConnected ? .primary : .secondary)
                
                Spacer()
            }
            
            Divider()
            
            // Recording Stats
            if recorder.isRecording || recorder.hasRecordedData {
                VStack(spacing: 12) {
                    HStack {
                        Label("Durata", systemImage: "clock.fill")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(formatDuration(recorder.duration))
                            .font(.title2)
                            .fontWeight(.bold)
                            .monospacedDigit()
                    }
                    
                    HStack {
                        Label("Campioni", systemImage: "waveform.path.ecg")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(recorder.sampleCount)")
                            .font(.title3)
                            .fontWeight(.semibold)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
    }
    
    // MARK: - Recording Controls
    
    private var recordingControls: some View {
        VStack(spacing: 16) {
            if !recorder.isRecording {
                // START Button
                Button(action: {
                    recorder.startRecording()
                }) {
                    HStack {
                        Image(systemName: "record.circle.fill")
                            .font(.title2)
                        Text("Inizia Registrazione")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(bleManager.isConnected ? Color.red : Color.gray)
                    .foregroundStyle(.white)
                    .cornerRadius(12)
                }
                .disabled(!bleManager.isConnected)
                
                if !bleManager.isConnected {
                    Text("Connetti un sensore per iniziare")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                // STOP Button
                Button(action: {
                    recorder.stopRecording()
                }) {
                    HStack {
                        Image(systemName: "stop.circle.fill")
                            .font(.title2)
                        Text("Ferma Registrazione")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.orange)
                    .foregroundStyle(.white)
                    .cornerRadius(12)
                }
                
                // Cancel Button
                Button(action: {
                    recorder.cancelRecording()
                }) {
                    Text("Annulla Registrazione")
                        .font(.subheadline)
                        .foregroundStyle(.red)
                }
                .padding(.top, 8)
            }
        }
    }
    
    // MARK: - Instructions Card
    
    private var instructionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Come Funziona", systemImage: "info.circle.fill")
                .font(.headline)
                .foregroundStyle(.blue)
            
            VStack(alignment: .leading, spacing: 8) {
                InstructionStep(number: 1, text: "Premi START per iniziare la registrazione")
                InstructionStep(number: 2, text: "Esegui le tue ripetizioni normalmente")
                InstructionStep(number: 3, text: "Premi STOP quando hai finito")
                InstructionStep(number: 4, text: "Compila il form con i dettagli")
            }
        }
        .padding()
        .background(Color.blue.opacity(0.1))
        .cornerRadius(12)
    }
    
    // MARK: - Real-time Stats Card
    
    private var realTimeStatsCard: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "waveform.path.ecg")
                    .foregroundStyle(.red)
                Text("Registrazione in corso...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            // Qui potresti aggiungere un grafico real-time
            RealTimeRecordingIndicator(isRecording: recorder.isRecording)
        }
        .padding()
        .background(Color.red.opacity(0.1))
        .cornerRadius(12)
    }
    
    // MARK: - Form Sheet
    
    private var patternFormSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nome Pattern (es. Squat 70%)", text: $patternLabel)
                        .autocorrectionDisabled()
                } header: {
                    Text("Informazioni Base")
                }
                
                Section {
                    Stepper("Numero Ripetizioni: \(repCount)", value: $repCount, in: 1...50)
                } header: {
                    Text("Ripetizioni")
                } footer: {
                    Text("Quante ripetizioni hai eseguito durante la registrazione?")
                }
                
                Section {
                    Toggle("Specifica % Carico", isOn: $useLoadPercentage)
                    
                    if useLoadPercentage {
                        HStack {
                            TextField("% Carico", text: $loadPercentage)
                                .keyboardType(.decimalPad)
                            Text("%")
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Carico (Opzionale)")
                } footer: {
                    Text("Specifica la % del massimale (es. 70%) per migliorare il riconoscimento automatico.")
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Durata:")
                            Spacer()
                            Text(formatDuration(recorder.duration))
                                .foregroundStyle(.secondary)
                        }
                        
                        HStack {
                            Text("Campioni:")
                            Spacer()
                            Text("\(recorder.sampleCount)")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.subheadline)
                } header: {
                    Text("Dati Registrati")
                }
            }
            .navigationTitle("Dettagli Pattern")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Annulla") {
                        showForm = false
                        recorder.reset()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Salva") {
                        savePattern()
                    }
                    .disabled(patternLabel.isEmpty)
                }
            }
        }
    }
    
    // MARK: - Actions
    
    private func savePattern() {
        let load = useLoadPercentage && !loadPercentage.isEmpty
            ? Double(loadPercentage)
            : nil
        
        recorder.savePattern(
            label: patternLabel,
            repCount: repCount,
            loadPercentage: load
        )
        
        showForm = false
        
        // Mostra conferma e chiudi
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            dismiss()
        }
    }
    
    // MARK: - Helpers
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        let millis = Int((duration.truncatingRemainder(dividingBy: 1)) * 10)
        
        if minutes > 0 {
            return String(format: "%d:%02d.%d", minutes, seconds, millis)
        } else {
            return String(format: "%d.%d s", seconds, millis)
        }
    }
}

// MARK: - Supporting Views

struct InstructionStep: View {
    let number: Int
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.blue))
            
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
        }
    }
}

struct RealTimeRecordingIndicator: View {
    let isRecording: Bool
    @State private var pulse = false
    
    var body: some View {
        Circle()
            .fill(Color.red)
            .frame(width: 16, height: 16)
            .scaleEffect(pulse ? 1.2 : 1.0)
            .opacity(pulse ? 0.6 : 1.0)
            .animation(
                isRecording ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true) : .default,
                value: pulse
            )
            .onAppear {
                if isRecording {
                    pulse = true
                }
            }
    }
}

// MARK: - Preview

#Preview {
    RecordPatternView(bleManager: BLEManager())
}
