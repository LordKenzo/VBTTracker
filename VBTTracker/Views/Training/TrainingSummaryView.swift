//
//  TrainingSummaryView.swift
//  VBTTracker
//
//  Riepilogo post-allenamento con analisi dettagliata rep
//

import SwiftUI
import Charts

struct TrainingSummaryView: View {
    let sessionData: TrainingSessionData
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                LinearGradient(
                    colors: [Color.black, Color(white: 0.1)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Header Stats
                        headerStats
                        
                        // Velocity Loss Indicator
                        velocityLossCard
                        
                        // Chart
                        velocityChart
                        
                        // Rep-by-Rep Analysis
                        repByRepSection
                        
                        // Action Buttons
                        actionButtons
                    }
                    .padding()
                }
            }
            .navigationTitle("Riepilogo Allenamento")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Fine") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    // MARK: - Header Stats
    
    private var headerStats: some View {
        VStack(spacing: 16) {
            // Success Icon
            Image(systemName: sessionData.wasSuccessful ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 60))
                .foregroundStyle(sessionData.wasSuccessful ? .green : .orange)
            
            Text(sessionData.wasSuccessful ? "Allenamento Completato!" : "Serie Interrotta")
                .font(.title2)
                .fontWeight(.bold)
            
            // Key Stats Grid
            HStack(spacing: 20) {
                StatCard(
                    icon: "number.circle.fill",
                    label: "Rep Totali",
                    value: "\(sessionData.totalReps)",
                    color: .blue
                )
                
                StatCard(
                    icon: "target",
                    label: "In Target",
                    value: "\(sessionData.repsInTarget)",
                    color: .green
                )
                
                StatCard(
                    icon: "chart.line.downtrend.xyaxis",
                    label: "Vel. Loss",
                    value: String(format: "%.1f%%", sessionData.velocityLoss),
                    color: velocityLossColor
                )
            }
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(16)
    }
    
    // MARK: - Velocity Loss Card
    
    private var velocityLossCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "chart.line.downtrend.xyaxis")
                    .foregroundStyle(velocityLossColor)
                
                Text("Velocity Loss")
                    .font(.headline)
                
                Spacer()
                
                Text(String(format: "%.1f%%", sessionData.velocityLoss))
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(velocityLossColor)
            }
            
            // Progress bar
            GeometryReader { geometry in
                // ✅ Calcola valori normalizzati e validali
                let normalizedVL = sessionData.velocityLoss / 100.0
                let normalizedThreshold = sessionData.velocityLossThreshold / 100.0
                
                // ✅ Assicura valori finiti e nel range [0, 1]
                let safeVL = normalizedVL.isFinite ? min(max(normalizedVL, 0), 1.0) : 0
                let safeThreshold = normalizedThreshold.isFinite ? min(max(normalizedThreshold, 0), 1.0) : 0
                
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.1))
                    
                    // Progress
                    RoundedRectangle(cornerRadius: 8)
                        .fill(velocityLossColor)
                        .frame(width: geometry.size.width * safeVL)
                    
                    // Threshold marker (solo se valido)
                    if safeThreshold > 0 && safeThreshold <= 1.0 {
                        Rectangle()
                            .fill(Color.white.opacity(0.5))
                            .frame(width: 2)
                            .offset(x: geometry.size.width * safeThreshold)
                    }
                }
            }
            .frame(height: 12)
            
            Text(velocityLossDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(velocityLossColor.opacity(0.1))
        .cornerRadius(12)
    }
    
    // MARK: - Velocity Chart
    
    private var velocityChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Velocità per Rep")
                .font(.headline)
            
            Chart {
                // Target zone background
                RectangleMark(
                    xStart: .value("Start", 0),
                    xEnd: .value("End", sessionData.reps.count + 1),
                    yStart: .value("Min", sessionData.targetZone.lowerBound),
                    yEnd: .value("Max", sessionData.targetZone.upperBound)
                )
                .foregroundStyle(.green.opacity(0.1))
                
                // Mean velocity line
                ForEach(Array(sessionData.reps.enumerated()), id: \.offset) { index, rep in
                    LineMark(
                        x: .value("Rep", index + 1),
                        y: .value("Vel Media", rep.meanVelocity)
                    )
                    .foregroundStyle(.blue)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    
                    PointMark(
                        x: .value("Rep", index + 1),
                        y: .value("Vel Media", rep.meanVelocity)
                    )
                    .foregroundStyle(.blue)
                    .symbolSize(60)
                }
                
                // Peak velocity line
                ForEach(Array(sessionData.reps.enumerated()), id: \.offset) { index, rep in
                    LineMark(
                        x: .value("Rep", index + 1),
                        y: .value("Vel Picco", rep.peakVelocity)
                    )
                    .foregroundStyle(.orange)
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 3]))
                    
                    PointMark(
                        x: .value("Rep", index + 1),
                        y: .value("Vel Picco", rep.peakVelocity)
                    )
                    .foregroundStyle(.orange)
                    .symbolSize(40)
                }
            }
            .frame(height: 200)
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisValueLabel {
                        if let velocity = value.as(Double.self) {
                            Text(String(format: "%.2f", velocity))
                                .font(.caption)
                        }
                    }
                }
            }
            
            // Legend
            HStack(spacing: 20) {
                LegendItem(color: .blue, label: "Vel. Media", style: .solid)
                LegendItem(color: .orange, label: "Vel. Picco", style: .dashed)
                LegendItem(color: .green, label: "Zona Target", style: .filled)
            }
            .font(.caption)
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
    }
    
    // MARK: - Rep by Rep Section
    
    private var repByRepSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Dettaglio Ripetizioni")
                .font(.headline)
            
            ForEach(Array(sessionData.reps.enumerated()), id: \.offset) { index, rep in
                RepDetailRow(
                    repNumber: index + 1,
                    rep: rep,
                    targetZone: sessionData.targetZone,
                    isFirstRep: index == 0
                )
            }
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
    }
    
    // MARK: - Action Buttons
    
    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button(action: {
                // TODO: Export data
            }) {
                Label("Esporta Dati (CSV)", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            
            Button(action: {
                dismiss()
            }) {
                Text("Nuovo Allenamento")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }
    
    // MARK: - Computed Properties
    
    private var velocityLossColor: Color {
        let vl = sessionData.velocityLoss
        if vl < 10 { return .green }
        else if vl < 20 { return .yellow }
        else if vl < 30 { return .orange }
        else { return .red }
    }
    
    private var velocityLossDescription: String {
        let vl = sessionData.velocityLoss
        if vl < sessionData.velocityLossThreshold {
            return "✅ Ottimo! Affaticamento sotto controllo"
        } else if vl < sessionData.velocityLossThreshold + 10 {
            return "⚠️ Soglia superata leggermente"
        } else {
            return "🔴 Affaticamento significativo raggiunto"
        }
    }
}

// MARK: - Rep Detail Row

struct RepDetailRow: View {
    let repNumber: Int
    let rep: RepData
    let targetZone: ClosedRange<Double>
    let isFirstRep: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Rep number badge
                ZStack {
                    Circle()
                        .fill(targetIndicatorColor.opacity(0.2))
                        .frame(width: 40, height: 40)
                    
                    Text("\(repNumber)")
                        .font(.headline)
                        .foregroundStyle(.white)
                }
                
                // Velocities
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Media:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Text(String(format: "%.2f m/s", rep.meanVelocity))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                        
                        Spacer()
                        
                        // Target indicator
                        targetIndicator
                    }
                    
                    HStack {
                        Text("Picco:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Text(String(format: "%.2f m/s", rep.peakVelocity))
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.orange)
                    }
                }
                
                Spacer()
                
                // Velocity loss indicator (if not first rep)
                if !isFirstRep {
                    VStack(spacing: 2) {
                        Text(String(format: "%.1f%%", rep.velocityLossFromFirst))
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(velocityLossColor)
                        
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(velocityLossColor)
                    }
                }
            }
            .padding()
            .background(Color.white.opacity(0.03))
            .cornerRadius(12)
        }
    }
    
    private var targetIndicator: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(targetIndicatorColor)
                .frame(width: 12, height: 12)
            
            Text(targetIndicatorText)
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(targetIndicatorColor)
        }
    }
    
    private var targetIndicatorColor: Color {
        let deviation = abs(rep.meanVelocity - targetZoneMid) / targetZoneMid
        
        if targetZone.contains(rep.meanVelocity) {
            return .green  // In target
        } else if deviation < 0.15 {
            return .yellow  // Vicino (entro 15%)
        } else {
            return .red  // Lontano
        }
    }
    
    private var targetIndicatorText: String {
        if targetZone.contains(rep.meanVelocity) {
            return "Target"
        } else if rep.meanVelocity < targetZone.lowerBound {
            return "Lenta"
        } else {
            return "Veloce"
        }
    }
    
    private var targetZoneMid: Double {
        (targetZone.lowerBound + targetZone.upperBound) / 2
    }
    
    private var velocityLossColor: Color {
        let vl = rep.velocityLossFromFirst
        if vl < 10 { return .green }
        else if vl < 20 { return .yellow }
        else { return .red }
    }
}

// MARK: - Supporting Views

struct StatCard: View {
    let icon: String
    let label: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
            
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(color.opacity(0.1))
        .cornerRadius(12)
    }
}

struct LegendItem: View {
    enum Style {
        case solid, dashed, filled
    }
    
    let color: Color
    let label: String
    let style: Style
    
    var body: some View {
        HStack(spacing: 6) {
            switch style {
            case .solid:
                Rectangle()
                    .fill(color)
                    .frame(width: 20, height: 3)
            case .dashed:
                Rectangle()
                    .fill(color)
                    .frame(width: 20, height: 3)
                    .overlay(
                        Rectangle()
                            .stroke(style: StrokeStyle(lineWidth: 3, dash: [3, 2]))
                            .foregroundStyle(color)
                    )
            case .filled:
                Rectangle()
                    .fill(color.opacity(0.3))
                    .frame(width: 20, height: 12)
                    .cornerRadius(2)
            }
            
            Text(label)
        }
    }
}

// MARK: - Data Models

struct TrainingSessionData {
    let date: Date
    let targetZone: ClosedRange<Double>
    let velocityLossThreshold: Double
    let reps: [RepData]
    
    var totalReps: Int {
        reps.count
    }
    
    var repsInTarget: Int {
        reps.filter { targetZone.contains($0.meanVelocity) }.count
    }
    
    var velocityLoss: Double {
        guard let first = reps.first?.meanVelocity,
              let last = reps.last?.meanVelocity,
              first > 0 else { return 0 }
        
        return ((first - last) / first) * 100
    }
    
    var wasSuccessful: Bool {
        // Successful if completed all reps OR stopped due to VL threshold
        velocityLoss >= velocityLossThreshold || totalReps > 0
    }
    
    // MARK: - Factory Method from TrainingSessionManager
    
    static func from(
        manager: TrainingSessionManager,
        targetZone: TrainingZone,
        velocityLossThreshold: Double
    ) -> TrainingSessionData {
        let targetRange = getRangeForZone(targetZone)
        
        // Create RepData for each rep
        var repsData: [RepData] = []
        let peakVelocities = manager.getRepPeakVelocities()
        
        guard !peakVelocities.isEmpty else {
            return TrainingSessionData(
                date: Date(),
                targetZone: targetRange,
                velocityLossThreshold: velocityLossThreshold,
                reps: []
            )
        }
        
        let firstPeakVelocity = peakVelocities.first!
        
        for (_, peakVel) in peakVelocities.enumerated() {
            // Calculate velocity loss from first rep
            let vlFromFirst = ((firstPeakVelocity - peakVel) / firstPeakVelocity) * 100
            
            // Mean velocity = peak velocity (simplified)
            // In futuro potrebbe essere calcolata diversamente
            let meanVel = peakVel * 0.85 // Stima: mean ≈ 85% del picco
            
            repsData.append(RepData(
                meanVelocity: meanVel,
                peakVelocity: peakVel,
                velocityLossFromFirst: max(0, vlFromFirst)
            ))
        }
        
        return TrainingSessionData(
            date: Date(),
            targetZone: targetRange,
            velocityLossThreshold: velocityLossThreshold,
            reps: repsData
        )
    }
    
    private static func getRangeForZone(_ zone: TrainingZone) -> ClosedRange<Double> {
        let ranges = SettingsManager.shared.velocityRanges
        switch zone {
        case .maxStrength: return ranges.maxStrength
        case .strength: return ranges.strength
        case .strengthSpeed: return ranges.strengthSpeed
        case .speed: return ranges.speed
        case .maxSpeed: return ranges.maxSpeed
        case .tooSlow: return 0.0...0.15
        }
    }
}

struct RepData: Identifiable {
    let id = UUID()
    let meanVelocity: Double
    let peakVelocity: Double
    let velocityLossFromFirst: Double
}

// MARK: - Preview

#Preview {
    TrainingSummaryView(sessionData: TrainingSessionData(
        date: Date(),
        targetZone: 0.40...0.75,
        velocityLossThreshold: 20.0,
        reps: [
            RepData(meanVelocity: 0.68, peakVelocity: 0.85, velocityLossFromFirst: 0),
            RepData(meanVelocity: 0.65, peakVelocity: 0.82, velocityLossFromFirst: 4.4),
            RepData(meanVelocity: 0.62, peakVelocity: 0.78, velocityLossFromFirst: 8.8),
            RepData(meanVelocity: 0.58, peakVelocity: 0.74, velocityLossFromFirst: 14.7),
            RepData(meanVelocity: 0.55, peakVelocity: 0.70, velocityLossFromFirst: 19.1),
            RepData(meanVelocity: 0.52, peakVelocity: 0.66, velocityLossFromFirst: 23.5),
        ]
    ))
}
