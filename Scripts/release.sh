#!/usr/bin/env bash
# release.sh — build, sign, notarize, staple, zip, update appcast, tag, and publish grapfel
# Usage: bash Scripts/release.sh  (run from repo root)
#
# One-time setup:
#   1. Download Sparkle release package, copy sign_update + generate_keys to /usr/local/bin/
#   2. Run: generate_keys    (stores EdDSA private key in Keychain, paste public key → Info.plist)
#   3. Run: xcrun notarytool store-credentials "grapfel-notarize" \
#             --apple-id "scotrick@mac.com" --team-id "MX6K4V7DP6" --password "<app-specific-pw>"
#   4. Enable GitHub Pages: repo Settings → Pages → main branch, /docs folder

set -euo pipefail

VERSION="0.1.3"
ZIP_NAME="grapfel-${VERSION}-macos26.zip"
BUILD_DIR="build"
APP_PATH="${BUILD_DIR}/Build/Products/Release/grapfel.app"
DIST_DIR="dist"
APPCAST="docs/appcast.xml"
RELEASE_URL="https://github.com/sfegette/grapfel/releases/download/v${VERSION}/${ZIP_NAME}"
PUB_DATE=$(date -R)
NOTARIZE_PROFILE="grapfel-notarize"

# ── Locate sign_update ───────────────────────────────────────────────────────

find_sign_update() {
  for candidate in \
      "/usr/local/bin/sign_update" \
      "${HOME}/.local/bin/sign_update" \
      "${HOME}/bin/sign_update"; do
    [[ -x "$candidate" ]] && echo "$candidate" && return
  done
  local found
  found=$(find "${HOME}/Library/Developer/Xcode/DerivedData" \
    -path "*/Sparkle/bin/sign_update" -type f 2>/dev/null | head -1)
  if [[ -n "$found" ]]; then echo "$found"; return; fi
  found=$(find "${HOME}/Library/Caches/org.swift.swiftpm" \
    -name "sign_update" -type f 2>/dev/null | head -1)
  [[ -n "$found" ]] && echo "$found"
}

SIGN_UPDATE=$(find_sign_update)
if [[ -z "$SIGN_UPDATE" ]]; then
  echo "ERROR: sign_update not found." >&2
  exit 1
fi
echo "==> sign_update: ${SIGN_UPDATE}"

# ── Build (Release, Developer ID signed) ────────────────────────────────────

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

echo "==> Stripping get-task-allow and re-signing with production entitlements..."
DIST_ENTITLEMENTS="grapfel/grapfel-dist.entitlements"
DEV_ID="Developer ID Application: Scott Fegette (MX6K4V7DP6)"

# Sign inner components first (inside-out), preserving Sparkle's own signatures
# by only touching the components we own.
codesign --force --sign "${DEV_ID}" --timestamp --options runtime \
  "${APP_PATH}/Contents/MacOS/grapfel"

# Re-sign the outer app bundle with clean entitlements (no --deep, preserves Sparkle)
codesign --force --sign "${DEV_ID}" \
  --entitlements "${DIST_ENTITLEMENTS}" \
  --timestamp --options runtime \
  "${APP_PATH}"

echo "==> Verifying code signature..."
codesign --verify --deep --strict "${APP_PATH}"
codesign -dv --verbose=4 "${APP_PATH}" 2>&1 | grep "Authority\|TeamIdentifier\|Timestamp"

# Confirm get-task-allow is gone
if codesign -d --entitlements - "${APP_PATH}" 2>&1 | grep -q "get-task-allow.*true\|true.*get-task-allow"; then
  echo "ERROR: get-task-allow=true still present after re-signing" >&2
  exit 1
fi
echo "    get-task-allow: absent/false (good)"

# ── Zip for notarization ─────────────────────────────────────────────────────

mkdir -p "${DIST_DIR}"
NOTARIZE_ZIP="${DIST_DIR}/grapfel-notarize-tmp.zip"
echo "==> Zipping for notarization..."
ditto -c -k --keepParent "${APP_PATH}" "${NOTARIZE_ZIP}"

# ── Notarize ─────────────────────────────────────────────────────────────────

echo "==> Submitting to Apple notarization (this takes ~1 min)..."
xcrun notarytool submit "${NOTARIZE_ZIP}" \
  --keychain-profile "${NOTARIZE_PROFILE}" \
  --wait

rm -f "${NOTARIZE_ZIP}"

# ── Staple ───────────────────────────────────────────────────────────────────

echo "==> Stapling notarization ticket to app..."
xcrun stapler staple "${APP_PATH}"
xcrun stapler validate "${APP_PATH}"

# ── Final zip (stapled app) ──────────────────────────────────────────────────

echo "==> Zipping stapled app → ${DIST_DIR}/${ZIP_NAME}..."
ditto -c -k --keepParent "${APP_PATH}" "${DIST_DIR}/${ZIP_NAME}"

# ── Sparkle EdDSA signature ──────────────────────────────────────────────────

echo "==> Signing with EdDSA (private key from Keychain)..."
SIGN_OUTPUT=$("${SIGN_UPDATE}" "${DIST_DIR}/${ZIP_NAME}")

ED_SIGNATURE=$(echo "$SIGN_OUTPUT" | grep -o 'sparkle:edSignature="[^"]*"' \
  | sed 's/sparkle:edSignature="//;s/"//')
ZIP_SIZE=$(echo "$SIGN_OUTPUT" | grep -o 'sparkle:length="[^"]*"' \
  | sed 's/sparkle:length="//;s/"//')

if [[ -z "$ED_SIGNATURE" ]]; then
  echo "ERROR: sign_update produced no signature." >&2
  echo "  Raw output: ${SIGN_OUTPUT}" >&2
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
import sys

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
3. Launch — no Gatekeeper prompts, no quarantine step needed.
4. The **✦** icon appears in your menubar. Future updates delivered automatically via Sparkle.

### Requirements

- macOS 26 Tahoe (beta) or later
- Apple Silicon (M-series)
- Apple Intelligence enabled in System Settings
- \`apfel\` v1.3.3+ — \`brew install apfel\`

### What's new in v${VERSION}

- **Signed & notarized** — opens directly from /Applications, no quarantine prompt
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
