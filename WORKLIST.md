# Grapfel Worklist

Last updated: 2026-05-21  
Baseline: v0.1.2 released — items 1–4 of apfel 1.3.3 upgrade complete

## Released

- [x] **v0.1.3 — Distribution & Advanced Options** (2026-05-02)  
  Sparkle auto-updates (#B), Developer ID signing/notarization, Permissive mode toggle (#A), apfel version check (#C), Token usage display (#D), and JSON mode support (#F).

- [x] **v0.1.2 — First-launch & attachment fixes** (2026-04-15)  
  Fixed panel invisible on icon click from /Applications (#1). File attachment size warnings and truncation (#11, #12).

- [x] **v0.1.0 — Initial public release** (2026-04-13)  
  Unsigned/ad-hoc zip for macOS 26 Tahoe beta users. Published to GitHub Releases as `grapfel-0.1.0-macos26.zip`. Gatekeeper bypass required (`xattr -dr com.apple.quarantine`).

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

---

## Backlog

### Immediately actionable

- [ ] **E — Homebrew install flow in SetupView**  
  On `binaryNotFound`: detect if Homebrew binary exists and show "Install with Homebrew" button that spawns `brew install apfel`.  
  _Files: SetupView.swift, ServerState.swift_

### Deferred (polish)

- [ ] **H — Brew services detection verification**  
  Verify `ApfelServerManager.start()` correctly handles `brew services start apfel` as a background daemon.  
  _Files: ApfelServerManager.swift (smoke test / integration test)_

---

## Closed — All Versions

- [x] **#7 — Error UI for binary not found / server start failed** — `SetupView` + `ServerState` singleton; AppDelegate propagates errors to UI state; Retry button re-attempts start (2026-05-01)
- [x] **SSE streaming broken** — apfel 1.3.3 confirmed stable; `streaming` now defaults to `true`; `FinishReason` enum handles `length` and `content_filter` (2026-05-01)
- [x] **Context strategy not sent to API** — `x_context_strategy` + `x_context_max_turns` now in every request body (2026-05-01)
- [x] **#1 — First launch only opens from hotkey** — global mouse-down monitor replaces resign-key notification; removed false-positive applicationDidResignActive handler
- [x] **#11 — Warn when attached file(s) exceed context budget** — orange label in PromptInputView
- [x] **#12 — Truncate oversized attachments with [truncated] marker** — budget enforced in buildUserContent
- [x] **#10 — Test suite** — added 21 unit tests across ChatViewModel, ApfelAPIClient, ApfelServerManager, ApfelOptions, and MarkdownSegmenter; full `xcodebuild test` passes, with the LSUIElement UI smoke test explicitly skipped under `XCUIApplication` (2026-05-21)
- [x] **#2 — Chat opens at top, not bottom**
- [x] **#3 — Welcome/empty-state message**
- [x] **#4 — Attached files not read by LLM**
- [x] **#5 — Attached files don't clear**
