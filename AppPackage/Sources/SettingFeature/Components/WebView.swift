import AppTools
import WebKit
import AppModels
import OSLogExt
import SwiftUI

private let logger = Logger(category: .init(describing: WebView.self))

struct WebView: UIViewControllerRepresentable {
    private let url: URL
    private let cookiesAction: (([LoginReducer.ImportedCookie]) -> Void)?

    init(url: URL, cookiesAction: (([LoginReducer.ImportedCookie]) -> Void)? = nil) {
        self.url = url
        self.cookiesAction = cookiesAction
    }

    final class Coodinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        private var parent: WebView
        private var didStartCookieImport = false

        init(parent: WebView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !didStartCookieImport,
                  parent.url.absoluteString == Defaults.URL.webLogin.absoluteString,
                  let webViewURL = webView.url,
                  let queryItems = URLComponents(url: webViewURL, resolvingAgainstBaseURL: false)?.queryItems,
                  queryItems.contains(where: { queryItem in
                    queryItem.name == Defaults.URL.Component.Key.code.rawValue
                        && queryItem.value == Defaults.URL.Component.Value.zeroOne.rawValue
                  })
            else { return }

            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                guard let self, !didStartCookieImport else { return }
                didStartCookieImport = true
                let importedCookies = cookies.map(LoginReducer.ImportedCookie.init(cookie:))
                DispatchQueue.main.async {
                    self.parent.cookiesAction?(importedCookies)
                }
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            logger.error("\(error, privacy: .public)")
        }
    }

    func makeCoordinator() -> WebView.Coodinator {
        Coodinator(parent: self)
    }

    func makeUIViewController(context: Context) -> EmbeddedWebviewController {
        let webViewController = EmbeddedWebviewController(coordinator: context.coordinator)
        webViewController.loadUrl(url)

        return webViewController
    }

    func updateUIViewController(
        _ uiViewController: EmbeddedWebviewController,
        context: UIViewControllerRepresentableContext<WebView>
    ) {}
}

final class EmbeddedWebviewController: UIViewController {
    private var webview: WKWebView

    private weak var delegate: WebView.Coordinator?

    init(coordinator: WebView.Coordinator) {
        delegate = coordinator
        webview = WKWebView()
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        webview = WKWebView()
        super.init(coder: coder)
    }

    func loadUrl(_ url: URL) {
        let request = URLRequest(url: url)
        webview.load(request)
    }

    override func loadView() {
        webview.navigationDelegate = delegate
        webview.uiDelegate = delegate
        view = webview
    }
}
