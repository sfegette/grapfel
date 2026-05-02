#!/usr/bin/env bash
# release.sh — build, sign (Sparkle EdDSA), zip, update appcast, tag, and publish grapfel
# Usage: bash Scripts/release.sh  (run from repo root)
#
# One-time setup:
#   1. Download the Sparkle release package from https://github.com/sparkle-project/Sparkle/releases
#      and copy sign_update to /usr/local/bin/ (or ~/bin/).
#   2. Run: sign_update --generate-keys    (stores private key in Keychain automatically)
#   3. Copy the printed public key into grapfel/Resources/Info.plist → SUPublicEDKey.
#   4. Enable GitHub Pages: repo Settings → Pages → Source: main branch, /docs folder.

set -euo pipefail

VERSION="0.1.3"
ZIP_NAME="grapfel-${VERSION}-macos26.zip"
BUILD_DIR="build"
APP_PATH="${BUILD_DIR}/Build/Products/Release/grapfel.app"
DIST_DIR="dist"
APPCAST="docs/appcast.xml"
RELEASE_URL="https://github.com/sfegette/grapfel/releases/download/v${VERSION}/${ZIP_NAME}"
PUB_DATE=$(date -R)

# ── Locate sign_update ───────────────────────────────────────────────────────

find_sign_update() {
  for candidate in \
      "/usr/local/bin/sign_update" \
      "${HOME}/.local/bin/sign_update" \
      "${HOME}/bin/sign_update"; do
    [[ -x "$candidate" ]] && echo "$candidate" && return
  done
  # SPM DerivedData checkouts (built as part of Xcode build)
  local found
  found=$(find "${HOME}/Library/Developer/Xcode/DerivedData" \
    -path "*/Sparkle/bin/sign_update" -type f 2>/dev/null | head -1)
  if [[ -n "$found" ]]; then echo "$found"; return; fi
  # Swift PM local cache
  found=$(find "${HOME}/Library/Caches/org.swift.swiftpm" \
    -name "sign_update" -type f 2>/dev/null | head -1)
  [[ -n "$found" ]] && echo "$found"
}

SIGN_UPDATE=$(find_sign_update)
if [[ -z "$SIGN_UPDATE" ]]; then
  echo "ERROR: sign_update not found." >&2
  echo "  Download Sparkle release from https://github.com/sparkle-project/Sparkle/releases" >&2
  echo "  and place sign_update in /usr/local/bin/ or ~/bin/" >&2
  exit 1
fi
echo "==> sign_update: ${SIGN_UPDATE}"

# ── Build ────────────────────────────────────────────────────────────────────

echo "==> Building grapfel ${VERSION} (Release)..."
xcodebuild build \
  -project grapfel.xcodeproj \
  -scheme grapfel \
  -configuration Release \
  -derivedDataPath "${BUILD_DIR}" \
  -quiet

if [ ! -d "${APP_PATH}" ]; then
  echo "ERROR: Build output not found at ${APP_PATH}" >&2
  exit 1
fi

# ── Zip ──────────────────────────────────────────────────────────────────────

echo "==> Zipping ${APP_PATH} → ${DIST_DIR}/${ZIP_NAME}..."
mkdir -p "${DIST_DIR}"
ditto -c -k --keepParent "${APP_PATH}" "${DIST_DIR}/${ZIP_NAME}"

# ── Sparkle EdDSA signature ──────────────────────────────────────────────────
# sign_update outputs:  sparkle:edSignature="<sig>" sparkle:length="<bytes>"

echo "==> Signing with EdDSA (private key from Keychain)..."
SIGN_OUTPUT=$("${SIGN_UPDATE}" "${DIST_DIR}/${ZIP_NAME}")

ED_SIGNATURE=$(echo "$SIGN_OUTPUT" | grep -o 'sparkle:edSignature="[^"]*"' \
  | sed 's/sparkle:edSignature="//;s/"//')
ZIP_SIZE=$(echo "$SIGN_OUTPUT" | grep -o 'sparkle:length="[^"]*"' \
  | sed 's/sparkle:length="//;s/"//')

if [[ -z "$ED_SIGNATURE" ]]; then
  echo "ERROR: sign_update produced no signature." >&2
  echo "  Raw output: ${SIGN_OUTPUT}" >&2
  echo "  Is the EdDSA private key in Keychain? Run: sign_update --generate-keys" >&2
  exit 1
fi
if [[ -z "$ZIP_SIZE" ]]; then
  ZIP_SIZE=$(stat -f%z "${DIST_DIR}/${ZIP_NAME}")
fi

echo "    Signature: ${ED_SIGNATURE:0:24}..."
echo "    Length:    ${ZIP_SIZE} bytes"

# ── Inject appcast item ──────────────────────────────────────────────────────

echo "==> Updating ${APPCAST} for v${VERSION}..."

python3 - <<PYEOF
import re, sys

appcast = "${APPCAST}"
with open(appcast) as f:
    content = f.read()

placeholder = "        <!-- ITEMS_PLACEHOLDER -->"
if placeholder not in content:
    print("ERROR: ITEMS_PLACEHOLDER not found in " + appcast, file=sys.stderr)
    sys.exit(1)

new_item = """\
        <item>
            <title>Version ${VERSION}</title>
            <pubDate>${PUB_DATE}</pubDate>
            <sparkle:version>${VERSION}</sparkle:version>
            <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
            <enclosure
                url="${RELEASE_URL}"
                length="${ZIP_SIZE}"
                type="application/octet-stream"
                sparkle:edSignature="${ED_SIGNATURE}"
            />
        </item>"""

content = content.replace(placeholder, new_item + "\n" + placeholder, 1)
with open(appcast, "w") as f:
    f.write(content)
print("    Appcast item prepended.")
PYEOF

git add "${APPCAST}"
git commit -m "release: appcast entry for v${VERSION}"
git push origin main

# ── Tag + GitHub Release ─────────────────────────────────────────────────────

echo "==> Tagging v${VERSION}..."
git tag -a "v${VERSION}" -m "Release v${VERSION}"
git push origin "v${VERSION}"

NOTES_FILE="${DIST_DIR}/release-notes.md"
cat > "${NOTES_FILE}" <<RELEASE_NOTES
## grapfel v${VERSION}

### Install

1. Download **${ZIP_NAME}** from the assets below.
2. Unzip and move \`grapfel.app\` to \`/Applications\`.
3. Launch. The **✦** icon appears in your menubar.
4. Future updates delivered automatically via Sparkle — or right-click ✦ → "Check for Updates…"

### Requirements

- macOS 26 Tahoe (beta) or later
- Apple Silicon (M-series)
- Apple Intelligence enabled in System Settings
- \`apfel\` v1.3.3+ — \`brew install apfel\`

### What's new in v${VERSION}

- **Auto-update** — Sparkle delivers new releases in-app; right-click ✦ → "Check for Updates…"
- **Token usage** — prompt / completion / total token count shown after each response
- **JSON mode** — toggle in the options panel to request structured JSON output
- **Permissive mode** — Settings → General to enable; server restarts automatically
- **apfel version check** — banner with one-click copy of \`brew upgrade apfel\` when outdated
- **Streaming on by default** — SSE streaming fully working with apfel 1.3.3+
- **Finish-reason surfacing** — truncated (\`length\`) and filtered (\`content_filter\`) responses annotated
RELEASE_NOTES

echo "==> Creating GitHub Release v${VERSION}..."
gh release create "v${VERSION}" \
  "${DIST_DIR}/${ZIP_NAME}" \
  --title "grapfel v${VERSION}" \
  --notes-file "${NOTES_FILE}"

echo ""
echo "Released: https://github.com/sfegette/grapfel/releases/tag/v${VERSION}"
echo "Appcast:  https://sfegette.github.io/grapfel/appcast.xml"
echo "Zip:      ${DIST_DIR}/${ZIP_NAME}  (gitignored)"
