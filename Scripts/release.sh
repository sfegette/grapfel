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

VERSION="0.1.4"
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

echo "==> Re-signing all components with Developer ID (inside-out)..."
DIST_ENTITLEMENTS="grapfel/grapfel-dist.entitlements"
DEV_ID="Developer ID Application: Scott Fegette (MX6K4V7DP6)"
SPARKLE="${APP_PATH}/Contents/Frameworks/Sparkle.framework/Versions/B"

# 1. Sparkle XPC services
for xpc in "${SPARKLE}/XPCServices/"*.xpc; do
  codesign --force --sign "${DEV_ID}" --timestamp --options runtime "$xpc"
done

# 2. Sparkle helper apps and binaries
codesign --force --sign "${DEV_ID}" --timestamp --options runtime "${SPARKLE}/Updater.app"
codesign --force --sign "${DEV_ID}" --timestamp --options runtime "${SPARKLE}/Autoupdate"

# 3. Sparkle framework
codesign --force --sign "${DEV_ID}" --timestamp \
  "${APP_PATH}/Contents/Frameworks/Sparkle.framework"

# 4. Main executable (strips get-task-allow injected by Xcode 26)
codesign --force --sign "${DEV_ID}" --timestamp --options runtime \
  "${APP_PATH}/Contents/MacOS/grapfel"

# 5. Outer app bundle with production entitlements
codesign --force --sign "${DEV_ID}" \
  --entitlements "${DIST_ENTITLEMENTS}" \
  --timestamp --options runtime \
  "${APP_PATH}"

echo "==> Verifying code signature..."
codesign --verify --deep --strict "${APP_PATH}"
codesign -dv --verbose=4 "${APP_PATH}" 2>&1 | grep "Authority\|TeamIdentifier\|Timestamp"

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

ED_SIGNATURE=$(echo "$SIGN_OUTPUT" | grep -o 'edSignature="[^"]*"' \
  | sed 's/edSignature="//;s/"//')
ZIP_SIZE=$(echo "$SIGN_OUTPUT" | grep -o 'length="[^"]*"' \
  | sed 's/length="//;s/"//')

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

- **Conversation sidebar** — hamburger menu reveals a slide-in sidebar; browse, rename, and delete past conversations. The chat area never moves or resizes.
- **Multi-conversation history** — each conversation is persisted as an individual JSON file in `~/Library/Application Support/grapfel/` with owner-only (0600) permissions
- **Stop / regenerate / edit** — stop mid-stream, regenerate the last response, or edit your last message
- **Streaming render fix** — in-progress tokens render in a fast plain-text bubble; completed turns use the Markdown renderer. Per-token re-render churn eliminated.
- **MCP servers** — Settings → Tools to add Model Context Protocol server paths; passed to apfel on next restart
- **Privacy tab** — Settings → Privacy to choose retention mode (session-only / last-N turns / unlimited) and review storage limits
- **Binary hardening** — apfel binary is validated (executable bit + Mach-O check) before launch; invalid path shows a clear error with retry
- **Orphaned-process cleanup** — `stop()` finds and kills any apfel process already listening on the configured port (e.g. from a previous SIGKILL'd Xcode run)
- **Menubar icon reliability fix** — clicking the ✦ icon now reliably shows the panel after app-switch or idle, not just on first launch
- **Accessibility** — all interactive controls have labels; streaming bubble is marked \`.updatesFrequently\`
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
