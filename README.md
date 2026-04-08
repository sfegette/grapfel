# grapfel

A native macOS menubar app that puts Apple Intelligence at your fingertips — no API keys, no cloud, no Ollama. Powered entirely by on-device inference via [apfel](https://github.com/Arthur-Ficial/apfel).

> **Requires macOS 26 Tahoe (beta) and Apple Silicon.** Apple Intelligence must be enabled on your device.

---

## what it does

grapfel sits in your menubar. Click the icon (or press **⌘⇧Space** from anywhere) to open a lightweight prompt window, type your request, hit **Enter** to send, and get a response from the on-device foundation model — instantly, privately, offline.

- **no API keys** — runs entirely on-device via Apple Intelligence
- **no cloud** — your prompts never leave your Mac
- **no Ollama** — uses Apple's own foundation model, not a third-party runtime
- **fast** — apfel's server mode keeps the model loaded; responses start in ~1 second
- **persistent conversations** — pick up exactly where you left off between sessions

---

## requirements

| Requirement | Details |
|---|---|
| macOS | 26 Tahoe (beta) or later |
| Hardware | Apple Silicon (M-series) |
| Apple Intelligence | Must be enabled in System Settings |
| [apfel](https://github.com/Arthur-Ficial/apfel) | v0.9.0+ — see install below |

---

## install apfel

grapfel requires `apfel` to be installed and available on your PATH.

```bash
brew tap Arthur-Ficial/tap
brew install apfel
```

Verify it works:

```bash
apfel "say hello"
```

---

## install grapfel

grapfel is currently distributed as source only — build it yourself in Xcode.

### build from source

1. Clone the repo:
   ```bash
   git clone https://github.com/sfegette/grapfel.git
   cd grapfel
   ```

2. Open the project in Xcode 26:
   ```bash
   open grapfel.xcodeproj
   ```

3. Select your Mac as the run destination and press **⌘R**.

The app will appear in your menubar as a ✦ icon.

> **Note:** The global hotkey (⌘⇧Space) uses Carbon `RegisterEventHotKey` and does not require Input Monitoring permission.

---

## usage

| Action | How |
|---|---|
| Open / close | Click menubar icon, or press **⌘⇧Space** from anywhere |
| Send prompt | Press **Enter** |
| Insert newline | Press **⌘+Enter** |
| New conversation | Click the ✏ icon in the header (appears once a conversation is active) |
| Copy response | Click **Copy** at the bottom of any assistant message |
| Copy as code block | Right-click **Copy** → "Copy as Code Block" |
| Copy as plain text | Right-click **Copy** → "Copy as Plain Text" |
| Attach file | Click the paperclip button |
| Adjust options | Click the options disclosure group (temperature, max tokens, etc.) |
| Preferences | Press **⌘,** or click the gear icon |

---

## conversations

grapfel maintains full multi-turn conversation history. Each message you send includes the complete prior context so the model can refer back to earlier turns.

Conversation state is automatically saved to `~/Library/Application Support/grapfel/conversation.json` — when you reopen the window (or relaunch the app), your conversation is restored exactly as you left it.

To start fresh, click the **✏** (compose) icon in the header. This clears the history and deletes the saved state.

---

## copying responses

Every assistant response has a **Copy** button at the bottom of its bubble. Tap to copy, or right-click for options:

| Option | What you get |
|---|---|
| Copy (tap) | Raw text — preserves Markdown syntax |
| Copy as Markdown | Same as above, explicitly labelled |
| Copy as Code Block | Response wrapped in ` ```markdown ``` ` — useful for embedding in docs |
| Copy as Plain Text | Markdown syntax stripped — clean text for pasting anywhere |

A brief **Copied ✓** confirmation appears for 2 seconds after copying.

---

## options

The options panel exposes the main apfel generation parameters:

| Option | Default | Notes |
|---|---|---|
| Temperature | 1.0 | Controls randomness (0.0–2.0) |
| Max tokens | 2048 | Maximum response length |
| Seed | — | Optional fixed seed for reproducibility |
| Streaming | off | SSE streaming — pending apfel v0.9.x fix |
| Permissive | off | Disables content safety filtering |
| System prompt | — | Sets the system role message |
| Context strategy | newest-first | How conversation history is managed |

---

## architecture

```
grapfel (menubar app)
  └── launches apfel --serve on port 11434
        └── wraps Apple's on-device foundation model
              └── exposes OpenAI-compatible HTTP API at 127.0.0.1:11434/v1
```

grapfel manages the `apfel --serve` process lifecycle: starts it on launch, health-checks it, restarts on crash, and terminates it cleanly on quit. All communication is over localhost — nothing touches the network.

```
AppDelegate
  ├── GrapfelPanel (NSPanel subclass — Liquid Glass, borderless, canBecomeKey)
  ├── ApfelServerManager (actor — subprocess lifecycle)
  └── Carbon hotkey (⌘⇧Space, no Input Monitoring permission required)

ChatViewModel (@Observable @MainActor)
  ├── history: [ChatMessage]   — full conversation context
  ├── send()                   — appends turns, calls API, saves to disk
  └── clearHistory()           — resets state and deletes saved file

ConversationView
  ├── MessageRow (user: right/.quaternary, assistant: left/purple tint)
  ├── MarkdownContent (fenced code blocks + AttributedString inline markdown)
  └── CopyButton (tap = raw markdown; context menu = code block / plain text)
```

---

## known limitations

- **SSE streaming not yet working** — apfel v0.9.0 closes the connection on `stream: true` requests. Non-streaming works fine (~1s response time). Will be re-enabled when fixed upstream.
- **Global hotkey is not yet configurable** — ⌘⇧Space is hardcoded; a settings UI is on the roadmap.
- **macOS 26 only** — Apple Intelligence and Liquid Glass APIs require the macOS 26 SDK.

---

## roadmap

- [x] Menubar icon + panel (Liquid Glass, GrapfelPanel)
- [x] apfel server lifecycle management (start, health-check, crash-restart)
- [x] Prompt → response via OpenAI-compatible API
- [x] Options panel (temperature, max tokens, system prompt, etc.)
- [x] Enter to send, ⌘+Enter for newline
- [x] Global hotkey (⌘⇧Space, no Input Monitoring permission)
- [x] Multi-turn conversation history with full context
- [x] Conversation persistence (auto-save/restore across sessions)
- [x] Markdown rendering (code blocks, bold, italic, inline code)
- [x] Copy response (raw, code block, plain text)
- [x] App icon (interim generated; final hand-crafted artwork pending)
- [x] Build output to `build/Debug/grapfel.app`
- [ ] Configurable hotkey in Settings
- [ ] Error UI for binary-not-found / server-start-failed
- [ ] SSE streaming (blocked on apfel upstream fix)
- [ ] Full test suite
- [ ] Final icon artwork

---

## credits

- [apfel](https://github.com/Arthur-Ficial/apfel) by Arthur-Ficial — the CLI/server that makes Apple Intelligence scriptable
- Built with SwiftUI + Swift 6 on macOS 26 Tahoe

---

## license

MIT
