# Plan: Fix — Overlay Images Appear Upside-Down

## Task Type

Bug Fix

## Bug Summary

**Reported behavior**: Images uploaded to the overlay viewer are rendered vertically inverted (upside-down) in the floating window.  
**Expected behavior**: Images should appear right-side up, aspect-fit within the overlay view.  
**Affected area**: `ImageCanvasView.swift` — the custom `NSView` subclass responsible for drawing the overlay image.

---

## Root Cause Hypothesis

1. **Confirmed root cause**: `override var isFlipped: Bool { true }` on line 20 of `ImageCanvasView.swift` inverts the Core Graphics Y-axis so that Y increases downward (top-left origin). However, `NSImage.draw(in:from:operation:fraction:)` is **not** context-flip-aware — unlike `NSImageView`, it does not compensate for a flipped coordinate system. The result is that the image is drawn mirrored on the Y-axis (upside-down).

No other hypotheses are needed — the root cause is confirmed and isolated to a single line.

---

## Reproduction Steps

1. Launch the overlay-viewer app.
2. Upload any image via the provided upload mechanism.
3. Observe the floating overlay window — the image appears upside-down.

---

## Fix Strategy

### Step 1: Remove the flipped coordinate override

**File to modify**: `overlay-viewer/ImageCanvasView.swift`  
**Line**: 20  
**Change**: Delete `override var isFlipped: Bool { true }`

**Why this is safe**: The centering math in `draw(_:)` computes `(viewSize - drawSize) / 2` for both the X and Y origins. This calculation is fully symmetric and produces the correct centered rectangle in both flipped (top-left) and standard AppKit (bottom-left) coordinate systems. No other code in this view depends on the flipped coordinate system.

**Result**: The view reverts to the standard AppKit bottom-left origin. `NSImage.draw(in:from:operation:fraction:)` works correctly in this coordinate space and renders the image right-side up.

### Step 2: Build and verify

1. Build the project in Xcode (`⌘B`) — confirm zero build errors and zero new warnings.
2. Run the app (`⌘R`).
3. Upload a test image with a clear top/bottom orientation (e.g., a photo with text or a known subject).
4. Confirm the image appears right-side up in the overlay window.
5. Confirm the image remains correctly centered and aspect-fit within the overlay bounds at multiple window sizes.
6. Confirm opacity changes (if exposed via UI) still function correctly.

### Step 3 (Contingency): If removing `isFlipped` causes unexpected layout regressions

If any other part of the app turns out to depend on the flipped coordinate system of this view (e.g., subview positioning, gesture hit-testing offsets — `[UNKNOWN]` until inspected), fall back to **Option C**: keep `isFlipped: true` and replace the `NSImage.draw()` call with a `CGImage`-based draw using an explicit CTM correction:

```swift
if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.saveGState()
    ctx.translateBy(x: 0, y: bounds.height)
    ctx.scaleBy(x: 1, y: -1)
    ctx.setAlpha(contentOpacity)
    ctx.draw(cgImage, in: drawRect)
    ctx.restoreGState()
}
```

> **Note**: The contingency adds complexity and should only be used if Step 2 reveals a regression. The recommended fix (Step 1) is strongly preferred.

---

## Side Effects & Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| Other subviews or layout code in `ImageCanvasView` may assume flipped coordinates | Low — view appears to contain only drawing code, no subviews `[UNKNOWN — verify]` | Inspect full class for any subview additions or frame calculations before committing |
| `isFlipped` removal affects hit-test or mouse event coordinate mapping | Low — overlay is primarily a display view | Manually test any mouse interaction (drag, resize) after the fix |
| Fix is too narrow and the same issue exists elsewhere | Low — image drawing is isolated to this one `draw(_:)` override | Search project for other `NSImage.draw(` call sites as a sanity check |

---

## Rollback Plan

The change is a single-line deletion. To revert:
- Re-add `override var isFlipped: Bool { true }` at line 20 of `ImageCanvasView.swift`.
- If using git: `git checkout overlay-viewer/ImageCanvasView.swift`

---

## Assumptions

- No other view, controller, or layout code passes coordinates into `ImageCanvasView` that depend on its flipped state. `[UNKNOWN — verify by inspecting call sites]`
- The app has no snapshot or UI tests that would catch a visual regression automatically. Manual verification in Step 2 is the primary check.
- The centering math (`(viewSize - drawSize) / 2`) is the only geometric calculation in `draw(_:)` and is coordinate-system agnostic — confirmed from the provided file content.
- The project builds cleanly on the current machine before this change is applied.

---

## Success Criteria

- [ ] Uploaded images render right-side up in the overlay window
- [ ] Images remain centered and aspect-fit at all overlay window sizes
- [ ] Opacity changes continue to work correctly
- [ ] Zero new build errors or warnings introduced
- [ ] The change is confined to the single deleted line in `ImageCanvasView.swift`
- [ ] No existing functionality (drag, resize, window float behavior) is regressed
