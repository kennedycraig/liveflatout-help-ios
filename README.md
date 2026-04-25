# LfhHelpWidget (iOS SPM package)

SwiftUI embed for the helpdesk chat widget.

## Adding the package

Host apps depend on the published mirror repo. SwiftPM URL form:

```swift
// Host app's Package.swift
dependencies: [
    .package(
        url: "https://github.com/kennedycraig/liveflatout-help-ios.git",
        from: "0.1.0"
    ),
],
targets: [
    .target(
        name: "HostApp",
        dependencies: [
            .product(name: "LfhHelpWidget", package: "liveflatout-help-ios"),
        ]
    ),
]
```

Or in Xcode: **File → Add Package Dependencies… → Search or Enter Package URL**
→ paste `https://github.com/kennedycraig/liveflatout-help-ios.git` →
**Add Package**. Pick "Up to Next Major Version" starting at `0.1.0`.

> **Where the source lives:** the canonical source is in the
> [`liveFlatoutHelp` monorepo](https://github.com/kennedycraig/liveFlatoutHelp)
> at `packages/ios-widget/`. The
> [`liveflatout-help-ios`](https://github.com/kennedycraig/liveflatout-help-ios)
> repo is a one-way mirror produced by `git subtree split` from the monorepo
> on each release. File issues and PRs against the monorepo, not the mirror.

## `HelpSheet` — batteries-included

For most host apps, `HelpSheet` is the entry point. It wraps `LfhHelpWidget`
in a `NavigationStack` with a "Done" toolbar, a `ProgressView` while the
identity loads, and a retry screen on failure.

### Anonymous

```swift
import SwiftUI
import LfhHelpWidget

struct RootView: View {
    @State private var helpOpen = false
    var body: some View {
        Button("Help") { helpOpen = true }
            .sheet(isPresented: $helpOpen) {
                HelpSheet(appId: "app1")
            }
    }
}
```

The visitor sees a contact form; submitting it creates a `channel: 'chat'`
conversation in the helpdesk Inbox.

### Secure Mode (identified user)

Prerequisite: the host app's Firebase project ID must be listed on
`/apps/{appId}.trustedProjects[]` in Firestore. Set via
`/admin/settings/<appId>` in the helpdesk admin dashboard.

```swift
import SwiftUI
import FirebaseAuth
import LfhHelpWidget

.sheet(isPresented: $helpOpen) {
    HelpSheet(appId: "app1") {
        guard let user = Auth.auth().currentUser else { return .anonymous }
        let token = try await user.getIDToken()
        return try await LfhHelpClient().issueSignature(
            appId: "app1",
            idToken: token,
            name: user.displayName
        )
    }
}
```

The closure runs every time the sheet is presented, so it always sees the
current signed-in user. `LfhHelpClient` defaults to production endpoints in
`LfhHelpConfig.production`; override via `LfhHelpClient(config: .init(...))`
for local or staging testing.

### Request timeout

`LfhHelpClient`'s `issueSignature(...)` inherits Foundation's 60-second
request timeout by default. Tighten it if you'd rather show a "try again"
UI sooner than that on a stalled cold start:

```swift
let client = LfhHelpClient(requestTimeout: 15)
```

## Low-level: `LfhHelpWidget` directly

If `HelpSheet`'s chrome doesn't fit your presentation style, skip it and
compose `LfhHelpWidget` yourself:

```swift
LfhHelpWidget(appId: "app1", identity: .anonymous, onClose: { dismiss() })
    .ignoresSafeArea(.keyboard)
```

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
