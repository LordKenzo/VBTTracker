//
//  VelocityRangesEditorView.swift
//  VBTTracker
//
//  Created by Lorenzo Franceschini on 17/10/25.
//


//
//  VelocityRangesEditorView.swift
//  VBTTracker
//
//  Editor per personalizzare i range di velocità
//

import SwiftUI

struct VelocityRangesEditorView: View {
    @ObservedObject var settings = SettingsManager.shared
    @Environment(\.dismiss) var dismiss
    
    @State private var showResetAlert = false
    @State private var localRanges: VelocityRanges
    
    init() {
        _localRanges = State(initialValue: SettingsManager.shared.velocityRanges)
    }
    
    var body: some View {
        NavigationStack {
            List {
                // Info Section
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Range Scientifici", systemImage: "books.vertical.fill")
                            .font(.headline)
                        
                        Text("Valori basati su letteratura scientifica per la panca piana:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("• González-Badillo & Sánchez-Medina (2010)")
                            Text("• Pareja-Blanco et al. (2017)")
                            Text("• Banyard et al. (2019)")
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                
                // Editable Ranges
                Section("Zone di Allenamento") {
                    RangeEditor(
                        title: "Forza Massima",
                        icon: "hammer.fill",
                        color: .red,
                        range: Binding(
                            get: { localRanges.maxStrength },
                            set: { localRanges.maxStrength = $0 }
                        )
                    )
                    
                    RangeEditor(
                        title: "Forza",
                        icon: "dumbbell.fill",
                        color: .orange,
                        range: Binding(
                            get: { localRanges.strength },
                            set: { localRanges.strength = $0 }
                        )
                    )
                    
                    RangeEditor(
                        title: "Forza-Velocità",
                        icon: "bolt.fill",
                        color: .yellow,
                        range: Binding(
                            get: { localRanges.strengthSpeed },
                            set: { localRanges.strengthSpeed = $0 }
                        )
                    )
                    
                    RangeEditor(
                        title: "Velocità",
                        icon: "hare.fill",
                        color: .green,
                        range: Binding(
                            get: { localRanges.speed },
                            set: { localRanges.speed = $0 }
                        )
                    )
                    
                    RangeEditor(
                        title: "Velocità Massima",
                        icon: "bolt.circle.fill",
                        color: .blue,
                        range: Binding(
                            get: { localRanges.maxSpeed },
                            set: { localRanges.maxSpeed = $0 }
                        )
                    )
                }
                
                // Actions
                Section {
                    Button(action: { showResetAlert = true }) {
                        Label("Ripristina Valori Predefiniti", systemImage: "arrow.counterclockwise")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Range di Velocità")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Annulla") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Salva") {
                        saveChanges()
                    }
                    .fontWeight(.semibold)
                }
            }
            .alert("Ripristina Valori", isPresented: $showResetAlert) {
                Button("Annulla", role: .cancel) { }
                Button("Ripristina", role: .destructive) {
                    localRanges = VelocityRanges.defaultRanges
                }
            } message: {
                Text("Ripristinare i range di velocità ai valori predefiniti dalla letteratura scientifica?")
            }
        }
    }
    
    private func saveChanges() {
        settings.velocityRanges = localRanges
        print("💾 Range di velocità aggiornati")
        dismiss()
    }
}

// MARK: - Range Editor Component

struct RangeEditor: View {
    let title: String
    let icon: String
    let color: Color
    @Binding var range: ClosedRange<Double>
    
    @State private var lowerBound: Double
    @State private var upperBound: Double
    
    init(title: String, icon: String, color: Color, range: Binding<ClosedRange<Double>>) {
        self.title = title
        self.icon = icon
        self.color = color
        self._range = range
        self._lowerBound = State(initialValue: range.wrappedValue.lowerBound)
        self._upperBound = State(initialValue: range.wrappedValue.upperBound)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                
                Text(title)
                    .font(.headline)
                
                Spacer()
                
                Text("\(String(format: "%.2f", lowerBound)) - \(String(format: "%.2f", upperBound)) m/s")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            // Lower Bound Slider
            VStack(alignment: .leading, spacing: 4) {
                Text("Minimo: \(String(format: "%.2f", lowerBound)) m/s")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Slider(value: $lowerBound, in: 0.0...2.0, step: 0.05)
                    .tint(color)
                    .onChange(of: lowerBound) { oldValue, newValue in
                        // Ensure lower bound doesn't exceed upper bound
                        if newValue >= upperBound {
                            lowerBound = upperBound - 0.05
                        }
                        updateRange()
                    }
            }
            
            // Upper Bound Slider
            VStack(alignment: .leading, spacing: 4) {
                Text("Massimo: \(String(format: "%.2f", upperBound)) m/s")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Slider(value: $upperBound, in: 0.0...2.0, step: 0.05)
                    .tint(color)
                    .onChange(of: upperBound) { oldValue, newValue in
                        // Ensure upper bound doesn't fall below lower bound
                        if newValue <= lowerBound {
                            upperBound = lowerBound + 0.05
                        }
                        updateRange()
                    }
            }
        }
        .padding(.vertical, 8)
    }
    
    private func updateRange() {
        range = lowerBound...upperBound
    }
}

#Preview {
    VelocityRangesEditorView()
}