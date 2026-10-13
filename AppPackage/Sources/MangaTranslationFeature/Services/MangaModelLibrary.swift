import Foundation
import Sharing

public enum MangaModelLibrary {
    public static func selectedArchive(for role: MangaModelRole) -> ModelArchive? {
        @Shared(.mangaModelLibrary) var configuration
        let selectedStorageKeys = configuration.selectedStorageKeys
        // Role keys landed after the single combined key; existing selections
        // keep working through the fallback until the next explicit select.
        let storageKey =
            selectedStorageKeys[role.selectionStorageKey]
            ?? selectedStorageKeys[ModelPurpose.mangaOCR.rawValue] ?? ""
        guard !storageKey.isEmpty else { return nil }
        return downloadedArchives().first { $0.storageKey == storageKey }
            ?? configuration.catalog?.models(for: .mangaOCR).first { $0.storageKey == storageKey }
    }

    public static func downloadedArchives() -> [ModelArchive] {
        @Shared(.mangaModelLibrary) var configuration
        return configuration.downloadedArchives
            .filter { $0.isValid && $0.purpose == .mangaOCR }
            .sorted {
                if $0.name == $1.name {
                    return $0.version > $1.version
                }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
    }

    public static func reconcile(storage: ModelStorage) {
        @Shared(.mangaModelLibrary) var configuration
        let registered = downloadedArchives()
        let known = Dictionary(
            (registered + (configuration.catalog?.models(for: .mangaOCR) ?? [])).map { ($0.storageKey, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for archive in known.values {
            let status = MangaModelManager.status(storage: storage.storage(for: archive), archive: archive)
            if status.packageExists {
                register(archive)
            }
        }
        for archive in registered {
            let status = MangaModelManager.status(storage: storage.storage(for: archive), archive: archive)
            if !status.packageExists {
                remove(archive)
            }
        }
    }

    public static func register(_ archive: ModelArchive) {
        guard archive.isValid, archive.purpose == .mangaOCR else { return }
        @Shared(.mangaModelLibrary) var configuration
        $configuration.withLock {
            $0.downloadedArchives.removeAll { $0.storageKey == archive.storageKey }
            $0.downloadedArchives.append(archive)
        }
    }

    public static func select(_ archive: ModelArchive, for role: MangaModelRole) {
        guard archive.purpose == .mangaOCR else { return }
        @Shared(.mangaModelLibrary) var configuration
        $configuration.withLock { library in
            library.selectedStorageKeys[role.selectionStorageKey] = archive.storageKey
            // The legacy combined key keeps the other role working until both
            // roles have explicit picks.
            let roleKeys = MangaModelRole.allCases.map(\.selectionStorageKey)
            if roleKeys.allSatisfy({ library.selectedStorageKeys[$0] != nil }) {
                library.selectedStorageKeys.removeValue(forKey: ModelPurpose.mangaOCR.rawValue)
            }
        }
    }

    public static func select(_ archive: ModelArchive) {
        // Single-role packages must not claim the other role's key: leaving it on
        // its current value keeps the legacy fallback and any explicit pick alive.
        for role in MangaModelRole.allCases where MangaModelSet.supports(archive, for: role) {
            select(archive, for: role)
        }
    }

    public static func remove(_ archive: ModelArchive) {
        @Shared(.mangaModelLibrary) var configuration
        $configuration.withLock {
            $0.downloadedArchives.removeAll { $0.storageKey == archive.storageKey }
            let selectionKeys =
                [ModelPurpose.mangaOCR.rawValue] + MangaModelRole.allCases.map(\.selectionStorageKey)
            for key in selectionKeys where $0.selectedStorageKeys[key] == archive.storageKey {
                $0.selectedStorageKeys.removeValue(forKey: key)
            }
        }
    }
}
