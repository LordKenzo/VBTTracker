//
//  ProfileImagePicker.swift
//  VBTTracker
//
//  Image picker per foto profilo con supporto fotocamera e libreria
//

import SwiftUI
import UIKit
import PhotosUI

// MARK: - Image Picker View

struct ProfileImagePicker: UIViewControllerRepresentable {

    @Binding var image: UIImage?
    @Environment(\.dismiss) var dismiss

    let sourceType: UIImagePickerController.SourceType

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        picker.allowsEditing = true  // Allow cropping to square
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {
        // No updates needed
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {

        let parent: ProfileImagePicker

        init(_ parent: ProfileImagePicker) {
            self.parent = parent
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            // Prefer edited image (cropped) over original
            if let editedImage = info[.editedImage] as? UIImage {
                parent.image = editedImage
            } else if let originalImage = info[.originalImage] as? UIImage {
                parent.image = originalImage
            }

            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

// MARK: - Photo Source Selection Sheet

struct PhotoSourceActionSheet: View {

    @Binding var showImagePicker: Bool
    @Binding var imageSourceType: UIImagePickerController.SourceType
    @Binding var showActionSheet: Bool

    var body: some View {
        VStack(spacing: 0) {
            Button(action: {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    imageSourceType = .camera
                    showActionSheet = false
                    showImagePicker = true
                }
            }) {
                HStack {
                    Image(systemName: "camera.fill")
                        .foregroundColor(.blue)
                    Text("Scatta Foto")
                        .foregroundColor(.primary)
                    Spacer()
                }
                .padding()
            }

            Divider()

            Button(action: {
                imageSourceType = .photoLibrary
                showActionSheet = false
                showImagePicker = true
            }) {
                HStack {
                    Image(systemName: "photo.fill")
                        .foregroundColor(.blue)
                    Text("Scegli dalla Libreria")
                        .foregroundColor(.primary)
                    Spacer()
                }
                .padding()
            }

            Divider()

            Button(action: {
                showActionSheet = false
            }) {
                HStack {
                    Spacer()
                    Text("Annulla")
                        .foregroundColor(.red)
                    Spacer()
                }
                .padding()
            }
        }
        .background(Color(UIColor.systemBackground))
        .cornerRadius(12)
        .padding()
    }
}

// MARK: - Profile Photo View with Picker

struct ProfilePhotoView: View {

    @Binding var profilePhoto: UIImage?

    @State private var showImagePicker = false
    @State private var showActionSheet = false
    @State private var imageSourceType: UIImagePickerController.SourceType = .photoLibrary

    var body: some View {
        VStack {
            // Photo Display
            if let photo = profilePhoto {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 120, height: 120)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(Color.blue, lineWidth: 3)
                    )
                    .shadow(radius: 5)
            } else {
                // Placeholder
                ZStack {
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 120, height: 120)

                    Image(systemName: "person.circle.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 100, height: 100)
                        .foregroundColor(.gray)
                }
            }

            // Action Buttons
            HStack(spacing: 16) {
                Button(action: {
                    showActionSheet = true
                }) {
                    Label(
                        profilePhoto == nil ? "Aggiungi Foto" : "Cambia Foto",
                        systemImage: "camera.fill"
                    )
                    .font(.subheadline)
                }
                .buttonStyle(.bordered)

                if profilePhoto != nil {
                    Button(action: {
                        profilePhoto = nil
                    }) {
                        Label("Rimuovi", systemImage: "trash")
                            .font(.subheadline)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
            }
            .padding(.top, 8)
        }
        .confirmationDialog("Scegli Sorgente", isPresented: $showActionSheet, titleVisibility: .visible) {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("Scatta Foto") {
                    imageSourceType = .camera
                    showImagePicker = true
                }
            }

            Button("Scegli dalla Libreria") {
                imageSourceType = .photoLibrary
                showImagePicker = true
            }

            Button("Annulla", role: .cancel) {}
        }
        .sheet(isPresented: $showImagePicker) {
            ProfileImagePicker(image: $profilePhoto, sourceType: imageSourceType)
                .ignoresSafeArea()
        }
    }
}
