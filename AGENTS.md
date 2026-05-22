# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this repository.

## Build & Test

**Build**: Open `grapfel.xcodeproj` in Xcode 26, select Mac destination, press ⌘R. There is no Makefile — all builds go through Xcode/XcodeGen.

**Regenerate Xcode project** (after editing `project.yml`):
```bash
xcodegen generate
```

**Run all tests**:
```bash
xcodebuild test -project grapfel.xcodeproj -scheme grapfel -destination 'platform=macOS'
```

**Run a single test class**:
```bash
xcodebuild test -project grapfel.xcodeproj -scheme grapfel -destination 'platform=macOS' -only-testing:grapfelTests/ChatViewModelTests
```

## Architecture

grapfel is a macOS menubar app (LSUIElement, no Dock presence) that wraps `apfel --serve` — a local server that exposes an OpenAI-compatible API over `localhost:11434/v1` backed by Apple's on-device foundation model.

```
AppDelegate (AppKit)
  ├── Manages menubar status item (✦) and NSPopover
  ├── Manages global hotkey monitor (⌘⇧Space)
  └── Owns ApfelServerManager lifecycle

ApfelServerManager (actor)        — subprocess start/stop/health-check/crash-restart
ApfelAPIClient                    — HTTP POST to localhost:11434/v1/chat/completions
ChatViewModel (@Observable @MainActor)  — all UI state + send() logic
Views (SwiftUI)                   — ContentView → PromptInputView, ResponseView, OptionsPanel
```

**Critical concurrency rules:**
- All `@Observable` view model classes must be annotated `@MainActor`. Swift 6 strict concurrency requires this — omitting it causes build errors.
- `ApfelServerManager` is an `actor` for safe subprocess management across async contexts.
- Use `async/await` throughout; no completion handlers.

## Key Design Decisions

- **No streaming yet** — `stream: true` in `ApfelAPIClient` is disabled pending an upstream `apfel` fix. Non-streaming requests complete in ~1s.
- **AppStorage keys** for user preferences: `serverPort` (default 11434), `defaultTemperature` (1.0), `defaultMaxTokens` (2048), `apfelBinaryPath` (auto-detect if blank).
- **Enter sends, ⌘+Enter inserts newline** — handled in `PromptInputView`.
- **Entitlements**: `network.client` (localhost HTTP) + `files.user-selected.read-only` (file attachments). Hardened Runtime is enabled.

## Requirements

- macOS 26 Tahoe (beta) — Apple Intelligence APIs require this SDK
- Xcode 26 (Swift 6.0)
- `apfel` v0.9.0+ installed via `brew tap Arthur-Ficial/tap && brew install apfel`
- Apple Silicon with Apple Intelligence enabled in System Settings
