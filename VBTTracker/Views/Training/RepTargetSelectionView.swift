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
    
    var body: some View {
        ZStack {
            // Background
            LinearGradient(
                colors: [Color.black, Color(white: 0.1)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            VStack(spacing: 32) {
                // Header
                VStack(spacing: 12) {
                    Image(systemName: targetZone.icon)
                        .font(.system(size: 60))
                        .foregroundStyle(targetZone.color)
                    
                    Text(targetZone.rawValue)
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text("Quante ripetizioni vuoi fare?")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 40)
                
                // Rep Selector
                VStack(spacing: 24) {
                    // Big number display
                    Text("\(targetReps)")
                        .font(.system(size: 100, weight: .bold, design: .rounded))
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
                
                Spacer()
                
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
            .padding()
        }
        .navigationTitle("Imposta Ripetizioni")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $navigateToSession) {
            TrainingSessionView(
                bleManager: bleManager,
                targetZone: targetZone,
                targetReps: targetReps  // ✅ Passa il target
            )
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
    
    /// Rep raccomandate (metà del range)
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