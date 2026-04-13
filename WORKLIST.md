# Grapfel Worklist

Last updated: 2026-04-09  
Baseline: Phase 9 complete (Liquid Glass panel, multi-turn history, persistence, Markdown, copy)

---

## Active — GitHub Issues (post-Phase 9)

### Bugs

- [x] **#1 — First launch only opens from hotkey**  
  Clicking the menubar icon (✦) before the window has ever appeared does nothing. Hotkey (⌘⇧Space) is required to open it the first time. Menubar icon click should always show the panel.

- [x] **#2 — Chat opens at top, not bottom**  
  On panel open, `ConversationView` scrolls to the first message instead of the last. Should always scroll to the most recent message (bottom).

- [ ] **#4 — Attached files not read by LLM**  
  File attachment UI exists but neither image nor text files are sent to apfel. Need to read file contents and include in the API request. Clarify format support: PNG/JPG for images; TXT/RTF/MD for text. Match to whatever apfel v0.9.0 accepts.

- [ ] **#5 — Attached files don't clear**  
  File list persists across "New conversation" and there is no per-session way to remove files.  
  - Purge file list on new conversation  
  - Add per-file remove control (Option-click icon or ✕ badge on attachment chip)  
  - Make discoverability obvious in UI

### Enhancements

- [x] **#3 — Welcome/empty-state message**  
  Blank chat panel looks bare. Show a styled placeholder ("How can I help you today?" or similar) when conversation history is empty. Hide once first message is sent.

---

## Backlog — Pre-existing (not yet filed as issues)

- [ ] **Phase 7 proper — Configurable hotkey UI**  
  Preferences UI to change the global hotkey away from ⌘⇧Space. Currently hardcoded in AppDelegate via Carbon `RegisterEventHotKey`.

- [ ] **Error UI — binary not found / server start failed**  
  No user-visible feedback when `apfel` binary is missing or the server fails to start. Need an in-panel error state.

- [ ] **App icon — final**  
  Interim generated icon in place. Spec at `Scripts/icon_spec.md`. Replace by dropping a 1024px master PNG and re-running `Scripts/generate_icon.swift`.

---

## Blocked / Deferred

- **SSE streaming** — `stream: true` breaks in apfel v0.9.0 (connection closes immediately). Keep `streaming: false`. Revisit when apfel ships a fix.
