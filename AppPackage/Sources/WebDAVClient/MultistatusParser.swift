import Foundation

/// Parses a WebDAV PROPFIND `multistatus` response body (RFC 4918 §9.1, DAV: namespace) into
/// `WebDAVFile` entries. Directory entries (those with a `collection` resourcetype) are excluded;
/// `nil` means the body wasn't a parseable multistatus at all.
enum MultistatusParser: Sendable {
    static func parse(_ data: Data) -> [WebDAVFile]? {
        let parser = XMLParser(data: data)
        let delegate = MultistatusParserDelegate()
        parser.delegate = delegate
        guard parser.parse(), delegate.didFinishRoot else { return nil }
        return delegate.files
    }
}

// MARK: - Parsing state

private struct ResponseState {
    var href = ""
    var size = 0
    var modified: Date?
    var isCollection = false
}

private enum ElementCapture {
    case href, size, modified
}

// MARK: - Delegate

private final class MultistatusParserDelegate: NSObject, XMLParserDelegate {
    var files: [WebDAVFile] = []
    var didFinishRoot = false

    private var current: ResponseState?
    private var capture: ElementCapture?
    private var characterBuffer = ""
    private var resourceTypeDepth = 0

    func parser(
        _ parser: XMLParser, didStartElement elementName: String,
        namespaceURI: String?, qualifiedName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        switch localName(of: elementName) {
        case "multistatus":
            didFinishRoot = true
        case "response":
            current = ResponseState()
        case "href":
            capture = .href
            characterBuffer = ""
        case "getcontentlength":
            capture = .size
            characterBuffer = ""
        case "getlastmodified":
            capture = .modified
            characterBuffer = ""
        case "resourcetype":
            resourceTypeDepth += 1
        case "collection":
            if resourceTypeDepth > 0 {
                current?.isCollection = true
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard capture != nil else { return }
        characterBuffer += string
    }

    func parser(
        _ parser: XMLParser, didEndElement elementName: String,
        namespaceURI: String?, qualifiedName: String?
    ) {
        switch localName(of: elementName) {
        case "href":
            current?.href = characterBuffer.trimmingCharacters(in: .whitespaces)
            capture = nil
        case "getcontentlength":
            current?.size = Int(characterBuffer.trimmingCharacters(in: .whitespaces)) ?? 0
            capture = nil
        case "getlastmodified":
            current?.modified = Self.httpDateFormatter.date(
                from: characterBuffer.trimmingCharacters(in: .whitespaces)
            )
            capture = nil
        case "resourcetype":
            resourceTypeDepth = max(0, resourceTypeDepth - 1)
        case "response":
            if let current, !current.isCollection, !current.href.isEmpty {
                files.append(WebDAVFile(
                    name: (current.href as NSString).lastPathComponent,
                    path: current.href,
                    size: current.size,
                    modifiedDate: current.modified
                ))
            }
            self.current = nil
        default:
            break
        }
    }

    /// Strips an optional namespace prefix ("D:href" → "href") — servers vary in whether they
    /// declare prefixes, and `XMLParser` reports the prefixed form in `elementName`.
    private func localName(of elementName: String) -> String {
        elementName.split(separator: ":", omittingEmptySubsequences: false).last.map(String.init)
            ?? elementName
    }

    private static let httpDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter
    }()
}
