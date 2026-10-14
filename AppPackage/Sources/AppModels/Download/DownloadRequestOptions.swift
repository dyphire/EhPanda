/// Execution policy for a download: *how* to fetch (thread limit, cellular, auto-retry),
/// not *what* to fetch. Deliberately separate from `DownloadRequestPayload` and never
/// persisted to a manifest or request: it is resolved fresh from the latest settings once
/// per run (see `downloadOptionsProvider`) and threaded to the workers, so a settings change
/// while a gallery sits queued takes effect when it finally starts.
public struct DownloadRequestOptions: Equatable, Sendable {
    public var threadLimit = Setting.downloadThreadLimitDefaultValue
    public var allowCellular = Setting.downloadAllowCellularDefaultValue
    public var autoRetryFailedPages = Setting.downloadAutoRetryFailedPagesDefaultValue
    public var detectsAdPages = false

    public init(
        threadLimit: Int = Setting.downloadThreadLimitDefaultValue,
        allowCellular: Bool = Setting.downloadAllowCellularDefaultValue,
        autoRetryFailedPages: Bool = Setting.downloadAutoRetryFailedPagesDefaultValue,
        detectsAdPages: Bool = false
    ) {
        self.threadLimit = threadLimit
        self.allowCellular = allowCellular
        self.autoRetryFailedPages = autoRetryFailedPages
        self.detectsAdPages = detectsAdPages
    }

    public var workerCount: Int {
        threadLimit
    }
}
