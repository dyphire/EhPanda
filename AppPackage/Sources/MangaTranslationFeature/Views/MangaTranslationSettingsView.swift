import SFSafeSymbols
import SFSafeSymbolsExt
import Sharing
import SwiftUI

public struct MangaTranslationSettingsView: View {
    @Shared(.mangaTranslationPreferences) private var preferences
    @Shared(.mangaTranslationProviders) private var providers

    @State private var showsClearCacheConfirmation = false
    @State private var cacheClearError: String?

    private var selectedProvider: MangaProviderConfig? {
        providers.first { $0.id == preferences.selectedProviderID }
    }

    private var usesConfiguredProvider: Bool {
        selectedProvider?.isConfigured == true
    }

    private func selectedName(for role: MangaModelRole) -> String {
        MangaModelLibrary.selectedArchive(for: role)?.name ?? String(localized: .notSelected)
    }

    private var selectedProviderName: String {
        if let selectedProvider, selectedProvider.isConfigured {
            return selectedProvider.resolvedDisplayName
        }
        return SystemTranslationProvider.isAvailable
            ? SystemTranslationProvider.displayName : String(localized: .notConfigured)
    }

    private var privacyDescription: String {
        if usesConfiguredProvider {
            return preferences.includeMetadata
                ? String(localized: .privacyProviderMetadata)
                : String(localized: .privacyProviderTextOnly)
        }
        if SystemTranslationProvider.isAvailable {
            return String(localized: .privacySystem)
        }
        return String(localized: .privacyUnconfigured)
    }

    public init() {}

    public var body: some View {
        Form {
            Section {
                Picker(.textDirection, selection: Binding($preferences.textDirection)) {
                    Text(.directionAuto).tag(MangaTranslationTextDirection.auto)
                    Text(.directionHorizontal).tag(MangaTranslationTextDirection.horizontal)
                    Text(.directionVertical).tag(MangaTranslationTextDirection.vertical)
                }
            }

            Section(
                header: Text(.languagesSection),
                footer: Text(.languagesFooter)
            ) {
                Picker(.targetLanguage, selection: Binding($preferences.targetLanguage)) {
                    let systemTarget = MangaTranslationLanguage.systemTarget
                    Text(.systemLanguage(LanguageCodeHelper.displayName(for: systemTarget)))
                        .tag("")
                    ForEach(
                        MangaTranslationLanguage.pickerCodes(including: preferences.targetLanguage),
                        id: \.self
                    ) { language in
                        Text(LanguageCodeHelper.displayName(for: language)).tag(language)
                    }
                }
                Picker(.defaultSourceLanguage, selection: Binding($preferences.sourceLanguage)) {
                    ForEach(
                        MangaTranslationLanguage.pickerCodes(including: preferences.sourceLanguage),
                        id: \.self
                    ) { language in
                        Text(LanguageCodeHelper.displayName(for: language)).tag(language)
                    }
                }
            }

            Section(
                header: Text(.translationSection),
                footer: Text(privacyDescription)
            ) {
                NavigationLink {
                    MangaProviderManagementView()
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(.translationProviders)
                            Text(selectedProviderName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    } icon: {
                        Image(systemSymbol: .translate)
                    }
                }
                NavigationLink {
                    MangaModelManagementView(role: .detector)
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(.detectionModel)
                            Text(selectedName(for: .detector))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    } icon: {
                        Image(systemSymbol: .textViewfinder)
                    }
                }
                NavigationLink {
                    MangaModelManagementView(role: .recognizer)
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(.recognitionModel)
                            Text(selectedName(for: .recognizer))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    } icon: {
                        Image(systemSymbol: .characterTextbox)
                    }
                }
                Toggle(isOn: Binding($preferences.includeMetadata)) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(.includeMetadata)
                        Text(.includeMetadataCaption)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Button(role: .destructive) {
                    showsClearCacheConfirmation = true
                } label: {
                    Label(.clearTranslationCache, systemSymbol: .trash)
                }
            }
        }
        .navigationTitle(.mangaTranslation)
        .alert(Text(.clearTranslationCache), isPresented: $showsClearCacheConfirmation) {
            Button(.clear, role: .destructive, action: clearTranslations)
            Button(.cancel, role: .cancel) {}
        } message: {
            Text(.clearCacheConfirmation)
        }
        .alert(Text(.errorTitle), isPresented: .init(
            get: { cacheClearError != nil },
            set: { if !$0 { cacheClearError = nil } }
        )) {
            Button(.ok, role: .cancel) {}
        } message: {
            if let cacheClearError {
                Text(cacheClearError)
            }
        }
    }

    private func clearTranslations() {
        Task {
            do {
                try MangaTranslationStore.clear()
            } catch {
                cacheClearError = error.localizedDescription
            }
        }
    }
}
