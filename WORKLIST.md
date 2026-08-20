# Grapfel Worklist

Last updated: 2026-08-19
Baseline: v1.0.0 released on `main` (2026-06-03). The Foundation Models migration and the local persistence, coverage, and preset slices remain unreleased and require independent review; this is not a release-readiness or timing claim.

## Released

- [x] **v0.1.3 — Distribution & Advanced Options** (2026-05-02)  
  Sparkle auto-updates (#B), Developer ID signing/notarization, Permissive mode toggle (#A), apfel version check (#C), Token usage display (#D), and JSON mode support (#F).

- [x] **v0.1.2 — First-launch & attachment fixes** (2026-04-15)  
  Fixed panel invisible on icon click from /Applications (#1). File attachment size warnings and truncation (#11, #12).

- [x] **v0.1.0 — Initial public release** (2026-04-13)  
  Unsigned/ad-hoc zip for macOS 26 Tahoe beta users. Published to GitHub Releases as `grapfel-0.1.0-macos26.zip`. Gatekeeper bypass required (`xattr -dr com.apple.quarantine`).

---

## Active — Native Foundation Models migration

- [ ] **Replace the apfel server dependency with Apple's Foundation Models framework**
  The local `codex/foundation-models` slice calls `SystemLanguageModel` and `LanguageModelSession` directly, supports native streaming, maps availability and generation errors, and removes Homebrew/server lifecycle code. The generated project builds, 51 routine tests pass locally, and an opt-in live native-streaming smoke test passes on eligible hardware; independent review and manual app UI UAT remain.

- [ ] **Keep model requests within the native context window**
  The local slice retains the newest complete user/assistant turns, reserves a safety margin and minimum response budget, and automatically downshifts the response ceiling when input grows. Token totals use Apple's tokenizer on macOS 26.4 or later. Manual long-conversation and attachment UAT remains.

- [ ] **Audit public privacy and setup copy after the runtime change**
  The local slice removes localhost, Homebrew, installer, and apfel-update claims; documents direct on-device processing; and preserves the existing bundle ID, Application Support paths, signing configuration, and Sparkle feed for continuity. Review remains.

## Active — Trust and data fidelity

### Bugs

- [ ] **#67 — Align permissive-mode default, migration, and public disclosure**
  Owner confirmed safety filtering as the default for new installs while preserving explicit saved preferences. The local implementation and regression coverage await independent review.

- [ ] **#65 — Report and recover from an atomic conversation-save failure**
  The local slice cleans up a failed replacement temporary file, preserves the previously saved record, and shows a dismissal warning that the latest change may not survive quitting. Independent review remains.

- [ ] **#66 — Persistent system-prompt presets with privacy controls**
  The local slice adds role/rules/general preset management, owner-only local persistence, tests, and storage/deletion disclosure. Review requested; Settings/options-panel smoke test remains.

### Reliability and maintenance

- [ ] **#50 — Fill the remaining test-coverage gaps**
  The remaining relevant persistence, prompt-preset, model-request, generation-setting, and view-model gaps have local coverage. Obsolete server-lifecycle coverage was removed with the server runtime. Independent review remains.

## Backlog

- [ ] **Provider boundary for future model routing**
  Keep `LanguageModelClientProtocol` narrow enough to add opt-in providers later without weakening the Apple-local default or coupling chat UI to transport details.

- [ ] **Tool and MCP execution foundation**
  Define explicit capabilities, consent, scopes, durable audit records, cancellation, and recovery before exposing file, repository, service, or scheduled actions. Do not treat raw model tool requests as authority.

- [ ] **#22 — Model/tool-policy limitation research**
  Re-evaluate tool-use behavior against the direct Foundation Models APIs before planning MCP execution. The former apfel/OpenAI-compatible path is no longer the relevant integration boundary.

- [ ] **Retire obsolete apfel setup/update issues after migration review**
  Close or supersede #44, #45, and the brew-services verification item once the direct Foundation Models migration is approved and released.

---

## Closed — All Versions

- [x] **#35 — Correct PrivacyInfo.xcprivacy UserDefaults reason code** — `CA92.1` correction committed as `f95c415` after independent review; closed with manifest lint and test evidence (2026-08-18)
- [x] **#30 — Preserve block content in Markdown conversation exports** — structured-export regression coverage committed as `1fc60b9` after independent review; closed with test evidence (2026-08-18)
- [x] **#51 — Document the accepted crash/restart/stop timing risk** — timing caveat and no-data-loss rationale documented at the termination semaphore; closed with verification (2026-08-18)
- [x] **#49 — Return focus after a successful hotkey capture** — recorder resigns first responder after capture, matching its Escape behavior; closed as already implemented (2026-08-18)
- [x] **#48 — Remove the dead hotkey rollback branch** — dead rollback removed and the successful-registration invariant documented; closed as already implemented (2026-08-18)
- [x] **#47 — Eliminate the conversation-file permission window** — Claude-reviewed temporary-file permission and atomic-replacement behavior; closed with evidence (2026-08-18)
- [x] **#46 — Prevent conversation-save memory/disk desynchronization** — Claude-reviewed best-effort permission handling and persistence consistency; closed with evidence (2026-08-18)
- [x] **#62 — Public-repository runner/workflow follow-up** — verified zero registered Actions runners, protection against force-pushes and branch deletion on `main`, and no current Actions workflows; closed with evidence (2026-08-18)
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
