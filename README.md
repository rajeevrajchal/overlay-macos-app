# Overlay Viewer

A lightweight macOS menu-bar utility that pins any image as a floating overlay above every window on your screen — across all Spaces, on every monitor, and even over fullscreen apps.

Useful for referencing a design mockup while coding, keeping a reference image visible while drawing or modeling, or comparing an asset against live work without alt-tabbing.

---

## Features

- **Always on top** — the overlay floats above every other application window, including fullscreen apps
- **Follows you everywhere** — stays visible across all Spaces and all connected monitors
- **Adjustable opacity** — fade the image to see what's underneath without moving it
- **Custom window size** — set an exact pixel width and height via the gear icon in the toolbar; the setting persists across relaunches
- **Reset to fit** — one click snaps the window back to the auto-fitted image size
- **Drag and drop** — drop an image file directly onto the welcome screen to open it
- **Persistent state** — remembers the last opened image, your opacity level, and any custom window size
- **No Dock icon** — lives entirely in the menu bar; stays out of your way

---

## How to Use

### Opening an image
1. Click the **photo icon** in the menu bar
2. Choose **Open Image…**, or press **Cmd+O** from anywhere
3. Alternatively, drag an image file onto the welcome screen

### Toolbar ribbon
Once an image is loaded, a thin toolbar appears at the top of the overlay:

| Button | Action |
|---|---|
| ✕ | Hide the overlay (does not remove the image) |
| Change… | Open a new image in place of the current one |
| Remove | Clear the image and return to the welcome screen |
| ⚙ | Open the size settings popover |
| Opacity slider | Fade the image content (0.1 → fully transparent, 1.0 → fully opaque) |

### Custom size
Click the **gear icon** (⚙) to open the size popover:
- Enter a **Width** and **Height** in pixels and press **Apply** — the window resizes immediately and the values are saved
- Press **Reset** to clear the saved size and snap the window back to the auto-fitted image dimensions
- Values below 400 × 96 px are clamped to the minimum window size

### Keyboard shortcuts
| Shortcut | Action |
|---|---|
| `Escape` | Hide the overlay |
| `Cmd+O` | Open image picker |

### Menu bar
Right-click (or click) the menu bar icon for quick access to:
- **Open Image…**
- **Toggle Visibility** — show or hide the overlay without closing it
- **Quit**

---

## Requirements

- macOS 26.5 or later
- No external dependencies

---

## Building

1. Open `overlay-viewer.xcodeproj` in Xcode
2. Select the **overlay-viewer** scheme
3. Press **Cmd+R** to build and run

No package dependencies, no build scripts — just standard AppKit/SwiftUI.

---

## Project Structure

```
overlay-viewer/
├── OverlayViewerApp.swift          # SwiftUI App entry point; wires NSApplicationDelegate
├── AppDelegate.swift               # Menu bar item, status icon, app lifecycle
├── OverlayWindow.swift             # Borderless floating NSWindow (always-on-top plumbing)
├── OverlayWindowController.swift   # Main controller: toolbar ribbon, image loading, size persistence
├── ImageCanvasView.swift           # Pure NSView that draws the image aspect-fitted
├── WelcomeWindowController.swift   # First-launch screen with click-to-open and drag-and-drop
└── SizeSettingsViewController.swift# Popover with Width/Height fields, Apply, and Reset
```

### How the pieces fit together

```
AppDelegate
  └── OverlayWindowController
        ├── OverlayWindow          (the floating NSWindow)
        ├── ToolbarRibbonView      (NSVisualEffectView strip at the top)
        │     └── buttons + opacity slider
        ├── ImageCanvasView        (fills the area below the ribbon)
        ├── SizeSettingsViewController  (shown as NSPopover from the gear button)
        └── WelcomeWindowController     (shown when no image is loaded)
              └── WelcomeWindow    (frosted-glass drop target)
```

### Key design decisions

- **Menu-bar only (`.accessory` policy)** — the app has no Dock icon and no main menu. All interaction goes through the status item and the overlay's own toolbar ribbon.
- **`canJoinAllSpaces` + `fullScreenAuxiliary`** — these two `NSWindow.CollectionBehavior` flags are what make the overlay follow the user across desktops and appear over fullscreen Spaces.
- **Separate window-level opacity vs. content opacity** — the window's `alphaValue` is always 1.0; only `ImageCanvasView.alphaValue` is adjusted by the slider. This prevents the toolbar ribbon from fading along with the image.
- **Layer properties deferred to `layout()`** — `NSVisualEffectView` subclasses set `cornerRadius` in `layout()` (not in `init`) to avoid a layout recursion triggered by AppKit's visual-effect layer management during the first Auto Layout pass.
- **Lazy window controller creation** — `OverlayWindowController` is a `lazy var` on `AppDelegate` so the `NSWindow` is not constructed until `applicationDidFinishLaunching`, avoiding issues with early window creation before `NSApp` is fully initialized.

---

## Persistence

All state is stored in `UserDefaults` under these keys:

| Key | What it stores |
|---|---|
| `overlay.lastImageURL` | Absolute URL of the last opened image |
| `overlay.opacity` | Opacity slider value (0.1 – 1.0) |
| `overlay.customWidth` | Custom window width in points (absent = auto-fit) |
| `overlay.customHeight` | Custom window height in points (absent = auto-fit) |
| `NSWindow Frame OverlayWindowFrame` | Window position/size managed by AppKit autosave |
