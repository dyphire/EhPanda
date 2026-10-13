import SFSafeSymbols
import SFSafeSymbolsExt
import Sharing
import SwiftUI

public struct MangaProviderManagementView: View {
    @Shared(.mangaTranslationPreferences) private var preferences
    @Shared(.mangaTranslationProviders) private var providers

    @State private var editingProvider: MangaProviderConfig?
    @State private var providerToDelete: MangaProviderConfig?
    @State private var showsDeleteConfirmation = false
    @State private var testingProviderID: String?
    @State private var testResultMessage: String?

    private var showsTestResult: Binding<Bool> {
        Binding(
            get: { testResultMessage != nil },
            set: { if !$0 { testResultMessage = nil } }
        )
    }

    private var sortedProviders: [MangaProviderConfig] {
        providers.sorted {
            $0.resolvedDisplayName.localizedStandardCompare($1.resolvedDisplayName) == .orderedAscending
        }
    }

    public init() {}

    public var body: some View {
        Form {
            Section(
                header: HStack {
                    Text(.providersSection)
                    Spacer()
                    Button {
                        editingProvider = MangaProviderConfig(baseURL: "", model: "", displayName: "")
                    } label: {
                        Label(.addProvider, systemSymbol: .plus)
                    }
                    .buttonStyle(.borderless)
                },
                footer: Text(.providersFooter)
            ) {
                if SystemTranslationProvider.isAvailable {
                    Button {
                        $preferences.withLock { $0.selectedProviderID = "" }
                    } label: {
                        HStack(spacing: 12) {
                            Image(
                                systemSymbol: preferences.selectedProviderID.isEmpty
                                    ? .checkmarkCircleFill : .circle
                            )
                            .foregroundStyle(
                                preferences.selectedProviderID.isEmpty
                                    ? Color.accentColor : Color.secondary
                            )
                            VStack(alignment: .leading, spacing: 4) {
                                Text(SystemTranslationProvider.displayName)
                                Text(.defaultOnDevice)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
                if sortedProviders.isEmpty {
                    Text(.noProvidersConfigured)
                        .foregroundStyle(.secondary)
                }
                ForEach(sortedProviders) { provider in
                    let isSelected = preferences.selectedProviderID == provider.id
                    Button {
                        $preferences.withLock { $0.selectedProviderID = provider.id }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemSymbol: isSelected ? .checkmarkCircleFill : .circle)
                                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                            providerDetails(provider)
                            if testingProviderID == provider.id {
                                Spacer()
                                ProgressView()
                            }
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        providerActions(for: provider)
                    }
                    .contextMenu {
                        providerActions(for: provider)
                    }
                }
            }
        }
        .navigationTitle(.translationProviders)
        .sheet(item: $editingProvider) { provider in
            NavigationStack {
                MangaProviderEditorView(
                    provider: provider,
                    isNew: !providers.contains(where: { $0.id == provider.id })
                )
            }
        }
        .alert(Text(.testProvider), isPresented: showsTestResult) {
            Button(.ok, role: .cancel) {}
        } message: {
            if let testResultMessage {
                Text(testResultMessage)
            }
        }
        .alert(Text(.deleteProvider), isPresented: $showsDeleteConfirmation) {
            Button(.delete, role: .destructive) {
                if let providerToDelete {
                    MangaProviderLibrary.delete(providerToDelete)
                }
            }
            Button(.cancel, role: .cancel) {}
        } message: {
            Text(providerToDelete?.resolvedDisplayName ?? "")
        }
    }

    @ViewBuilder
    private func providerDetails(_ provider: MangaProviderConfig) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(provider.resolvedDisplayName)
            Text(provider.baseURL)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(provider.model)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private func providerActions(for provider: MangaProviderConfig) -> some View {
        Button {
            test(provider)
        } label: {
            Label(.testProvider, systemSymbol: .network)
        }
        .disabled(!provider.isConfigured)

        Button {
            editingProvider = provider
        } label: {
            Label(.edit, systemSymbol: .pencil)
        }

        Button(role: .destructive) {
            providerToDelete = provider
            showsDeleteConfirmation = true
        } label: {
            Label(.delete, systemSymbol: .trash)
        }
    }

    private func test(_ provider: MangaProviderConfig) {
        guard testingProviderID == nil else { return }
        testingProviderID = provider.id
        Task {
            let message: String
            do {
                let translations = try await MangaTranslationService.shared.testProvider(
                    configuration: provider,
                    preferences: preferences
                )
                message = translations.joined(separator: " / ")
            } catch {
                message =
                    (error as? MangaTranslationFailure)?.description ?? error.localizedDescription
            }
            // A provider deleted mid-test has no row left to show its result for.
            if providers.contains(where: { $0.id == provider.id }) {
                testResultMessage = message
            }
            testingProviderID = nil
        }
    }
}
