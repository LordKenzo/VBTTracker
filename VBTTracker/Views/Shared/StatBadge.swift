//
//  StatBadge.swift
//  VBTTracker
//
//  Badge per visualizzare statistiche con icona e colore
//

import SwiftUI

struct StatBadge: View {
    let icon: String?
    let label: String
    let value: String
    let color: Color?
    
    // Inizializzatore completo (con icona e colore)
    init(icon: String, label: String, value: String, color: Color) {
        self.icon = icon
        self.label = label
        self.value = value
        self.color = color
    }
    
    // Inizializzatore semplice (retrocompatibilità - senza icona)
    init(label: String, value: String) {
        self.icon = nil
        self.label = label
        self.value = value
        self.color = nil
    }
    
    var body: some View {
        VStack(spacing: 8) {
            // Icona (se presente)
            if let icon = icon {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color ?? .blue)
            }
            
            // Valore
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(.white)
            
            // Label
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            (color ?? .blue).opacity(0.1)
        )
        .cornerRadius(12)
    }
}

// MARK: - Preview

#Preview("Con Icona") {
    HStack(spacing: 12) {
        StatBadge(
            icon: "calendar",
            label: "Sessioni",
            value: "12",
            color: .blue
        )
        
        StatBadge(
            icon: "figure.strengthtraining.traditional",
            label: "Reps Totali",
            value: "156",
            color: .green
        )
    }
    .padding()
    .background(Color.black)
}

#Preview("Semplice") {
    StatBadge(
        label: "Media",
        value: "0.75 m/s"
    )
    .padding()
    .background(Color.black)
}
