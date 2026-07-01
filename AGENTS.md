# AGENTS.md

Instructions for AI coding agents working in this repo. See `README.md` for
user-facing docs (features, build/run, Figma OAuth setup, linting).

## What this is

A macOS menu-bar utility (`overlay-viewer` target, Swift/AppKit, no SwiftUI,
no third-party dependencies) that pins an image — a local file or a Figma
frame fetched via OAuth — as a floating always-on-top overlay window.

## Architecture

```
overlay-viewer/
  App/         entry point + AppDelegate + AppEnvironment (composition root)
  Core/        DesignSourceProviding — the plugin protocol for image sources
  Features/
    Overlay/   the floating window, its controllers, and its own views
    Figma/     the one DesignSourceProviding conformance today (FigmaProvider),
               plus the OAuth/API/Keychain/URL-parsing pieces it wraps
```

- `AppEnvironment` is the single composition root, constructed once in
  `AppDelegate`. Window controllers receive it via initializer — never reach
  for `.shared` singletons directly from `Features/Overlay/`.
- To add a new image source (Sketch, a plain URL source, etc.): implement
  `DesignSourceProviding` in its own `Features/<Name>/` folder, add it to
  `AppEnvironment`. See `README.md`'s "Adding a new design source" section.
- `overlay-viewer/` is an Xcode **file-system-synchronized group** — moving
  files there is a plain `git mv`/`mkdir`, no `project.pbxproj` bookkeeping.
  `overlay-viewerTests/` is a **traditional group** with explicit
  `PBXFileReference`s — adding/moving files there requires editing
  `project.pbxproj`, most reliably via the `xcodeproj` Ruby gem:
  ```
  GEM_HOME="/opt/homebrew/Cellar/cocoapods/<version>/libexec" /opt/homebrew/opt/ruby/bin/ruby script.rb
  ```
  (the system Ruby doesn't have the gem; the CocoaPods-bundled one does).
  Check the installed cocoapods version under `/opt/homebrew/Cellar/cocoapods/`
  before assuming a path.

## Build / test

```
xcodebuild -project overlay-viewer.xcodeproj -scheme overlay-viewer -configuration Debug build
xcodebuild test  -project overlay-viewer.xcodeproj -scheme overlay-viewer -destination 'platform=macOS'
```

Module name is `overlay_viewer` (hyphen → underscore) — that's what test
files `@testable import`. Always run the full test suite after a change; a
regression here is a real behavior break for a working app someone uses
daily, not a toy project.

## Linting (pre-commit gate)

`.swiftlint.yml` + `.githooks/pre-commit` (wired via
`git config core.hooksPath .githooks`) block a commit on **error**-severity
SwiftLint violations in staged Swift files. Currently that's `force_cast` and
`force_try` — both zero-instance in this codebase today, so keep them that
way rather than disabling the rule if one shows up. `force_unwrapping` is a
warning, not an error, because 19 existing instances were individually
audited as safe (hardcoded literals or values null-checked immediately
before) — don't add new ones without doing the same reasoning, but don't feel
obligated to eliminate the existing ones either.

Run `swiftlint lint` directly to see the full report before committing.

## Things that bit us before — don't repeat

- **Never hardcode Figma OAuth credentials in `overlay-viewer.xcodeproj/xcshareddata/xcschemes/*.xcscheme`.**
  A real client secret was once committed there and had to be rotated + the
  entire git history scrubbed with `git-filter-repo`. Secrets come from the
  gitignored root `.env`, pulled into build settings via
  `overlay-viewer/Local.xcconfig`'s `#include? "../.env"`, referenced in the
  scheme only as `$(FIGMA_CLIENT_ID)`/`$(FIGMA_CLIENT_SECRET)`.
- **Don't force-unwrap anything built from external/user input** (a pasted
  URL, an API response). The one real security bug found in this codebase
  was exactly that pattern in `FigmaAPIClient` — percent-encode and
  `guard let`/`throws` instead.
- **`FigmaURLParser`'s host check must be an exact/subdomain match**
  (`host == "figma.com" || host.hasSuffix(".figma.com")`), not
  `hasSuffix("figma.com")` — the latter also matches `evilfigma.com`.
- Persistence keys (`overlay.lastFigmaFileKey`, `overlay.opacity`, etc. — see
  README's Persistence table) are read by real installs on relaunch. Don't
  rename/reshape them without a migration path.

## Verifying a change is actually done

Build + full test suite passing is the bar for "done," not just "compiles."
This is a GUI app with OAuth flows that can't be fully exercised by unit
tests alone — if a change touches window behavior, OAuth, or persistence,
say explicitly in your summary that it needs a manual smoke test rather than
implying the test suite alone proves it works.
