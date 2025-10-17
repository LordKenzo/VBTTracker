//
//  RealTimeAccelerationGraph.swift
//  VBTTracker
//
//  Grafico accelerazione real-time come app WitMotion
//

import SwiftUI
import Charts

struct RealTimeAccelerationGraph: View {
    let data: [AccelerationSample]
    let maxSamples: Int = 200 // 4 secondi a 50Hz
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Accelerazione Verticale (Z)")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Chart {
                ForEach(Array(data.enumerated()), id: \.offset) { index, sample in
                    LineMark(
                        x: .value("Sample", index),
                        y: .value("AccZ", sample.accZ)
                    )
                    .foregroundStyle(.orange)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    
                    // Marker per picchi (rep rilevate)
                    if sample.isPeak {
                        PointMark(
                            x: .value("Sample", index),
                            y: .value("AccZ", sample.accZ)
                        )
                        .foregroundStyle(.green)
                        .symbolSize(100)
                    }
                    
                    // Marker per valli
                    if sample.isValley {
                        PointMark(
                            x: .value("Sample", index),
                            y: .value("AccZ", sample.accZ)
                        )
                        .foregroundStyle(.red)
                        .symbolSize(100)
                    }
                }
                
                // Linea zero
                RuleMark(y: .value("Zero", 0))
                    .foregroundStyle(.white.opacity(0.3))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3]))
            }
            .chartYScale(domain: -2...2) // ±2g range
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5))
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .frame(height: 200)
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
    }
}

// MARK: - Preview

#Preview {
    RealTimeAccelerationGraph(data: [
        AccelerationSample(timestamp: Date(), accZ: 0.5),
        AccelerationSample(timestamp: Date(), accZ: -0.3),
        AccelerationSample(timestamp: Date(), accZ: 0.8, isPeak: true),
        AccelerationSample(timestamp: Date(), accZ: -0.5, isValley: true),
    ])
    .padding()
}
