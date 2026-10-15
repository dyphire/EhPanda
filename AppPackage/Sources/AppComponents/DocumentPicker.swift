import SwiftUI

/// A `UIDocumentPickerViewController` wrapper that matches documents by filename extension.
///
/// SwiftUI's `.fileImporter(allowedContentTypes:)` routes to the modern
/// `forOpeningContentTypes:` API, which matches strictly through UTI conformance — and on
/// devices where a file's UTI got re-tagged along the way (saved through a share sheet to
/// iCloud, transferred by third-party apps, and so on), such files come up greyed out and
/// unselectable even for types as broad as `public.data`. The legacy `documentTypes:` API
/// accepts plain extension strings and matches by extension, so a `*.json` file stays
/// selectable no matter how its UTI was tagged. The initializer is deprecated but remains
/// fully functional; a picked non-JSON file is still rejected later by the importer's
/// strict decoding.
public struct DocumentPicker: UIViewControllerRepresentable {
    private let documentTypes: [String]
    private let onPick: (URL?) -> Void

    public init(documentTypes: [String] = ["public.json", "json"], onPick: @escaping (URL?) -> Void) {
        self.documentTypes = documentTypes
        self.onPick = onPick
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    public func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(documentTypes: documentTypes, in: .import)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    public func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    public final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let onPick: (URL?) -> Void

        init(onPick: @escaping (URL?) -> Void) {
            self.onPick = onPick
        }

        public func documentPicker(
            _ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]
        ) {
            onPick(urls.first)
        }

        public func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onPick(nil)
        }
    }
}
