//
//  ExerciseSelectionView.swift
//  VBTTracker
//
//  Vista per selezione esercizio con configurazioni specifiche
//

import SwiftUI

struct ExerciseSelectionView: View {
    @ObservedObject private var exerciseManager = ExerciseManager.shared
    @ObservedObject private var settings = SettingsManager.shared
    @Environment(\.dismiss) var dismiss

    var body: some View {
        List {
            // Current Exercise Section
            Section {
                currentExerciseCard
            } header: {
                Text("Esercizio Corrente")
            } footer: {
                Text("L'esercizio selezionato configura automaticamente ROM, zone di velocità e parametri di rilevamento.")
            }

            // Available Exercises Section
            Section {
                ForEach(exerciseManager.availableExercises) { exercise in
                    ExerciseRow(
                        exercise: exercise,
                        isSelected: exercise.id == exerciseManager.selectedExercise.id,
                        onSelect: {
                            exerciseManager.selectedExercise = exercise
                        }
                    )
                }
            } header: {
                Text("Esercizi Disponibili")
            }

            // Configuration Details Section
            Section {
                configurationDetails
            } header: {
                Text("Configurazione Applicata")
            }
        }
        .navigationTitle("Esercizio")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Current Exercise Card

    private var currentExerciseCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: exerciseManager.selectedExercise.icon)
                    .font(.largeTitle)
                    .foregroundStyle(exerciseManager.selectedExercise.category.color)
                    .frame(width: 60, height: 60)
                    .background(exerciseManager.selectedExercise.category.color.opacity(0.2))
                    .cornerRadius(12)

                VStack(alignment: .leading, spacing: 4) {
                    Text(exerciseManager.selectedExercise.name)
                        .font(.title3)
                        .fontWeight(.bold)

                    Text(exerciseManager.selectedExercise.category.rawValue)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Configuration Details

    private var configurationDetails: some View {
        VStack(spacing: 0) {
            // ROM (Arduino)
            if settings.selectedSensorType == .arduino {
                ConfigRow(
                    icon: "ruler",
                    label: "ROM",
                    value: String(format: "%.2f m (±%.0f%%)",
                        exerciseManager.selectedExercise.defaultROM,
                        exerciseManager.selectedExercise.romTolerance * 100
                    ),
                    color: .blue
                )
                Divider().padding(.leading, 40)
            }

            // Velocity Zones
            ConfigRow(
                icon: "speedometer",
                label: "Zona Forza",
                value: String(format: "%.2f-%.2f m/s",
                    exerciseManager.selectedExercise.velocityRanges.strength.lowerBound,
                    exerciseManager.selectedExercise.velocityRanges.strength.upperBound
                ),
                color: .orange
            )
            Divider().padding(.leading, 40)

            ConfigRow(
                icon: "bolt",
                label: "Zona Forza-Velocità",
                value: String(format: "%.2f-%.2f m/s",
                    exerciseManager.selectedExercise.velocityRanges.strengthSpeed.lowerBound,
                    exerciseManager.selectedExercise.velocityRanges.strengthSpeed.upperBound
                ),
                color: .yellow
            )

            // Movement Profile (WitMotion)
            if settings.selectedSensorType == .witmotion {
                Divider().padding(.leading, 40)

                ConfigRow(
                    icon: "timer",
                    label: "Durata Min Concentrica",
                    value: String(format: "%.1f s",
                        exerciseManager.selectedExercise.movementProfile.minConcentricDuration
                    ),
                    color: .purple
                )

                Divider().padding(.leading, 40)

                ConfigRow(
                    icon: "waveform",
                    label: "Ampiezza Minima",
                    value: String(format: "%.2f g",
                        exerciseManager.selectedExercise.movementProfile.minAmplitude
                    ),
                    color: .green
                )
            }
        }
    }
}

// MARK: - Exercise Row

struct ExerciseRow: View {
    let exercise: Exercise
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 16) {
                // Icon
                Image(systemName: exercise.icon)
                    .font(.title2)
                    .foregroundStyle(exercise.category.color)
                    .frame(width: 44, height: 44)
                    .background(exercise.category.color.opacity(0.2))
                    .cornerRadius(10)

                // Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(exercise.name)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    HStack(spacing: 8) {
                        Label(exercise.category.rawValue, systemImage: exercise.category.icon)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text("•")
                            .foregroundStyle(.secondary)

                        Text("ROM: \(String(format: "%.0f", exercise.defaultROM * 100))cm")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Selection indicator
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.title3)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Config Row

struct ConfigRow: View {
    let icon: String
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 24)

            Text(label)
                .font(.subheadline)

            Spacer()

            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ExerciseSelectionView()
    }
}
