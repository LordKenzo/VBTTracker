//
//  TrainingSessionView.swift
//  VBTTracker
//
//  STEP 2.5: Smart pattern loading dalla libreria (no UserDefaults)
//  ✅ AGGIUNTO: Salvataggio sessione a fine allenamento
//

import SwiftUI

struct TrainingSessionView: View {
    @ObservedObject var sensorManager: UnifiedSensorManager
    let targetZone: TrainingZone
    let targetReps: Int
    let loadPercentage: Double?  // ✅ STEP 3: Pattern matching pesato

    @ObservedObject var settings = SettingsManager.shared

    @StateObject private var sessionManager = TrainingSessionManager()
    @StateObject private var distanceDetector = DistanceBasedRepDetector()
    @Environment(\.dismiss) var dismiss

    @State private var dataStreamTimer: Timer?
    @State private var showEndSessionAlert = false
    @State private var showRepReview = false  // ✅ Nuova: mostra revisione reps
    @State private var showSummary = false
    @State private var sessionData: TrainingSessionData?

    // Computed property to access bleManager
    private var bleManager: BLEManager {
        sensorManager.bleManager
    }

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

                    // 6. PATTERN ATTIVO (solo WitMotion)
                    if settings.selectedSensorType == .witmotion && sessionManager.isRecording,
                       sessionManager.repDetector.learnedPattern != nil {
                        activePatternCard
                    }

                    // 7. PULSANTI
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
            let fallbackHz = 1.0 / 0.02 // 50 Hz
            let sampleRate = sensorManager.sampleRateHz ?? fallbackHz
            sessionManager.setSampleRateHz(sampleRate)

            // Setup distance detector per Arduino
            if settings.selectedSensorType == .arduino {
                distanceDetector.sampleRateHz = sampleRate
                distanceDetector.lookAheadSamples = 10

                // Callback quando viene rilevata una rep
                distanceDetector.onRepDetected = { metrics in
                    sessionManager.addRepetitionFromDistance(
                        mpv: metrics.meanPropulsiveVelocity,
                        ppv: metrics.peakPropulsiveVelocity,
                        displacement: metrics.displacement,
                        concentricDuration: metrics.concentricDuration
                    )
                }

                print("🎯 Modalità Arduino: rilevamento basato su distanza")
                print("   • Sample rate: \(String(format: "%.1f", sampleRate)) Hz")
                print("   • ROM target: \(String(format: "%.3f", distanceDetector.expectedROM/1000.0)) m")
            }

            // 🧠 Pattern loading: solo per WitMotion
            if settings.selectedSensorType == .witmotion {
                Task { @MainActor in
                    let library = LearnedPatternLibrary.shared

                    // Se libreria vuota → default
                    guard !library.patterns.isEmpty else {
                        sessionManager.repDetector.apply(pattern: .defaultPattern)
                        print("🔧 Pattern di default (libreria vuota)")
                        return
                    }

                    print("🔍 Ricerca pattern ottimale...")
                    if let load = loadPercentage {
                        print("   • Carico target: \(Int(load))%")
                    }

                    // Puoi passare anche i pochi sample iniziali (ok se vuoto: il metodo gestisce il caso)
                    let seedSeq = sessionManager.getAccelerationSamples()

                    // MATCH PESATO: 70% feature, 30% vicinanza %carico
                    let matched = library.matchPatternWeighted(for: seedSeq, loadPercentage: loadPercentage)
                        ?? library.patterns.first!  // fallback: più recente

                    let learned = LearnedPattern(from: matched)
                    sessionManager.repDetector.apply(pattern: learned)

                    print("🎯 Pattern attivo: \(matched.label)")
                    print("   • ROM≈\(String(format: "%.0f cm", learned.estimatedROM*100))")
                    print("   • thr≈\(String(format: "%.2f g", learned.dynamicMinAmplitude))  • dur≈\(String(format: "%.2f s", learned.avgConcentricDuration))")
                }
            }

            startDataStream()
            sessionManager.startRecording()
        }
        .onDisappear {
            stopDataStream()
            if sessionManager.isRecording {
                sessionManager.stopRecording()
            }
        }
        .alert("Terminare Sessione?", isPresented: $showEndSessionAlert) {
            Button("Termina", role: .destructive) {
                // ✅ Crea sessionData e mostra revisione reps
                sessionData = TrainingSessionData.from(
                    manager: sessionManager,
                    targetZone: targetZone,
                    velocityLossThreshold: SettingsManager.shared.velocityLossThreshold
                )
                sessionManager.stopRecording()
                showRepReview = true  // ✅ Mostra revisione invece dell'alert
            }
        } message: {
            Text("Ripetizioni completate: \(sessionManager.repCount)/\(targetReps)")
        }
        .fullScreenCover(isPresented: $showRepReview) {
            if let data = sessionData {
                // ✅ Binding mutabile per permettere modifiche
                RepReviewView(
                    sessionData: Binding(
                        get: { data },
                        set: { sessionData = $0 }
                    ),
                    targetReps: targetReps,
                    onSave: {
                        saveSession()
                        showSummary = true
                    },
                    onDiscard: {
                        // Non salvare, ma mostra comunque il summary
                        showSummary = true
                    }
                )
            }
        }
        .sheet(isPresented: $showSummary) {
            if let data = sessionData {
                TrainingSummaryView(sessionData: data)
            }
        }
        .onReceive(bleManager.$sampleRateHz.compactMap { $0 }) { hz in
            sessionManager.setSampleRateHz(hz)
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
    
    // MARK: - 2. Compact Velocity Card
    
    private var compactVelocityCard: some View {
        VStack(spacing: 12) {
            // Velocity + Zone
            HStack(spacing: 16) {
                // Velocità
                VStack(alignment: .leading, spacing: 4) {
                    Text("VELOCITÀ")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                    
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(String(format: "%.2f", sessionManager.currentVelocity))
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        
                        Text("m/s")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                // Zona corrente
                VStack(alignment: .trailing, spacing: 4) {
                    Text("ZONA")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                    
                    Text(sessionManager.currentZone.rawValue)
                        .font(.headline)
                        .foregroundStyle(sessionManager.currentZone.color)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(sessionManager.currentZone.color.opacity(0.2))
                        .cornerRadius(8)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }
    
    // MARK: - 3. Compact Graph Card

    private var compactGraphCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            if settings.selectedSensorType == .arduino {
                Text("DISTANZA")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)

                RealTimeDistanceGraph(data: sensorManager.arduinoManager.getDistanceSamples())
                    .frame(height: 120)
            } else {
                Text("ACCELERAZIONE")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)

                RealTimeAccelerationGraph(data: sessionManager.getAccelerationSamples())
                    .frame(height: 120)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }
    
    // MARK: - 4. Last Rep Feedback Card
    
    private var lastRepFeedbackCard: some View {
        HStack(spacing: 16) {
            // Info rep
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "figure.strengthtraining.traditional")
                        .foregroundStyle(.blue)
                    Text("REP #\(sessionManager.repCount)")
                        .font(.headline)
                        .foregroundStyle(.primary)
                }
                
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Velocità")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.2f m/s", sessionManager.lastRepPeakVelocity))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Zona")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(getZoneForVelocity(sessionManager.lastRepPeakVelocity))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                }
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

    // MARK: - 7. Active Pattern Badge (WitMotion only)

    private var activePatternCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "brain.head.profile.fill")
                .font(.title3)
                .foregroundStyle(.purple)

            VStack(alignment: .leading, spacing: 2) {
                Text("Pattern Riconosciuto")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)

                if let pattern = sessionManager.repDetector.learnedPattern {
                    Text("Parametri adattati automaticamente")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Nessun pattern attivo")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(.green)
        }
        .padding()
        .background(
            LinearGradient(
                colors: [Color.purple.opacity(0.1), Color.purple.opacity(0.05)],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .cornerRadius(12)
        .shadow(radius: 2)
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
        // chiudi eventuale timer precedente
        stopDataStream()

        func startTimer(with hz: Double) {
            let sr = max(5.0, min(hz, 200.0))         // clamp di sicurezza
            let interval = 1.0 / sr
            dataStreamTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
                // Processa dati in base al tipo di sensore
                if settings.selectedSensorType == .witmotion {
                    sessionManager.processSensorData(
                        acceleration: sensorManager.bleManager.acceleration,
                        angularVelocity: sensorManager.bleManager.angularVelocity,
                        angles: sensorManager.bleManager.angles,
                        isCalibrated: sensorManager.bleManager.isCalibrated
                    )
                } else if settings.selectedSensorType == .arduino {
                    // Processa dati di distanza con stato movimento dall'Arduino
                    distanceDetector.processSample(
                        distance: sensorManager.arduinoManager.distance,
                        velocity: sensorManager.arduinoManager.velocity,
                        movementState: sensorManager.arduinoManager.movementState,
                        timestamp: Date()
                    )
                }

                if settings.stopOnVelocityLoss &&
                   sessionManager.isRecording &&
                   sessionManager.velocityLoss >= settings.velocityLossThreshold {
                    sessionManager.stopRecording()
                }

                if sessionManager.isRecording &&
                   sessionManager.repCount == self.targetReps {
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                }
            }
        }

        // avvio iniziale con fallback
        let fallbackHz = 50.0
        startTimer(with: sensorManager.sampleRateHz ?? fallbackHz)

        // se cambia la SR del BLE, ri-crea il timer con il nuovo passo
        NotificationCenter.default.addObserver(forName: NSNotification.Name("BLE_SR_UPDATED"), object: nil, queue: .main) { _ in
            stopDataStream()
            startTimer(with: sensorManager.sampleRateHz ?? fallbackHz)
        }
    }

    
    private func stopDataStream() {
        dataStreamTimer?.invalidate()
        dataStreamTimer = nil
    }
    
    // MARK: - Save Session
    
    private func saveSession() {
        // Calcola le medie reali
        let meanMPV = sessionManager.averageMPV()
        let meanPPV = sessionManager.averagePPV()


        
        guard let data = sessionData else { return }
        
        // 1. Salva sessione nello storico
        let session = TrainingSession.from(data, targetReps: targetReps)
        TrainingHistoryManager.shared.saveSession(session)
        print("💾 Sessione salvata nello storico")
        
        // 2. ✅ STEP 3: Salva pattern se sessione completata con successo (solo WitMotion)
        if settings.selectedSensorType == .witmotion && data.wasSuccessful && data.totalReps >= 3 {
            let exerciseName = "Panca Piana"  // Per ora hardcoded

            // Salva pattern con informazioni complete
            sessionManager.repDetector.savePatternSequence(
                label: exerciseName,
                repCount: data.totalReps,
                loadPercentage: loadPercentage,
                avgMPV: meanMPV,
                avgPPV: meanPPV
            )

            print("🧠 Pattern salvato in libreria:")
            print("   • Esercizio: \(exerciseName)")
            print("   • Reps: \(data.totalReps)")
            if let load = loadPercentage {
                print("   • Carico: \(Int(load))%")
            }
            if !data.reps.isEmpty {
                let meanMPV = data.reps.map(\.meanVelocity).reduce(0, +) / Double(data.reps.count)
                print("   • MPV medio: \(String(format: "%.3f", meanMPV)) m/s")
            } else {
                print("   • MPV medio: N/D (nessuna ripetizione registrata)")
            }
        } else {
            print("⚠️ Pattern non salvato (sessione non completata o <3 reps)")
        }
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
            sensorManager: UnifiedSensorManager(),
            targetZone: .strength,
            targetReps: 5,
            loadPercentage: 70
        )
    }
}
