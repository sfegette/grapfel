#!/usr/bin/env bash
# release.sh — build, sign, notarize, staple, zip, update appcast, tag, and publish grapfel
#
# Usage:
#   bash Scripts/release.sh               — full release (build, notarize, appcast, tag, GitHub)
#   bash Scripts/release.sh --no-tag      — same but skip git tag + push (used by CI)
#   bash Scripts/release.sh --local-test  — dev-signed build only; no notarization, appcast, or publish
#
# One-time setup:
#   1. Download Sparkle release package, copy sign_update + generate_keys to /usr/local/bin/
#   2. Run: generate_keys    (stores EdDSA private key in Keychain, paste public key → Info.plist)
#   3. Run: xcrun notarytool store-credentials "grapfel-notarize" \
#             --apple-id "scotrick@mac.com" --team-id "MX6K4V7DP6" --password "<app-specific-pw>"
#   4. Enable GitHub Pages: repo Settings → Pages → main branch, /docs folder

set -euo pipefail

VERSION=$(xcodebuild -project grapfel.xcodeproj -scheme grapfel \
  -showBuildSettings 2>/dev/null | awk '/MARKETING_VERSION/{print $3; exit}')
VERSION=${VERSION:-1.0.0}

ZIP_NAME="grapfel-${VERSION}-macos26.zip"
BUILD_DIR="build"
APP_PATH="${BUILD_DIR}/Build/Products/Release/grapfel.app"
DIST_DIR="dist"
APPCAST="docs/appcast.xml"
RELEASE_URL="https://github.com/sfegette/grapfel/releases/download/v${VERSION}/${ZIP_NAME}"
PUB_DATE=$(date -R)
NOTARIZE_PROFILE="grapfel-notarize"

DO_TAG=true
DO_LOCAL_TEST=false
for arg in "$@"; do
  case "$arg" in
    --no-tag)     DO_TAG=false ;;
    --local-test) DO_LOCAL_TEST=true; DO_TAG=false ;;
  esac
done

# ── Build tracker self-reporting ─────────────────────────────────────────────
# Reports release start/success/failure to the build tracker.
# Enable by exporting TRACKER_API_TOKEN; unset = silently skipped.
TRACKER_API_URL="${TRACKER_API_URL:-https://tracker.scottfegette.com/api/builds.php}"
TRACKER_DEPLOY_ID="$(uuidgen | tr '[:upper:]' '[:lower:]')"
TRACKER_STARTED_TS=0
tracker_started=false
tracker_final=false

tracker_post() {
  [ -n "${TRACKER_API_TOKEN:-}" ] || return 0
  curl -sf -X POST "${TRACKER_API_URL}?token=${TRACKER_API_TOKEN}" \
    -H 'Content-Type: application/json' -d "$1" >/dev/null \
    || echo "⚠️  tracker report failed (non-fatal)"
}

tracker_report_started() {
  if [ -z "${TRACKER_API_TOKEN:-}" ]; then
    echo "ℹ️  TRACKER_API_TOKEN unset — skipping build-tracker reporting"
    return 0
  fi
  TRACKER_STARTED_TS=$(date -u +%s)
  local started_at sha branch
  started_at=$(date -u '+%Y-%m-%d %H:%M:%S')
  sha=$(git rev-parse HEAD 2>/dev/null || echo "")
  branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")
  tracker_post "$(VERSION="$VERSION" SHA="$sha" BRANCH="$branch" \
    DEPLOY_ID="$TRACKER_DEPLOY_ID" STARTED_AT="$started_at" python3 -c "
import json, os
print(json.dumps({
    'repo_name':    'grapfel',
    'build_type':   'release',
    'version_tag':  'v' + os.environ['VERSION'],
    'commit_hash':  os.environ['SHA'],
    'branch':       os.environ['BRANCH'],
    'deploy_id':    os.environ['DEPLOY_ID'],
    'started_at':   os.environ['STARTED_AT'],
    'status':       'started',
    'triggered_by': 'release.sh',
}))")"
  tracker_started=true
  echo "▶ Build tracker: reported start (deploy_id ${TRACKER_DEPLOY_ID})"
}

tracker_report_success() {
  $tracker_started || return 0
  $tracker_final && return 0
  local finished_at duration
  finished_at=$(date -u '+%Y-%m-%d %H:%M:%S')
  duration=$(( $(date -u +%s) - TRACKER_STARTED_TS ))
  tracker_post "$(VERSION="$VERSION" DEPLOY_ID="$TRACKER_DEPLOY_ID" \
    FINISHED_AT="$finished_at" DURATION="$duration" python3 -c "
import json, os
print(json.dumps({
    'deploy_id':        os.environ['DEPLOY_ID'],
    'status':           'success',
    'finished_at':      os.environ['FINISHED_AT'],
    'duration_seconds': int(os.environ['DURATION']),
    'artifact_url':     'https://github.com/sfegette/grapfel/releases/tag/v' + os.environ['VERSION'],
}))")"
  tracker_final=true
  echo "✅ Build tracker: reported success"
}

tracker_report_failed() {
  $tracker_started || return 0
  $tracker_final && return 0
  local finished_at duration
  finished_at=$(date -u '+%Y-%m-%d %H:%M:%S')
  duration=$(( $(date -u +%s) - TRACKER_STARTED_TS ))
  tracker_post "$(DEPLOY_ID="$TRACKER_DEPLOY_ID" FINISHED_AT="$finished_at" \
    DURATION="$duration" python3 -c "
import json, os
print(json.dumps({
    'deploy_id':        os.environ['DEPLOY_ID'],
    'status':           'failed',
    'finished_at':      os.environ['FINISHED_AT'],
    'duration_seconds': int(os.environ['DURATION']),
}))")"
  tracker_final=true
  echo "✗ Build tracker: reported failure"
}

trap 'tracker_report_failed' ERR

echo "▶ grapfel ${VERSION}"

# ── Local test mode ──────────────────────────────────────────────────────────

if $DO_LOCAL_TEST; then
  echo "==> Local test build (dev-signed, no notarization)..."
  xcodebuild build \
    -project grapfel.xcodeproj \
    -scheme grapfel \
    -configuration Release \
    -derivedDataPath "${BUILD_DIR}" \
    -quiet
  echo "✅ Local test build ready: ${APP_PATH}"
  echo "   open '${APP_PATH}'"
  exit 0
fi

tracker_report_started

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

if $DO_TAG; then
  echo "==> Tagging v${VERSION}..."
  git tag -a "v${VERSION}" -m "Release v${VERSION}"
  git push origin "v${VERSION}"
fi

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

**Major feature release.**

- **Conversations sidebar** — persistent multi-conversation history stored as secure JSON files (0600). Switch, rename, and delete conversations; in-memory and disk state stay in sync even on write failure.
- **Conversation auto-title** — new conversations are titled from the first message (40-char word-boundary truncation) the moment you send.
- **Configurable global hotkey** — record any key combo in Settings; grapfel registers it via Carbon, falls back to the default ⌘⇧Space on failure, and shows a visible status message if registration fails.
- **Conversation export** — copy any conversation as Markdown or save it to a file; export all conversations as a JSON archive from the sidebar.
- **Setup / Homebrew flow** — grapfel detects whether Homebrew and apfel are installed and walks you through staged installation before the first chat.
- **Privacy manifest** — \`PrivacyInfo.xcprivacy\` added; in-product privacy disclosure in Settings (Privacy tab) explains what is stored and where.
- **Refreshed icon** — new app icon and menubar template glyph.
- **Retention modes** — choose between session-only (auto-purge on close), last-50-turns, or unlimited (capped at 200). Switching to session-only shows a destructive confirmation dialog.
- **Termination hardening** — app quit waits up to 4 s for apfel to shut down cleanly; save-panel guard prevents outside-click from closing the panel during an NSSavePanel sheet.
RELEASE_NOTES

echo "==> Creating GitHub Release v${VERSION}..."
gh release create "v${VERSION}" \
  "${DIST_DIR}/${ZIP_NAME}" \
  --title "grapfel v${VERSION}" \
  --notes-file "${NOTES_FILE}"

tracker_report_success

echo ""
echo "Released: https://github.com/sfegette/grapfel/releases/tag/v${VERSION}"
echo "Appcast:  https://sfegette.github.io/grapfel/appcast.xml"
echo "Zip:      ${DIST_DIR}/${ZIP_NAME}  (gitignored)"
