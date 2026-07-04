#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------------------------
# Overlay Viewer — release pipeline (FREE / no paid Apple Developer account)
#
# Builds a Release .app, ad-hoc signs it (required so it runs on Apple Silicon),
# packages a .dmg, and optionally publishes it to GitHub Releases.
#
# There is NO Developer ID signing and NO notarization here — those need the paid
# Apple Developer Program. Because the build isn't notarized, downloaders must
# do a one-time Gatekeeper bypass (right-click ▸ Open, or `xattr -dr
# com.apple.quarantine …`) — see CHANGELOG.md / RELEASE.md for the exact steps.
#
# Nothing secret is involved: ad-hoc signing uses no certificate or password.
#
# Usage:
#   ./release.sh            build + ad-hoc sign + package the .dmg
#   ./release.sh --publish  the above, then tag + create the GitHub release
# ------------------------------------------------------------------------------

cd "$(dirname "$0")"

# --- Load non-secret overrides from .env if present (.env is git-ignored) ---
if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

# --- Config (override via env / .env) ---
PROJECT="overlay-viewer.xcodeproj"
SCHEME="overlay-viewer"
PRODUCT_NAME="overlay-viewer"        # the .app bundle name (PRODUCT_NAME in the project)
APP_DISPLAY_NAME="Overlay Viewer"    # cosmetic: DMG volume + release title
VERSION="${VERSION:-1.0.0}"

BUILD_DIR="./build"
DERIVED_DATA="$BUILD_DIR/DerivedData"
APP_PATH="$DERIVED_DATA/Build/Products/Release/$PRODUCT_NAME.app"
ADHOC_ENTITLEMENTS="$BUILD_DIR/adhoc.entitlements"
DMG_STAGING="$BUILD_DIR/dmg-staging"
DMG_PATH="$BUILD_DIR/$PRODUCT_NAME-$VERSION.dmg"
TAG="v$VERSION"

log()  { printf '\n\033[1;34m▶ %s\033[0m\n' "$1"; }
die()  { printf '\n\033[1;31m✗ %s\033[0m\n' "$1" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "missing required tool: $1"; }

need xcodebuild
need hdiutil
need codesign

log "Building $APP_DISPLAY_NAME $VERSION (free / ad-hoc signed)"

# --- Clean ---
log "Cleaning previous build artifacts…"
rm -rf "$BUILD_DIR"; mkdir -p "$BUILD_DIR" "$DMG_STAGING"

# --- Build an unsigned Release .app ---
# CODE_SIGNING_ALLOWED=NO skips Xcode's provisioning (a free Apple ID can't
# provision the keychain-access-group entitlement); we sign ad-hoc ourselves.
log "Building unsigned Release .app…"
xcodebuild build \
  -project "$PROJECT" -scheme "$SCHEME" \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO
[[ -d "$APP_PATH" ]] || die "Expected app not found at $APP_PATH"

# --- Bake Figma credentials into Info.plist (before signing) ---
# A distributed .app has no process environment, so the app reads these from
# Info.plist at runtime (FigmaOAuthConfiguration.fromInfoDictionary). Values come
# from .env, sourced above. NOTE: this embeds the client secret in the shipped
# app — only do this for a trusted test build, and rotate the secret afterward.
INFO_PLIST="$APP_PATH/Contents/Info.plist"
if [[ -n "${FIGMA_CLIENT_ID:-}" && -n "${FIGMA_CLIENT_SECRET:-}" && -n "${FIGMA_REDIRECT_URI:-}" ]]; then
  log "Baking Figma credentials into Info.plist…"
  set_info() {  # key, value — add or overwrite
    /usr/libexec/PlistBuddy -c "Add :$1 string $2" "$INFO_PLIST" 2>/dev/null \
      || /usr/libexec/PlistBuddy -c "Set :$1 $2" "$INFO_PLIST"
  }
  set_info FigmaClientID     "$FIGMA_CLIENT_ID"
  set_info FigmaClientSecret "$FIGMA_CLIENT_SECRET"
  set_info FigmaRedirectURI  "$FIGMA_REDIRECT_URI"
else
  echo "  (FIGMA_* not set in .env — Figma will be disabled in this build)"
fi

# --- Ad-hoc sign ---
# Minimal entitlements: sandbox + network (Figma) + user-selected read files.
# The keychain-access-group entitlement is dropped on purpose — it requires a
# provisioning profile and isn't needed for the app's own Keychain items.
log "Ad-hoc signing…"
cat > "$ADHOC_ENTITLEMENTS" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>                    <true/>
    <key>com.apple.security.network.client</key>                <true/>
    <key>com.apple.security.files.user-selected.read-only</key> <true/>
</dict>
</plist>
PLIST
codesign --force --deep --sign - --entitlements "$ADHOC_ENTITLEMENTS" --timestamp=none "$APP_PATH"
codesign --verify --strict --verbose=2 "$APP_PATH"

# --- Build the .dmg ---
log "Building .dmg…"
if command -v create-dmg >/dev/null 2>&1; then
  create-dmg \
    --volname "$APP_DISPLAY_NAME" \
    --window-size 540 380 \
    --icon-size 100 \
    --icon "$PRODUCT_NAME.app" 150 185 \
    --app-drop-link 390 185 \
    "$DMG_PATH" "$APP_PATH"
else
  cp -R "$APP_PATH" "$DMG_STAGING/"
  ln -s /Applications "$DMG_STAGING/Applications"
  hdiutil create -volname "$APP_DISPLAY_NAME" -srcfolder "$DMG_STAGING" \
    -ov -format UDZO "$DMG_PATH"
fi

log "Done → $DMG_PATH"
echo "  (unsigned/ad-hoc: testers do a one-time Gatekeeper bypass — see CHANGELOG.md)"

# --- Optional: publish to GitHub Releases ---
if [[ "${1:-}" == "--publish" ]]; then
  need gh
  need git
  log "Publishing GitHub release $TAG…"
  git tag "$TAG" 2>/dev/null || echo "  tag $TAG already exists — reusing"
  git push origin "$TAG"
  gh release create "$TAG" "$DMG_PATH" \
    --title "$APP_DISPLAY_NAME $VERSION" \
    --notes-file CHANGELOG.md
  log "Published: $(gh release view "$TAG" --json url -q .url 2>/dev/null || echo "$TAG")"
else
  cat <<EOF

Next — publish to GitHub Releases when ready:
  ./release.sh --publish
or manually:
  git tag $TAG && git push origin $TAG
  gh release create $TAG "$DMG_PATH" --title "$APP_DISPLAY_NAME $VERSION" --notes-file CHANGELOG.md
EOF
fi
