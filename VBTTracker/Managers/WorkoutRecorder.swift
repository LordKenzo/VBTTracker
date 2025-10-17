//
//  WorkoutRecorder.swift
//  VBTTracker
//
//  Created by Lorenzo Franceschini on 17/10/25.
//


//
//  WorkoutRecorder.swift
//  VBTTracker
//
//  Orchestratore per registrazione serie di allenamento completa
//

import Foundation
import Combine

class WorkoutRecorder: ObservableObject {
    
    // MARK: - Published Properties
    @Published var isRecording = false
    @Published var currentRepCount = 0
    @Published var statusMessage = "Pronto per iniziare"
    
    // MARK: - Private Properties
    private var repDetectionManager = RepDetectionManager()
    private var dataStreamTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    
    // Configurazione serie
    private var exerciseName: String = ""
    private var loadKg: Double = 0
    private var targetReps: Int = 0
    private var calibrationData: CalibrationData?
    
    // Timestamp inizio
    private var startTime: Date?
    
    // Callbacks
    var onRepDetected: ((RepData) -> Void)?
    var onTargetReached: (() -> Void)?
    var onSetCompleted: ((WorkoutSet) -> Void)?
    
    // MARK: - Initialization
    
    init() {
        setupBindings()
    }
    
    // MARK: - Setup
    
    private func setupBindings() {
        // Osserva il conteggio ripetizioni dal RepDetectionManager
        repDetectionManager.$currentRepCount
            .sink { [weak self] count in
                guard let self = self else { return }
                
                DispatchQueue.main.async {
                    self.currentRepCount = count
                    self.updateStatus()
                }
                
                // Notifica nuova rep rilevata
                if count > 0, let lastRep = self.repDetectionManager.detectedReps.last {
                    self.onRepDetected?(lastRep)
                }
                
                // Check target raggiunto
                if count >= self.targetReps {
                    self.handleTargetReached()
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Public Methods
    
    /// Inizia registrazione serie
    func startRecording(
        exerciseName: String,
        loadKg: Double,
        targetReps: Int,
        calibrationData: CalibrationData?,
        sensorManager: BLEManager
    ) {
        guard !isRecording else { return }
        
        // Salva configurazione
        self.exerciseName = exerciseName
        self.loadKg = loadKg
        self.targetReps = targetReps
        self.calibrationData = calibrationData
        self.startTime = Date()
        
        // Reset stato
        currentRepCount = 0
        
        // Avvia rilevamento
        repDetectionManager.startDetection()
        
        // Avvia streaming dati dal sensore
        startDataStream(sensorManager: sensorManager)
        
        isRecording = true
        statusMessage = "Registrazione in corso... (0/\(targetReps))"
        
        print("🎬 WorkoutRecorder: registrazione iniziata")
        print("   Esercizio: \(exerciseName)")
        print("   Carico: \(loadKg) kg")
        print("   Target: \(targetReps) reps")
        print("   Calibrato: \(calibrationData != nil ? "SI" : "NO")")
    }
    
    /// Ferma registrazione manualmente
    func stopRecording() {
        guard isRecording else { return }
        
        stopDataStream()
        repDetectionManager.stopDetection()
        
        // Crea WorkoutSet
        let workoutSet = createWorkoutSet()
        
        isRecording = false
        statusMessage = "Registrazione completata"
        
        print("⏹️ WorkoutRecorder: registrazione fermata")
        print("   Ripetizioni: \(currentRepCount)/\(targetReps)")
        
        // Notifica completamento
        onSetCompleted?(workoutSet)
    }
    
    /// Reset completo
    func reset() {
        stopRecording()
        repDetectionManager.reset()
        currentRepCount = 0
        statusMessage = "Pronto per iniziare"
    }
    
    // MARK: - Private Methods
    
    private func startDataStream(sensorManager: BLEManager) {
        // Timer per campionare dati dal sensore a 50Hz
        dataStreamTimer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { [weak self] _ in
            guard let self = self, self.isRecording else { return }
            
            // Passa dati al RepDetectionManager
            self.repDetectionManager.processSample(
                acceleration: sensorManager.acceleration,
                isCalibrated: sensorManager.isCalibrated
            )
        }
    }
    
    private func stopDataStream() {
        dataStreamTimer?.invalidate()
        dataStreamTimer = nil
    }
    
    private func updateStatus() {
        statusMessage = "Registrazione in corso... (\(currentRepCount)/\(targetReps))"
    }
    
    private func handleTargetReached() {
        print("🎯 Target raggiunto: \(currentRepCount)/\(targetReps)")
        
        // Notifica target raggiunto (l'utente può decidere se continuare o fermare)
        onTargetReached?()
        
        // Auto-stop dopo target (opzionale, commentabile)
        // DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
        //     self?.stopRecording()
        // }
    }
    
    private func createWorkoutSet() -> WorkoutSet {
        let reps = repDetectionManager.detectedReps
        
        let workoutSet = WorkoutSet(
            timestamp: startTime ?? Date(),
            exerciseName: exerciseName,
            loadKg: loadKg,
            targetReps: targetReps,
            reps: reps,
            calibrationData: calibrationData
        )
        
        // Log statistiche
        print("📊 WorkoutSet creato:")
        print("   Reps: \(workoutSet.actualReps)")
        print("   Avg Peak Velocity: \(String(format: "%.3f", workoutSet.avgPeakVelocity)) m/s")
        print("   Avg Mean Velocity: \(String(format: "%.3f", workoutSet.avgMeanVelocity)) m/s")
        print("   Total Volume: \(String(format: "%.1f", workoutSet.totalVolume)) kg")
        
        if let vl = workoutSet.velocityLoss {
            print("   Velocity Loss: \(String(format: "%.1f", vl))%")
        }
        
        return workoutSet
    }
    
    // MARK: - Computed Properties
    
    var currentPhase: RepDetectionManager.MovementPhase {
        repDetectionManager.currentPhase
    }
    
    var currentVelocity: Double {
        repDetectionManager.currentVelocity
    }
    
    var detectedReps: [RepData] {
        repDetectionManager.detectedReps
    }
}