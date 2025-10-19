//
//  VelocitySettingsView.swift
//  VBTTracker
//
//  Created by Lorenzo Franceschini on 19/10/25.
//


//
//  VelocitySettingsView.swift
//  VBTTracker
//
//  Impostazioni Zone Velocità e Velocity Loss
//

import SwiftUI

struct VelocitySettingsView: View {
    @ObservedObject var settings = SettingsManager.shared
    @State private var showVelocityRangesEditor = false
    
    var body: some View {
        List {
            // MARK: - Measurement Mode Section
            Section {
                Picker("Modalità Misurazione", selection: $settings.velocityMeasurementMode) {
                    Text("Solo Concentrica").tag(VBTRepDetector.VelocityMeasurementMode.concentricOnly)
                    Text("ROM Completo").tag(VBTRepDetector.VelocityMeasurementMode.fullROM)
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Modalità Misurazione")
            } footer: {
                Text(measurementModeDescription)
            }
            
            // MARK: - Velocity Zones Section
            Section {
                Button(action: { showVelocityRangesEditor = true }) {
                    HStack {
                        Label("Zone di Velocità", systemImage: "speedometer")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                // Preview zone attuali
                VStack(alignment: .leading, spacing: 8) {
                    velocityZonePreview(
                        title: "Forza Massima",
                        range: settings.velocityRanges.maxStrength,
                        color: .red
                    )
                    
                    velocityZonePreview(
                        title: "Forza",
                        range: settings.velocityRanges.strength,
                        color: .orange
                    )
                    
                    velocityZonePreview(
                        title: "Forza-Velocità",
                        range: settings.velocityRanges.strengthSpeed,
                        color: .yellow
                    )
                    
                    velocityZonePreview(
                        title: "Velocità",
                        range: settings.velocityRanges.speed,
                        color: .green
                    )
                    
                    velocityZonePreview(
                        title: "Velocità Massima",
                        range: settings.velocityRanges.maxSpeed,
                        color: .blue
                    )
                }
                .font(.caption)
                .padding(.vertical, 4)
                
            } header: {
                Text("Zone di Allenamento")
            } footer: {
                Text("Definisci i range di velocità per ogni zona di allenamento. Basati su letteratura scientifica per panca piana.")
            }
            
            // MARK: - Velocity Loss Section
            Section {
                SliderSettingRow(
                    title: "Soglia Velocity Loss",
                    value: $settings.velocityLossThreshold,
                    range: 10.0...40.0,
                    step: 5.0,
                    unit: "%",
                    description: velocityLossDescription
                )
                
                ToggleSettingRow(
                    title: "Auto-Stop su VL",
                    isOn: $settings.stopOnVelocityLoss,
                    icon: "stop.circle.fill",
                    description: "Interrompi automaticamente la serie al raggiungimento della soglia"
                )
                
            } header: {
                Text("Velocity Loss")
            } footer: {
                Text("La Velocity Loss indica l'affaticamento neuromuscolare. Valori tipici: forza massima 10-15%, forza 15-20%, ipertrofia 20-30%.")
            }
            
            // MARK: - Scientific Info
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: "book.closed.fill")
                            .foregroundStyle(.blue)
                        Text("Base Scientifica")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        referenceRow("González-Badillo & Sánchez-Medina (2010)", "MPV solo fase concentrica")
                        referenceRow("Pareja-Blanco et al. (2017)", "Velocity Loss su fase propulsiva")
                        referenceRow("Banyard et al. (2019)", "Standard VBT professionale")
                    }
                    .padding(.leading, 36)
                }
                .padding(.vertical, 4)
            } header: {
                Text("Riferimenti")
            }
        }
        .navigationTitle("Velocità")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showVelocityRangesEditor) {
            VelocityRangesEditorView()
        }
    }
    
    // MARK: - Helper Views
    
    private func velocityZonePreview(title: String, range: ClosedRange<Double>, color: Color) -> some View {
        HStack {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            
            Text(title)
                .foregroundStyle(.primary)
            
            Spacer()
            
            Text("\(range.lowerBound, specifier: "%.2f") - \(range.upperBound, specifier: "%.2f") m/s")
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
    
    private func referenceRow(_ author: String, _ description: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(author)
                .font(.caption)
                .fontWeight(.medium)
            
            Text(description)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
    
    // MARK: - Computed Properties
    
    private var measurementModeDescription: String {
        switch settings.velocityMeasurementMode {
        case .concentricOnly:
            return "Standard VBT: misura solo la fase concentrica (sollevamento). Raccomandato per confronto con letteratura scientifica."
        case .fullROM:
            return "Misura l'intero movimento (eccentrica + concentrica). Utile per analisi complete del movimento."
        }
    }
    
    private var velocityLossDescription: String {
        let threshold = settings.velocityLossThreshold
        
        if threshold <= 15 {
            return "🔴 Forza Massima: basso volume, alta intensità"
        } else if threshold <= 20 {
            return "🟠 Forza: volume moderato"
        } else if threshold <= 30 {
            return "🟡 Ipertrofia: volume alto"
        } else {
            return "⚠️ Volume molto alto, rischio affaticamento eccessivo"
        }
    }
}

#Preview {
    NavigationStack {
        VelocitySettingsView()
    }
}