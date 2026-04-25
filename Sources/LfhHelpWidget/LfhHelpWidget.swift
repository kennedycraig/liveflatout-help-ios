import Foundation
#if canImport(UIKit) && canImport(WebKit)
import SwiftUI
import UIKit
import WebKit

/// SwiftUI view that embeds the helpdesk chat widget in a `WKWebView`.
///
/// Typical usage inside a host app:
///
/// ```swift
/// LfhHelpWidget(appId: "app1", identity: identity, onClose: { dismiss() })
///     .ignoresSafeArea(.keyboard)
/// ```
///
/// The widget performs its own Firebase sign-in (anonymous or custom-token
/// via `widgetMintToken`) — this wrapper only builds the URL.
///
/// > **Presentation note:** when host apps want users to attach files via
/// > the in-widget picker, present this view through `.fullScreenCover(...)`
/// > rather than `.sheet(...)`. SwiftUI `.sheet` is dismissed by iOS when a
/// > `UIDocumentPicker` (Files app) presents over it. `.fullScreenCover`
/// > with this view's underlying `UIViewControllerRepresentable` keeps the
/// > picker presentation context intact.
public struct LfhHelpWidget: UIViewControllerRepresentable {
    public let appId: String
    public let identity: Identity
    public let config: LfhHelpConfig
    public let onClose: (() -> Void)?

    public init(
        appId: String,
        identity: Identity,
        config: LfhHelpConfig = .production,
        onClose: (() -> Void)? = nil
    ) {
        self.appId = appId
        self.identity = identity
        self.config = config
        self.onClose = onClose
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(onClose: onClose)
    }

    public func makeUIViewController(context: Context) -> WidgetHostController {
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true

        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "lfhHelp")

        let cfg = WKWebViewConfiguration()
        cfg.defaultWebpagePreferences = prefs
        cfg.userContentController = contentController
        cfg.allowsInlineMediaPlayback = true

        let webView = WKWebView(frame: .zero, configuration: cfg)
        webView.allowsBackForwardNavigationGestures = false
        webView.scrollView.keyboardDismissMode = .interactive
        webView.isOpaque = false
        webView.backgroundColor = .systemBackground

        // Since iOS 16.4 WKWebView is opt-in for Web Inspector. Enable in
        // DEBUG builds so host-app developers can attach Mac Safari's
        // inspector to diagnose widget JS issues. Production builds stay
        // un-inspectable.
        #if DEBUG
        if #available(iOS 16.4, *) {
            webView.isInspectable = true
        }
        #endif

        let initial = iframeURL()
        context.coordinator.lastLoadedURL = initial
        webView.load(URLRequest(url: initial))

        return WidgetHostController(webView: webView)
    }

    public func updateUIViewController(_ controller: WidgetHostController, context: Context) {
        // Compare against the last URL we *intentionally* loaded, not
        // webView.url — the iframe page strips its Secure Mode query
        // params via history.replaceState() shortly after first load,
        // so webView.url drifts from the target on every SwiftUI
        // re-render. Reloading on that drift would re-mount the React
        // tree, killing in-flight UI like a file picker.
        let target = iframeURL()
        if context.coordinator.lastLoadedURL != target {
            context.coordinator.lastLoadedURL = target
            controller.webView.load(URLRequest(url: target))
        }
        context.coordinator.onClose = onClose
    }

    private func iframeURL() -> URL {
        let base = config.widgetOrigin.appendingPathComponent("widget").appendingPathComponent(appId)
        return Identity.buildIframeURL(base: base, identity: identity)
    }

    public final class Coordinator: NSObject, WKScriptMessageHandler {
        var onClose: (() -> Void)?
        var lastLoadedURL: URL?
        init(onClose: (() -> Void)?) {
            self.onClose = onClose
        }
        public func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == "lfhHelp",
                  let body = message.body as? [String: Any],
                  let type = body["type"] as? String
            else { return }
            switch type {
            case "close":
                onClose?()
            default:
                break
            }
        }
    }
}

/// Plain UIViewController whose only job is to host the WKWebView. Having
/// a real UIViewController in the responder chain is what lets iOS find a
/// presentation context for system pickers (UIDocumentPicker, PHPicker,
/// etc.) that WKWebView triggers from `<input type="file">`. Without this
/// the file picker silently fails to present from inside a SwiftUI sheet
/// or fullScreenCover.
public final class WidgetHostController: UIViewController {
    public let webView: WKWebView

    init(webView: WKWebView) {
        self.webView = webView
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }
}

#if DEBUG
#Preview("Anonymous") {
    LfhHelpWidget(appId: "test-app", identity: .anonymous)
}
#Preview("Signed (synthetic)") {
    LfhHelpWidget(
        appId: "test-app",
        identity: .signed(
            email: "preview@example.com",
            name: "Preview",
            signature: "deadbeef",
            version: 1
        )
    )
}
#endif

#endif // canImport(UIKit) && canImport(WebKit)
