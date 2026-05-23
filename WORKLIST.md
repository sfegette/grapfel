# Grapfel Worklist

Last updated: 2026-05-22  
Baseline: v0.1.5 released on `main`; `prep/release-readiness` is the current integration branch

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

- [ ] **#22 — Known limitation: Apple Foundation Model refuses MCP tool-use for third-party service domains**  
  Model-side limitation; no grapfel-side fix currently available.

- [ ] **#30 — Preserve block content in Markdown conversation exports**  
  Exporter still prefixes message bodies with inline speaker labels, which can break fenced code blocks and lists.

- [ ] **#35 — Correct PrivacyInfo.xcprivacy UserDefaults reason code**  
  Privacy manifest and in-app disclosure exist, but the UserDefaults required-reason code still needs verification/correction.

### Enhancements

_(none currently open)_

### Design

_(none currently open)_

---

## Backlog

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
- [x] **#8 — Configurable global hotkey** — Settings privacy/preferences UI now records and persists hotkeys, re-registers Carbon bindings, and surfaces failure rollback messaging (2026-05-22)
- [x] **#9 — Final app icon artwork** — replaced interim generated purple star with shipped app icon master assets, regenerated appiconset, and added menubar template glyph (2026-05-22)
- [x] **#19 — Add an app privacy manifest and explicit in-product privacy disclosure** — added `PrivacyInfo.xcprivacy` and in-app privacy disclosures in Settings; manifest reason-code follow-up tracked separately in `#35` (2026-05-22)
- [x] **#26 — Conversation auto-title** — first user message titles new conversations via `ConversationTitleFormatter` (2026-05-22)
- [x] **#27 — Conversation export: copy as Markdown or save to file** — sidebar/header export actions added for Markdown and full-archive export (2026-05-22)
- [x] **#28 — Setup flow: detect Homebrew, guide staged install** — added `SetupChecker`, Homebrew-aware setup states, and install guidance (2026-05-22)
- [x] **#29 — Confirm before purging stored conversations in session-only mode** — retention-mode switch now shows a destructive confirmation dialog (2026-05-22)
- [x] **#31 — Keep conversation store memory and disk state consistent on save failure** — persistence writes now preserve in-memory state when disk writes fail (2026-05-22)
- [x] **#32 — Wait for apfel shutdown on app termination** — app termination now gives `ApfelServerManager.stop()` a bounded chance to complete (2026-05-22)
- [x] **#33 — Avoid force unwraps when resolving the conversation storage directory** — storage path resolution now falls back safely instead of assuming Application Support exists (2026-05-22)
- [x] **#34 — Harden global hotkey failure handling and user visibility** — startup fallback, rollback, and visible status messaging added around hotkey registration (2026-05-22)
- [x] **#2 — Chat opens at top, not bottom**
- [x] **#3 — Welcome/empty-state message**
- [x] **#4 — Attached files not read by LLM**
- [x] **#5 — Attached files don't clear**
