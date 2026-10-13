import SFSafeSymbols
import SFSafeSymbolsExt
import SwiftUI

public struct MangaProviderEditorView: View {
    private let providerID: String
    private let isNew: Bool

    @Environment(\.dismiss) private var dismiss

    @State private var displayName: String
    @State private var baseURL: String
    @State private var endpointPreset: MangaProviderEndpointPreset
    @State private var model: String
    @State private var apiKey: String
    @State private var availableModels: [String] = []
    @State private var isLoadingModels = false
    @State private var isSaving = false
    @State private var alertMessage: String?

    public init(provider: MangaProviderConfig, isNew: Bool) {
        providerID = provider.id
        self.isNew = isNew
        let initialBaseURL =
            isNew && provider.baseURL.isEmpty
            ? MangaProviderEndpointPreset.openAI.baseURL ?? "" : provider.baseURL
        _displayName = State(initialValue: provider.displayName)
        _baseURL = State(initialValue: initialBaseURL)
        _endpointPreset = State(initialValue: MangaProviderEndpointPreset(baseURL: initialBaseURL))
        _model = State(initialValue: provider.model)
        _apiKey = State(initialValue: provider.apiKey)
    }

    private var draft: MangaProviderConfig {
        MangaProviderConfig(
            id: providerID,
            baseURL: baseURL,
            model: model,
            displayName: displayName,
            apiKey: apiKey
        )
    }

    private var modelChoices: [String] {
        if model.isEmpty || availableModels.contains(model) {
            return availableModels
        }
        return availableModels + [model]
    }

    private var canSave: Bool {
        draft.isConfigured
    }

    private var canFetchModels: Bool {
        draft.endpoint("models") != nil
            && !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var body: some View {
        Form {
            Section(
                header: Text(.openaiCompatibleApi),
                footer: Text(.apiSectionFooter)
            ) {
                TextField(.displayName, text: $displayName)
                Picker(.baseUrl, selection: $endpointPreset) {
                    ForEach(MangaProviderEndpointPreset.allCases) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
                .onChange(of: endpointPreset) { _, preset in
                    if let presetURL = preset.baseURL {
                        baseURL = presetURL
                    }
                }
                if endpointPreset == .custom {
                    TextField(.customBaseUrl, text: $baseURL)
                        .textContentType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                }
                SecureField(.apiKey, text: $apiKey)
                    .textContentType(.password)
                    .autocorrectionDisabled()
            }

            Section(
                header: HStack {
                    Text(.model)
                    Spacer()
                    Button(action: fetchModels) {
                        if isLoadingModels {
                            Label(.loadingModels, systemSymbol: .arrowClockwise)
                        } else {
                            Label(.fetchModels, systemSymbol: .arrowClockwise)
                        }
                    }
                    .symbolEffect(.pulse, options: .repeating, isActive: isLoadingModels)
                    .buttonStyle(.borderless)
                    .disabled(isLoadingModels || !canFetchModels)
                },
                footer: Text(.modelSectionFooter)
            ) {
                HStack(spacing: 8) {
                    TextField(.model, text: $model)
                        .autocorrectionDisabled()
                    if !availableModels.isEmpty {
                        Menu {
                            ForEach(modelChoices, id: \.self) { availableModel in
                                Button(availableModel) {
                                    model = availableModel
                                }
                            }
                        } label: {
                            Image(systemSymbol: .chevronUpChevronDown)
                                .accessibilityLabel(.availableModels)
                        }
                    }
                }
            }
        }
        .navigationTitle(isNew ? String(localized: .addProvider) : String(localized: .editProvider))
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(action: save) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Text(.save)
                    }
                }
                .disabled(!canSave || isSaving)
            }
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

    private func fetchModels() {
        guard !isLoadingModels else { return }
        isLoadingModels = true
        Task {
            do {
                availableModels = try await MangaProviderModelService.fetchModels(
                    configuration: draft
                )
                if availableModels.isEmpty {
                    alertMessage = String(localized: .noModelsReturned)
                }
            } catch {
                availableModels = []
                alertMessage =
                    (error as? MangaTranslationFailure)?.description ?? error.localizedDescription
            }
            isLoadingModels = false
        }
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = trimmedName.isEmpty ? draft.resolvedDisplayName : trimmedName
        let provider = MangaProviderConfig(
            id: providerID,
            baseURL: baseURL,
            model: model,
            displayName: resolvedName,
            apiKey: apiKey
        )
        MangaProviderLibrary.save(provider, select: isNew)
        dismiss()
    }
}
