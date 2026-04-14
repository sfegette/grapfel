#!/usr/bin/env bash
# release.sh — build, zip, tag, and publish grapfel to GitHub Releases
# Usage: bash Scripts/release.sh  (run from repo root)

set -euo pipefail

VERSION="0.1.0"
ZIP_NAME="grapfel-${VERSION}-macos26.zip"
APP_PATH="build/Release/grapfel.app"
DIST_DIR="dist"

echo "==> Building grapfel ${VERSION} (Release)..."
xcodebuild build \
  -project grapfel.xcodeproj \
  -scheme grapfel \
  -configuration Release \
  -quiet

if [ ! -d "${APP_PATH}" ]; then
  echo "ERROR: Build output not found at ${APP_PATH}" >&2
  exit 1
fi

echo "==> Zipping ${APP_PATH} → ${DIST_DIR}/${ZIP_NAME}..."
mkdir -p "${DIST_DIR}"
ditto -c -k --keepParent "${APP_PATH}" "${DIST_DIR}/${ZIP_NAME}"

echo "==> Tagging v${VERSION}..."
git tag -a "v${VERSION}" -m "Release v${VERSION}"
git push origin "v${VERSION}"

echo "==> Creating GitHub Release v${VERSION}..."
gh release create "v${VERSION}" \
  "${DIST_DIR}/${ZIP_NAME}" \
  --title "grapfel v${VERSION}" \
  --notes "$(cat <<'RELEASE_NOTES'
## grapfel v0.1.0

First public release. Requires **macOS 26 Tahoe (beta)** and **Apple Silicon** with Apple Intelligence enabled.

### Install

1. Download **grapfel-0.1.0-macos26.zip** from the assets below.
2. Unzip and move `grapfel.app` to `/Applications`.
3. Clear the quarantine flag (this build is unsigned):
   ```
   xattr -dr com.apple.quarantine /Applications/grapfel.app
   ```
   Or: right-click `grapfel.app` → **Open** → **Open** in the dialog.
4. Launch. The **✦** icon appears in your menubar.

### Requirements

- macOS 26 Tahoe (beta) or later
- Apple Silicon (M-series)
- Apple Intelligence enabled in System Settings
- `apfel` v0.9.0+ — `brew tap Arthur-Ficial/tap && brew install apfel`

### What's in this release

- Menubar icon + Liquid Glass panel (⌘⇧Space or click ✦)
- On-device inference via apfel — no API keys, no cloud
- Multi-turn conversation with persistence
- Markdown rendering + copy response (raw / code block / plain text)
- File attachment (text, source, JSON, RTF)
- Options panel (temperature, max tokens, seed, system prompt, context strategy)

### Known limitations

- SSE streaming not yet working (apfel v0.9.x upstream issue)
- Global hotkey ⌘⇧Space is not yet configurable
- Context window is 4096 tokens — large file attachments may be truncated in a future release
RELEASE_NOTES
)"

echo ""
echo "Released: https://github.com/sfegette/grapfel/releases/tag/v${VERSION}"
echo "Zip: ${DIST_DIR}/${ZIP_NAME} (gitignored — not committed)"
