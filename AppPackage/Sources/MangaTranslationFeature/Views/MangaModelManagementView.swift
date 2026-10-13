import SFSafeSymbols
import Sharing
import SwiftUI

public struct MangaModelManagementView: View {
    private let role: MangaModelRole

    @Shared(.mangaModelLibrary) private var libraryConfiguration

    @State private var catalog: ModelCatalog?
    @State private var downloadedArchives: [ModelArchive] = []
    @State private var statuses: [String: MangaModelStorageStatus] = [:]
    @State private var isLoadingCatalog = false
    @State private var preparingStorageKey: String?
    @State private var downloadProgress: Double?
    @State private var deletingStorageKey: String?
    @State private var archiveToDelete: ModelArchive?
    @State private var showsDeleteConfirmation = false
    @State private var alertMessage: String?
    @State private var showsCatalogEditor = false
    @State private var catalogURLDraft = ""

    private var isModelOperationInProgress: Bool {
        preparingStorageKey != nil || deletingStorageKey != nil
    }

    private var canSaveCatalogURL: Bool {
        let value = catalogURLDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: value),
            components.scheme?.lowercased() == "https",
            components.host?.isEmpty == false
        else {
            return false
        }
        return true
    }

    private var availableArchives: [ModelArchive] {
        let downloadedKeys = Set(downloadedArchives.map(\.storageKey))
        return (catalog?.models(for: .mangaOCR) ?? []).filter {
            !downloadedKeys.contains($0.storageKey) && MangaModelSet.supports($0, for: role)
        }
    }

    private var selectableArchives: [ModelArchive] {
        downloadedArchives.filter { MangaModelSet.supports($0, for: role) }
    }

    public init(role: MangaModelRole) {
        self.role = role
    }

    private var roleTitle: String {
        switch role {
        case .detector: return String(localized: .detectionModel)
        case .recognizer: return String(localized: .recognitionModel)
        }
    }

    public var body: some View {
        Form {
            Section(
                header: Text(roleTitle),
                footer: Text(.modelRolesFooter)
            ) {
                if selectableArchives.isEmpty {
                    Text(.noModelsDownloaded)
                        .foregroundStyle(.secondary)
                }
                ForEach(selectableArchives, id: \.storageKey) { archive in
                    Button {
                        MangaModelLibrary.select(archive, for: role)
                        reloadDownloadedModels()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemSymbol: isSelected(archive) ? .checkmarkCircleFill : .circle)
                                .foregroundStyle(isSelected(archive) ? Color.accentColor : Color.secondary)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(archive.name)
                                MangaModelCapabilityChips(archive: archive)
                                if let comment = archive.comment, !comment.isEmpty {
                                    Text(comment)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }

            Section(
                header: Text(.downloadedSection),
                footer: Text(.downloadedFooter)
            ) {
                if downloadedArchives.isEmpty {
                    Text(.noModelsDownloaded)
                        .foregroundStyle(.secondary)
                }
                ForEach(downloadedArchives, id: \.storageKey) { archive in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(archive.name)
                            Text(detailText(for: archive))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            MangaModelCapabilityChips(archive: archive)
                            if let comment = archive.comment, !comment.isEmpty {
                                Text(comment)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if preparingStorageKey == archive.storageKey || deletingStorageKey == archive.storageKey {
                            ProgressView()
                        } else {
                            Button(role: .destructive) {
                                archiveToDelete = archive
                                showsDeleteConfirmation = true
                            } label: {
                                Image(systemSymbol: .trash)
                            }
                            .buttonStyle(.borderless)
                            .disabled(isModelOperationInProgress)
                        }
                    }
                }
            }

            Section(header: Text(.availableModels)) {
                if availableArchives.isEmpty && !isLoadingCatalog {
                    Text(.noAdditionalModels)
                        .foregroundStyle(.secondary)
                }
                ForEach(availableArchives, id: \.storageKey) { archive in
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(archive.name)
                            Text(detailText(for: archive))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            MangaModelCapabilityChips(archive: archive)
                            if let comment = archive.comment, !comment.isEmpty {
                                Text(comment)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if preparingStorageKey == archive.storageKey {
                                ProgressView(value: downloadProgress ?? 0)
                            }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 6) {
                            Text(archive.bytes.map { formatBytes(Int64($0)) } ?? String(localized: .unknown))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button {
                                prepare(archive)
                            } label: {
                                if preparingStorageKey == archive.storageKey {
                                    ProgressView()
                                } else {
                                    Image(systemSymbol: .squareAndArrowDown)
                                        .accessibilityLabel(.downloadAndUse)
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(isModelOperationInProgress)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Section(
                header: HStack {
                    Text(.catalogSection)
                    Spacer()
                    Button(action: refreshCatalog) {
                        Image(systemSymbol: .arrowClockwise)
                            .symbolEffect(.pulse, options: .repeating, isActive: isLoadingCatalog)
                            .accessibilityLabel(.refreshCatalog)
                    }
                    .buttonStyle(.borderless)
                    .disabled(isLoadingCatalog || isModelOperationInProgress)
                },
                footer: Text(.catalogFooter)
            ) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(.catalogUrl)
                        Text(libraryConfiguration.catalogURL)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Button(.edit, action: beginCatalogEdit)
                        .buttonStyle(.borderless)
                        .disabled(isLoadingCatalog)
                }
            }
        }
        .navigationTitle(roleTitle)
        .onAppear {
            catalog = libraryConfiguration.catalog
            reloadDownloadedModels()
            if catalog == nil {
                refreshCatalog()
            }
        }
        .alert(Text(.deleteModel), isPresented: $showsDeleteConfirmation) {
            Button(.delete, role: .destructive) {
                if let archiveToDelete {
                    delete(archiveToDelete)
                }
            }
            Button(.cancel, role: .cancel) {}
        } message: {
            Text(archiveToDelete?.name ?? "")
        }
        .sheet(isPresented: $showsCatalogEditor) {
            NavigationStack {
                Form {
                    Section(footer: Text(.catalogFooter)) {
                        TextField(.catalogUrl, text: $catalogURLDraft)
                            .textContentType(.URL)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                            .onSubmit(saveCatalogURL)
                    }
                }
                .navigationTitle(.catalogUrl)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(.resetToDefault) {
                            catalogURLDraft = ModelLibraryConfiguration.defaultCatalogURL
                            saveCatalogURL()
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(.save, action: saveCatalogURL)
                            .disabled(!canSaveCatalogURL)
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .alert(Text(.errorTitle), isPresented: .init(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )) {
            Button(.ok, role: .cancel) {}
        } message: {
            if let alertMessage {
                Text(alertMessage)
            }
        }
    }

    private func isSelected(_ archive: ModelArchive) -> Bool {
        let key =
            libraryConfiguration.selectedStorageKeys[role.selectionStorageKey]
            ?? libraryConfiguration.selectedStorageKeys[ModelPurpose.mangaOCR.rawValue] ?? ""
        return key == archive.storageKey
    }

    private func beginCatalogEdit() {
        guard !isLoadingCatalog else { return }
        catalogURLDraft = libraryConfiguration.catalogURL
        showsCatalogEditor = true
    }

    private func saveCatalogURL() {
        guard canSaveCatalogURL else { return }
        let value = catalogURLDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        $libraryConfiguration.withLock {
            $0.catalogURL = value
            $0.catalog = nil
        }
        catalog = nil
        catalogURLDraft = ""
        showsCatalogEditor = false
        refreshCatalog()
    }

    private func detailText(for archive: ModelArchive) -> String {
        let version = String(localized: .modelVersion(version: archive.version))
        let size = statuses[archive.storageKey].map { formatBytes($0.totalBytes) }
        return [version, archive.license, size].compactMap { $0 }.joined(separator: " · ")
    }

    private func refreshCatalog() {
        guard !isLoadingCatalog else { return }
        isLoadingCatalog = true
        Task {
            do {
                catalog = try await ModelCatalogService.fetch()
                reloadDownloadedModels()
            } catch {
                alertMessage = error.localizedDescription
            }
            isLoadingCatalog = false
        }
    }

    private func prepare(_ archive: ModelArchive) {
        guard !isModelOperationInProgress else { return }
        preparingStorageKey = archive.storageKey
        downloadProgress = nil
        Task {
            do {
                try await MangaTranslationService.shared.prepareModels(archive: archive) { received, expected in
                    Task { @MainActor in
                        downloadProgress = expected.map { min(1, Double(received) / Double($0)) }
                    }
                }
                MangaModelLibrary.select(archive)
                reloadDownloadedModels()
            } catch is CancellationError {
            } catch {
                alertMessage = error.localizedDescription
            }
            preparingStorageKey = nil
            downloadProgress = nil
        }
    }

    private func delete(_ archive: ModelArchive) {
        guard !isModelOperationInProgress else { return }
        deletingStorageKey = archive.storageKey
        Task {
            do {
                try await MangaTranslationService.shared.clearModels(
                    storage: ModelStorage.shared,
                    archive: archive
                )
                reloadDownloadedModels()
            } catch {
                alertMessage = error.localizedDescription
            }
            deletingStorageKey = nil
        }
    }

    private func reloadDownloadedModels() {
        guard let storage = try? ModelStorage.shared else {
            downloadedArchives = []
            statuses = [:]
            return
        }
        MangaModelLibrary.reconcile(storage: storage)
        downloadedArchives = MangaModelLibrary.downloadedArchives()
        statuses = Dictionary(
            downloadedArchives.map {
                ($0.storageKey, MangaModelManager.status(storage: storage.storage(for: $0), archive: $0))
            },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
