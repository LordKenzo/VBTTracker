//
//  HomeView.swift
//  VBTTracker
//

import SwiftUI

struct HomeView: View {
    @StateObject private var bleManager = BLEManager()
    @ObservedObject var settings = SettingsManager.shared
    @StateObject private var calibrationManager = CalibrationManager()

    @State private var showSettings = false
    @State private var showZonesEditor = false  // 👈 Per aprire la vista delle zone

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color.blue.opacity(0.1), Color.purple.opacity(0.05)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        heroSection
                        sensorStatusCard
                        quickActionsSection
                    }
                    .padding()
                }
                .gesture(
                    DragGesture()
                        .onEnded { value in
                            // Swipe verso destra → mostra zone
                            if value.translation.width > 100 {
                                showZonesEditor = true
                            }
                        }
                )
            }
            .navigationTitle("VBT Tracker")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showSettings = true }) {
                        Image(systemName: "gearshape.fill")
                            .foregroundStyle(.blue)
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(
                    bleManager: bleManager,
                    calibrationManager: calibrationManager
                )
            }
            .sheet(isPresented: $showZonesEditor) {
                VelocityRangesEditorView()
            }
            .onAppear {
                loadSavedCalibration()
                attemptAutoConnect()
            }
        }
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 70))
                .foregroundStyle(
                    LinearGradient(colors: [.blue, .purple],
                                   startPoint: .topLeading,
                                   endPoint: .bottomTrailing)
                )

            Text("Velocity Based Training")
                .font(.title2).fontWeight(.bold)
            Text("Allena con precisione scientifica")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical)
    }

    // MARK: - Sensor Card

    private var sensorStatusCard: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top) {
                Circle()
                    .fill(bleManager.isConnected ? Color.green : Color.gray)
                    .frame(width: 12, height: 12)
                    .padding(.top, 4)

                VStack(alignment: .leading, spacing: 6) {
                    Text(bleManager.sensorName)
                        .font(.headline)

                    Text(bleManager.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        if let sr = bleManager.sampleRateHz {
                            Label(formatSampleRate(sr), systemImage: "waveform.path.ecg")
                                .font(.caption2)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.blue.opacity(0.12))
                                .foregroundStyle(.blue)
                                .clipShape(Capsule())
                        }
                        if bleManager.isCalibrated {
                            Label("Calibrato", systemImage: "checkmark.seal.fill")
                                .font(.caption2)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.green.opacity(0.15))
                                .foregroundStyle(.green)
                                .clipShape(Capsule())
                        }
                    }
                }

                Spacer()

                if !bleManager.isConnected {
                    Button(action: { showSettings = true }) {
                        Label("Connetti", systemImage: "sensor.fill")
                            .font(.caption)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
    }

    // MARK: - Quick Actions

    private var quickActionsSection: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Azioni Rapide").font(.headline)
                Spacer()
                // 👈 RIMOSSO il pulsante "Mostra Zone"
            }

            NavigationLink(destination: TrainingSelectionView(bleManager: bleManager)) {
                HStack {
                    Image(systemName: "play.circle.fill")
                        .font(.title2)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Inizia Allenamento").font(.headline)
                        Text("Scegli obiettivo e inizia")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(
                    LinearGradient(colors: [Color.blue, Color.blue.opacity(0.8)],
                                   startPoint: .leading, endPoint: .trailing)
                )
                .foregroundStyle(.white)
                .cornerRadius(16)
                .shadow(color: .blue.opacity(0.3), radius: 8, x: 0, y: 4)
            }
            .disabled(!bleManager.isConnected)
            
            // 💡 OPZIONALE: aggiungi un hint visivo per lo swipe
            Text("💡 Swipe verso destra per vedere le zone di allenamento")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
        }
    }

    // MARK: - Helpers

    private func loadSavedCalibration() {
        if let calibration = settings.savedCalibration {
            bleManager.applyCalibration(calibration)
            print("📥 Calibrazione caricata da settings")
        }
    }

    private func attemptAutoConnect() {
        if let id = settings.lastConnectedPeripheralID {
            print("🔄 Tentativo auto-riconnessione a peripheralID: \(id)")
            DispatchQueue.main.async { [bleManager] in
                bleManager.attemptAutoReconnect(with: id)
            }
        } else {
            print("ℹ️ Nessun dispositivo salvato per auto-connessione")
        }
    }
}

// MARK: - Utils

private func formatSampleRate(_ hz: Double?) -> String {
    guard let hz, hz > 0 else { return "—" }
    return hz >= 100 ? "\(Int(round(hz))) Hz" : String(format: "%.1f Hz", hz)
}

#Preview {
    HomeView()
}
