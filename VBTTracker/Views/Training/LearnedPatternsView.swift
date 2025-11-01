//
//  LearnedPatternsView 2.swift
//  VBTTracker
//
//  Created by Lorenzo Franceschini on 31/10/25.
//


//
//  LearnedPatternsView.swift
//  VBTTracker
//
//  📚 View per gestire la libreria di pattern appresi
//  ✅ Lista pattern con dettagli (rep, MPV, PPV, durata, % carico)
//  ✅ Swipe-to-delete singoli pattern
//  ✅ Pulsante "Elimina Tutti"
//

import SwiftUI

struct LearnedPatternsView: View {
    @ObservedObject private var library = LearnedPatternLibrary.shared
    @State private var showDeleteAllAlert = false
    
    var body: some View {
        Group {
            if library.patterns.isEmpty {
                emptyState
            } else {
                patternsList
            }
        }
        .navigationTitle("Pattern Appresi")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if !library.patterns.isEmpty {
                    Button(action: { showDeleteAllAlert = true }) {
                        Label("Elimina Tutti", systemImage: "trash")
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .alert("Elimina Tutti i Pattern", isPresented: $showDeleteAllAlert) {
            Button("Annulla", role: .cancel) { }
            Button("Elimina Tutti", role: .destructive) {
                library.removeAll()
            }
        } message: {
            Text("Sei sicuro di voler eliminare tutti i pattern salvati? Questa azione non può essere annullata.")
        }
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 70))
                .foregroundStyle(.secondary)
            
            Text("Nessun Pattern Salvato")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Registra il tuo primo pattern per iniziare a usare il riconoscimento automatico dei movimenti.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Patterns List
    
    private var patternsList: some View {
        List {
            Section {
                ForEach(library.patterns.sorted(by: { $0.date > $1.date })) { pattern in
                    PatternCard(pattern: pattern)
                }
                .onDelete(perform: deletePattern)
            } header: {
                HStack {
                    Text("\(library.patterns.count) Pattern")
                    Spacer()
                    Text("Swipe per eliminare")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .textCase(.none)
                }
            }
        }
        .listStyle(.insetGrouped)
    }
    
    // MARK: - Actions
    
    private func deletePattern(at offsets: IndexSet) {
        let sortedPatterns = library.patterns.sorted(by: { $0.date > $1.date })
        for index in offsets {
            let pattern = sortedPatterns[index]
            library.removePattern(id: pattern.id)
        }
    }
}

// MARK: - Pattern Card

struct PatternCard: View {
    let pattern: PatternSequence
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header: Label + Badge
            HStack {
                Text(pattern.label)
                    .font(.headline)
                
                Spacer()
                
                if let load = pattern.loadPercentage {
                    LoadBadge(percentage: load)
                }
            }
            
            // Stats Grid
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                StatRow(icon: "arrow.triangle.2.circlepath", label: "Reps", value: "\(pattern.repCount)")
                StatRow(icon: "speedometer", label: "MPV", value: String(format: "%.2f m/s", pattern.avgMPV))
                StatRow(icon: "bolt.fill", label: "PPV", value: String(format: "%.2f m/s", pattern.avgPPV))
                StatRow(icon: "timer", label: "Durata", value: String(format: "%.1f s", pattern.avgDuration))
            }
            
            // Date
            HStack {
                Image(systemName: "calendar")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(pattern.date, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Supporting Views

struct LoadBadge: View {
    let percentage: Double
    
    var badgeColor: Color {
        switch percentage {
        case ..<50:
            return .green      // Leggero
        case 50..<70:
            return .blue       // Medio
        case 70..<85:
            return .orange     // Pesante
        default:
            return .red        // Massimale
        }
    }
    
    var body: some View {
        Text("\(Int(percentage))%")
            .font(.caption)
            .fontWeight(.semibold)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(badgeColor.opacity(0.2))
            .foregroundStyle(badgeColor)
            .clipShape(Capsule())
    }
}

struct StatRow: View {
    let icon: String
    let label: String
    let value: String
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            
            Spacer()
        }
    }
}

// MARK: - Preview

#Preview("Con Patterns") {
    NavigationStack {
        LearnedPatternsView()
    }
    .onAppear {
        // Mock patterns per preview
        let mockPatterns = [
            PatternSequence(
                id: UUID(),
                date: Date(),
                label: "Squat 70%",
                repCount: 5,
                loadPercentage: 70,
                avgDuration: 0.85,
                avgAmplitude: 0.52,
                avgMPV: 0.65,
                avgPPV: 0.82,
                featureVector: []
            ),
            PatternSequence(
                id: UUID(),
                date: Date().addingTimeInterval(-86400),
                label: "Panca 60%",
                repCount: 8,
                loadPercentage: 60,
                avgDuration: 0.72,
                avgAmplitude: 0.48,
                avgMPV: 0.78,
                avgPPV: 0.95,
                featureVector: []
            ),
            PatternSequence(
                id: UUID(),
                date: Date().addingTimeInterval(-172800),
                label: "Stacco 85%",
                repCount: 3,
                loadPercentage: 85,
                avgDuration: 1.2,
                avgAmplitude: 0.65,
                avgMPV: 0.45,
                avgPPV: 0.58,
                featureVector: []
            )
        ]
        
        for pattern in mockPatterns {
            LearnedPatternLibrary.shared.addPattern(pattern)
        }
    }
}

#Preview("Empty State") {
    NavigationStack {
        LearnedPatternsView()
    }
    .onAppear {
        LearnedPatternLibrary.shared.removeAll()
    }
}