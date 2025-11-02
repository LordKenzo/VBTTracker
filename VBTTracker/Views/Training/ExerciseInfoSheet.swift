//
//  ExerciseInfoSheet.swift
//  VBTTracker
//
//  Sheet per specificare % carico prima della sessione
//  (Esercizio: "Panca Piana" hardcoded per ora)
//

import SwiftUI

struct ExerciseInfoSheet: View {
    @Binding var loadPercentage: Double?
    @Environment(\.dismiss) var dismiss
    
    @State private var useLoadPercentage = true
    @State private var tempLoadPercentage: Double = 70.0
    
    // Per ora solo Panca Piana
    private let exerciseName = "Panca Piana"
    
    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Esercizio Section
                Section {
                    HStack {
                        Image(systemName: "figure.strengthtraining.traditional")
                            .foregroundStyle(.blue)
                            .font(.title2)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(exerciseName)
                                .font(.headline)
                            Text("Selezionato")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.title3)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Esercizio")
                }
                
                // MARK: - Carico Section
                Section {
                    Toggle("Specifica % Carico", isOn: $useLoadPercentage)
                        .tint(.blue)
                    
                    if useLoadPercentage {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .firstTextBaseline) {
                                Text("\(Int(tempLoadPercentage))%")
                                    .font(.system(size: 48, weight: .bold, design: .rounded))
                                    .foregroundStyle(.blue)
                                
                                Spacer()
                                
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("del massimale")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    
                                    Text(loadDescription)
                                        .font(.caption2)
                                        .fontWeight(.medium)
                                        .foregroundStyle(loadColor)
                                }
                            }
                            
                            Slider(value: $tempLoadPercentage, in: 30...100, step: 5)
                                .tint(.blue)
                            
                            // Quick select buttons
                            HStack(spacing: 8) {
                                ForEach([60, 70, 80, 85, 90], id: \.self) { value in
                                    Button("\(value)%") {
                                        withAnimation(.spring(response: 0.3)) {
                                            tempLoadPercentage = Double(value)
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(tempLoadPercentage == Double(value) ? .blue : .gray)
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    }
                } header: {
                    Text("Intensità")
                } footer: {
                    Text("Specificare la % del carico aiuta il sistema a trovare pattern simili e migliorare significativamente il rilevamento delle ripetizioni. Maggiore è la precisione, migliore sarà il tracking.")
                }
                
                // MARK: - Info Section
                Section {
                    InfoRow(
                        icon: "brain.head.profile",
                        title: "Pattern Learning",
                        description: "Il sistema userà questa info per caricare il pattern più adatto"
                    )
                    
                    InfoRow(
                        icon: "chart.line.uptrend.xyaxis",
                        title: "Miglioramento Continuo",
                        description: "Più sessioni fai con lo stesso carico, più accurato diventa il rilevamento"
                    )
                } header: {
                    Text("Come Funziona")
                }
            }
            .navigationTitle("Info Allenamento")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Conferma") {
                        if useLoadPercentage {
                            loadPercentage = tempLoadPercentage
                        } else {
                            loadPercentage = nil
                        }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var loadDescription: String {
        switch tempLoadPercentage {
        case 30..<50: return "Riscaldamento"
        case 50..<65: return "Tecnica/Volume"
        case 65..<75: return "Ipertrofia"
        case 75..<85: return "Forza"
        case 85..<95: return "Max Forza"
        default: return "Massimale"
        }
    }
    
    private var loadColor: Color {
        switch tempLoadPercentage {
        case 30..<50: return .green
        case 50..<65: return .cyan
        case 65..<75: return .blue
        case 75..<85: return .orange
        case 85..<95: return .red
        default: return .purple
        }
    }
}

// MARK: - Info Row Component

struct InfoRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview

#Preview {
    ExerciseInfoSheet(loadPercentage: .constant(70))
}

#Preview("No Load") {
    ExerciseInfoSheet(loadPercentage: .constant(nil))
}
