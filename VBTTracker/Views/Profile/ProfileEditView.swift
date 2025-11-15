//
//  ProfileEditView.swift
//  VBTTracker
//
//  Vista completa per modificare il profilo utente
//

import SwiftUI

struct ProfileEditView: View {

    @ObservedObject var profileManager = ProfileManager.shared
    @Environment(\.dismiss) var dismiss

    // Local state for editing
    @State private var editedProfile: UserProfile
    @State private var editedPhoto: UIImage?

    @State private var showValidationError = false
    @State private var validationErrorMessage = ""

    // Age picker
    @State private var showAgePicker = false
    private let ageRange = 10...120

    // Height/Weight pickers
    @State private var showHeightPicker = false
    @State private var showWeightPicker = false
    private let heightRange = stride(from: 100.0, through: 250.0, by: 0.5)
    private let weightRange = stride(from: 30.0, through: 300.0, by: 0.1)

    init() {
        // Initialize state from current profile
        let currentProfile = ProfileManager.shared.profile
        let currentPhoto = ProfileManager.shared.profilePhoto

        _editedProfile = State(initialValue: currentProfile)
        _editedPhoto = State(initialValue: currentPhoto)
    }

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Photo Section
                Section {
                    HStack {
                        Spacer()
                        ProfilePhotoView(profilePhoto: $editedPhoto)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                } header: {
                    Text("Foto Profilo")
                }

                // MARK: - Basic Info Section
                Section {
                    TextField("Nome", text: $editedProfile.name)
                        .autocorrectionDisabled()

                    // Age Picker
                    HStack {
                        Text("Età")
                        Spacer()
                        if let age = editedProfile.age {
                            Text("\(age) anni")
                                .foregroundColor(.secondary)
                        } else {
                            Text("Non impostata")
                                .foregroundColor(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        showAgePicker = true
                    }

                    // Gender Picker
                    Picker("Sesso", selection: $editedProfile.gender) {
                        Text("Non specificato").tag(nil as UserProfile.Gender?)
                        ForEach(UserProfile.Gender.allCases, id: \.self) { gender in
                            Text(gender.rawValue).tag(gender as UserProfile.Gender?)
                        }
                    }

                } header: {
                    Text("Informazioni Personali")
                } footer: {
                    Text("Questi dati saranno utilizzati per personalizzare l'esperienza e calcolare l'indice di fatica.")
                }

                // MARK: - Physical Characteristics Section
                Section {
                    // Height
                    HStack {
                        Text("Altezza")
                        Spacer()
                        if let height = editedProfile.height {
                            Text(String(format: "%.1f cm", height))
                                .foregroundColor(.secondary)
                        } else {
                            Text("Non impostata")
                                .foregroundColor(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        showHeightPicker = true
                    }

                    // Weight
                    HStack {
                        Text("Peso")
                        Spacer()
                        if let weight = editedProfile.weight {
                            Text(String(format: "%.1f kg", weight))
                                .foregroundColor(.secondary)
                        } else {
                            Text("Non impostato")
                                .foregroundColor(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        showWeightPicker = true
                    }

                    // BMI Display (if available)
                    if let bmi = editedProfile.bmi, let category = editedProfile.bmiCategory {
                        HStack {
                            Text("BMI")
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(String(format: "%.1f", bmi))
                                    .foregroundColor(.secondary)
                                Text(category)
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                        }
                    }

                } header: {
                    Text("Caratteristiche Fisiche")
                }

                // MARK: - Profile Completion Section
                Section {
                    HStack {
                        Text("Completamento Profilo")
                        Spacer()
                        Text("\(Int(editedProfile.completionPercentage * 100))%")
                            .foregroundColor(editedProfile.isComplete ? .green : .orange)
                    }

                    ProgressView(value: editedProfile.completionPercentage)
                        .tint(editedProfile.isComplete ? .green : .orange)

                } footer: {
                    if !editedProfile.isComplete {
                        Text("Completa tutti i campi per sbloccare funzionalità avanzate come l'indice di fatica personalizzato.")
                    }
                }
            }
            .navigationTitle("Profilo Utente")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") {
                        saveProfile()
                    }
                    .disabled(editedProfile.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .alert("Errore Validazione", isPresented: $showValidationError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(validationErrorMessage)
            }
            // Age Picker Sheet
            .sheet(isPresented: $showAgePicker) {
                NavigationStack {
                    Picker("Età", selection: Binding(
                        get: { editedProfile.age ?? 25 },
                        set: { editedProfile.age = $0 }
                    )) {
                        ForEach(Array(ageRange), id: \.self) { age in
                            Text("\(age) anni").tag(age)
                        }
                    }
                    .pickerStyle(.wheel)
                    .navigationTitle("Seleziona Età")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Fine") {
                                showAgePicker = false
                            }
                        }
                    }
                }
                .presentationDetents([.height(300)])
            }
            // Height Picker Sheet
            .sheet(isPresented: $showHeightPicker) {
                NavigationStack {
                    Picker("Altezza", selection: Binding(
                        get: { editedProfile.height ?? 170.0 },
                        set: { editedProfile.height = $0 }
                    )) {
                        ForEach(Array(heightRange), id: \.self) { height in
                            Text(String(format: "%.1f cm", height)).tag(height)
                        }
                    }
                    .pickerStyle(.wheel)
                    .navigationTitle("Seleziona Altezza")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Fine") {
                                showHeightPicker = false
                            }
                        }
                    }
                }
                .presentationDetents([.height(300)])
            }
            // Weight Picker Sheet
            .sheet(isPresented: $showWeightPicker) {
                NavigationStack {
                    Picker("Peso", selection: Binding(
                        get: { editedProfile.weight ?? 70.0 },
                        set: { editedProfile.weight = $0 }
                    )) {
                        ForEach(Array(weightRange), id: \.self) { weight in
                            Text(String(format: "%.1f kg", weight)).tag(weight)
                        }
                    }
                    .pickerStyle(.wheel)
                    .navigationTitle("Seleziona Peso")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Fine") {
                                showWeightPicker = false
                            }
                        }
                    }
                }
                .presentationDetents([.height(300)])
            }
        }
    }

    // MARK: - Actions

    private func saveProfile() {
        do {
            // Validate profile
            try editedProfile.validate()

            // Save to ProfileManager
            profileManager.profile = editedProfile
            profileManager.profilePhoto = editedPhoto

            print("✅ Profile saved successfully")
            dismiss()
        } catch let error as UserProfileValidationError {
            validationErrorMessage = error.localizedDescription
            showValidationError = true
        } catch {
            validationErrorMessage = "Errore sconosciuto: \(error.localizedDescription)"
            showValidationError = true
        }
    }
}

// MARK: - Preview

#Preview {
    ProfileEditView()
}
