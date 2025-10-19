//
//  InstructionRow.swift
//  VBTTracker
//
//  Created by Lorenzo Franceschini on 18/10/25.
//


//
//  SharedViews.swift
//  VBTTracker
//
//  Componenti UI condivisi
//

import SwiftUI

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
            Circle()
                .fill(Color.blue)
                .frame(width: 30, height: 30)
                .overlay {
                    Text(number)
                        .font(.headline)
                        .foregroundStyle(.white)
                }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(text)
                    .font(.headline)
                    .foregroundStyle(.white)
                
                if let detail = detail {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
        }
    }
}