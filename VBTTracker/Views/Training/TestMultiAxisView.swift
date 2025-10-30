//
//  TestMultiAxisView.swift
//  VBTTracker
//
//  Created by Lorenzo Franceschini on 22/10/25.
//


//
//  TestMultiAxisView.swift
//  VBTTracker
//
//  View di DEBUG per confrontare detection Z-only vs Multi-Axis
//

import SwiftUI
import Charts

struct TestMultiAxisView: View {
    
    @ObservedObject var bleManager: BLEManager
    @State private var isRecording = false
    @State private var samples: [MultiAxisTestSample] = []
    @State private var detectionResults: [DetectionComparison] = []
    
    // Detectors
    private let detectorZOnly = VBTRepDetector()
    private let detectorMultiAxis = VBTRepDetector()
    
    @State private var timer: Timer?
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                headerSection
                controlButtons
                metricsComparison
                realtimeGraphs
                detectionLog
            }
            .padding()
        }
        .navigationTitle("Test Multi-Axis")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    // MARK: - Header
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            Text("Confronto Detection")
                .font(.title2.bold())
            
            Text("Z-Only vs Multi-Axis + Gyro")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            if !bleManager.isConnected {
                Label("Sensore disconnesso", systemImage: "sensor.fill")
                    .foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    // MARK: - Controls
    
    private var controlButtons: some View {
        HStack(spacing: 12) {
            Button(action: {
                if isRecording {
                    stopTest()
                } else {
                    startTest()
                }
            }) {
                Label(
                    isRecording ? "STOP" : "START TEST",
                    systemImage: isRecording ? "stop.circle.fill" : "play.circle.fill"
                )
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
            }
            .buttonStyle(.borderedProminent)
            .tint(isRecording ? .red : .green)
            .disabled(!bleManager.isConnected)
            
            Button(action: resetTest) {
                Label("Reset", systemImage: "arrow.counterclockwise")
                    .frame(width: 100)
                    .frame(height: 50)
            }
            .buttonStyle(.bordered)
        }
    }
    
    // MARK: - Metrics
    
    private var metricsComparison: some View {
        VStack(spacing: 16) {
            Text("Risultati Detection")
                .font(.headline)
            
            HStack(spacing: 20) {
                // Z-Only
                VStack(spacing: 8) {
                    Text("Z-Only")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Text("\(countReps(mode: .zOnly))")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(.blue)
                    
                    Text("rep")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue.opacity(0.1))
                .cornerRadius(12)
                
                // Multi-Axis
                VStack(spacing: 8) {
                    Text("Multi-Axis")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Text("\(countReps(mode: .multiAxis))")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(.green)
                    
                    Text("rep")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.green.opacity(0.1))
                .cornerRadius(12)
            }
            
            // Differenza
            if !detectionResults.isEmpty {
                let diff = countReps(mode: .multiAxis) - countReps(mode: .zOnly)
                HStack {
                    Image(systemName: diff > 0 ? "arrow.up.circle.fill" : diff < 0 ? "arrow.down.circle.fill" : "equal.circle.fill")
                    Text("Differenza: \(abs(diff)) rep")
                        .font(.subheadline.bold())
                }
                .foregroundStyle(diff > 0 ? .green : diff < 0 ? .red : .gray)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }
    
    // MARK: - Graphs
    
    private var realtimeGraphs: some View {
        VStack(spacing: 16) {
            Text("Segnali Real-Time")
                .font(.headline)
            
            // Grafico AccZ
            graphCard(
                title: "AccZ (Verticale)",
                data: samples.suffix(100).map { ($0.timestamp, $0.accZ) },
                color: .orange
            )
            
            // Grafico Horizontal Magnitude
            graphCard(
                title: "Horizontal Mag (X² + Y²)",
                data: samples.suffix(100).map { ($0.timestamp, $0.horizontalMag) },
                color: .blue
            )
            
            // Grafico Motion Intensity
            graphCard(
                title: "Motion Intensity (H + Gyro*0.005)",
                data: samples.suffix(100).map { ($0.timestamp, $0.motionIntensity) },
                color: .green
            )
        }
    }
    
    private func graphCard(title: String, data: [(Date, Double)], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            
            if #available(iOS 16.0, *) {
                Chart(data, id: \.0) { timestamp, value in
                    LineMark(
                        x: .value("Time", timestamp),
                        y: .value("Value", value)
                    )
                    .foregroundStyle(color)
                }
                .frame(height: 120)
                .chartYScale(domain: -0.5...1.5)
            } else {
                Text("Charts requires iOS 16+")
                    .frame(height: 120)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
    
    // MARK: - Detection Log
    
    private var detectionLog: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Log Detection")
                .font(.headline)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(detectionResults.suffix(10).reversed()) { result in
                        detectionLogRow(result)
                    }
                }
            }
            .frame(maxHeight: 300)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private func detectionLogRow(_ result: DetectionComparison) -> some View {
        HStack {
            Text(result.timestamp, style: .time)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            
            Spacer()
            
            // Z-Only
            Image(systemName: result.detectedZOnly ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(result.detectedZOnly ? .blue : .gray.opacity(0.3))
            
            // Multi-Axis
            Image(systemName: result.detectedMultiAxis ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(result.detectedMultiAxis ? .green : .gray.opacity(0.3))
        }
        .padding(.vertical, 4)
    }
    
    // MARK: - Logic
    
    private func startTest() {
        isRecording = true
        detectorZOnly.reset()
        detectorMultiAxis.reset()
        
        timer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { _ in
            processSample()
        }
    }
    
    private func stopTest() {
        isRecording = false
        timer?.invalidate()
        timer = nil
    }
    
    private func resetTest() {
        samples.removeAll()
        detectionResults.removeAll()
        detectorZOnly.reset()
        detectorMultiAxis.reset()
    }
    
    private func processSample() {
        let accX = bleManager.acceleration[0]
        let accY = bleManager.acceleration[1]
        let accZ = bleManager.acceleration[2]
        let gyro = bleManager.angularVelocity
        
        // Rimuovi gravità da Z
        let accZNoGravity = bleManager.isCalibrated ? accZ : (accZ - 1.0)
        
        // Calcola metriche
        let horizontalMag = sqrt(accX * accX + accY * accY)
        let gyroMag = sqrt(gyro[0]*gyro[0] + gyro[1]*gyro[1] + gyro[2]*gyro[2])
        let motionIntensity = horizontalMag + (gyroMag * 0.005)
        
        // Salva sample
        let sample = MultiAxisTestSample(
            timestamp: Date(),
            accX: accX,
            accY: accY,
            accZ: accZNoGravity,
            gyroMag: gyroMag,
            horizontalMag: horizontalMag,
            motionIntensity: motionIntensity
        )
        samples.append(sample)
        
        // Limita buffer
        if samples.count > 500 {
            samples.removeFirst()
        }
        
        // Test detection Z-Only
        let resultZOnly = detectorZOnly.addSample(
            accZ: accZNoGravity,
            timestamp: Date()
        )
        
        // Test detection Multi-Axis
        let resultMultiAxis = detectorMultiAxis.addMultiAxisSample(
            accX: accX,
            accY: accY,
            accZ: accZNoGravity,
            gyro: gyro,
            timestamp: Date()
        )
        
        // Salva confronto se almeno uno ha rilevato
        if resultZOnly.repDetected || resultMultiAxis.repDetected {
            let comparison = DetectionComparison(
                timestamp: Date(),
                detectedZOnly: resultZOnly.repDetected,
                detectedMultiAxis: resultMultiAxis.repDetected,
                amplitudeZOnly: resultZOnly.currentValue,
                amplitudeMultiAxis: resultMultiAxis.currentValue
            )
            detectionResults.append(comparison)
            
            print("🔔 Detection: Z=\(resultZOnly.repDetected), Multi=\(resultMultiAxis.repDetected)")
        }
    }
    
    private func countReps(mode: DetectionMode) -> Int {
        switch mode {
        case .zOnly:
            return detectionResults.filter { $0.detectedZOnly }.count
        case .multiAxis:
            return detectionResults.filter { $0.detectedMultiAxis }.count
        }
    }
}

// MARK: - Models

struct MultiAxisTestSample: Identifiable {
    let id = UUID()
    let timestamp: Date
    let accX: Double
    let accY: Double
    let accZ: Double
    let gyroMag: Double
    let horizontalMag: Double
    let motionIntensity: Double
}

struct DetectionComparison: Identifiable {
    let id = UUID()
    let timestamp: Date
    let detectedZOnly: Bool
    let detectedMultiAxis: Bool
    let amplitudeZOnly: Double
    let amplitudeMultiAxis: Double
}

enum DetectionMode {
    case zOnly
    case multiAxis
}

// MARK: - Preview

#if DEBUG
struct TestMultiAxisView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            TestMultiAxisView(bleManager: BLEManager())
        }
    }
}
#endif