//
//  RealTimeDistanceGraph.swift
//  VBTTracker
//
//  Grafico distanza real-time per Arduino laser sensor
//

import SwiftUI
import Charts

struct RealTimeDistanceGraph: View {
    let data: [DistanceSample]
    let maxSamples: Int = 200 // 4 secondi a 50Hz

    // Calcola range dinamico della distanza
    private var distanceRange: ClosedRange<Double> {
        guard !data.isEmpty else { return 0...1000 }

        let distances = data.map { $0.distance }
        let minDist = distances.min() ?? 0
        let maxDist = distances.max() ?? 1000

        // Aggiungi margine del 10% sopra e sotto
        let range = maxDist - minDist
        let margin = range * 0.1
        let effectiveMargin = max(margin, range < 0.1 ? 50.0 : 0)  // margine minimo di 50mm
        let lower = max(0, minDist - effectiveMargin)
        let upper = maxDist + effectiveMargin

        return lower...upper
    }

    var body: some View {
        Chart {
            ForEach(Array(data.enumerated()), id: \.offset) { index, sample in
                LineMark(
                    x: .value("Sample", index),
                    y: .value("Distance", sample.distance)
                )
                .foregroundStyle(.blue)
                .lineStyle(StrokeStyle(lineWidth: 2))

                // Marker per inizio rep (fase eccentrica)
                if sample.isRepStart {
                    PointMark(
                        x: .value("Sample", index),
                        y: .value("Distance", sample.distance)
                    )
                    .foregroundStyle(.green)
                    .symbolSize(100)
                }

                // Marker per fine rep (fase concentrica)
                if sample.isRepEnd {
                    PointMark(
                        x: .value("Sample", index),
                        y: .value("Distance", sample.distance)
                    )
                    .foregroundStyle(.orange)
                    .symbolSize(100)
                }
            }
        }
        .chartYScale(domain: distanceRange)
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

// MARK: - Preview

#Preview {
    RealTimeDistanceGraph(data: [
        DistanceSample(timestamp: Date(), distance: 800, velocity: 0),
        DistanceSample(timestamp: Date(), distance: 700, velocity: -100),
        DistanceSample(timestamp: Date(), distance: 600, velocity: -100, isRepStart: true),
        DistanceSample(timestamp: Date(), distance: 500, velocity: -100),
        DistanceSample(timestamp: Date(), distance: 600, velocity: 100),
        DistanceSample(timestamp: Date(), distance: 700, velocity: 100),
        DistanceSample(timestamp: Date(), distance: 800, velocity: 100, isRepEnd: true),
    ])
    .padding()
}
