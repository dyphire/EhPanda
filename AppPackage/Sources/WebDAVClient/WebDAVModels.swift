import Foundation
import AppModels
import Sharing

/// WebDAV server connection and auto-backup preferences, persisted whole in app storage like the
/// other account preferences. The password is plaintext, matching the project's posture for the
/// manga-translation API keys and the backup envelope's cookie snapshots — the backup screen's
/// description warns the user accordingly.
public struct WebDAVConfiguration: Codable, Equatable, Sendable, SchemaVersioned {
    public init(
        serverURL: String = "",
        path: String = "/ehpanda",
        username: String = "",
        password: String = "",
        isEnabled: Bool = false,
        lastBackupDate: Date? = nil
    ) {
        self.serverURL = serverURL
        self.path = path
        self.username = username
        self.password = password
        self.isEnabled = isEnabled
        self.lastBackupDate = lastBackupDate
    }

    /// This model's schema history (oldest → newest); see `SchemaVersioned` / `VersionedSchema`.
    /// `currentSchemaVersion` derives from the head. Append a `VersionedSchema` and adopt
    /// `MigratableModel` when a breaking change lands.
    public static var schemas: [any VersionedSchema.Type] { [SchemaV1.self] }
    /// The v1 base schema. Its `migrate` is empty — nothing precedes v1, and the engine only runs
    /// schemas newer than the stored version, so it exists solely to anchor version 1.
    enum SchemaV1: VersionedSchema {
        static let version = 1
        static func migrate(_ object: inout [String: JSONValue]) throws {}
    }
    // Self-validating (see `SchemaVersion`): a newer/downgrade blob is rejected on decode, failing
    // the whole decode so Sharing resets to the key default. A field added later must stay optional
    // so old blobs keep decoding.
    public var schemaVersion: SchemaVersion<WebDAVConfiguration> = 1

    /// The server root, as typed. May lack a scheme; use `normalizedServerURL` for requests.
    public var serverURL: String
    /// Remote directory for backups, e.g. "/ehpanda". Created on demand during upload.
    public var path: String
    public var username: String
    public var password: String
    /// Drives the launch/foreground staleness auto-backup.
    public var isEnabled: Bool
    /// Last successful backup, local time. The staleness check compares against this.
    public var lastBackupDate: Date?

    /// Trimmed server URL with a default https scheme — what the user typed may lack one.
    public var normalizedServerURL: URL? {
        let trimmed = serverURL.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed), url.scheme != nil {
            return url
        }
        return URL(string: "https://" + trimmed)
    }

    /// Minimum input for any WebDAV operation: a reachable-looking server plus credentials.
    public var isUsable: Bool { normalizedServerURL != nil && !username.isEmpty }
}

/// One file entry from a PROPFIND listing.
public struct WebDAVFile: Equatable, Hashable, Identifiable, Sendable {
    public init(name: String, path: String, size: Int, modifiedDate: Date? = nil) {
        self.name = name
        self.path = path
        self.size = size
        self.modifiedDate = modifiedDate
    }

    public var id: String { path }
    public var name: String
    /// The raw href from the server (URL-encoded, as returned).
    public var path: String
    public var size: Int
    public var modifiedDate: Date?
}

extension SharedKey where Self == AppStorageKey<WebDAVConfiguration>.Default {
    public static var webDAVConfiguration: Self {
        Self[.appStorage("webDAVConfiguration"), default: WebDAVConfiguration()]
    }
}
