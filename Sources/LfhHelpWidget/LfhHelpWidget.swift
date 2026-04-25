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
public struct LfhHelpWidget: UIViewRepresentable {
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

    public func makeUIView(context: Context) -> WKWebView {
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

        webView.load(URLRequest(url: iframeURL()))
        return webView
    }

    public func updateUIView(_ webView: WKWebView, context: Context) {
        let target = iframeURL()
        if webView.url != target {
            webView.load(URLRequest(url: target))
        }
        context.coordinator.onClose = onClose
    }

    private func iframeURL() -> URL {
        let base = config.widgetOrigin.appendingPathComponent("widget").appendingPathComponent(appId)
        return Identity.buildIframeURL(base: base, identity: identity)
    }

    public final class Coordinator: NSObject, WKScriptMessageHandler {
        var onClose: (() -> Void)?
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
