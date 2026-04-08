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

The app will appear in your menubar as a ✦ (sparkles) icon.

> **Note:** macOS will ask for **Input Monitoring** permission the first time you use the global hotkey (⌘⇧Space). Grant it in System Settings → Privacy & Security → Input Monitoring. The app does not monitor any other input.

---

## usage

| Action | How |
|---|---|
| Open / close | Click menubar icon, or press **⌘⇧Space** from anywhere |
| Send prompt | Press **Enter** |
| Insert newline | Press **⌘+Enter** |
| Attach file | Click the paperclip button |
| Adjust options | Click the options disclosure group (temperature, max tokens, etc.) |
| Preferences | Press **⌘,** or click the gear icon |

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

---

## known limitations

- **SSE streaming not yet working** — apfel v0.9.0 closes the connection on `stream: true` requests. Non-streaming works fine (~1s response time). Will be re-enabled when fixed upstream.
- **No app icon yet** — using an SF Symbol placeholder until Affinity Designer assets are complete.
- **Global hotkey requires Input Monitoring permission** — standard macOS requirement for system-wide shortcuts.
- **macOS 26 only** — Apple Intelligence and Liquid Glass APIs require the macOS 26 SDK.

---

## roadmap

- [x] Menubar icon + popover
- [x] apfel server lifecycle management (start, health-check, crash-restart)
- [x] Prompt → response via OpenAI-compatible API
- [x] Options panel (temperature, max tokens, system prompt, etc.)
- [x] Enter to send, ⌘+Enter for newline
- [x] Global hotkey (⌘⇧Space)
- [ ] SSE streaming (blocked on apfel upstream fix)
- [ ] Configurable hotkey in Settings
- [ ] Persistent preferences (port, binary path, defaults)
- [ ] Liquid Glass styling (macOS 26)
- [ ] App icon + menubar icon assets
- [ ] Full test suite

---

## credits

- [apfel](https://github.com/Arthur-Ficial/apfel) by Arthur-Ficial — the CLI/server that makes Apple Intelligence scriptable
- Built with SwiftUI + Swift 6 on macOS 26 Tahoe

---

## license

MIT
