//
//  AudioSettingsView.swift
//  VBTTracker
//
//  Created by Lorenzo Franceschini on 19/10/25.
//


//
//  AudioSettingsView.swift
//  VBTTracker
//
//  Impostazioni Feedback Vocale
//

import SwiftUI
import AVFoundation

struct AudioSettingsView: View {
    @ObservedObject var settings = SettingsManager.shared
    @State private var isTesting = false
    
    var body: some View {
        List {
            // MARK: - Voice Feedback Toggle
            Section {
                ToggleSettingRow(
                    title: "Feedback Vocale",
                    isOn: $settings.voiceFeedbackEnabled,
                    icon: "speaker.wave.2.fill",
                    description: "Annuncia stacco, conteggio rep e completamento serie"
                )
            }
            
            // MARK: - Voice Settings
            if settings.voiceFeedbackEnabled {
                Section {
                    SliderSettingRow(
                        title: "Volume",
                        value: $settings.voiceVolume,
                        range: 0.0...1.0,
                        step: 0.1,
                        description: volumeDescription
                    )
                    
                    SliderSettingRow(
                        title: "Velocità",
                        value: $settings.voiceRate,
                        range: 0.0...1.0,
                        step: 0.1,
                        description: voiceRateDescription
                    )
                    
                    Picker("Lingua", selection: $settings.voiceLanguage) {
                        Text("Italiano").tag("it-IT")
                        Text("English").tag("en-US")
                    }
                    .pickerStyle(.segmented)
                    
                } header: {
                    Text("Impostazioni Voce")
                }
                
                // MARK: - Test Button
                Section {
                    Button(action: testVoiceFeedback) {
                        HStack {
                            Spacer()
                            
                            if isTesting {
                                ProgressView()
                                    .padding(.trailing, 8)
                                Text("In riproduzione...")
                            } else {
                                Label("Prova Feedback Vocale", systemImage: "play.circle.fill")
                            }
                            
                            Spacer()
                        }
                    }
                    .disabled(isTesting)
                } footer: {
                    Text("Testa il feedback vocale con un annuncio di esempio")
                }
            }
            
            // MARK: - Feedback Info
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(.blue)
                        Text("Durante l'allenamento riceverai:")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        feedbackTypeRow(icon: "arrow.up.circle", text: "Annuncio stacco bilanciere")
                        feedbackTypeRow(icon: "number.circle", text: "Conteggio rep completate")
                        feedbackTypeRow(icon: "checkmark.circle", text: "Completamento serie")
                    }
                    .padding(.leading, 36)
                }
                .padding(.vertical, 4)
            } header: {
                Text("Tipo di Feedback")
            }
        }
        .navigationTitle("Audio")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    // MARK: - Helper Views
    
    private func feedbackTypeRow(icon: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    
    // MARK: - Computed Properties
    
    private var volumeDescription: String {
        if settings.voiceVolume < 0.3 {
            return "🔉 Basso"
        } else if settings.voiceVolume < 0.7 {
            return "🔊 Medio"
        } else {
            return "🔊 Alto"
        }
    }
    
    private var voiceRateDescription: String {
        if settings.voiceRate < 0.3 {
            return "🐢 Lenta"
        } else if settings.voiceRate < 0.7 {
            return "⚡ Normale"
        } else {
            return "🚀 Veloce"
        }
    }
    
    // MARK: - Actions
    
    private func testVoiceFeedback() {
        isTesting = true
        
        let synthesizer = AVSpeechSynthesizer()
        let utterance = AVSpeechUtterance(string: "Stacco! Uno. Due. Tre. Fine serie!")
        
        utterance.voice = AVSpeechSynthesisVoice(language: settings.voiceLanguage)
        utterance.rate = Float(settings.voiceRate)
        utterance.volume = Float(settings.voiceVolume)
        utterance.pitchMultiplier = 1.1
        
        synthesizer.speak(utterance)
        
        // Reset dopo 5 secondi (tempo approssimativo del test)
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            isTesting = false
        }
    }
}

#Preview {
    NavigationStack {
        AudioSettingsView()
    }
}