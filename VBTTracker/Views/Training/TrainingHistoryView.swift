//
//  TrainingHistoryView.swift
//  VBTTracker
//
//  Vista storico sessioni di allenamento
//

import SwiftUI

struct TrainingHistoryView: View {
    @ObservedObject var historyManager = TrainingHistoryManager.shared
    @Environment(\.dismiss) var dismiss
    
    @State private var showDeleteAllAlert = false
    @State private var selectedSession: TrainingSession?
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background gradient
                LinearGradient(
                    colors: [Color.black, Color(white: 0.1)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                if historyManager.sessions.isEmpty {
                    emptyStateView
                        .padding()
                } else {
                    // ✅ List principale: swipe funzionante e sfondo pulito
                    List {
                        // MARK: - Statistiche
                        Section {
                            statsCard
                                .listRowBackground(Color.clear)
                                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                        } header: {
                            Text("Statistiche Totali")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                        }
                        
                        // MARK: - Sessioni recenti
                        Section {
                            ForEach(historyManager.sessions) { session in
                                SessionRowView(session: session)
                                    .contentShape(Rectangle())
                                    .onTapGesture { selectedSession = session }
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            withAnimation {
                                                historyManager.deleteSession(session)
                                            }
                                        } label: {
                                            Label("Elimina", systemImage: "trash")
                                        }
                                    }
                                    .contextMenu {
                                        Button(role: .destructive) {
                                            withAnimation {
                                                historyManager.deleteSession(session)
                                            }
                                        } label: {
                                            Label("Elimina", systemImage: "trash")
                                        }
                                    }
                                    // 🔑 elimina la card grigia di sistema
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            }
                            .onDelete { indexSet in
                                withAnimation { delete(at: indexSet) }
                            }
                        } header: {
                            Text("Sessioni Recenti")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden) // lascia il gradient visibile
                    .background(Color.clear)
                }
            }
            .navigationTitle("Storico Allenamenti")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Chiudi") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !historyManager.sessions.isEmpty {
                        Button(role: .destructive) {
                            showDeleteAllAlert = true
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            .sheet(item: $selectedSession) { session in
                TrainingSummaryView(sessionData: session.toTrainingSessionData())
            }
            .alert("Elimina Tutto", isPresented: $showDeleteAllAlert) {
                Button("Annulla", role: .cancel) { }
                Button("Elimina Tutto", role: .destructive) {
                    historyManager.deleteAllSessions()
                }
            } message: {
                Text("Sei sicuro di voler eliminare tutte le \(historyManager.sessions.count) sessioni salvate? Questa azione non può essere annullata.")
            }
        }
    }
    
    private func delete(at indexSet: IndexSet) {
        for index in indexSet {
            guard historyManager.sessions.indices.contains(index) else { continue }
            let session = historyManager.sessions[index]
            historyManager.deleteSession(session)
        }
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "clock.badge.exclamationmark")
                .font(.system(size: 70))
                .foregroundStyle(.gray.opacity(0.5))
            
            Text("Nessuna Sessione Salvata")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Completa un allenamento e scegli di salvarlo per vederlo qui")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }
    
    // MARK: - Stats Card
    
    private var statsCard: some View {
        let stats = historyManager.getStats()
        
        return VStack(spacing: 16) {
            HStack(spacing: 12) {
                StatBadge(
                    icon: "calendar",
                    label: "Sessioni",
                    value: "\(stats.totalSessions)",
                    color: .blue
                )
                
                StatBadge(
                    icon: "figure.strengthtraining.traditional",
                    label: "Reps Totali",
                    value: "\(stats.totalReps)",
                    color: .green
                )
            }
            
            HStack(spacing: 12) {
                StatBadge(
                    icon: "speedometer",
                    label: "Vel. Media",
                    value: String(format: "%.2f", stats.avgMeanVelocity),
                    color: .orange
                )
                
                StatBadge(
                    icon: "chart.line.downtrend.xyaxis",
                    label: "VL Medio",
                    value: String(format: "%.1f%%", stats.avgVelocityLoss),
                    color: .purple
                )
            }
        }
        .padding()
        .background(Color.white.opacity(0.07))
        .cornerRadius(16)
    }
}

// MARK: - Session Row View

struct SessionRowView: View {
    let session: TrainingSession
    
    var body: some View {
        HStack(spacing: 16) {
            // Date Badge
            VStack(spacing: 4) {
                Text(dateDay)
                    .font(.title2)
                    .fontWeight(.bold)
                Text(dateMonth)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 50)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.10))
            .cornerRadius(10)
            
            // Session Info
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "target")
                        .foregroundStyle(zoneColor)
                        .font(.caption)
                    Text(session.targetZone.displayName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Spacer()
                    if session.wasSuccessful {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    }
                }
                
                HStack(spacing: 12) {
                    Label("\(session.completedReps)/\(session.targetReps)", systemImage: "figure.strengthtraining.traditional")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Label(String(format: "%.1f%%", session.velocityLoss), systemImage: "chart.line.downtrend.xyaxis")
                        .font(.caption)
                        .foregroundStyle(velocityLossColor)
                }
            }
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .background(Color.white.opacity(0.07))
        .cornerRadius(16)
    }
    
    private var dateDay: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd"
        return formatter.string(from: session.date)
    }
    
    private var dateMonth: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        return formatter.string(from: session.date).uppercased()
    }
    
    private var zoneColor: Color {
        switch session.targetZone.color {
        case "red": return .red
        case "orange": return .orange
        case "yellow": return .yellow
        case "green": return .green
        case "blue": return .blue
        default: return .gray
        }
    }
    
    private var velocityLossColor: Color {
        let vl = session.velocityLoss
        if vl < 10 { return .green }
        else if vl < 20 { return .yellow }
        else { return .red }
    }
}

// MARK: - TrainingSession Extension

extension TrainingSession {
    func toTrainingSessionData() -> TrainingSessionData {
        let ranges = SettingsManager.shared.velocityRanges
        let targetRange: ClosedRange<Double>
        
        switch self.targetZone {
        case .maxStrength: targetRange = ranges.maxStrength
        case .strength: targetRange = ranges.strength
        case .strengthSpeed: targetRange = ranges.strengthSpeed
        case .speed: targetRange = ranges.speed
        case .maxSpeed: targetRange = ranges.maxSpeed
        case .tooSlow: targetRange = 0.0...0.15
        }
        
        let repDataArray = self.reps.map { $0.toRepData() }
        
        return TrainingSessionData(
            date: self.date,
            targetZone: targetRange,
            velocityLossThreshold: self.velocityLossThreshold,
            reps: repDataArray
        )
    }
}

// MARK: - Preview

#Preview {
    TrainingHistoryView()
}
