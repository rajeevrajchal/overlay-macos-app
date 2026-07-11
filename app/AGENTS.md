# AGENTS.md

Instructions for AI coding agents working in this repo. See `README.md` for
user-facing docs (features, build/run, Figma OAuth setup, linting) and
`RELEASE.md` for the release/distribution process.

## What this is

A macOS menu-bar utility (`overlay-viewer` target, no third-party dependencies)
that pins an image — a local file or a Figma frame fetched via OAuth — as a
floating always-on-top overlay window.

It's a **hybrid AppKit + SwiftUI** app: AppKit owns the hand-tuned windows
(always-on-top, titled-but-transparent, drag-anywhere) and app lifecycle;
SwiftUI (hosted via `NSHostingView`) renders the start screen and the overlay
toolbar, driven by `@MainActor ObservableObject` view models. The SwiftUI views
are dumb renderers; behavior lives in the view models, which talk to the outside
world only through the `DesignSourceProviding` seam (so they unit-test with a
mock — no real network or browser).

## Architecture

```
overlay-viewer/
  App/         main.swift + AppDelegate (menu bar, Quit) + AppEnvironment (composition root)
  Core/        DesignSourceProviding (image-source plugin protocol),
               FigmaConnectionState, DesignTokens, VisualEffectView (SwiftUI vibrancy bridge)
  Features/
    Overlay/   the floating window + controller, OverlayToolbar (SwiftUI) +
               OverlayControlsViewModel, CanvasGridView, ImageCanvasView,
               ResizeHandleView, WelcomeWindowController
    Welcome/   WelcomeView (SwiftUI start screen) + WelcomeViewModel
    Figma/     the one DesignSourceProviding conformance (FigmaProvider) + the
               OAuth/API/Keychain/URL-parsing pieces it wraps
```

- `AppEnvironment` is the single composition root, constructed once in
  `AppDelegate`. Window controllers receive it via initializer — never reach
  for `.shared` singletons directly from `Features/`.
- To add a new image source (Sketch, a plain URL source, etc.): implement
  `DesignSourceProviding` in its own `Features/<Name>/` folder, add it to
  `AppEnvironment`. See `README.md`'s "Adding a new design source" section.
- `overlay-viewer/` is an Xcode **file-system-synchronized group** — adding or
  moving source files there is a plain `git mv`/`mkdir`, no `project.pbxproj`
  bookkeeping.
- `overlay-viewerTests/` is a **traditional group** with explicit
  `PBXFileReference`s. New test files are silently ignored (they compile but
  never run, and the suite still reports success) until registered in
  `project.pbxproj` in **four** places: a `PBXBuildFile`, a `PBXFileReference`,
  the group's `children`, and the test target's `PBXSourcesBuildPhase` `files`.
  Hand-editing those four (mimic the existing `Mocks.swift` entries) works
  fine; the `xcodeproj` Ruby gem is the alternative:

  ```
  GEM_HOME="/opt/homebrew/Cellar/cocoapods/<version>/libexec" /opt/homebrew/opt/ruby/bin/ruby script.rb
  ```

  (the system Ruby doesn't have the gem; the CocoaPods-bundled one does).
  Symptom of a forgotten registration: grep the test log for the new class
  name and get zero matches even though `** TEST SUCCEEDED **`.

## Build / test

```
xcodebuild -project overlay-viewer.xcodeproj -scheme overlay-viewer -configuration Debug build
xcodebuild test  -project overlay-viewer.xcodeproj -scheme overlay-viewer -destination 'platform=macOS'
```

Module name is `overlay_viewer` (hyphen → underscore) — that's what test
files `@testable import`. Always run the full test suite after a change; a
regression here is a real behavior break for a working app someone uses
daily, not a toy project. The per-file SourceKit "Cannot find type … in
scope" diagnostics during editing are cross-file indexing noise — trust the
whole-module `xcodebuild` result, not those.

## Linting (pre-commit gate)

`.swiftlint.yml` + `.githooks/pre-commit` (wired via
`git config core.hooksPath .githooks`) block a commit on **error**-severity
SwiftLint violations in staged Swift files. Currently that's `force_cast` and
`force_try` — both zero-instance in this codebase today, so keep them that
way. `force_unwrapping` is a warning, not an error, because the existing
instances were individually audited as safe (hardcoded literals or values
null-checked immediately before) — don't add new ones without the same
reasoning, but don't feel obligated to eliminate the existing ones either.

Run `swiftlint lint` directly to see the full report before committing.

## Distribution / releasing

Distributed **outside the App Store** as an **ad-hoc-signed** `.dmg` published to
GitHub Releases — no paid Apple Developer account, cert, or notarization. The
whole thing is scripted in `release.sh` (`./release.sh` builds; `--publish`
tags + creates the GitHub release). See `RELEASE.md`.

- The app is built unsigned (`CODE_SIGNING_ALLOWED=NO`) then ad-hoc signed with
  a stripped entitlements set (sandbox + network + user-selected files; the
  `keychain-access-group` is dropped because it needs a provisioning profile).
  Ad-hoc signing is mandatory — an unsigned app won't launch on Apple Silicon.
- Because it isn't notarized, testers do a one-time Gatekeeper bypass (right-
  click ▸ Open) — documented in `CHANGELOG.md`, which is used as the release notes.
- `release.sh` bakes the Figma credentials into the built app's `Info.plist`
  (`FigmaClientID`/`FigmaClientSecret`/`FigmaRedirectURI`) before signing, since
  a distributed `.app` has no process environment. `FigmaOAuthConfiguration.resolved`
  reads env first (dev) then Info.plist (release). This embeds the client secret
  in the shipped app — only for trusted test builds; rotate the secret after.

## Behavioral invariants — preserve these

- **Opacity is content-only.** The slider drives `ImageCanvasView.contentOpacity`
  (a `draw(fraction:)` pixel fade), never `window.alphaValue`. The window, its
  border, the toolbar, and the `CanvasGridView` calibration grid must stay fully
  visible at every opacity. The grid's alpha is a fixed constant, never tied to
  the opacity value.
- **Close ≠ hide.** `windowShouldClose` on both window controllers calls
  `NSApplication.shared.terminate(nil)` — the close button (and `Cmd+W`) quit the
  app. `Toggle Visibility` (`Cmd+H`) and `Escape` use `orderOut`/`orderFront`
  instead, so they hide without quitting. Keep these two code paths distinct;
  don't route them through one shared method.
- **Native traffic lights.** Both windows are `.titled` + `titlebarAppearsTransparent`
  + `.fullSizeContentView` (not `.borderless`) so the system draws real traffic
  lights; minimize/zoom are hidden. Hosted SwiftUI in these windows needs
  `.ignoresSafeArea()` or it gets shoved down under the invisible title bar.

## Things that bit us before — don't repeat

- **Never hardcode Figma OAuth credentials in `…/xcshareddata/xcschemes/*.xcscheme`.**
  A real client secret was once committed there and had to be rotated + the
  entire git history scrubbed with `git-filter-repo`. For dev, secrets come from
  the gitignored root `.env` (copy `.env.example`), pulled into build settings
  via `overlay-viewer/Local.xcconfig`'s `#include? "../.env"`, referenced only as
  `$(FIGMA_CLIENT_ID)`/`$(FIGMA_CLIENT_SECRET)`.
- **The Figma redirect URI scheme is `overlay-viewer-figma://oauth-callback`**
  (matches `Info.plist` `CFBundleURLTypes`), not `overlay-viewer://`. Getting
  this wrong silently breaks the OAuth callback.
- **The status-bar menu retargets every item to `self`** (`for item in menu.items
  { item.target = self }`). A menu item wired to `#selector(NSApplication.terminate(_:))`
  therefore ends up disabled (AppDelegate doesn't respond to it) — use a local
  `@objc quitApp()` that calls `terminate(nil)` instead.
- **Don't force-unwrap anything built from external/user input** (a pasted URL,
  an API response). The one real security bug found here was exactly that in
  `FigmaAPIClient` — percent-encode and `guard let`/`throws` instead.
- **`FigmaURLParser`'s host check must be an exact/subdomain match**
  (`host == "figma.com" || host.hasSuffix(".figma.com")`), not
  `hasSuffix("figma.com")` — the latter also matches `evilfigma.com`.
- **Notarization requires the Hardened Runtime** (`ENABLE_HARDENED_RUNTIME = YES`,
  now set). Inert for the current ad-hoc flow, but required if the project ever
  moves to Developer ID + notarization.
- Persistence keys (`overlay.lastFigmaFileKey`, `overlay.opacity`, etc. — see
  README's Persistence table) are read by real installs on relaunch. Don't
  rename/reshape them without a migration path.

## Verifying a change is actually done

Build + full test suite passing is the bar for "done," not just "compiles."
This is a GUI app with OAuth flows that can't be fully exercised by unit
tests alone — if a change touches window behavior, OAuth, opacity/toolbar, or
persistence, say explicitly in your summary that it needs a manual smoke test
rather than implying the test suite alone proves it works.
