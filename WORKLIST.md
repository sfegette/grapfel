# Grapfel Worklist

Last updated: 2026-04-14  
Baseline: v0.1.0 released — all Phase 9 issues resolved

## Released

- [x] **v0.1.0 — Initial public release** (2026-04-13)  
  Unsigned/ad-hoc zip for macOS 26 Tahoe beta users. Published to GitHub Releases as `grapfel-0.1.0-macos26.zip`. Gatekeeper bypass required (`xattr -dr com.apple.quarantine`).

---

## Active — Open GitHub Issues

### Bugs

- [ ] **#1 — First launch only opens from hotkey** *(re-opened — confirmed in v0.1.0)*  
  Clicking the menubar icon (✦) before the window has ever appeared does nothing. Hotkey (⌘⇧Space) is required to open it the first time. Menubar icon click should always show the panel. Compounded by #8 (hotkey not configurable) — users have no workaround until both are fixed.

### Enhancements

- [ ] **#7 — Error UI — binary not found / server start failed**  
  No user-visible feedback when `apfel` binary is missing or the server fails to start. Need an in-panel error state.

- [ ] **#8 — Configurable hotkey UI**  
  Preferences UI to change the global hotkey away from ⌘⇧Space. Currently hardcoded in AppDelegate via Carbon `RegisterEventHotKey`.

- [ ] **#11 — Warn user when attached file(s) may exceed context window**  
  No feedback when file content is likely to overflow the 4096-token context window. Show a warning before sending.

- [ ] **#12 — Truncate oversized file attachments with a [truncated] note**  
  When file content exceeds the context budget, truncate it server-side and append a `[truncated]` marker so the model isn't silently fed a partial file.

### Design

- [ ] **#9 — App icon — final**  
  Interim generated icon in place. Spec at `Scripts/icon_spec.md`. Replace by dropping a 1024px master PNG and re-running `Scripts/generate_icon.swift`.

### Testing

- [ ] **#10 — Test suite**  
  No automated tests exist. Priority targets: ChatViewModel, ApfelAPIClient, ApfelServerManager, MarkdownContent parser.

---

## Closed — Post-Phase 9

- [x] **#2 — Chat opens at top, not bottom**
- [x] **#3 — Welcome/empty-state message**
- [x] **#4 — Attached files not read by LLM**
- [x] **#5 — Attached files don't clear**

---

## Blocked / Deferred

- **SSE streaming** — `stream: true` breaks in apfel v0.9.0 (connection closes immediately). Keep `streaming: false`. Revisit when apfel ships a fix.
