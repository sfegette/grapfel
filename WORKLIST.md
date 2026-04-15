# Grapfel Worklist

Last updated: 2026-04-15  
Baseline: v0.1.0 released — all Phase 9 issues resolved

## Released

- [x] **v0.1.0 — Initial public release** (2026-04-13)  
  Unsigned/ad-hoc zip for macOS 26 Tahoe beta users. Published to GitHub Releases as `grapfel-0.1.0-macos26.zip`. Gatekeeper bypass required (`xattr -dr com.apple.quarantine`).

---

## Active — Open GitHub Issues

### Bugs

- [x] **#1 — First launch only opens from hotkey** *(fixed)*  
  Root cause: resign-key notification fired immediately after `makeKeyAndOrderFront` due to focus handoff from the status bar click, causing `panelDidResignKey` → `hidePanel()` before the panel was visible. Fix: 300ms timestamp guard in `panelDidResignKey` ignores spurious dismiss events within the click activation window.

### Enhancements

- [ ] **#7 — Error UI — binary not found / server start failed**  
  No user-visible feedback when `apfel` binary is missing or the server fails to start. Need an in-panel error state.

- [ ] **#8 — Configurable hotkey UI**  
  Preferences UI to change the global hotkey away from ⌘⇧Space. Currently hardcoded in AppDelegate via Carbon `RegisterEventHotKey`.

- [x] **#11 — Warn user when attached file(s) may exceed context window** *(fixed)*  
  `attachedFilesExceedBudget` computed property on `ChatViewModel` uses `URLResourceValues` (file size, no content read) to cheaply estimate whether attached files exceed the 8 000-char budget. `PromptInputView` shows an orange warning label below the attachment chips when true.

- [x] **#12 — Truncate oversized file attachments with a [truncated] note** *(fixed)*  
  `buildUserContent` now enforces a shared 8 000-char budget across all attached files. Each file is read in order; once the budget is consumed the remainder is replaced with `[truncated]`.

### Design

- [ ] **#9 — App icon — final**  
  Interim generated icon in place. Spec at `Scripts/icon_spec.md`. Replace by dropping a 1024px master PNG and re-running `Scripts/generate_icon.swift`.

### Testing

- [ ] **#10 — Test suite**  
  No automated tests exist. Priority targets: ChatViewModel, ApfelAPIClient, ApfelServerManager, MarkdownContent parser.

---

## Closed — Post-v0.1.0

- [x] **#1 — First launch only opens from hotkey** — 300ms resign-key guard in AppDelegate
- [x] **#11 — Warn when attached file(s) exceed context budget** — orange label in PromptInputView
- [x] **#12 — Truncate oversized attachments with [truncated] marker** — budget enforced in buildUserContent
- [x] **#2 — Chat opens at top, not bottom**
- [x] **#3 — Welcome/empty-state message**
- [x] **#4 — Attached files not read by LLM**
- [x] **#5 — Attached files don't clear**

---

## Blocked / Deferred

- **SSE streaming** — `stream: true` breaks in apfel v0.9.0 (connection closes immediately). Keep `streaming: false`. Revisit when apfel ships a fix.
