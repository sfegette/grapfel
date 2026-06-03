# grapfel

A native macOS menubar app that puts Apple Intelligence at your fingertips — no API keys, no cloud, no Ollama. Powered entirely by on-device inference via [apfel](https://github.com/Arthur-Ficial/apfel).

> **Requires macOS 26 Tahoe and Apple Silicon.** Apple Intelligence must be enabled in System Settings.

---

## what it does

grapfel sits in your menubar. Click the icon (or press **⌘⇧Space** from anywhere) to open a lightweight chat window, type your request, hit **Enter** to send, and get a response from the on-device foundation model — instantly, privately, offline.

- **no API keys** — runs entirely on-device via Apple Intelligence
- **no cloud** — your prompts never leave your Mac
- **no Ollama** — uses Apple's own foundation model, not a third-party runtime
- **fast** — apfel keeps the model loaded; responses stream token-by-token in ~1 second
- **persistent conversations** — full multi-conversation sidebar; pick up exactly where you left off
- **auto-installs apfel** — grapfel detects missing dependencies and installs them for you on first launch
- **configurable hotkey** — record any key combo in Settings; grapfel registers it globally via Carbon

---

## requirements

| Requirement | Details |
|---|---|
| macOS | 26 Tahoe or later |
| Hardware | Apple Silicon (M-series) |
| Apple Intelligence | Must be enabled in System Settings → Apple Intelligence & Siri |
| Homebrew | Required for apfel install (grapfel installs apfel automatically if Homebrew is present) |

---

## download

Download the latest release from the [Releases page](https://github.com/sfegette/grapfel/releases).

1. Download **grapfel-1.0.0-macos26.zip** from the Assets section.
2. Unzip and move `grapfel.app` to `/Applications`.
3. Launch. The **✦** icon appears in your menubar.

grapfel is signed with a Developer ID certificate and notarized by Apple — no Gatekeeper prompt, no quarantine step required. Future updates are delivered automatically via Sparkle.

---

## first launch

On first launch, grapfel checks whether `apfel` is installed:

- **If apfel is present:** grapfel starts it immediately and you're ready to chat.
- **If apfel is missing and Homebrew is installed:** grapfel installs apfel automatically — progress streams in real time right in the app window.
- **If Homebrew is not installed:** grapfel shows a setup screen with a link to brew.sh and a Retry button.

Once apfel is installed, grapfel manages its lifecycle: starts it on launch, health-checks it on startup, restarts it on crash, and terminates it cleanly on quit.

---

## usage

| Action | How |
|---|---|
| Open / close | Click the ✦ menubar icon, or press **⌘⇧Space** from anywhere |
| Send prompt | Press **Enter** |
| Insert newline | Press **⌘+Enter** |
| New conversation | Click the ✏ icon in the header |
| Browse conversations | Click the ☰ icon to open the sidebar |
| Rename conversation | Double-click a conversation name in the sidebar |
| Delete conversation | Hover the conversation in the sidebar → click the trash icon |
| Copy response | Click **Copy** at the bottom of any assistant message |
| Copy as code block | Right-click **Copy** → "Copy as Code Block" |
| Copy as plain text | Right-click **Copy** → "Copy as Plain Text" |
| Export conversation | Sidebar → ··· menu → "Export as Markdown" |
| Export all conversations | Sidebar → ··· menu → "Export all as JSON" |
| Attach file | Click the paperclip button in the input area |
| Adjust generation options | Click the options disclosure group (temperature, max tokens, etc.) |
| Settings | Press **⌘,** or click the gear icon |
| Change global hotkey | Settings → General → Global Shortcut → click to record |
| Update apfel | Banner appears automatically when an update is available → click Upgrade |
| Check for app updates | Right-click the ✦ menubar icon → "Check for Updates…" |

---

## conversations

grapfel has a full multi-conversation sidebar. Each conversation is stored as a secure JSON file in `~/Library/Application Support/grapfel/conversations/` (permissions: 0600 per file, 0700 on the directory).

Conversations are auto-titled from the first message you send (trimmed to 40 characters at a word boundary). Switch between them instantly — the model gets the full context of whichever conversation is active.

**Retention modes** (Settings → Storage):

| Mode | Behavior |
|---|---|
| Session only | Nothing written to disk — conversations purge on quit |
| Last 50 turns | Keeps the most recent 50 user+assistant pairs per conversation |
| Unlimited | Retains all messages up to a 200-message cap |

---

## options

| Option | Default | Notes |
|---|---|---|
| Temperature | 1.0 | Controls randomness (0.0–2.0) |
| Max tokens | 2048 | Maximum response length |
| Streaming | on | Token-by-token output as the model generates |
| JSON mode | off | Requests structured JSON output |
| System prompt | — | Sets the system role message sent before every turn |

Token usage (prompt / completion / total) is shown beneath each assistant response.

**Permissive mode** (disables content safety filtering) is a server-level flag — enable it in **Settings → General**. The server restarts automatically when toggled.

---

## architecture

```
grapfel (menubar app, LSUIElement)
  └── spawns apfel --serve on port 11434
        └── wraps Apple's on-device foundation model
              └── exposes OpenAI-compatible HTTP at 127.0.0.1:11434/v1
```

```
AppDelegate (@MainActor)
  ├── GrapfelPanel (NSPanel subclass, canBecomeKey=true, 621 pt wide)
  │   └── NSHostingView → ContentView (direct contentView, not nested)
  ├── Carbon RegisterEventHotKey — configurable, no Input Monitoring permission
  ├── Outside-click monitor (NSEvent global) with activation-timing guards
  └── Sparkle SPU updater

ApfelServerManager (actor)       — subprocess lifecycle, health-check, crash-restart
HomebrewInstaller                — brew detect, install apfel, upgrade apfel (streaming output)
ServerState (@Observable @MainActor) — .starting/.running/.binaryNotFound/.homebrewNotFound/.startFailed

ConversationStore (@Observable @MainActor)
  ├── UUID-named JSON files, 0o600 permissions, 0o700 directory
  ├── RetentionMode: .sessionOnly / .lastNTurns(50) / .unlimited(cap 200)
  ├── Auto-title (ConversationTitleFormatter, 40-char word-boundary)
  └── Legacy migration: single conversation.json → UUID-named files

ChatViewModel (@Observable @MainActor)
  ├── displayedConversationID snapshot — prevents cross-conversation writes during streams
  └── Streaming (SSE) enabled by default

Views (SwiftUI)
  └── ContentView → SidebarView, HeaderBar, ConversationView, PromptInputView, OptionsPanel
```

All communication is over localhost — nothing touches the internet except Sparkle update checks (to GitHub Releases).

---

## updates

**grapfel** updates itself automatically via [Sparkle](https://sparkle-project.org). Right-click the ✦ menubar icon → **Check for Updates…** to check manually.

**apfel** — when a newer version is available in Homebrew, grapfel shows an update banner. Click **Upgrade** to install the update in-app (no terminal required).

---

## known limitations

- **macOS 26 only** — Apple Intelligence and the Liquid Glass material require the macOS 26 SDK.
- **Apple Silicon only** — Apple Intelligence is not available on Intel Macs.

---

## roadmap

- [x] Menubar icon + panel (Liquid Glass, GrapfelPanel)
- [x] apfel server lifecycle management (start, health-check, crash-restart)
- [x] Prompt → response via OpenAI-compatible API
- [x] Options panel (temperature, max tokens, system prompt, streaming, JSON mode)
- [x] Enter to send, ⌘+Enter for newline
- [x] Global hotkey — configurable in Settings, Carbon registration, no Input Monitoring permission
- [x] Multi-turn conversation history with full context
- [x] Persistent multi-conversation sidebar (UUID-named JSON, 0600/0700 permissions)
- [x] Conversation auto-title (first message, 40-char word-boundary)
- [x] Conversation export (Markdown per conversation, JSON archive for all)
- [x] Retention modes: session-only, last-50-turns, unlimited
- [x] Markdown rendering (fenced code blocks, bold, italic, inline code)
- [x] Copy response (raw, code block, plain text)
- [x] SSE streaming (token-by-token output)
- [x] Sparkle auto-update for grapfel
- [x] Developer ID signed + notarized
- [x] Token usage display
- [x] JSON mode and permissive mode
- [x] Auto-install apfel on first launch (in-app, streaming progress)
- [x] In-app apfel update (brew upgrade, no terminal required)
- [x] Privacy manifest (PrivacyInfo.xcprivacy) + in-product privacy disclosure
- [x] Full test suite (52 tests, Swift 6 strict concurrency)
- [x] App icon + menubar template glyph

---

## credits

- [apfel](https://github.com/Arthur-Ficial/apfel) by Arthur-Ficial — the CLI/server that makes Apple Intelligence scriptable
- Built with SwiftUI + Swift 6 on macOS 26 Tahoe

---

## license

MIT
