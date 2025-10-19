//
//  InstructionRow.swift
//  VBTTracker
//
//  Created by Lorenzo Franceschini on 19/10/25.
//

import SwiftUI

// MARK: - Instruction Row

struct InstructionRow: View {
    let number: String
    let text: String
    let detail: String?
    
    init(number: String, text: String, detail: String? = nil) {
        self.number = number
        self.text = text
        self.detail = detail
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Number badge
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.2))
                    .frame(width: 32, height: 32)
                
                Text(number)
                    .font(.headline)
                    .foregroundStyle(.blue)
            }
            
            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(text)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                
                if let detail = detail {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

#Preview("Instruction Row") {
    VStack(spacing: 12) {
        InstructionRow(
            number: "1",
            text: "Carica bilanciere LEGGERO",
            detail: "Usa solo il bilanciere o carico minimo"
        )
        InstructionRow(
            number: "2",
            text: "Posizionati correttamente",
            detail: "Come faresti normalmente nell'esercizio"
        )
    }
    .padding()
    .background(Color.black)
}
