import PhotosUI
import SwiftUI
import UIKit

struct PersonEditorSheet: View {
    let title: LocalizedStringResource
    let initialName: String
    let showsPhoto: Bool
    let deleteConfirmationMessage: String?
    let onCancel: () -> Void
    let onSave: (String, Data?) throws -> Void
    let onDelete: (() -> Void)?

    @State private var name: String
    @State private var imageData: Data?
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isLoadingPhoto = false
    @State private var photoLoadTask: Task<Void, Never>?
    @State private var photoSessionID = UUID()
    @State private var errorMessage: String?
    @State private var measuredContentHeight: CGFloat
    @State private var headerHeight: CGFloat = 56
    @FocusState private var nameIsFocused: Bool

    init(
        title: LocalizedStringResource,
        initialName: String,
        initialImageData: Data? = nil,
        showsPhoto: Bool = true,
        deleteConfirmationMessage: String? = nil,
        onCancel: @escaping () -> Void,
        onSave: @escaping (String, Data?) throws -> Void,
        onDelete: (() -> Void)? = nil
    ) {
        self.title = title
        self.initialName = initialName
        self.showsPhoto = showsPhoto
        self.deleteConfirmationMessage = deleteConfirmationMessage
        self.onCancel = onCancel
        self.onSave = onSave
        self.onDelete = onDelete
        _name = State(initialValue: initialName)
        _imageData = State(initialValue: initialImageData)
        _measuredContentHeight = State(
            initialValue: 78 + (showsPhoto ? 54 : 0) + (onDelete == nil ? 0 : 34) + (initialImageData == nil ? 0 : 40)
        )
    }

    var body: some View {
        IntrinsicModalScaffold(
            title: title,
            leadingActionTitle: "Cancel",
            onLeadingAction: onCancel,
            leadingActionAccessibilityIdentifier: "person-editor.cancel",
            trailingActionTitle: "Save",
            onTrailingAction: save,
            trailingActionIsEnabled: canSave,
            trailingActionAccessibilityIdentifier: "person-editor.save",
            titleAccessibilityIdentifier: "person-editor.title"
        ) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    PersonEditorNameField(name: $name, isFocused: $nameIsFocused)
                    if showsPhoto {
                        PersonEditorPhotoActions(
                            imageData: imageData,
                            isLoading: isLoadingPhoto,
                            onRemove: removePhoto,
                            selectedPhotoItem: $selectedPhotoItem
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
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 16)
                .onGeometryChange(for: CGFloat.self) { geometry in
                    geometry.size.height
                } action: { height in
                    measuredContentHeight = height
                }
            }
            .scrollIndicators(.hidden)
            .accessibilityIdentifier("person-editor.scroll")
            .scrollDismissesKeyboard(.interactively)
        }
        .onPreferenceChange(IntrinsicModalHeaderHeightKey.self) { headerHeight = $0 }
        .presentationDetents([.height(preferredHeight)])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.bg)
        .onAppear { nameIsFocused = true }
        .onChange(of: selectedPhotoItem) { _, item in loadPhoto(item) }
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

    private var preferredHeight: CGFloat {
        headerHeight + measuredContentHeight
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
        isLoadingPhoto = false
        selectedPhotoItem = nil
        imageData = nil
    }

    private func loadPhoto(_ item: PhotosPickerItem?) {
        photoLoadTask?.cancel()
        guard let item else { return }
        let sessionID = photoSessionID
        isLoadingPhoto = true
        photoLoadTask = Task {
            defer {
                if photoSessionID == sessionID, selectedPhotoItem == item { isLoadingPhoto = false }
            }
            do {
                guard let data = try await item.loadTransferable(type: Data.self),
                    let processed = downsampledImageData(data),
                    !Task.isCancelled
                else { throw CocoaError(.fileReadCorruptFile) }
                guard photoSessionID == sessionID, selectedPhotoItem == item else { return }
                imageData = processed
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

    private func downsampledImageData(_ data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let maxDimension: CGFloat = 640
        let scale = min(1, maxDimension / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.jpegData(withCompressionQuality: 0.75) { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

private struct PersonEditorNameField: View {
    @Binding var name: String
    @FocusState.Binding var isFocused: Bool

    var body: some View {
        TextField("Name", text: $name)
            .font(Font.app(17, .regular))
            .focused($isFocused)
            .submitLabel(.done)
            .padding(.horizontal, 14)
            .frame(height: 54)
            .background(Color.card, in: RoundedRectangle(cornerRadius: DesignMetrics.cornerRadius))
            .accessibilityIdentifier("person-editor.name")
    }
}

private struct PersonEditorPhotoActions: View {
    let imageData: Data?
    let isLoading: Bool
    let onRemove: () -> Void
    @Binding var selectedPhotoItem: PhotosPickerItem?

    var body: some View {
        VStack(spacing: 10) {
            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                Label(imageData == nil ? "Choose photo" : "Change photo", systemImage: "photo")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(isLoading)
            .accessibilityIdentifier("person-editor.photo")

            if imageData != nil {
                Button("Remove photo", role: .destructive, action: onRemove)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("person-editor.remove-photo")
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
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.red)
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
