# Changelog

All notable changes to GD AI Assistant are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.1.0] — 2026-09-15

First public release.

### Added
- Bottom-panel editor UI with touch-friendly layout (48px min targets, wrap-friendly rows).
- 11 AI providers: OpenRouter, ModelScope, OpenAI, Anthropic (native, coming soon), Google Gemini, Groq, DeepSeek, Mistral, xAI Grok, Ollama, LM Studio, Custom.
- 4 agent modes: ASK, PLAN, AGENT, AUTO.
- 6 project tools: `get_project_info`, `list_files`, `search_files`, `read_file`, `write_file`, `patch_file`.
- Seven-layer safety chain on every file write: path guard, read-before-edit, backup, verify, rollback, approval gate, (checkpoints coming soon).
- Model list fetch with filter (All / Free / Paid) and sort (A→Z / Cheapest / Expensive / Coding / Smartest).
- Per-provider API key storage in `user://gd_ai_assistant.cfg` (never in `res://`).
- Token budget trimming with tool-call-pair preservation.
- Desktop Features toggle for streaming, doc injection, and other high-CPU features.
- Special chat commands: `@clear`, `@errors`.
- Copy Latest / Copy All buttons.

### Known limitations
- Scene, script, signal, and resource tools arrive in v0.2.0.
- Anthropic provider is registry-listed but not yet implemented (native API differs from OpenAI's).
- No streaming responses in v0.1.0.
- No screenshot or image generation support yet.

### Notes
- Android is the primary target platform. Windows, macOS, and Linux are fully supported.
- Tested on Godot 4.7.2 stable.
