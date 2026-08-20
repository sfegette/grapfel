# grapfel

A native macOS menubar chat for Apple's on-device Foundation Models framework. No API key, model server, Homebrew dependency, or third-party inference runtime required.

> **Requires macOS 26 Tahoe, Apple silicon, and Apple Intelligence enabled in System Settings.**

## what it does

grapfel sits in the menubar. Click its icon or press **⌘⇧Space** from anywhere, type a request, and chat directly with the model built into macOS.

- **Apple-local by default** — prompts and selected file text are processed through Apple's Foundation Models framework on the Mac
- **direct native integration** — no `apfel`, localhost HTTP service, or OpenAI-compatible translation layer
- **streaming responses** — text appears as the model generates it
- **adaptive context** — recent complete turns are retained while old turns and response limits are reduced when needed to fit the model context
- **persistent conversations** — optional local history with owner-only file permissions
- **system-prompt presets** — reusable local roles and rules
- **configurable hotkey** — record a global shortcut in Settings

## requirements

| Requirement | Details |
|---|---|
| macOS | 26 Tahoe or later |
| Hardware | An Apple silicon Mac eligible for Apple Intelligence |
| Apple Intelligence | Enabled and ready in System Settings → Apple Intelligence & Siri |

## download

Download the latest published build from the [Releases page](https://github.com/sfegette/grapfel/releases).

1. Download the macOS zip from the release Assets section.
2. Unzip and move `grapfel.app` to `/Applications`.
3. Launch it. The grapfel icon appears in the menubar.

Published builds are signed with a Developer ID certificate, notarized by Apple, and updated through Sparkle.

## usage

| Action | How |
|---|---|
| Open / close | Click the menubar icon, or press **⌘⇧Space** |
| Send prompt | Press **Enter** |
| Insert newline | Press **⌘+Enter** |
| New conversation | Click the compose icon in the header |
| Browse conversations | Click the sidebar icon |
| Rename conversation | Double-click its name in the sidebar |
| Delete conversation | Hover over it and click the trash icon |
| Copy response | Click **Copy** below an assistant message |
| Export conversation | Sidebar menu → **Export as Markdown** |
| Export all conversations | Sidebar menu → **Export all as JSON** |
| Attach file | Click the paperclip in the input area |
| Adjust generation | Open the options disclosure group |
| Settings | Press **⌘,** or click the gear icon |
| Check for updates | Right-click the menubar icon → **Check for Updates…** |

## conversations and local storage

Conversation retention is controlled in **Settings → Privacy**:

| Mode | Behavior |
|---|---|
| Session only | Nothing is written to disk; conversations are discarded on quit |
| Last 50 turns | Keeps the most recent 50 user/assistant pairs per conversation |
| Unlimited | Retains messages up to the 200-message application cap |

When storage is enabled, conversations are JSON files in `~/Library/Application Support/grapfel/conversations/` with owner-only permissions (`0600` files and a `0700` directory).

Saved system-prompt presets are stored separately at `~/Library/Application Support/grapfel/system-prompts.json`, also with owner-only permissions. Changing conversation retention does not remove presets; delete them from the role or rules menu in the options panel.

## generation options

| Option | Default | Notes |
|---|---|---|
| Temperature | 1.0 | Controls variation from 0.0–2.0 |
| Top P | 1.0 | Narrows probabilistic sampling when reduced |
| Max tokens | 2048 | Requested response ceiling; automatically reduced if context is tight |
| Streaming | On | Displays text as the model generates it |
| JSON mode | Off | Instructs the model to return one unfenced JSON value |
| System prompt | Empty | Adds reusable instructions before the conversation |

The on-device model has a finite context window. grapfel reserves a response floor, retains the newest complete turns that fit, and lowers the maximum response budget when the prompt needs more room. On macOS 26.4 or later, the token total shown below a response is measured with Apple's model tokenizer.

**Permissive transformations** is off by default. Enabling it opts into Apple's narrower permissive-transformation guardrail mode; Apple's core safety protections remain active.

## privacy and network activity

Model prompts, responses, and selected file contents are passed directly to Apple's on-device Foundation Models framework. grapfel does not send them to an app-owned server or a third-party model provider.

Sparkle uses the network to check the configured GitHub-hosted update feed and download updates. Attached files are opened read-only for the current request and are not copied into grapfel's storage.

## architecture

```text
AppDelegate (@MainActor)
  ├── menubar status item and GrapfelPanel
  ├── Carbon global hotkey
  └── Sparkle updater

ChatViewModel (@Observable @MainActor)
  ├── conversation and streaming state
  └── FoundationModelClient
        ├── SystemLanguageModel availability and guardrail selection
        ├── LanguageModelSession native completion/streaming
        └── adaptive transcript and response-token budgeting

ConversationStore (@Observable @MainActor)
  ├── UUID-named local JSON files
  ├── retention policies and atomic persistence
  └── local system-prompt presets
```

## known limitations

- Apple Intelligence availability, supported languages, guardrails, rate limits, and context size are controlled by the system framework.
- Model generation is local-only today; Private Cloud Compute and third-party model providers are not integrated.
- Tool calling, MCP, scheduled work, and autonomous agents are not part of the current chat foundation.

## development

Open `grapfel.xcodeproj` in Xcode 26, or regenerate it after changing `project.yml`:

```bash
xcodegen generate
xcodebuild test -project grapfel.xcodeproj -scheme grapfel -destination 'platform=macOS'
```

The app uses Swift 6 strict concurrency and targets macOS 26.

## license

[MIT](LICENSE)
