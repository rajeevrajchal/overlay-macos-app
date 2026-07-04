# Changelog

All notable changes to Overlay Viewer are documented here.

## v1.0.0 — First test build (2026-07-04)

First externally-distributed build. Overlay Viewer places a reference image as an
always-on-top, adjustable-opacity overlay so you can pixel-compare a design against a live
build, a canvas, or a physical reference.

### Opening the app the first time

This build isn't from the App Store and isn't notarized, so macOS will warn you once. To open it:

1. Open the DMG and drag **overlay-viewer** to **Applications**.
2. In Applications, **right-click the app → Open**, then click **Open** in the dialog.
   *(Double-clicking the first time will be blocked — you must use right-click → Open once.)*

If macOS still refuses, run this once in Terminal, then open normally:

```bash
xattr -dr com.apple.quarantine "/Applications/overlay-viewer.app"
```

You only have to do this on the first launch of each new version.

### In this build
- Always-on-top overlay window showing a reference image with adjustable **content opacity**.
- Redesigned start ("Add a reference") panel: drag-and-drop, click-to-browse, or a Figma URL.
- **Figma connect** flow (OAuth) with paste-a-URL frame import.
- **Native macOS window controls** (real traffic lights) on both windows.
- Refined overlay toolbar: **Clear**, a **size gear** (custom width/height), and an opacity module.
- Dot-grid **calibration background** behind the image, plus small-size resizing.

### Please test these areas (recent fixes — most likely to regress silently)

1. **Opacity at low percentages.** Drag the opacity slider toward the minimum. Only the *image*
   should fade — the window **border, toolbar, and dot-grid background must stay fully visible**.
   Nothing should vanish or read as "broken," and the canvas should update **live** as you drag.

2. **Figma connect flow.** Connect a Figma account from the start panel, paste a file/frame URL,
   and confirm the frame loads as an overlay. Disconnect and reconnect. Connection state should be
   legible from **icon + text**, not color alone.

3. **Window controls.** The red close button on both the start panel and the overlay closes/hides
   as expected; **⌘W** works; minimize/zoom are intentionally hidden. Toolbar controls should never
   sit underneath the traffic lights.

4. **Resize & custom size.** Drag the overlay small — it should shrink well below the old limit and
   the toolbar should collapse gracefully. Open the **size gear** to set an exact width/height;
   **"Reset to Fit"** should refit the window to the image.

### Known constraints
- Distributed outside the App Store; the app is ad-hoc signed and **not notarized**, so the
  first launch needs the one-time Gatekeeper bypass above.
- Figma import requires a Figma account and network access.

Feedback welcome — please include your macOS version and steps to reproduce any issue.
