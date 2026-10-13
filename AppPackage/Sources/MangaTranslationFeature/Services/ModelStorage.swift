import Foundation

public struct ModelStorage: Hashable, Sendable {
    public let rootDirectory: URL

    public init(rootDirectory: URL) {
        self.rootDirectory = rootDirectory
    }

    public var packagesDirectory: URL { rootDirectory.appendingPathComponent("Models") }
    public var compiledDirectory: URL { rootDirectory.appendingPathComponent("CompiledModels") }
    public var downloadsDirectory: URL { rootDirectory.appendingPathComponent("Downloads") }

    public func storage(for archive: ModelArchive) -> ModelStorage {
        ModelStorage(
            rootDirectory:
                rootDirectory
                .appendingPathComponent("Bundles", isDirectory: true)
                .appendingPathComponent(archive.purpose.rawValue, isDirectory: true)
                .appendingPathComponent(archive.storageKey, isDirectory: true)
        )
    }

    public static var shared: ModelStorage {
        get throws {
            let rootDirectory = URL.applicationSupportDirectory
                .appendingPathComponent("MangaTranslationModels", isDirectory: true)
            try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
            // Models are re-downloadable from the catalog; keep them out of backups.
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var target = rootDirectory
            try? target.setResourceValues(values)
            return ModelStorage(rootDirectory: rootDirectory)
        }
    }
}
