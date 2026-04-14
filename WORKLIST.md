# Grapfel Worklist

Last updated: 2026-04-13  
Baseline: Phase 9 complete + simplify pass (UserDefaults key enum, historyFileURL stored let, trimmedPrompt, regex caching, observer guard)

## Released

- [x] **v0.1.0 — Initial public release** (2026-04-13)  
  Unsigned/ad-hoc zip for macOS 26 Tahoe beta users. Published to GitHub Releases as `grapfel-0.1.0-macos26.zip`. Gatekeeper bypass required (`xattr -dr com.apple.quarantine`).

---

## Active — GitHub Issues (post-Phase 9)

### Bugs

- [x] **#1 — First launch only opens from hotkey**  
  Clicking the menubar icon (✦) before the window has ever appeared does nothing. Hotkey (⌘⇧Space) is required to open it the first time. Menubar icon click should always show the panel.

- [x] **#2 — Chat opens at top, not bottom**  
  On panel open, `ConversationView` scrolls to the first message instead of the last. Should always scroll to the most recent message (bottom).

- [x] **#4 — Attached files not read by LLM**  
  Text files injected into API payload as `<file name="...">` blocks (UTF-8, RTF, latin-1 fallback). Images not supported by apple-foundationmodel — picker restricted to text/source/JSON/XML/RTF only. File content injected only for current turn (not persisted in history). Entitlements fixed (`network.client` + `files.user-selected.read-only`).

- [x] **#5 — Attached files don't clear**  
  Files cleared on `clearHistory()` and on send. Picker now appends (not replaces) selections. Per-file ✕ chip in PromptInputView via `removeAttachedFile(_:)`.

### Enhancements

- [x] **#3 — Welcome/empty-state message**  
  Blank chat panel looks bare. Show a styled placeholder ("How can I help you today?" or similar) when conversation history is empty. Hide once first message is sent.

---

## Backlog — Pre-existing (not yet filed as issues)

- [ ] **#7 — Error UI — binary not found / server start failed**  
  No user-visible feedback when `apfel` binary is missing or the server fails to start. Need an in-panel error state.

- [ ] **#8 — Configurable hotkey UI**  
  Preferences UI to change the global hotkey away from ⌘⇧Space. Currently hardcoded in AppDelegate via Carbon `RegisterEventHotKey`.

- [ ] **#9 — App icon — final**  
  Interim generated icon in place. Spec at `Scripts/icon_spec.md`. Replace by dropping a 1024px master PNG and re-running `Scripts/generate_icon.swift`.

- [ ] **#10 — Test suite**  
  No automated tests exist. Priority targets: ChatViewModel, ApfelAPIClient, ApfelServerManager, MarkdownContent parser.

---

## Blocked / Deferred

- **SSE streaming** — `stream: true` breaks in apfel v0.9.0 (connection closes immediately). Keep `streaming: false`. Revisit when apfel ships a fix.
