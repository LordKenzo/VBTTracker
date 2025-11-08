//
//  RepReviewView.swift
//  VBTTracker
//
//  Vista di revisione ripetizioni prima del salvataggio
//  Permette di eliminare reps non volute
//

import SwiftUI

struct RepReviewView: View {
    @Binding var sessionData: TrainingSessionData
    let targetReps: Int
    let onSave: () -> Void
    let onDiscard: () -> Void

    @Environment(\.dismiss) var dismiss
    @State private var showDiscardAlert = false

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

                VStack(spacing: 0) {
                    // Header con statistiche
                    headerCard
                        .padding()

                    // Lista ripetizioni (editable)
                    if sessionData.reps.isEmpty {
                        emptyStateView
                    } else {
                        repsList
                    }

                    // Pulsanti azione in basso
                    actionButtons
                        .padding()
                }
            }
            .navigationTitle("Revisione Ripetizioni")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Scarta", role: .destructive) {
                        showDiscardAlert = true
                    }
                }
            }
            .alert("Scartare Sessione?", isPresented: $showDiscardAlert) {
                Button("Annulla", role: .cancel) { }
                Button("Scarta", role: .destructive) {
                    onDiscard()
                    dismiss()
                }
            } message: {
                Text("Tutti i dati di questa sessione verranno persi.")
            }
        }
    }

    // MARK: - Header Card

    private var headerCard: some View {
        VStack(spacing: 16) {
            // Icona e titolo
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 50))
                .foregroundStyle(.green)

            Text("Sessione Completata")
                .font(.title2)
                .fontWeight(.bold)

            Text("Rivedi le ripetizioni e rimuovi quelle non volute")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            // Stats
            HStack(spacing: 20) {
                StatBubble(
                    icon: "number.circle.fill",
                    value: "\(sessionData.totalReps)",
                    label: "Reps",
                    color: .blue
                )

                StatBubble(
                    icon: "target",
                    value: "\(sessionData.repsInTarget)",
                    label: "In Target",
                    color: .green
                )

                StatBubble(
                    icon: "chart.line.downtrend.xyaxis",
                    value: String(format: "%.0f%%", sessionData.velocityLoss),
                    label: "VL",
                    color: velocityLossColor
                )
            }
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(16)
    }

    // MARK: - Reps List

    private var repsList: some View {
        List {
            Section {
                ForEach(Array(sessionData.reps.enumerated()), id: \.element.id) { index, rep in
                    RepRowView(
                        repNumber: index + 1,
                        rep: rep,
                        targetZone: sessionData.targetZone,
                        isFirstRep: index == 0
                    )
                    .listRowBackground(Color.white.opacity(0.05))
                }
                .onDelete(perform: deleteReps)
            } header: {
                HStack {
                    Text("Ripetizioni Rilevate")
                    Spacer()
                    Text("Scorri per eliminare")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } footer: {
                if sessionData.totalReps > 0 {
                    Text("Elimina le ripetizioni errate o di riscaldamento scorren do da destra a sinistra.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.orange)

            Text("Nessuna Ripetizione")
                .font(.title3)
                .fontWeight(.semibold)

            Text("Hai eliminato tutte le ripetizioni.\nLa sessione non può essere salvata.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .padding()
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 12) {
            // Pulsante Salva (solo se ci sono reps)
            if sessionData.totalReps > 0 {
                Button(action: {
                    onSave()
                    dismiss()
                }) {
                    Label("SALVA SESSIONE", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }

            // Pulsante Scarta
            Button(action: {
                showDiscardAlert = true
            }) {
                Label("SCARTA SESSIONE", systemImage: "trash.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
            }
            .buttonStyle(.bordered)
            .tint(.red)
        }
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.3))
    }

    // MARK: - Delete Function

    private func deleteReps(at offsets: IndexSet) {
        sessionData.removeReps(at: offsets)
    }

    // MARK: - Helpers

    private var velocityLossColor: Color {
        let loss = sessionData.velocityLoss
        let threshold = sessionData.velocityLossThreshold

        if loss < threshold * 0.5 {
            return .green
        } else if loss < threshold * 0.8 {
            return .orange
        } else {
            return .red
        }
    }
}

// MARK: - Rep Row View

struct RepRowView: View {
    let repNumber: Int
    let rep: RepData
    let targetZone: ClosedRange<Double>
    let isFirstRep: Bool

    private var isInTarget: Bool {
        targetZone.contains(rep.meanVelocity)
    }

    private var zone: String {
        SettingsManager.shared.getTrainingZone(for: rep.meanVelocity).rawValue
    }

    var body: some View {
        HStack(spacing: 12) {
            // Numero rep
            ZStack {
                Circle()
                    .fill(isInTarget ? Color.green.opacity(0.2) : Color.orange.opacity(0.2))
                    .frame(width: 44, height: 44)

                Text("#\(repNumber)")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundStyle(isInTarget ? .green : .orange)
            }

            // Metriche
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    // MPV
                    HStack(spacing: 4) {
                        Text("MPV:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.2f m/s", rep.meanVelocity))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }

                    // PPV
                    HStack(spacing: 4) {
                        Text("PPV:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.2f m/s", rep.peakVelocity))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                }

                // Zona + VL
                HStack(spacing: 12) {
                    Text(zone)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(isInTarget ? Color.green.opacity(0.2) : Color.orange.opacity(0.2))
                        .cornerRadius(4)

                    if !isFirstRep {
                        Text("VL: \(String(format: "%.1f%%", rep.velocityLossFromFirst))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            // Indicatore Target
            Image(systemName: isInTarget ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(isInTarget ? .green : .orange)
                .font(.title3)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Stat Bubble

struct StatBubble: View {
    let icon: String
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)

            Text(value)
                .font(.title3)
                .fontWeight(.bold)

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var sessionData = TrainingSessionData(
        date: Date(),
        targetZone: 0.40...0.75,
        velocityLossThreshold: 20.0,
        reps: [
            RepData(meanVelocity: 0.68, peakVelocity: 0.85, velocityLossFromFirst: 0),
            RepData(meanVelocity: 0.65, peakVelocity: 0.82, velocityLossFromFirst: 4.4),
            RepData(meanVelocity: 0.62, peakVelocity: 0.78, velocityLossFromFirst: 8.8),
            RepData(meanVelocity: 0.15, peakVelocity: 0.20, velocityLossFromFirst: 78.0), // Errore
            RepData(meanVelocity: 0.58, peakVelocity: 0.74, velocityLossFromFirst: 14.7),
        ]
    )

    RepReviewView(
        sessionData: $sessionData,
        targetReps: 5,
        onSave: { print("Salvato!") },
        onDiscard: { print("Scartato!") }
    )
}
