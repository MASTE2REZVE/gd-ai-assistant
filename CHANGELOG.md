# Changelog

All notable changes to GD AI Assistant are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.2.0] — 2026-09-20

Scene and script tools, plus a full checkpoint / undo system.

### Added
- **12 scene tools** — `list_scenes`, `get_scene_tree`, `create_scene`, `open_scene`, `save_scene`, `get_node`, `add_node`, `remove_node`, `rename_node`, `move_node`, `set_node_property`, `get_node_property`. The AI can now build `.tscn` scenes from a chat prompt.
- **5 script tools** — `create_script`, `read_script`, `validate_script`, `get_script_symbols`, `attach_script`. Create GDScript files, inspect their symbols, and attach them to nodes.
- **Checkpoints / undo** — every turn creates a checkpoint. Click ⟲ Undo (or type `@undo`) to revert every file the AI touched during that turn. Checkpoints persist across editor restarts.
- **Fast mode** — a ⚡ Fast toggle that tells the model to skip exploration and write directly. Roughly 40% faster on simple tasks.
- **Uncapped mode** — an ∞ Uncapped toggle that raises the agent step limit from 20 (mobile) / 40 (desktop) to 200.
- **Live status display** — the status bar now shows what the agent is doing in real time: "Thinking (step 3/20)...", "Running tool: add_node...", "Waiting for your approval...".
- **Instant FileSystem refresh** — new and modified files appear in Godot's FileSystem dock within 1–2 seconds, no project reload required.
- **Abstract-class detection** — attempting to create `Light3D`, `Shape3D`, or another abstract class now returns a helpful error listing concrete subclasses.

### Changed
- Chained edits work in a single turn: writing a file marks it as inspected, so a follow-up mutation on the same file does not require a fresh `read_file`.
- `get_script_symbols` no longer lists `_`-prefixed (private) properties, methods, or constants.

### Fixed
- Removed an OpenRouter API key that could leak into `panel.tscn` if the settings bar was open. The key field now shows a `••••••••••••••••` placeholder instead of the real key. This prevents accidental exposure via Git commits.

### Known limitations
- Streaming responses are not enabled — the plugin uses non-streaming requests. The code is present but disabled pending compatibility testing.
- Anthropic is registry-listed but not implemented (native API differs from OpenAI's).
- Mutating scene tools refuse to run if the scene is currently open in the editor. Close the scene first.

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
- Scene, script, signal, and resource tools arrive in v0.2.0 and later.
- Anthropic provider is registry-listed but not yet implemented (native API differs from OpenAI's).
- No streaming responses in v0.1.0.
- No screenshot or image generation support yet.

### Notes
- Android is the primary target platform. Windows, macOS, and Linux are fully supported.
- Tested on Godot 4.7.2 stable.