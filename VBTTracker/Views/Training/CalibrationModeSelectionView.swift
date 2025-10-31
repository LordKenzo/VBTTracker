//
//  CalibrationModeSelectionView.swift
//  VBTTracker
//
//  Pulito: niente scelta modalità, lancia direttamente l’automatica
//

import SwiftUI

struct CalibrationModeSelectionView: View {
    @ObservedObject var calibrationManager: ROMCalibrationManager
    @ObservedObject var bleManager: BLEManager
    @Environment(\.dismiss) var dismiss

    @State private var showCalibrationView = false

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color.black, Color(white: 0.1)],
                    startPoint: .top, endPoint: .bottom
                ).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        headerSection

                        if calibrationManager.isCalibrated,
                           let pattern = calibrationManager.learnedPattern {
                            savedPatternCard(pattern)
                        }

                        actionButtons
                    }
                    .padding()
                }
            }
            .navigationTitle("Calibrazione ROM")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Chiudi") { dismiss() }
                }
            }
            .fullScreenCover(isPresented: $showCalibrationView) {
                AutomaticCalibrationView(
                    calibrationManager: calibrationManager,
                    bleManager: bleManager
                )
            }
        }
    }

    // MARK: - UI

    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 60))
                .foregroundStyle(.blue)

            Text("Calibrazione Range of Motion")
                .font(.title2.bold())
                .foregroundStyle(.white)

            Text("Impara il tuo pattern di movimento per un rilevamento più accurato")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(16)
    }

    private func savedPatternCard(_ pattern: LearnedPattern) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("Calibrazione Salvata")
                    .font(.headline).foregroundStyle(.white)
                Spacer()
                Button {
                    calibrationManager.deletePattern()
                } label: {
                    Image(systemName: "trash").foregroundStyle(.red)
                }
            }

            /*
            Divider().background(.white.opacity(0.3))

            VStack(alignment: .leading, spacing: 8) {
                row("Modalità:", pattern.)
                row("Data:", pattern.shortDescription)
                row("ROM:", String(format: "%.0f cm", pattern.estimatedROM * 100))
            }
            */

            Button("Usa Questa Calibrazione") { dismiss() }
                .buttonStyle(.bordered).tint(.green).frame(maxWidth: .infinity)
        }
        .padding()
        .background(Color.green.opacity(0.1))
        .cornerRadius(12)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.caption).fontWeight(.medium)
        }
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button {
                calibrationManager.selectMode(.automatic)
                showCalibrationView = true
            } label: {
                HStack {
                    Image(systemName: "play.circle.fill")
                    Text("Inizia Calibrazione Automatica")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            if !calibrationManager.isCalibrated {
                Button("Salta (usa default)") {
                    calibrationManager.skipCalibration()
                    dismiss()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
    }
}
