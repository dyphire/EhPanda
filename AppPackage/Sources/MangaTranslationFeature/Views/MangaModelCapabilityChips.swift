import SFSafeSymbols
import Sharing
import SwiftUI

public struct MangaModelCapabilityChips: View {
    let archive: ModelArchive

    private var roles: [MangaModelRole] {
        MangaModelRole.supported(by: archive)
    }

    private func title(for role: MangaModelRole) -> String {
        switch role {
        case .detector: return String(localized: .detectionCapability)
        case .recognizer: return String(localized: .recognitionCapability)
        }
    }

    public init(archive: ModelArchive) {
        self.archive = archive
    }

    public var body: some View {
        if !roles.isEmpty {
            HStack {
                ForEach(roles) { role in
                    Text(title(for: role))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: .capsule)
                }
            }
        }
    }
}
