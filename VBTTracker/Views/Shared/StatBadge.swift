//
//  StatBadge.swift
//  VBTTracker
//
//  Created by Lorenzo Franceschini on 19/10/25.
//

import SwiftUI

// MARK: - Stat Badge

struct StatBadge: View {
    let label: String
    let value: String
    
    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(.white)
            
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color.white.opacity(0.1))
        .cornerRadius(12)
    }
}

#Preview("Stat Badge") {
    HStack(spacing: 16) {
        StatBadge(label: "ROM", value: "52cm")
        StatBadge(label: "Soglia", value: "0.42g")
    }
    .padding()
    .background(Color.black)
}
