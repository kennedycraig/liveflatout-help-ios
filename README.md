# LfhHelpWidget (iOS SPM package)

SwiftUI embed for the helpdesk chat widget.

## Adding the package

> **Monorepo caveat:** this package lives at `packages/ios-widget/` inside the
> helpdesk monorepo. Swift Package Manager expects `Package.swift` at the root
> of a fetched git URL, so you **cannot** depend on this via a GitHub URL today.
> Use a **local path dependency** while dogfooding:

```swift
// Host app's Package.swift
dependencies: [
    .package(path: "../liveFlatoutHelp/packages/ios-widget"),
],
targets: [
    .target(
        name: "HostApp",
        dependencies: [.product(name: "LfhHelpWidget", package: "ios-widget")]
    ),
]
```

If your host app is an Xcode project (not a Swift package), add the local
package via **File → Add Packages… → Add Local…** and select
`packages/ios-widget`.

A separate mirror repository for remote consumption is tracked in
`docs/backlog.md`.

## Anonymous widget

```swift
import SwiftUI
import LfhHelpWidget

struct HelpView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        LfhHelpWidget(appId: "app1", identity: .anonymous, onClose: { dismiss() })
            .ignoresSafeArea(.keyboard)
    }
}
```

The visitor sees a contact form; submitting it creates a `channel: 'chat'`
conversation in the helpdesk Inbox.

## Secure Mode (identified user)

Prerequisite: the host app's Firebase project ID must be listed on
`/apps/{appId}.trustedProjects[]` in Firestore. Set via
`/admin/settings/<appId>` in the helpdesk admin dashboard.

```swift
import FirebaseAuth
import LfhHelpWidget

func openHelp() async throws {
    guard let user = Auth.auth().currentUser else { return }
    let idToken = try await user.getIDToken()

    let identity = try await LfhHelpClient().issueSignature(
        appId: "app1",
        idToken: idToken,
        name: user.displayName
    )
    // Present LfhHelpWidget(appId: "app1", identity: identity)
}
```

`LfhHelpClient` defaults to production endpoints defined in `LfhHelpConfig.production`.
Override via `LfhHelpClient(config: .init(widgetOrigin: ..., issueSignatureURL: ...))`
for local or staging testing.

## iOS version support

- iOS 16+
- Swift 5.9+

## Closing the widget from inside the iframe

Not yet wired on the iframe side. When the iframe is updated to emit
`window.webkit.messageHandlers.lfhHelp.postMessage({type: "close"})`,
the `onClose` closure you pass to `LfhHelpWidget` will fire.

## Testing

```bash
cd packages/ios-widget
swift test   # runs Identity + LfhHelpClient tests (macOS)
```

`LfhHelpWidget` itself is `#if canImport(UIKit)`-guarded and not part of the
macOS build. Verify rendering via the `#Preview` blocks in Xcode.
