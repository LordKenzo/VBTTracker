//
//  VelocityTestView.swift
//  VBTTracker
//
//  View di test per calcolo velocità VBT
//

import SwiftUI

struct VelocityTestView: View {
    @ObservedObject var sensorManager: BLEManager
    
    @State private var dataStreamTimer: Timer?
    @State private var velocity: Double = 0.0
    @State private var peakVelocity: Double = 0.0
    @State private var isRecording = false
    
    // Storico per grafico
    @State private var velocityHistory: [Double] = []
    @State private var accelerationHistory: [Double] = []
    
    // Rilevamento movimento
    @State private var isMoving = false
    @State private var movementStartTime: Date?
    @State private var phase: MovementPhase = .idle
    
    @State private var repCount: Int = 0
    @State private var lastPeakDetected: Double = 0.0
    @State private var inConcentricPhase: Bool = false
    @State private var concentricPeakReached: Bool = false
    @State private var lastRepTime: Date?
    
    // Parametri calcolo
    private let samplingRate: Double = 50.0 // Hz
    private let dt: Double = 0.02 // 20ms
    
    // Soglie rilevamento (da letteratura VBT)
    private let movementThreshold: Double = 0.3 // m/s² - soglia per rilevare inizio movimento
    private let velocityNoiseThreshold: Double = 0.05 // m/s - soglia rumore velocità
    
    enum MovementPhase {
        case idle           // Fermo
        case concentric     // Fase concentrica (salita)
        case eccentric      // Fase eccentrica (discesa)
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    
                    // Status
                    statusCard
                    
                    repCounterSection
                    
                    // Metriche Principali
                    metricsSection
                    
                    // Grafico Velocità
                    velocityChartSection
                    
                    // Dati Raw (Debug)
                    rawDataSection
                    
                    // Controlli
                    controlButtons
                }
                .padding()
            }
            .navigationTitle("Test Velocità VBT")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                startDataStream()
            }
            .onDisappear {
                stopDataStream()
            }
        }
    }
    
    // MARK: - Status Card
    
    private var statusCard: some View {
        HStack {
            Circle()
                .fill(phaseColor)
                .frame(width: 12, height: 12)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(phaseText)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                if isRecording {
                    Text("Registrazione attiva")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }
    
    private var phaseColor: Color {
        switch phase {
        case .idle: return .gray
        case .concentric: return .green
        case .eccentric: return .orange
        }
    }
    
    private var phaseText: String {
        switch phase {
        case .idle: return "Fermo"
        case .concentric: return "⬆️ Fase Concentrica (Salita)"
        case .eccentric: return "⬇️ Fase Eccentrica (Discesa)"
        }
    }
    
    // Rep Counter Section
    private var repCounterSection: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(size: 40))
                    .foregroundStyle(.blue)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ripetizioni")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Text("\(repCount)")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundStyle(.blue)
                }
                
                Spacer()
                
                if isRecording && repCount > 0 {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Ultima Rep")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        
                        Text("\(String(format: "%.2f", lastPeakDetected)) m/s")
                            .font(.headline)
                            .foregroundStyle(.green)
                    }
                }
            }
            .padding()
            .background(
                LinearGradient(
                    colors: [Color.blue.opacity(0.1), Color.blue.opacity(0.05)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .cornerRadius(16)
        }
    }
    
    // MARK: - Metrics Section
    
    private var metricsSection: some View {
        VStack(spacing: 16) {
            Text("Metriche VBT")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            HStack(spacing: 12) {
                MetricCard(
                    title: "Velocità Istantanea",
                    value: String(format: "%.3f", velocity),
                    unit: "m/s",
                    color: velocityColor(for: velocity)
                )
                
                MetricCard(
                    title: "Velocità Picco",
                    value: String(format: "%.3f", peakVelocity),
                    unit: "m/s",
                    color: .purple
                )
            }
            
            // Velocità Media (se in movimento)
            if isRecording && !velocityHistory.isEmpty {
                let positiveVelocities = velocityHistory.filter { $0 > 0 }
                let meanVelocity = positiveVelocities.isEmpty ? 0 : positiveVelocities.reduce(0, +) / Double(positiveVelocities.count)
                
                MetricCard(
                    title: "Mean Propulsive Velocity (MPV)",
                    value: String(format: "%.3f", meanVelocity),
                    unit: "m/s",
                    color: .blue
                )
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }
    
    // MARK: - Velocity Chart
    
    private var velocityChartSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Grafico Velocità (ultimi 100 campioni)")
                .font(.headline)
            
            GeometryReader { geometry in
                ZStack {
                    // Background
                    Rectangle()
                        .fill(Color(.systemGray6))
                    
                    // Linea zero
                    Path { path in
                        let y = geometry.size.height / 2
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                    }
                    .stroke(Color.gray.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [5, 3]))
                    
                    // Grafico velocità
                    Path { path in
                        guard velocityHistory.count > 1 else { return }
                        
                        let maxValue = max(1.0, max(abs(velocityHistory.max() ?? 1.0), abs(velocityHistory.min() ?? 1.0)))
                        let width = geometry.size.width
                        let height = geometry.size.height
                        let stepX = width / CGFloat(velocityHistory.count - 1)
                        
                        for (index, value) in velocityHistory.enumerated() {
                            let x = CGFloat(index) * stepX
                            let y = height / 2 - CGFloat(value / maxValue) * (height / 2 * 0.9)
                            
                            if index == 0 {
                                path.move(to: CGPoint(x: x, y: y))
                            } else {
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                    }
                    .stroke(Color.blue, lineWidth: 2)
                }
            }
            .frame(height: 150)
            .cornerRadius(8)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }
    
    // MARK: - Raw Data
    
    private var rawDataSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Dati Raw (Debug)")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            let accelZ = sensorManager.acceleration[2] // ⭐ Asse Z
            let accelNoGravity = sensorManager.isCalibrated ? accelZ : (accelZ - 1.0)
            let accelMS2 = accelNoGravity * 9.81
            
            Group {
                Text("Accel Z (raw): \(String(format: "%.3f", accelZ)) g")
                Text("Accel Z (no gravity): \(String(format: "%.3f", accelNoGravity)) g")
                Text("Accel Z (m/s²): \(String(format: "%.3f", accelMS2)) m/s²")
                Divider()
                Text("Calibrato: \(sensorManager.isCalibrated ? "SI" : "NO")")
                Text("Movimento: \(isMoving ? "SI" : "NO")")
                Text("Fase: \(phaseText)")
                Text("Campioni: \(velocityHistory.count)")
            }
            .font(.system(.caption, design: .monospaced))
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
    
    // MARK: - Control Buttons
    
    private var controlButtons: some View {
        VStack(spacing: 12) {
            if isRecording {
                Button(action: {
                    stopRecording()
                }) {
                    Label("Stop Registrazione", systemImage: "stop.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            } else {
                Button(action: {
                    startRecording()
                }) {
                    Label("Inizia Registrazione", systemImage: "play.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            
            Button(action: {
                resetCalculations()
            }) {
                Label("Reset", systemImage: "arrow.counterclockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }
    
    // MARK: - Helpers
    
    private func velocityColor(for velocity: Double) -> Color {
        if velocity > 0.1 {
            return .green
        } else if velocity < -0.1 {
            return .red
        } else {
            return .gray
        }
    }
    
    // MARK: - Data Stream & Calculations
    
    private func startDataStream() {
        dataStreamTimer = Timer.scheduledTimer(withTimeInterval: dt, repeats: true) { _ in
            calculateVelocityVBT()
        }
    }
    
    private func stopDataStream() {
        dataStreamTimer?.invalidate()
        dataStreamTimer = nil
    }
    
    // ⭐ ALGORITMO VBT CON REP COUNTER
    private func calculateVelocityVBT() {
        // 1. Ottieni accelerazione asse Z (verticale)
        let accelZ = sensorManager.acceleration[2]
        
        let accelNoGravity: Double
        if sensorManager.isCalibrated {
            accelNoGravity = accelZ
        } else {
            accelNoGravity = accelZ - 1.0
        }
        
        let accelMS2 = accelNoGravity * 9.81
        
        // 2. Rileva movimento
        let movementDetected = abs(accelMS2) > 3.5
        
        if movementDetected && !isMoving {
            // 🟢 INIZIO MOVIMENTO
            isMoving = true
            velocity = 0.0
            peakVelocity = 0.0
            inConcentricPhase = false
            concentricPeakReached = false
            movementStartTime = Date()
            print("🟢 Movimento iniziato - accel: \(String(format: "%.2f", accelMS2)) m/s²")
        }
        
        if isMoving {
            // 3. Integra velocità
            let previousVelocity = velocity
            velocity += accelMS2 * dt
            
            // 4. ⭐ RILEVAMENTO FASI E RIPETIZIONI
            
            // FASE CONCENTRICA (salita, velocità > 0.15 m/s)
            if velocity > 0.15 {
                if !inConcentricPhase {
                    // Inizio fase concentrica
                    inConcentricPhase = true
                    concentricPeakReached = false
                    print("⬆️ Inizio fase concentrica")
                }
                
                phase = .concentric
                
                // Aggiorna picco
                if velocity > peakVelocity {
                    peakVelocity = velocity
                }
            }
            
            // ⭐ RILEVAMENTO PICCO: velocità inizia a decrescere dopo fase concentrica
            if inConcentricPhase && !concentricPeakReached {
                // Rileva quando velocità smette di crescere (picco raggiunto)
                if previousVelocity > velocity && peakVelocity > 0.2 {
                    concentricPeakReached = true
                    lastPeakDetected = peakVelocity
                    print("🔝 Picco concentrico: \(String(format: "%.3f", peakVelocity)) m/s")
                }
            }
            
            // FASE ECCENTRICA (discesa, velocità < -0.15 m/s)
            if velocity < -0.15 {
                phase = .eccentric
                
                // ⭐ CONTA RIPETIZIONE: con anti-doppio conteggio
                if concentricPeakReached && inConcentricPhase {
                    
                    // ⭐ Validazione ripetizione
                    let timeSinceLastRep = lastRepTime?.timeIntervalSinceNow ?? -1.0
                    let isValidTiming = abs(timeSinceLastRep) > 0.5 || lastRepTime == nil
                    
                    if isValidTiming {
                        repCount += 1
                        lastRepTime = Date()
                        print("✅ RIPETIZIONE #\(repCount) completata - Picco: \(String(format: "%.3f", lastPeakDetected)) m/s")
                        
                        // Reset flags per prossima rep
                        inConcentricPhase = false
                        concentricPeakReached = false
                        
                    } else {
                        print("⏭️ Ripetizione ignorata (troppo veloce, \(String(format: "%.2f", abs(timeSinceLastRep)))s)")
                        
                        // ⭐ NUOVO: Reset flags anche quando ignoriamo (evita loop infinito)
                        inConcentricPhase = false
                        concentricPeakReached = false
                    }
                }
            }
            
            // 5. Rileva FINE movimento
            let movementDuration = Date().timeIntervalSince(movementStartTime ?? Date())
            let isAlmostStopped = abs(velocity) < 0.12
            let lowAcceleration = abs(accelMS2) < 2.0
            let minDurationPassed = movementDuration > 0.3
            
            if isAlmostStopped && lowAcceleration && minDurationPassed {
                // 🔴 FINE MOVIMENTO
                print("🔴 Fine movimento - Durata: \(String(format: "%.2f", movementDuration))s")
                
                isMoving = false
                phase = .idle
                velocity = 0.0
                inConcentricPhase = false
                concentricPeakReached = false
            }
            
            // Safety: force stop dopo 3 secondi (ridotto per rep più rapide)
            if movementDuration > 3.0 {
                print("⚠️ Force stop - rep troppo lunga")
                isMoving = false
                phase = .idle
                velocity = 0.0
                inConcentricPhase = false
                concentricPeakReached = false
            }
            
            // Salva storico
            if isRecording {
                velocityHistory.append(velocity)
                accelerationHistory.append(accelMS2)
                
                if velocityHistory.count > 100 {
                    velocityHistory.removeFirst()
                    accelerationHistory.removeFirst()
                }
            }
            
        } else {
            // FERMO
            velocity = 0.0
            phase = .idle
        }
    }
    
    private func startRecording() {
        isRecording = true
        resetCalculations()
        print("▶️ Registrazione VBT iniziata")
    }
    
    private func stopRecording() {
        isRecording = false
        
        let positiveVelocities = velocityHistory.filter { $0 > 0 }
        let mpv = positiveVelocities.isEmpty ? 0 : positiveVelocities.reduce(0, +) / Double(positiveVelocities.count)
        
        print("⏹️ Registrazione fermata")
        print("📊 Risultati VBT:")
        print("   - Ripetizioni: \(repCount)") // ⭐ NUOVO
        print("   - Campioni: \(velocityHistory.count)")
        print("   - Peak Velocity: \(String(format: "%.3f", peakVelocity)) m/s")
        print("   - Mean Propulsive Velocity: \(String(format: "%.3f", mpv)) m/s")
    }
    
    private func resetCalculations() {
        velocity = 0.0
        peakVelocity = 0.0
        velocityHistory.removeAll()
        accelerationHistory.removeAll()
        isMoving = false
        phase = .idle
        repCount = 0
        lastPeakDetected = 0.0
        inConcentricPhase = false
        concentricPeakReached = false
        lastRepTime = nil // ⭐ NUOVO
        print("🔄 Calcoli resettati")
    }
}

// MARK: - Supporting Views

struct MetricCard: View {
    let title: String
    let value: String
    let unit: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(color)
                
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(color.opacity(0.1))
        .cornerRadius(10)
    }
}

#Preview {
    VelocityTestView(sensorManager: BLEManager())
}
