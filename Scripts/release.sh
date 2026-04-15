#!/usr/bin/env bash
# release.sh — build, zip, tag, and publish grapfel to GitHub Releases
# Usage: bash Scripts/release.sh  (run from repo root)

set -euo pipefail

VERSION="0.1.1"
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

NOTES_FILE="${DIST_DIR}/release-notes.md"
cat > "${NOTES_FILE}" << 'RELEASE_NOTES'
## grapfel v0.1.1

Patch release fixing the first-launch click bug and adding file attachment guardrails.

### Install

1. Download **grapfel-0.1.1-macos26.zip** from the assets below.
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

### What's new in v0.1.1

- **Fix #1** — Menubar icon click now opens the panel on first launch. Previously, clicking ✦ before the hotkey had ever been used did nothing; the panel was appearing and immediately self-dismissing due to a focus handoff race on first activation.
- **Fix #11** — Warning label appears in the input area when attached file(s) are likely to exceed the context window budget (~8 000 characters / ~2 000 tokens).
- **Fix #12** — File content is now hard-truncated at the context budget before sending, with a `[truncated]` marker appended so the model knows the file was cut. No more silently oversized payloads.

### Known limitations

- SSE streaming not yet working (apfel v0.9.x upstream issue)
- Global hotkey ⌘⇧Space is not yet configurable
RELEASE_NOTES

echo "==> Creating GitHub Release v${VERSION}..."
gh release create "v${VERSION}" \
  "${DIST_DIR}/${ZIP_NAME}" \
  --title "grapfel v${VERSION}" \
  --notes-file "${NOTES_FILE}"

echo ""
echo "Released: https://github.com/sfegette/grapfel/releases/tag/v${VERSION}"
echo "Zip: ${DIST_DIR}/${ZIP_NAME} (gitignored — not committed)"
