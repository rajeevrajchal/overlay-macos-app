# Plan: Add "Change Image" — Toolbar + Menu Bar

## Task Type

Feature Implementation

## Overview

Add a "Change Image…" action that clears the current overlay image and immediately opens `NSOpenPanel` to pick a replacement. The action is exposed in two places: the floating toolbar HUD and the status item menu bar. No intermediate empty state is shown to the user.

## Goals

- [ ] **Goal 1** — `OverlayWindowController` exposes a `clearAndReopen()` method that clears the canvas and opens the file picker immediately
- [ ] **Goal 2** — The toolbar HUD shows a "Change Image…" button in a new bottom row
- [ ] **Goal 3** — The menu bar status item shows a "Change Image…" menu item with key equivalent `r`

---

## Assumptions

- `canvasView` is a property on `OverlayWindowController` with an `image: NSImage?` property (type assumed to be a custom `NSImageView` subclass or similar). `[UNKNOWN — exact type/class name not provided]`
- `overlayController` is the property name on `AppDelegate` that holds the `OverlayWindowController` instance. `[UNKNOWN — exact property name not confirmed; infer from existing `openImage` action]`
- `repositionToolbar()` reads `toolbarWindow.frame.height` dynamically at call time, so no manual adjustment is needed after the height change.
- If the user cancels the picker after "Change Image…", the overlay remains hidden (no image, no window). This is accepted behavior for this iteration.
- Menu item validation (`validateMenuItem`) is treated as optional/nice-to-have and is noted but not required for the initial implementation.

---

## Architecture Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Clear + open in one method | `clearAndReopen()` on controller | Keeps UI logic out of `AppDelegate` and `ToolbarWindow`; single source of truth |
| Toolbar expansion direction | Grow downward (add row at y=8) | Matches existing layout pattern; all controls shift up by 32pt |
| Key equivalent for menu item | `r` ("replace") | `o` is taken by "Open Image…"; `r` is mnemonic for "replace" |
| Cancel behavior | Overlay stays hidden | Simplest safe default; restoring prior image is a future enhancement |

---

## Implementation Steps

### Phase 1: Add `clearAndReopen()` to `OverlayWindowController.swift` (Simple)

**Goal link**: Goal 1  
**File**: `overlay-viewer/OverlayWindowController.swift`  
**Depends on**: Nothing

1. Add the following `public` method after `showOpenPanelIfNeeded()`:

```swift
func clearAndReopen() {
    canvasView.image = nil
    window?.orderOut(nil)   // hide overlay while picker is open
    presentOpenPanel()      // immediately show file picker
}
```

2. No changes needed to `load(imageURL:)` — `window?.orderFrontRegardless()` is already called there, so the overlay reappears automatically on successful selection.

> **Gotcha**: If the user cancels the picker, `canvasView.image` remains `nil` and `window` stays hidden. This is acceptable; document as a known limitation.

---

### Phase 2: Expand `ToolbarWindow.swift` and add button (Moderate)

**Goal link**: Goal 2  
**File**: `overlay-viewer/ToolbarWindow.swift`  
**Depends on**: Phase 1 (button action calls `clearAndReopen()`)

#### 2a — Expand window and effect view height

**Before** (initializer content rect):
```swift
contentRect: NSRect(x: 0, y: 0, width: 280, height: 96)
```
**After**:
```swift
contentRect: NSRect(x: 0, y: 0, width: 280, height: 128)
```

**Before** (`NSVisualEffectView` frame):
```swift
NSRect(x: 0, y: 0, width: 280, height: 96)
```
**After**:
```swift
NSRect(x: 0, y: 0, width: 280, height: 128)
```

#### 2b — Shift all existing controls up by 32pt

| Control | Old frame | New frame |
|---|---|---|
| "Window" label | `(16, 70, 60, 16)` | `(16, 102, 60, 16)` |
| Window opacity slider | `(80, 68, 184, 20)` | `(80, 100, 184, 20)` |
| "Image" label | `(16, 40, 60, 16)` | `(16, 72, 60, 16)` |
| Image opacity slider | `(80, 38, 184, 20)` | `(80, 70, 184, 20)` |
| Click-through checkbox | `(16, 8, 150, 18)` | `(16, 40, 150, 18)` |

#### 2c — Add "Change Image…" button in the new bottom row

Add the following block after the click-through checkbox setup, before `setContentView`:

```swift
let changeImageButton = NSButton(frame: NSRect(x: 16, y: 8, width: 248, height: 24))
changeImageButton.title = "Change Image…"
changeImageButton.bezelStyle = .rounded
changeImageButton.target = self
changeImageButton.action = #selector(changeImageAction)
effectView.addSubview(changeImageButton)
```

Add the corresponding action selector (mark `weak` reference to controller to avoid retain cycle):

```swift
@objc private func changeImageAction() {
    controller?.clearAndReopen()
}
```

> **Note**: `ToolbarWindow` already holds a `controller` reference matching the pattern of existing action methods (`setWindowOpacity`, `setContentOpacity`, `setClickThrough`). No new reference plumbing needed.

> **Gotcha — toolbar repositioning**: `repositionToolbar()` in `OverlayWindowController` uses `toolbarWindow.frame.height` at call time. Since the window is initialized taller from the start, repositioning will automatically account for the new height. No changes needed there.

> **Gotcha — toolbar creation guard**: `showToolbar()` is guarded by `toolbarWindow == nil` so the window is created once. The height change applies at initialization time and is safe.

---

### Phase 3: Add "Change Image…" to the menu bar in `AppDelegate.swift` (Simple)

**Goal link**: Goal 3  
**File**: `overlay-viewer/AppDelegate.swift`  
**Depends on**: Phase 1 (calls `clearAndReopen()` on controller)

#### 3a — Insert menu item after "Open Image…"

**Before**:
```swift
menu.addItem(withTitle: "Open Image…",    action: #selector(openImage),       keyEquivalent: "o")
menu.addItem(NSMenuItem.separator())
menu.addItem(withTitle: "Toggle Visibility", action: #selector(toggleVisibility), keyEquivalent: "h")
```

**After**:
```swift
menu.addItem(withTitle: "Open Image…",    action: #selector(openImage),       keyEquivalent: "o")
menu.addItem(withTitle: "Change Image…",  action: #selector(changeImage),     keyEquivalent: "r")
menu.addItem(NSMenuItem.separator())
menu.addItem(withTitle: "Toggle Visibility", action: #selector(toggleVisibility), keyEquivalent: "h")
```

#### 3b — Add `changeImage` action method

```swift
@objc private func changeImage() {
    overlayController.clearAndReopen()
}
```

> **[UNKNOWN]**: Confirm the exact property name for the controller on `AppDelegate`. The plan assumes `overlayController`; adjust if it differs (e.g., `controller`, `windowController`).

---

## Optional Enhancement (Out of Scope — Future)

**Menu item validation**: Disable "Change Image…" when no image is loaded.

```swift
// AppDelegate.swift — add NSMenuDelegate conformance
func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
    if menuItem.action == #selector(changeImage) {
        return overlayController.hasImage   // add computed var to controller
    }
    return true
}
```

This requires adding a `var hasImage: Bool { canvasView.image != nil }` computed property to `OverlayWindowController`. Mark for a follow-up PR.

---

## Verification Checklist

- [ ] **Build succeeds** with no new compiler errors or warnings
- [ ] **Toolbar height** visually expands — HUD is taller and shows the "Change Image…" button in the bottom row
- [ ] **Existing controls** (sliders, checkbox) render at their correct shifted y-positions — no overlap
- [ ] **Toolbar repositioning** — after loading an image, the toolbar still snaps correctly below/near the overlay window
- [ ] **Button action (toolbar)**: Clicking "Change Image…" in the toolbar clears the current image, hides the overlay, and opens `NSOpenPanel`
- [ ] **Selecting a new image** via the picker loads the image, resizes the overlay, re-centers it, and brings it to front
- [ ] **Cancelling the picker** (toolbar path): overlay remains hidden, no crash
- [ ] **Menu bar action**: "Change Image…" (`⌘R`) in the status menu triggers the same behavior as the toolbar button
- [ ] **Cancelling the picker** (menu bar path): same safe hidden state, no crash
- [ ] **"Open Image…"** (`⌘O`) still works as before — no regression
- [ ] **Toggle Visibility** and **Quit** still work — no regression

---

## Edge Cases & Risks

| Risk | Impact | Mitigation |
|---|---|---|
| `overlayController` property name differs in `AppDelegate` | High — compile error | Confirm exact name before Phase 3 |
| Controller reference is `nil` when button is tapped (e.g., controller deallocated) | Medium — silent no-op | Existing pattern uses optional chaining (`controller?.`); maintain this pattern |
| User clicks "Change Image…" rapidly (double-tap) | Low — two `NSOpenPanel`s could open | `NSOpenPanel.begin` is modal per window; unlikely to cause issues, but consider a guard flag if observed |
| Toolbar height change breaks any hardcoded frame in `repositionToolbar()` | Medium | Verify `repositionToolbar()` reads `toolbarWindow.frame.height` dynamically, not a hardcoded `96` constant `[UNKNOWN — confirm]` |

---

## Open Questions

- [ ] What is the exact type/class of `canvasView`? (Need to confirm `.image = nil` is the correct way to clear it)
- [ ] What is the exact property name for `OverlayWindowController` on `AppDelegate`?
- [ ] Does `repositionToolbar()` use a hardcoded height constant anywhere, or is it fully dynamic via `toolbarWindow.frame.height`?

---

## Success Criteria

- [ ] "Change Image…" button is visible and functional in the toolbar HUD
- [ ] "Change Image…" menu item is visible and functional in the status bar menu with key equivalent `r`
- [ ] Both entry points call the same `clearAndReopen()` method — no duplicated logic
- [ ] Selecting a new image via either entry point loads and displays it correctly
- [ ] Cancelling the picker from either entry point does not crash
- [ ] All existing features (opacity sliders, click-through, open image, toggle visibility, quit) continue to work
- [ ] No new Swift compiler errors or warnings
