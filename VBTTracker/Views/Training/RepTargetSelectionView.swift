//
//  RepTargetSelectionView.swift
//  VBTTracker
//
//  Created by Lorenzo Franceschini on 19/10/25.
//


//
//  RepTargetSelectionView.swift
//  VBTTracker
//
//  Selezione numero ripetizioni target prima di iniziare
//

import SwiftUI

struct RepTargetSelectionView: View {
    @ObservedObject var bleManager: BLEManager
    let targetZone: TrainingZone
    
    @State private var targetReps: Int = 5
    @State private var navigateToSession = false
    
    // ✅ STEP 3: Info esercizio e carico
    @State private var loadPercentage: Double? = nil
    @State private var showExerciseInfo = false
    
    var body: some View {
        ZStack {
            // Background
            LinearGradient(
                colors: [Color.black, Color(white: 0.1)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            ScrollView {
                
                VStack(spacing: 32) {
                    // Header
                    VStack(spacing: 12) {
                        Image(systemName: targetZone.icon)
                            .font(.system(size: 45))
                            .foregroundStyle(targetZone.color)
                        
                        Text(targetZone.rawValue)
                            .font(.title)
                            .fontWeight(.bold)
                        
                        Text("Quante ripetizioni vuoi fare?")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 10)
                    
                    // Rep Selector
                    VStack(spacing: 20) {
                        // Big number display
                        Text("\(targetReps)")
                            .font(.system(size: 55, weight: .bold, design: .rounded))
                            .foregroundStyle(targetZone.color)
                        
                        Text("ripetizioni")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                        
                        // Slider
                        VStack(spacing: 16) {
                            Slider(
                                value: Binding(
                                    get: { Double(targetReps) },
                                    set: { targetReps = Int($0) }
                                ),
                                in: Double(repRange.lowerBound)...Double(repRange.upperBound),
                                step: 1
                            )
                            .tint(targetZone.color)
                            
                            // Range indicator
                            HStack {
                                Text("\(repRange.lowerBound)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                
                                Spacer()
                                
                                Text("Consigliato: \(recommendedReps)")
                                    .font(.caption)
                                    .foregroundStyle(targetZone.color)
                                
                                Spacer()
                                
                                Text("\(repRange.upperBound)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal)
                    }
                    .padding()
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(20)
                    
                    // Quick presets
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Preset veloci")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        HStack(spacing: 12) {
                            ForEach(quickPresets, id: \.self) { preset in
                                Button(action: { targetReps = preset }) {
                                    Text("\(preset)")
                                        .font(.headline)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(
                                            targetReps == preset ?
                                            targetZone.color :
                                                Color.white.opacity(0.1)
                                        )
                                        .foregroundStyle(.white)
                                        .cornerRadius(12)
                                }
                            }
                        }
                    }
                    
                    // ✅ STEP 3: Info Allenamento button
                    Button(action: { showExerciseInfo = true }) {
                        HStack(spacing: 12) {
                            Image(systemName: "info.circle.fill")
                                .font(.title3)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Info Allenamento")
                                    .font(.headline)
                                
                                if let load = loadPercentage {
                                    Text("Carico: \(Int(load))%")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("Imposta % carico")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(loadPercentage != nil ?
                                      Color.blue.opacity(0.2) :
                                        Color.white.opacity(0.05))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(loadPercentage != nil ?
                                        Color.blue :
                                            Color.white.opacity(0.1),
                                        lineWidth: loadPercentage != nil ? 2 : 1)
                        )
                    }
                    .foregroundStyle(.white)
                    
                    // Start button
                    Button(action: { navigateToSession = true }) {
                        Label("Inizia Allenamento", systemImage: "play.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(targetZone.color)
                    .controlSize(.large)
                }
            }
            .padding()
            .padding(.bottom, 10)
        }
        .navigationTitle("Imposta Ripetizioni")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $navigateToSession) {
            TrainingSessionView(
                bleManager: bleManager,
                targetZone: targetZone,
                targetReps: targetReps,
                loadPercentage: loadPercentage
            )
        }
        .sheet(isPresented: $showExerciseInfo) {
            ExerciseInfoSheet(loadPercentage: $loadPercentage)
        }
    }
    
    // MARK: - Computed Properties
    
    /// Range di rep consigliato per la zona
    private var repRange: ClosedRange<Int> {
        switch targetZone {
        case .maxStrength:
            return 1...6
        case .strength:
            return 1...8
        case .strengthSpeed:
            return 1...12
        case .speed:
            return 1...15
        case .maxSpeed:
            return 1...20
        case .tooSlow:
            return 1...10
        }
    }
    
    /// Rep raccomandate (metà  del range)
    private var recommendedReps: Int {
        (repRange.lowerBound + repRange.upperBound) / 2
    }
    
    /// Preset veloci per la zona
    private var quickPresets: [Int] {
        let mid = recommendedReps
        return [
            max(repRange.lowerBound, mid - 2),
            mid,
            min(repRange.upperBound, mid + 2)
        ].filter { repRange.contains($0) }
    }
}

#Preview {
    NavigationStack {
        RepTargetSelectionView(
            bleManager: BLEManager(),
            targetZone: .strength
        )
    }
}
