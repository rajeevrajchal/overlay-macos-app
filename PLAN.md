# Plan: Overlay Viewer — Slider Fix, Remove Behavior, Placeholder State

## Task Type

Bug Fix (×2) + Behavior Change (×1)

## Overview

Three targeted changes to `OverlayWindowController.swift` and (conditionally) `ImageCanvasView.swift`:

1. **Phase 1 — Opacity Slider Fix**: The slider currently uses `autoresizingMask = [.width]` which causes it to stretch or compress as the window resizes, appearing cropped at narrow widths. Fix: give it a fixed width of 120pt and remove the autoresizing mask.

2. **Phase 2 — "Remove" Button Behavior**: Clicking "Remove" currently calls `presentOpenPanel()`, immediately opening a system file picker. Correct behavior: return the app to its initial empty/placeholder state — either via `WelcomeWindowController` (Sub-case A) if it is implemented, or by keeping the overlay window visible and rendering placeholder UI in the canvas (Sub-case B).

3. **Phase 3 — Placeholder State in `ImageCanvasView`** (Sub-case B fallback): If `WelcomeWindowController` is not yet functional, add a `draw(_:)` branch in `ImageCanvasView` that draws a centered SF Symbol icon and helper text when `image == nil`.

All changes are frame-based AppKit. No SwiftUI. No Auto Layout. Zero new dependencies.

---

## Goals

- [ ] **Goal A** — Slider occupies a fixed 120pt-wide region and does not stretch or compress on window resize.
- [ ] **Goal B** — Clicking "Remove" returns the app to a welcome/placeholder state rather than opening a file picker.
- [ ] **Goal C** — When no image is loaded, the canvas (or welcome window) shows clear placeholder UI so the user knows how to proceed.

---

## Assumptions

- `OverlayWindowController.swift` is the single source of truth for the toolbar ribbon and window management; the code block in this plan is its exact current state.
- `ImageCanvasView` is an `NSView` subclass in `ImageCanvasView.swift` with at minimum: `var image: NSImage?` and `var contentOpacity: CGFloat`. Its `draw(_:)` implementation handles aspect-fit drawing; whether it currently handles the `image == nil` case is **[UNKNOWN — check file before Phase 3]**.
- `WelcomeWindowController` is referenced in `OverlayWindowController.swift` but its implementation status is **[UNKNOWN]**. Phase 2 instructions are written for both sub-cases; the developer must verify which applies.
- The project targets macOS 13+ (SF Symbols are available; `NSImage(systemSymbolName:accessibilityDescription:)` is supported).
- `OverlayWindow` (custom `NSWindow` subclass) handles `canBecomeKey`, `level`, and `styleMask`; its implementation is not modified here.
- The existing `minSize` of `NSSize(width: 200, height: ribbonHeight + 60)` may cause visual overlap of ribbon controls at very narrow widths. A recommended (but optional) adjustment to `400pt` minimum width is noted in Phase 1.

---

## Pre-Flight: Check `WelcomeWindowController` Status

Before beginning Phase 2, verify whether `WelcomeWindowController` is implemented and functional:

```
# In Xcode Project Navigator or Terminal:
find . -name "WelcomeWindowController.swift"
```

- **File exists AND has a working `showWindow(_:)` implementation** → follow **Sub-case A** in Phase 2. Phase 3 is not required.
- **File does not exist, or exists but is a stub/empty** → follow **Sub-case B** in Phase 2 and execute Phase 3.

---

## Architecture Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Slider width | Fixed 120pt, `autoresizingMask = []` | Compact ribbon control; avoids cropping/overflow at any practical window width |
| Remove → empty state routing | `showWelcomeWindow()` (Sub-case A) or in-canvas placeholder (Sub-case B) | Matches the app's existing welcome flow; avoids introducing a third window |
| Placeholder drawing | `NSString.draw(in:withAttributes:)` + `NSImage.draw(in:)` (SF Symbol) | Pure AppKit, no image assets needed, works at any canvas size |
| Minimum window width | Recommend raising to 400pt | Prevents ribbon controls overlapping at the leftmost edge when slider occupies x=268..388 |

---

## Implementation Steps

---

### Phase 1: Fix Opacity Slider — Fixed Width, No Autoresizing (Estimated: Simple)

**Goal link**: Goal A
**Files touched**: `OverlayWindowController.swift`
**Depends on**: Nothing

#### Slider Value Ratio Confirmation

The slider is already correctly configured for a 0–1 opacity ratio:

- `minValue = 0.05` (5 % minimum — prevents the window from becoming fully invisible)
- `maxValue = 1.0` (100 % — fully opaque)
- `windowOpacityChanged(_:)` reads `sender.doubleValue` and assigns it directly to `window?.alphaValue`

The thumb position within the slider track represents `(currentValue - 0.05) / (1.0 - 0.05) = (value - 0.05) / 0.95` of full track width — this is handled automatically by AppKit. **No value transformation is needed.** The fix is purely visual/layout.

#### Step-by-step

1. **Open** `OverlayWindowController.swift`.

2. **Locate** the `buildToolbarRibbon()` method, specifically the `opacitySlider` block (approximately lines 127–135 in the provided code):

   ```swift
   // BEFORE
   let opacitySlider = NSSlider(
       value: 1.0, minValue: 0.05, maxValue: 1.0,
       target: self, action: #selector(windowOpacityChanged(_:))
   )
   opacitySlider.frame = NSRect(x: 268, y: 8, width: 324, height: 20)
   opacitySlider.isContinuous = true
   opacitySlider.autoresizingMask = [.width]   // <-- BUG: makes slider stretch with window
   ```

3. **Replace** with:

   ```swift
   // AFTER
   let opacitySlider = NSSlider(
       value: 1.0, minValue: 0.05, maxValue: 1.0,
       target: self, action: #selector(windowOpacityChanged(_:))
   )
   opacitySlider.frame = NSRect(x: 268, y: 8, width: 120, height: 20)
   opacitySlider.isContinuous = true
   opacitySlider.autoresizingMask = []   // fixed width — does not stretch with window
   ```

   **Exact diff:**
   - Line `opacitySlider.frame = NSRect(x: 268, y: 8, width: 324, height: 20)` → `width: 120`
   - Line `opacitySlider.autoresizingMask = [.width]` → `autoresizingMask = []`

4. **(Recommended — optional)** In the `convenience init()`, update `minSize` to prevent ribbon control overlap at very narrow window widths:

   ```swift
   // BEFORE
   window.minSize = NSSize(width: 200, height: ribbonHeight + 60)

   // AFTER (recommended)
   window.minSize = NSSize(width: 400, height: ribbonHeight + 60)
   ```

   **Rationale**: The fixed opacity block spans x=212 to x=388 (Opacity label + slider). With buttons on the left ending around x=204, a minimum of 400pt ensures no overlap even at the smallest allowed size. If 200pt is required for other reasons, accept that the label/slider may be partially clipped at very narrow windows.

5. **Build and run**. Resize the window. The slider should remain 120pt wide regardless of window width.

---

### Phase 2: "Remove" Button — Route to Welcome/Placeholder State (Estimated: Simple–Moderate)

**Goal link**: Goal B
**Files touched**: `OverlayWindowController.swift` (both sub-cases); `WelcomeWindowController.swift` (Sub-case A, verify only — no edits expected)
**Depends on**: Pre-flight check (know which sub-case applies)

#### Sub-case A: `WelcomeWindowController` EXISTS and is functional

1. **Open** `OverlayWindowController.swift`.

2. **Locate** `removeImageAction()`:

   ```swift
   // BEFORE
   @objc private func removeImageAction() {
       canvasView.image = nil
       window?.orderOut(nil)
       // TODO: replace with showWelcomeWindow() when WelcomeWindowController is integrated
       presentOpenPanel()   // <-- BUG: should show placeholder/welcome state, not file picker
   }
   ```

3. **Replace** with:

   ```swift
   // AFTER — Sub-case A
   @objc private func removeImageAction() {
       guard canvasView.image != nil else { return }   // no-op if already in empty state
       canvasView.image = nil
       window?.orderOut(nil)
       showWelcomeWindow()   // returns to initial empty/placeholder state
   }
   ```

   **Key changes:**
   - Added early-exit guard: if `canvasView.image` is already `nil` (e.g., user double-taps Remove), the method returns immediately — safe no-op.
   - Replaced `presentOpenPanel()` with `showWelcomeWindow()`.
   - Removed the stale `// TODO` comment.

4. **Verify** that `showWelcomeWindow()` (already implemented in the class) correctly:
   - Creates `WelcomeWindowController` lazily if `welcomeController == nil`
   - Sets `wc.onImagePicked` closure to call `self?.load(imageURL:)`
   - Calls `welcomeController?.window?.center()` and `showWindow(nil)`
   - Calls `NSApp.activate(ignoringOtherApps: true)`

   No changes to `showWelcomeWindow()` should be needed. Read the method body to confirm.

5. **Verify** that `WelcomeWindowController` handles the case where its window fails to load (e.g., missing nib/xib). If `wc.window` is `nil` after init, `showWindow(nil)` is a silent no-op in AppKit — the welcome window simply won't appear. Add a defensive check if desired:

   ```swift
   // Optional defensive addition inside showWelcomeWindow(), after showWindow(nil):
   if welcomeController?.window == nil {
       // WelcomeWindowController failed to load its window — fall back to presentOpenPanel()
       presentOpenPanel()
   }
   ```

   This is an **optional safety net**, not a required change.

---

#### Sub-case B: `WelcomeWindowController` does NOT exist or is a stub

1. **Open** `OverlayWindowController.swift`.

2. **Locate** `removeImageAction()` (same as above).

3. **Replace** with:

   ```swift
   // AFTER — Sub-case B
   @objc private func removeImageAction() {
       guard canvasView.image != nil else { return }   // no-op if already in empty state
       canvasView.image = nil
       // Keep the overlay window visible — ImageCanvasView.draw(_:) renders placeholder UI
       // when image is nil (see Phase 3 for the draw implementation).
       window?.orderFrontRegardless()
   }
   ```

   **Key changes:**
   - Added early-exit guard (same as Sub-case A).
   - Removed `window?.orderOut(nil)` — the window stays on screen to show the placeholder.
   - Replaced `presentOpenPanel()` with `window?.orderFrontRegardless()` to ensure the window is visible.
   - Phase 3 must be completed for the placeholder to actually render.

4. **Also update `changeImageAction()`** to check whether WelcomeWindowController exists. Currently `changeImageAction()` calls `clearAndReopen()` which calls `presentOpenPanel()`. This is correct behavior for "Change" (user explicitly wants a picker), so **no change is needed** to `changeImageAction()`.

---

### Phase 3: Placeholder State in `ImageCanvasView` — Sub-case B Only (Estimated: Moderate)

**Goal link**: Goal C
**Files touched**: `ImageCanvasView.swift`
**Depends on**: Phase 2 Sub-case B — only execute if `WelcomeWindowController` is absent

> **Skip this phase entirely if following Sub-case A.**

#### Step-by-step

1. **Open** `ImageCanvasView.swift`. Read the existing `draw(_ dirtyRect: NSRect)` implementation in full before editing.

2. **Locate** (or add) the `draw(_ dirtyRect: NSRect)` override. The current implementation handles the `image != nil` case (aspect-fit drawing with `contentOpacity`). It likely does nothing or draws a blank background when `image == nil`.

3. **Add a `when image == nil` branch** at the top of `draw(_:)`:

   ```swift
   override func draw(_ dirtyRect: NSRect) {
       // MARK: Placeholder state — no image loaded
       guard let image else {
           drawPlaceholder(in: dirtyRect)
           return
       }

       // ... existing image-drawing code below (unchanged) ...
   }

   // MARK: - Private Placeholder Drawing

   private func drawPlaceholder(in rect: NSRect) {
       // 1. Background — semi-transparent dark fill matching the app's aesthetic
       NSColor.black.withAlphaComponent(0.15).setFill()
       rect.fill()

       // 2. SF Symbol icon — centered in upper half of available space
       let iconSize = NSSize(width: 64, height: 64)
       let iconOrigin = NSPoint(
           x: (rect.width - iconSize.width) / 2,
           y: (rect.height / 2) - 8   // slightly above vertical center
       )
       let iconRect = NSRect(origin: iconOrigin, size: iconSize)

       if let symbolImage = NSImage(
           systemSymbolName: "photo.badge.plus",
           accessibilityDescription: "Open an image"
       ) {
           let config = NSImage.SymbolConfiguration(pointSize: 48, weight: .thin)
           let tinted = symbolImage.withSymbolConfiguration(config)
           // Draw tinted white icon
           NSGraphicsContext.current?.imageInterpolation = .high
           tinted?.draw(
               in: iconRect,
               from: .zero,
               operation: .sourceOver,
               fraction: 0.6   // 60% opacity — subtle
           )
       }

       // 3. Helper text — centered below icon
       let labelText = "Click to open an image"
       let labelAttributes: [NSAttributedString.Key: Any] = [
           .font: NSFont.systemFont(ofSize: 13, weight: .regular),
           .foregroundColor: NSColor.white.withAlphaComponent(0.7)
       ]
       let labelSize = (labelText as NSString).size(withAttributes: labelAttributes)
       let labelRect = NSRect(
           x: (rect.width - labelSize.width) / 2,
           y: iconOrigin.y - labelSize.height - 10,
           width: labelSize.width,
           height: labelSize.height
       )
       (labelText as NSString).draw(in: labelRect, withAttributes: labelAttributes)
   }
   ```

4. **Make the canvas clickable** to trigger the open panel when in placeholder state. Add a `mouseDown` override to `ImageCanvasView`:

   ```swift
   // In ImageCanvasView.swift — add a delegate/callback property:
   var onPlaceholderTapped: (() -> Void)?

   override func mouseDown(with event: NSEvent) {
       if image == nil {
           onPlaceholderTapped?()   // fires only in placeholder state
       } else {
           super.mouseDown(with: event)
       }
   }
   ```

5. **Wire up `onPlaceholderTapped`** in `OverlayWindowController`'s `convenience init()`, after `canvasView` is created:

   ```swift
   // Add after: let container = OverlayContainerView(...)
   canvasView.onPlaceholderTapped = { [weak self] in
       self?.presentOpenPanelOrWelcome()
   }
   ```

6. **Ensure `needsDisplay` is triggered** when `canvasView.image` is set to `nil`. In `ImageCanvasView.swift`, if `image` is a plain stored property:

   ```swift
   // BEFORE (likely):
   var image: NSImage?

   // AFTER — add didSet to trigger redraw:
   var image: NSImage? {
       didSet { needsDisplay = true }
   }
   ```

   If `image` already has a `didSet` that calls `needsDisplay = true`, skip this step.

7. **Build and run**. Remove an image. The overlay window should stay visible and display the photo.badge.plus icon with "Click to open an image" text. Clicking anywhere on the canvas should open the file picker.

---

## Slider Value Ratio — Confirmation Summary

| Property | Value | Meaning |
|---|---|---|
| `minValue` | `0.05` | 5% opacity — window is nearly invisible but still interactable |
| `maxValue` | `1.0` | 100% opacity — fully opaque |
| `alphaValue` binding | `window?.alphaValue = CGFloat(sender.doubleValue)` | Direct 1-to-1 mapping — no transformation |
| Thumb at far left | `alphaValue = 0.05` | Window at 5% opacity |
| Thumb at far right | `alphaValue = 1.0` | Window at 100% opacity |

**No change to value logic is required.** The fix is layout-only.

---

## Edge Cases & Risks

| Risk | Impact | Mitigation |
|---|---|---|
| Window narrower than 388pt causes slider/label overlap with left buttons | Low | Raise `minSize.width` from 200pt to 400pt (Phase 1, Step 4) |
| `removeImageAction()` called when `canvasView.image` is already `nil` (double-tap Remove) | Low | Added `guard canvasView.image != nil else { return }` in both sub-cases |
| `WelcomeWindowController` init succeeds but `window` is `nil` (missing xib/nib) | Medium | `showWindow(nil)` is a silent no-op; add optional defensive fallback to `presentOpenPanel()` (Phase 2, Sub-case A, Step 5) |
| `NSImage(systemSymbolName:)` returns `nil` on macOS < 11.0 | Low | Project targets macOS 13+; confirmed available. If target ever drops below 11.0, wrap in `if #available(macOS 11, *)` |
| `drawPlaceholder(in:)` flickers on rapid `needsDisplay` calls | Low | `ImageCanvasView` is not animated; `needsDisplay` is triggered only on `image` property change |
| Placeholder `mouseDown` intercepting drags/other gestures | Low | Only intercepts `mouseDown` when `image == nil`; restores `super.mouseDown` otherwise |
| `changeImageAction()` → `clearAndReopen()` still calls `presentOpenPanel()` — this is intentional for "Change" | None | Confirmed correct; user explicitly wants a picker when clicking "Change…" |
| Slider at `x=268`, fixed `width=120` → right edge at `x=388` — sits inside 600pt default width | None | Default window is 600pt wide; 388 < 600. At minimum recommended width of 400pt, right edge is 12pt from window edge — comfortable |

---

## Verification Checklist

- [ ] **1. Slider no longer stretches**: Open window, drag it wider and narrower — slider width stays 120pt. Confirm in View Debugger (Xcode Debug → View Debugging → Capture View Hierarchy) that `NSSlider` frame width is exactly 120pt.
- [ ] **2. Slider no longer crops**: At minimum window width (200pt or 400pt if adjusted), slider is fully visible and fully interactive.
- [ ] **3. Slider value is correct**: Drag slider to far left — window becomes nearly transparent (5% opacity). Drag to far right — window becomes fully opaque. No off-by-one or inverted behavior.
- [ ] **4. Remove button (Sub-case A)**: Click "Remove". File picker does NOT open. Welcome window appears centered. Overlay window hides (`isVisible == false`).
- [ ] **5. Remove button (Sub-case B)**: Click "Remove". File picker does NOT open. Overlay window remains visible. Canvas shows `photo.badge.plus` icon and "Click to open an image" text.
- [ ] **6. Placeholder click (Sub-case B)**: Click anywhere on the placeholder canvas — file picker opens. Load an image — canvas renders the image (placeholder disappears).
- [ ] **7. Double-tap Remove is a no-op**: Click "Remove" twice rapidly. No crash, no file picker, no unexpected state change. Second click returns immediately (guard fires).
- [ ] **8. Load image after Remove**: After clicking Remove and returning to empty state, pick a new image via the welcome window or canvas click. Image loads, displays correctly, window resizes to match image dimensions.
- [ ] **9. Opacity slider after reload**: After loading a new image post-Remove, the opacity slider still controls `window.alphaValue` correctly.
- [ ] **10. Minimum window width (if adjusted to 400pt)**: Window cannot be resized narrower than 400pt. Ribbon controls do not overlap at that width.

---

## Open Questions

- [ ] **Is `WelcomeWindowController` fully implemented?** Run the pre-flight check (`find . -name "WelcomeWindowController.swift"`) and inspect the file. Determines Sub-case A vs. Sub-case B for Phase 2, and whether Phase 3 is needed at all.
- [ ] **Does `ImageCanvasView.image` already have a `didSet { needsDisplay = true }` observer?** If so, skip Phase 3 Step 6. If not, the placeholder will not redraw after Remove.
- [ ] **What is the intended cursor for the placeholder canvas (Sub-case B)?** Consider setting `addCursorRect(bounds, cursor: .pointingHand)` in `ImageCanvasView.resetCursorRects()` when `image == nil` to signal clickability.
- [ ] **Should the overlay window be visible or hidden after Remove (Sub-case B)?** Current plan: keep it visible with placeholder. If the window's transparent/floating style makes a blank canvas confusing, hiding and showing a separate panel may be preferable — but this requires WelcomeWindowController (loop back to Sub-case A).

---

## Success Criteria

- [ ] Opacity slider is exactly 120pt wide at all window sizes — confirmed via View Debugger frame inspection
- [ ] `autoresizingMask` on `opacitySlider` is `[]` — no stretch, no compress
- [ ] Clicking "Remove" never opens a system file picker
- [ ] After clicking "Remove", the user sees a clear visual state (welcome window or placeholder canvas) that indicates how to open an image
- [ ] `removeImageAction()` is idempotent — calling it when no image is loaded is a safe no-op
- [ ] All existing behaviors (Change, Close, Opacity, drag-to-move, toggle visibility) are unaffected
- [ ] Zero new compiler warnings or errors
- [ ] Build succeeds with no third-party dependencies added
