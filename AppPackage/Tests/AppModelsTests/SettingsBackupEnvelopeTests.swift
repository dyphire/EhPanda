import Testing
import Foundation
import AppModels

// The backup envelope must round-trip across app versions: members absent from a file decode as
// `nil` (import keeps the current value), unknown extra keys are ignored, and the `JSONValue`
// bridging carries feature-module payloads without `AppModels` knowing their types.
@Suite
struct SettingsBackupEnvelopeTests {
    private let exportDate = Date(timeIntervalSince1970: 1_700_000_000)

    @Test
    func fullEnvelopeRoundTripsExactly() throws {
        let preferencesJSON: [String: JSONValue] = ["enabled": .bool(true)]
        let envelope = SettingsBackupEnvelope(
            exportDate: exportDate,
            setting: Setting(galleryHost: .exhentai),
            searchFilter: Filter(doujinshi: true),
            globalFilter: Filter(manga: true),
            watchedFilter: Filter(western: true),
            quickSearchWords: [QuickSearchWord(name: "preset", content: "f:abc")],
            historyKeywords: ["keyword"],
            galleryHistory: [
                GalleryHistoryEntry(gid: "1", token: "a", lastOpenDate: exportDate, readingProgress: 3)
            ],
            user: User(displayName: "Tester", favoriteCategories: [0: "A"]),
            cookies: [ExportedCookie(name: "ipb_member_id", value: "42", domain: "e-hentai.org")],
            mangaTranslationPreferences: JSONValue(encoding: preferencesJSON)
        )

        let data = try JSONEncoder().encode(envelope)
        let decoded = try JSONDecoder().decode(SettingsBackupEnvelope.self, from: data)

        // SwiftUI `Color.==` compares providers, not resolved RGBA, so a decoded `Setting` (whose
        // `accentColor` was rebuilt from RGBA components) never equals the original value. Assert
        // at the information level instead: re-encoding both must produce identical JSON.
        let decodedJSON = try canonicalJSONString(decoded)
        let originalJSON = try canonicalJSONString(envelope)
        #expect(decodedJSON == originalJSON)
    }

    private func canonicalJSONString<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    @Test
    func absentMembersDecodeAsNil() throws {
        // A minimal file — e.g. exported by an older app that only knew the settings blob.
        let json = try #require(#"{"formatVersion":1,"exportDate":700000000,"setting":null}"#
            .data(using: .utf8))

        let decoded = try JSONDecoder().decode(SettingsBackupEnvelope.self, from: json)

        #expect(decoded.formatVersion == 1)
        #expect(decoded.setting == nil)
        #expect(decoded.searchFilter == nil)
        #expect(decoded.globalFilter == nil)
        #expect(decoded.watchedFilter == nil)
        #expect(decoded.quickSearchWords == nil)
        #expect(decoded.historyKeywords == nil)
        #expect(decoded.galleryHistory == nil)
        #expect(decoded.user == nil)
        #expect(decoded.cookies == nil)
        #expect(decoded.mangaTranslationPreferences == nil)
        #expect(decoded.mangaTranslationProviders == nil)
        #expect(decoded.mangaModelLibrary == nil)
    }

    @Test
    func unknownExtraKeysAreIgnored() throws {
        let envelope = SettingsBackupEnvelope(exportDate: exportDate, historyKeywords: ["x"])
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(envelope))
            as? [String: Any])
        object["futureMember"] = ["anything": 1]

        let data = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(SettingsBackupEnvelope.self, from: data)

        #expect(decoded == envelope)
    }

    @Test
    func jsonValueBridgesCodableInBothDirections() throws {
        struct Payload: Codable, Equatable {
            var name: String
            var count: Int
        }
        let payload = Payload(name: "x", count: 3)

        let json = JSONValue(encoding: payload)
        #expect(json != nil)
        #expect(json?.decoded(as: Payload.self) == payload)

        // A tree that doesn't match the target model decodes to nil rather than crashing.
        #expect(json?.decoded(as: Setting.self) == nil)
    }
}
