import PhotosUI
import SwiftUI
import UIKit

struct PersonEditorSheet: View {
    let title: LocalizedStringResource
    let initialName: String
    let showsPhoto: Bool
    let deleteConfirmationMessage: String?
    let focusesNameOnAppear: Bool
    let onCancel: () -> Void
    let onSave: (String, Data?) throws -> Void
    let onDelete: (() -> Void)?

    @State private var name: String
    @State private var imageData: Data?
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isPhotoPickerPresented = false
    @State private var isLoadingPhoto = false
    @State private var photoLoadTask: Task<Void, Never>?
    @State private var photoSessionID = UUID()
    @State private var cropSession: PersonPhotoCropSession?
    @State private var errorMessage: String?
    @FocusState private var nameIsFocused: Bool

    init(
        title: LocalizedStringResource,
        initialName: String,
        initialImageData: Data? = nil,
        showsPhoto: Bool = true,
        deleteConfirmationMessage: String? = nil,
        focusesNameOnAppear: Bool = true,
        onCancel: @escaping () -> Void,
        onSave: @escaping (String, Data?) throws -> Void,
        onDelete: (() -> Void)? = nil
    ) {
        self.title = title
        self.initialName = initialName
        self.showsPhoto = showsPhoto
        self.deleteConfirmationMessage = deleteConfirmationMessage
        self.focusesNameOnAppear = focusesNameOnAppear
        self.onCancel = onCancel
        self.onSave = onSave
        self.onDelete = onDelete
        _name = State(initialValue: initialName)
        _imageData = State(initialValue: initialImageData)
    }

    var body: some View {
        VStack(spacing: 0) {
            PersonEditorHeader(
                title: title,
                name: name,
                canSave: canSave,
                onCancel: onCancel,
                onSave: save
            )
            ScrollView {
                VStack(spacing: 20) {
                    PersonEditorNameField(name: $name, isFocused: $nameIsFocused)
                    if showsPhoto {
                        PersonEditorPhotoMenu(
                            imageData: imageData,
                            isLoading: isLoadingPhoto,
                            isPickerPresented: $isPhotoPickerPresented,
                            onRemove: removePhoto
                        )
                    }
                    if let onDelete {
                        PersonEditorDeleteAction(
                            name: initialName,
                            confirmationMessage: deleteConfirmationMessage ?? "",
                            isDisabled: isLoadingPhoto,
                            action: onDelete
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .accessibilityIdentifier("person-editor.scroll")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.bg)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.bg)
        .interactiveDismissDisabled(isLoadingPhoto)
        .onAppear {
            if focusesNameOnAppear {
                nameIsFocused = true
            }
        }
        .photosPicker(
            isPresented: $isPhotoPickerPresented,
            selection: $selectedPhotoItem,
            matching: .images
        )
        .onChange(of: selectedPhotoItem) { _, item in
            loadPhoto(item)
        }
        .fullScreenCover(item: $cropSession) { session in
            PersonPhotoCropView(
                image: session.image,
                onCancel: {
                    selectedPhotoItem = nil
                    cropSession = nil
                },
                onConfirm: { data in
                    imageData = data
                    selectedPhotoItem = nil
                    cropSession = nil
                }
            )
        }
        .alert(
            "Photo and name",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } })
        ) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .onDisappear {
            photoLoadTask?.cancel()
            photoLoadTask = nil
            photoSessionID = UUID()
            isLoadingPhoto = false
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !isLoadingPhoto
    }

    private func save() {
        guard canSave else { return }
        do {
            try onSave(name, imageData)
        } catch PersonUpdateError.duplicateName {
            errorMessage = NSLocalizedString("A person with this name already exists.", comment: "")
        } catch {
            errorMessage = NSLocalizedString("Could not save person changes.", comment: "")
        }
    }

    private func removePhoto() {
        photoLoadTask?.cancel()
        photoSessionID = UUID()
        isLoadingPhoto = false
        selectedPhotoItem = nil
        imageData = nil
    }

    private func loadPhoto(_ item: PhotosPickerItem?) {
        photoLoadTask?.cancel()
        photoSessionID = UUID()
        guard let item else {
            isLoadingPhoto = false
            return
        }
        let sessionID = photoSessionID
        isLoadingPhoto = true
        photoLoadTask = Task {
            defer {
                if photoSessionID == sessionID, selectedPhotoItem == item {
                    isLoadingPhoto = false
                }
            }
            do {
                guard let data = try await item.loadTransferable(type: Data.self),
                    let image = PersonPhotoImageProcessor.normalizedImage(from: data),
                    !Task.isCancelled
                else { throw CocoaError(.fileReadCorruptFile) }
                guard photoSessionID == sessionID, selectedPhotoItem == item else { return }
                cropSession = PersonPhotoCropSession(image: image)
            } catch is CancellationError {
                return
            } catch {
                guard photoSessionID == sessionID, selectedPhotoItem == item else { return }
                errorMessage = NSLocalizedString("Could not load that photo.", comment: "")
                isLoadingPhoto = false
                selectedPhotoItem = nil
            }
        }
    }
}

private struct PersonEditorHeader: View {
    let title: LocalizedStringResource
    let name: String
    let canSave: Bool
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.ink)
                    .frame(width: 42, height: 42)
                    .background(Color.card, in: Circle())
            }
            .accessibilityLabel(Text("Cancel"))
            .accessibilityIdentifier("person-editor.cancel")

            Spacer(minLength: 0)
            if !name.isEmpty {
                Text(verbatim: name)
                    .accessibilityIdentifier("person-editor.title")
                    .accessibilityAddTraits(.isHeader)
            } else {
                Text(title)
                    .accessibilityIdentifier("person-editor.title")
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer(minLength: 0)

            Button(action: onSave) {
                Image(systemName: "checkmark")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.white)
                    .frame(width: 42, height: 42)
                    .background(canSave ? Color.ink : Color.muted3, in: Circle())
            }
            .disabled(!canSave)
            .accessibilityLabel(Text("Save"))
            .accessibilityIdentifier("person-editor.save")
        }
        .font(.headline)
        .foregroundStyle(Color.ink)
        .multilineTextAlignment(.center)
        .lineLimit(2)
        .minimumScaleFactor(0.75)
        .frame(minHeight: 58)
        .padding(.horizontal, 18)
        .padding(.top, 12)
    }
}

private struct PersonEditorNameField: View {
    @Binding var name: String
    @FocusState.Binding var isFocused: Bool

    var body: some View {
        TextField("Name", text: $name)
            .font(.title3)
            .multilineTextAlignment(.center)
            .focused($isFocused)
            .submitLabel(.done)
            .onSubmit { isFocused = false }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(minHeight: 58)
            .background(Color.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .accessibilityIdentifier("person-editor.name")
    }
}

private struct PersonEditorPhotoMenu: View {
    let imageData: Data?
    let isLoading: Bool
    @Binding var isPickerPresented: Bool
    let onRemove: () -> Void

    var body: some View {
        Menu {
            Button {
                isPickerPresented = true
            } label: {
                Label {
                    if imageData == nil {
                        Text("Choose photo")
                    } else {
                        Text("Change photo")
                    }
                } icon: {
                    Image(systemName: "photo")
                }
            }
            .accessibilityIdentifier("person-editor.choose-photo")

            if imageData != nil {
                Button(role: .destructive, action: onRemove) {
                    Label("Remove photo", systemImage: "trash")
                }
                .accessibilityIdentifier("person-editor.remove-photo")
            }
        } label: {
            VStack(spacing: 10) {
                ZStack(alignment: .bottomTrailing) {
                    photoPreview
                        .frame(width: 116, height: 116)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.sep, lineWidth: 1))
                    Image(systemName: isLoading ? "hourglass" : "plus")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.white)
                        .frame(width: 28, height: 28)
                        .background(Color.ink, in: Circle())
                        .overlay(Circle().stroke(Color.bg, lineWidth: 2))
                }
                Text("Photo")
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color.muted)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(Color.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .disabled(isLoading)
        .accessibilityLabel(imageData == nil ? Text("Choose photo") : Text("Change photo"))
        .accessibilityIdentifier("person-editor.photo")
    }

    @ViewBuilder
    private var photoPreview: some View {
        if let imageData, let image = UIImage(data: imageData) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            Circle()
                .fill(Color.bg)
                .overlay {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 48, weight: .light, design: .default))
                        .foregroundStyle(Color.muted3)
                }
        }
    }
}

private struct PersonEditorDeleteAction: View {
    let name: String
    let confirmationMessage: String
    let isDisabled: Bool
    let action: () -> Void
    @State private var isConfirming = false

    var body: some View {
        Button {
            isConfirming = true
        } label: {
            Label("Delete", systemImage: "trash")
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.red)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 58)
                .background(Color.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityIdentifier("person-editor.delete")
        .alert("Delete \(name)?", isPresented: $isConfirming) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive, action: action)
        } message: {
            Text(confirmationMessage)
        }
    }
}
