//
//  PatternRow.swift
//  VBTTracker
//
//  Created by Lorenzo Franceschini on 19/10/25.
//


//
//  CalibrationSharedComponents.swift
//  VBTTracker
//
//  Componenti UI condivise per viste di calibrazione
//

import SwiftUI

// MARK: - Pattern Row

struct PatternRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Spacer()
            
            Text(value)
                .font(.headline)
                .foregroundStyle(.white)
        }
    }
}





// MARK: - Preview

#Preview("Pattern Row") {
    VStack(spacing: 8) {
        PatternRow(label: "Ampiezza", value: "0.85 g")
        PatternRow(label: "Durata", value: "0.75 s")
        PatternRow(label: "Velocità", value: "1.15 m/s")
    }
    .padding()
    .background(Color.black)
}



