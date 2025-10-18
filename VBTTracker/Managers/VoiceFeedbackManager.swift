//
//  VoiceFeedbackManager.swift
//  VBTTracker
//
//  Gestisce feedback vocale durante allenamento
//

import Foundation
@preconcurrency import AVFoundation  // ⭐ FIX Swift 6

class VoiceFeedbackManager: NSObject, ObservableObject {
    
    // MARK: - Properties
    
    nonisolated(unsafe) private let synthesizer = AVSpeechSynthesizer()  // ⭐ FIX
    private var settings = SettingsManager.shared
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        synthesizer.delegate = self
        print("🔊 VoiceFeedbackManager inizializzato")
    }
    
    // MARK: - Public Methods
    
    /// Feedback: Stacco bilanciere
    func announceBarUnrack() {
        guard settings.voiceFeedbackEnabled else { return }
        speak("Stacco del bilanciere")
    }
    
    /// Feedback: Inizio fase concentrica
    func announceConcentric() {
        guard settings.voiceFeedbackEnabled else { return }
        speak("Concentrica")
    }
    
    /// Feedback: Inizio fase eccentrica
    func announceEccentric() {
        guard settings.voiceFeedbackEnabled else { return }
        speak("Eccentrica")
    }
    
    /// Feedback: Rep completata
    func announceRep(number: Int, isInTarget: Bool) {
        guard settings.voiceFeedbackEnabled else { return }
        
        let message: String
        if number == 1 {
            message = "1 rep"
        } else {
            message = "\(number) reps"
        }
        
        speak(message)
    }
    
    /// Feedback: Velocity loss raggiunta
    func announceVelocityLoss(percentage: Double) {
        guard settings.voiceFeedbackEnabled else { return }
        speak("Velocity loss \(Int(percentage)) percento. Stop!")
    }
    
    /// Feedback: Inizio allenamento
    func announceWorkoutStart() {
        guard settings.voiceFeedbackEnabled else { return }
        speak("Inizio")
    }
    
    /// Feedback: Fine allenamento
    func announceWorkoutEnd(reps: Int) {
        guard settings.voiceFeedbackEnabled else { return }
        speak("Fine. Totale \(reps) reps")
    }
    
    /// Stop di tutto
    func stopSpeaking() {
        synthesizer.stopSpeaking(at: .immediate)
    }
    
    // MARK: - Private Methods
    
    private func speak(_ text: String) {
        // Stop eventuali speech in corso
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .word)
        }
        
        let utterance = AVSpeechUtterance(string: text)
        
        // Configurazione da Settings
        utterance.voice = AVSpeechSynthesisVoice(language: settings.voiceLanguage)
        utterance.rate = Float(settings.voiceRate)
        utterance.volume = Float(settings.voiceVolume)
        
        // Pitch leggermente più alto per maggiore chiarezza in palestra
        utterance.pitchMultiplier = 1.1
        
        print("🔊 Voice: \(text)")
        
        // ⭐ Speak su main thread
        DispatchQueue.main.async { [weak self] in
            self?.synthesizer.speak(utterance)
        }
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension VoiceFeedbackManager: AVSpeechSynthesizerDelegate {
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        // Opzionale: log quando inizia a parlare
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        // Opzionale: log quando finisce
    }
}
