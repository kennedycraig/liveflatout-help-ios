import Foundation
#if canImport(UIKit) && canImport(WebKit)
import SwiftUI

/// Batteries-included help sheet. Wraps `LfhHelpWidget` inside a
/// `NavigationStack` with a "Done" toolbar button, a loading spinner while
/// the identity is being fetched, and a retry screen on failure.
///
/// Host apps that want the default UX drop this straight into `.sheet(...)`:
///
/// ```swift
/// import LfhHelpWidget
/// import FirebaseAuth
///
/// .sheet(isPresented: $helpOpen) {
///     HelpSheet(appId: "app1") {
///         guard let user = Auth.auth().currentUser else { return .anonymous }
///         let token = try await user.getIDToken()
///         return try await LfhHelpClient().issueSignature(
///             appId: "app1",
///             idToken: token,
///             name: user.displayName
///         )
///     }
/// }
/// ```
///
/// Host apps that need custom chrome (different toolbar, different presentation
/// style) can skip this and compose `LfhHelpWidget` directly.
public struct HelpSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var identity: Identity?
    @State private var loadError: String?

    private let appId: String
    private let config: LfhHelpConfig
    private let identityProvider: () async throws -> Identity

    /// - Parameters:
    ///   - appId: helpdesk app slug.
    ///   - config: endpoint config; defaults to production.
    ///   - identity: async closure that returns the end-user's `Identity`.
    ///     Defaults to `{ .anonymous }` for hosts that don't need Secure Mode.
    public init(
        appId: String,
        config: LfhHelpConfig = .production,
        identity: @escaping () async throws -> Identity = { .anonymous }
    ) {
        self.appId = appId
        self.config = config
        self.identityProvider = identity
    }

    public var body: some View {
        NavigationStack {
            content
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let identity {
            LfhHelpWidget(
                appId: appId,
                identity: identity,
                config: config,
                onClose: { dismiss() }
            )
            .ignoresSafeArea(.keyboard)
        } else if let loadError {
            VStack(spacing: 12) {
                Text("Couldn't open help").font(.headline)
                Text(loadError)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Retry") { Task { await load() } }
            }
            .padding()
        } else {
            ProgressView().task { await load() }
        }
    }

    private func load() async {
        loadError = nil
        do {
            identity = try await identityProvider()
        } catch {
            loadError = String(describing: error)
        }
    }
}

#if DEBUG
#Preview("Anonymous") {
    HelpSheet(appId: "test-app")
}
#endif

#endif // canImport(UIKit) && canImport(WebKit)
