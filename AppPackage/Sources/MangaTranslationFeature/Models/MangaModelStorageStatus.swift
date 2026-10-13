import Foundation

public struct MangaModelStorageStatus: Equatable, Sendable {
    public let packageExists: Bool
    public let compiledExists: Bool
    public let packageBytes: Int64
    public let compiledBytes: Int64
    public let downloadBytes: Int64

    public init(
        packageExists: Bool, compiledExists: Bool,
        packageBytes: Int64, compiledBytes: Int64, downloadBytes: Int64
    ) {
        self.packageExists = packageExists
        self.compiledExists = compiledExists
        self.packageBytes = packageBytes
        self.compiledBytes = compiledBytes
        self.downloadBytes = downloadBytes
    }

    public var totalBytes: Int64 { packageBytes + compiledBytes + downloadBytes }
}
