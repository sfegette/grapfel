# Grapfel Worklist

Last updated: 2026-05-01  
Baseline: v0.1.2 released — items 1–4 of apfel 1.3.3 upgrade complete

## Released

- [x] **v0.1.0 — Initial public release** (2026-04-13)  
  Unsigned/ad-hoc zip for macOS 26 Tahoe beta users. Published to GitHub Releases as `grapfel-0.1.0-macos26.zip`. Gatekeeper bypass required (`xattr -dr com.apple.quarantine`).

- [x] **v0.1.2 — First-launch & attachment fixes** (2026-04-15)  
  Fixed panel invisible on icon click from /Applications (#1). File attachment size warnings and truncation (#11, #12).

---

## Active — Open GitHub Issues

### Bugs

_(none currently open)_

### Enhancements

- [ ] **#8 — Configurable hotkey UI**  
  Preferences UI to change the global hotkey away from ⌘⇧Space. Currently hardcoded in AppDelegate via Carbon `RegisterEventHotKey`.

### Design

- [ ] **#9 — App icon — final**  
  Interim generated icon in place. Spec at `Scripts/icon_spec.md`. Replace by dropping a 1024px master PNG and re-running `Scripts/generate_icon.swift`.

### Testing

- [ ] **#10 — Test suite**  
  Unit test property names fixed (`.response` → `.history`). Remaining blocker: NSApplication double-init when SwiftUI `@main` + XCTest host both fire — entry point needs `XCTestSessionIdentifier` guard (item G below). Priority targets: ChatViewModel, ApfelAPIClient, ApfelServerManager, MarkdownContent parser.

---

## Backlog — Post-apfel-1.3.3 Upgrade

Items from research into apfel 1.3.3 (done 2026-05-01). Priority order:

### Immediately actionable

- [ ] **A — Permissive toggle: server-level restart, not per-request**  
  The `permissive` toggle in OptionsPanel is non-functional — apfel does not accept a per-request permissive flag; it is a server startup flag (`--permissive`). Move to Settings as a toggle that calls `stop()` + `start(["--serve", "--port", ..., "--permissive"])`. Remove from OptionsPanel.  
  _Files: OptionsPanel.swift, SettingsView.swift, ApfelServerManager.swift_

- [ ] **C — apfel version check on startup**  
  Parse `version` field from `/health` JSON response (added in apfel 1.2.2). On startup, if version < 1.3.3, show a non-blocking nudge banner: "apfel X.Y.Z is running — upgrade with `brew upgrade apfel`". Clear once dismissed.  
  _Files: ApfelServerManager.swift (parse `/health` body), ContentView.swift or ServerState.swift (expose version), ConversationView or ContentView (banner)_

- [ ] **G — Test host fix (NSApplication double-init)**  
  `GrapfelApp.swift` `@main` fires NSApplicationMain when XCTest loads the host binary, creating a second NSApplication. Guard with `ProcessInfo.processInfo.environment["XCTestSessionIdentifier"] != nil` to skip the App lifecycle in test runs, or restructure the `@main` entry point.  
  _Files: GrapfelApp.swift_

### Next milestone

- [ ] **B — Sparkle auto-update**  
  EdDSA-signed appcast XML hosted on GitHub Pages; `SPUUpdater` wired into AppDelegate; "Check for Updates" added to right-click status-bar menu. `com.apple.security.network.client` entitlement already present — no new entitlements needed. Zero hosting cost (GitHub Pages + Releases).  
  _Files: project.yml (SPM dep), AppDelegate.swift, Scripts/release.sh (sign_update + appcast gen), Info.plist (public EdDSA key)_

- [ ] **E — Homebrew install flow in SetupView**  
  On `binaryNotFound`: detect if Homebrew binary exists at `/opt/homebrew/bin/brew` or `/usr/local/bin/brew`. If found, show "Install with Homebrew" button that spawns `brew install apfel` as a subprocess and streams stdout/stderr into a scrollable log view in the panel. On success, call `serverState.retry()` automatically.  
  _Files: SetupView.swift (new subprocess streaming UI), ServerState.swift_

### Deferred (polish)

- [ ] **D — Token usage display**  
  Send `stream_options: {"include_usage": true}` with streaming requests. Parse the final usage SSE chunk (`prompt_tokens`, `completion_tokens`). Show as "N / 4096 tokens" in OptionsPanel header or HeaderBar.  
  _Files: ApfelAPIClient.swift, ChatViewModel.swift, ConversationView.swift or OptionsPanel.swift_

- [ ] **F — JSON mode option**  
  Add `response_format: json_object` toggle to OptionsPanel. apfel 1.0.4+ strips markdown fences from JSON mode output automatically.  
  _Files: ApfelOptions.swift, ApfelAPIClient.swift (buildRequest), OptionsPanel.swift_

- [ ] **H — Brew services detection verification**  
  `ApfelServerManager.start()` already adopts an existing healthy process via early health-check return. Verify this correctly handles the case where `brew services start apfel` is running as a background daemon — no explicit spawn needed, no crash-restart interference.  
  _Files: ApfelServerManager.swift (smoke test / integration test)_

---

## Closed — All Versions

- [x] **#7 — Error UI for binary not found / server start failed** — `SetupView` + `ServerState` singleton; AppDelegate propagates errors to UI state; Retry button re-attempts start (2026-05-01)
- [x] **SSE streaming broken** — apfel 1.3.3 confirmed stable; `streaming` now defaults to `true`; `FinishReason` enum handles `length` and `content_filter` (2026-05-01)
- [x] **Context strategy not sent to API** — `x_context_strategy` + `x_context_max_turns` now in every request body (2026-05-01)
- [x] **#1 — First launch only opens from hotkey** — global mouse-down monitor replaces resign-key notification; removed false-positive applicationDidResignActive handler
- [x] **#11 — Warn when attached file(s) exceed context budget** — orange label in PromptInputView
- [x] **#12 — Truncate oversized attachments with [truncated] marker** — budget enforced in buildUserContent
- [x] **#2 — Chat opens at top, not bottom**
- [x] **#3 — Welcome/empty-state message**
- [x] **#4 — Attached files not read by LLM**
- [x] **#5 — Attached files don't clear**
