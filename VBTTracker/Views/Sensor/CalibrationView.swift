//
//  CalibrationView.swift
//  VBTTracker
//
//  Created by Lorenzo Franceschini on 16/10/25.
//


//
//  CalibrationView.swift
//  VBTTracker
//
//  Interfaccia per calibrazione sensore
//

import SwiftUI

struct CalibrationView: View {
    @ObservedObject var calibrationManager: CalibrationManager
    @ObservedObject var sensorManager: BLEManager
    
    @State private var dataStreamTimer: Timer?
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 30) {
                
                // Istruzioni
                instructionsSection
                
                // Progress Circle
                if calibrationManager.isCalibrating {
                    progressSection
                }
                
                // Status
                statusSection
                
                // Dati real-time (per debug)
                if sensorManager.isConnected {
                    realTimeDataSection
                }
                
                Spacer()
                
                // Controlli
                controlButtons
            }
            .padding()
            .navigationTitle("Calibrazione Sensore")
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
    
    // MARK: - Instructions Section
    
    private var instructionsSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "sensor.fill")
                .font(.system(size: 60))
                .foregroundStyle(.blue)
            
            Text("Istruzioni Calibrazione")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                InstructionRow(number: "1", text: "Posiziona il sensore su una superficie piana")
                InstructionRow(number: "2", text: "NON muovere il sensore durante la calibrazione")
                InstructionRow(number: "3", text: "Attendi il completamento (3 secondi)")
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
    }
    
    // MARK: - Progress Section
    
    private var progressSection: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 15)
                    .frame(width: 150, height: 150)
                
                Circle()
                    .trim(from: 0, to: calibrationManager.calibrationProgress)
                    .stroke(Color.blue, style: StrokeStyle(lineWidth: 15, lineCap: .round))
                    .frame(width: 150, height: 150)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.1), value: calibrationManager.calibrationProgress)
                
                VStack {
                    Text("\(Int(calibrationManager.calibrationProgress * 100))%")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                    Text("Calibrazione...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
    
    // MARK: - Status Section
    
    private var statusSection: some View {
        HStack {
            Circle()
                .fill(calibrationManager.isCalibrating ? Color.orange : 
                      calibrationManager.currentCalibration != nil ? Color.green : Color.gray)
                .frame(width: 12, height: 12)
            
            Text(calibrationManager.statusMessage)
                .font(.subheadline)
            
            Spacer()
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }
    
    // MARK: - Real-time Data (Debug)
    
    private var realTimeDataSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Dati Correnti (Debug)")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            HStack(spacing: 20) {
                DataPreview(label: "Accel", values: sensorManager.acceleration)
                DataPreview(label: "Gyro", values: sensorManager.angularVelocity)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }
    
    // MARK: - Control Buttons
    
    private var controlButtons: some View {
        VStack(spacing: 12) {
            if calibrationManager.isCalibrating {
                Button(action: {
                    calibrationManager.cancelCalibration()
                }) {
                    Label("Annulla Calibrazione", systemImage: "xmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.red)
            } else if calibrationManager.currentCalibration != nil {
                Button(action: {
                    calibrationManager.resetCalibration()
                }) {
                    Label("Nuova Calibrazione", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                
                Button(action: {
                    // SALVA calibrazione nel BLEManager
                    if let calibration = calibrationManager.currentCalibration {
                        sensorManager.applyCalibration(calibration)
                        SettingsManager.shared.savedCalibration = calibration
                    }
                    dismiss()
                }) {
                    Label("Usa Questa Calibrazione", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button(action: {
                    calibrationManager.startCalibration()
                }) {
                    Label("Inizia Calibrazione", systemImage: "play.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!sensorManager.isConnected)
            }
        }
    }
    
    // MARK: - Data Stream
    
    private func startDataStream() {
        guard sensorManager.isConnected else { return }
        
        dataStreamTimer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { _ in
            if calibrationManager.isCalibrating {
                calibrationManager.addSample(
                    acceleration: sensorManager.acceleration,
                    angularVelocity: sensorManager.angularVelocity,
                    angles: sensorManager.angles
                )
            }
        }
    }
    
    private func stopDataStream() {
        dataStreamTimer?.invalidate()
        dataStreamTimer = nil
    }
}

// MARK: - Supporting Views

struct InstructionRow: View {
    let number: String
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.blue))
            
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
            
            Spacer()
        }
    }
}

struct DataPreview: View {
    let label: String
    let values: [Double]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            
            Text("[\(values.map { String(format: "%.2f", $0) }.joined(separator: ", "))]")
                .font(.system(.caption, design: .monospaced))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    CalibrationView(
        calibrationManager: CalibrationManager(),
        sensorManager: BLEManager()
    )
}
