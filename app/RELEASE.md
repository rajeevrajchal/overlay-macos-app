# Releasing Overlay Viewer

A reproducible DMG published to GitHub Releases, built entirely by
[`release.sh`](release.sh). This is the **free** flow — no paid Apple Developer
account, no certificate, no notarization.

## What "free" means here

- The app is **ad-hoc signed** (required so it launches on Apple Silicon), but it
  is **not** signed with a Developer ID and **not** notarized.
- Because it isn't notarized, macOS Gatekeeper blocks it on first open. Downloaders
  do a **one-time bypass** — see [CHANGELOG.md](CHANGELOG.md) ("Opening the app the
  first time"). Fine for testers you can give instructions to.
- To remove that friction later, enroll in the paid Apple Developer Program and
  switch to a Developer ID + notarization flow.

## Prerequisites

- Xcode command-line tools (`xcodebuild`, `codesign`, `hdiutil`) — you already have these.
- To publish: `gh` installed and authenticated (`gh auth login`) with a GitHub remote.
- Optional: `brew install create-dmg` for a nicer DMG window.

No Apple certificate, provisioning profile, or notary password is required.

## Build

```bash
./release.sh
```

Produces `build/overlay-viewer-<version>.dmg`: an unsigned Release build,
ad-hoc signed, packaged into a DMG.

## Publish

```bash
./release.sh --publish          # tags vX.Y.Z, pushes, creates the GitHub release, uploads the DMG
```

or manually:

```bash
git tag v1.0.0 && git push origin v1.0.0
gh release create v1.0.0 build/overlay-viewer-1.0.0.dmg \
  --title "Overlay Viewer 1.0.0" --notes-file CHANGELOG.md
```

Different version:

```bash
VERSION=1.0.1 ./release.sh --publish
```

## What never gets committed

`.env`, `*.dmg`, `*.xcarchive`, `build/`, and any signing material — all covered by
`.gitignore`. The DMG is a **GitHub Release asset**, not a file in the git tree.
