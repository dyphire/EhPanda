import Foundation

public struct MangaModelPaths: Sendable {
    public let packagesDirectory: URL
    public let compiledDirectory: URL
    public let manifest: ModelPackageManifest

    public init(packagesDirectory: URL, compiledDirectory: URL, manifest: ModelPackageManifest) {
        self.packagesDirectory = packagesDirectory
        self.compiledDirectory = compiledDirectory
        self.manifest = manifest
    }

    public func packageURL(component: String, file: String) -> URL? {
        guard let path = manifest.components[component]?.files[file] else { return nil }
        return packagesDirectory.appendingPathComponent(path)
    }

    public func compiledModelURL(component: String, file: String) -> URL {
        compiledDirectory.appendingPathComponent("\(component)-\(file).mlmodelc")
    }
}
