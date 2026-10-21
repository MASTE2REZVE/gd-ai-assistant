# GD AI Assistant

An AI coding assistant that lives inside the Godot 4 editor. Chat with an LLM and let it read, write, create, modify, and **debug** your project safely and autonomously.

**Android-first.** Built and tested on an Android tablet. Works on Windows, macOS, and Linux.

---

## 🌟 Why GD AI Assistant?

Most Godot AI plugins just generate code snippets. GD AI Assistant is an **Autonomous Agent**. 
- It doesn't just write code; it **runs the scene, reads the crash logs, and fixes its own bugs**.
- It doesn't just edit files; it **builds scene trees, wires signals, and manages resources**.
- Every edit is protected by a **7-layer safety chain** (backups, verification, and one-click undo).
- Includes a **Dual Theme Engine** (Light, Dark, Cyber) and **Performance Modes** (Full animations on PC, Lightweight on Android).

---

## 🚀 Installation

1. Download the latest release from the [Releases page](https://github.com/MASTE2REZVE/gd-ai-assistant/releases).
2. Extract `gd_ai_assistant/` into your Godot project's `addons/` folder.
3. Open Godot: **Project → Project Settings → Plugins**.
4. Enable **GD AI Assistant**. A bottom panel will appear.

**Requires Godot 4.4 or newer.** Tested on Godot 4.7.2 stable.

---

## 🔑 Getting an API Key

You need an API key from one of our 11 supported providers. We recommend **OpenRouter** (supports hundreds of models) or **Ollama** (free, local). 
Keys are stored locally in `user://gd_ai_assistant.cfg` and are **never** committed to your project.

| Provider | Free Tier? | Where to get a key |
|---|---|---|
| OpenRouter | Yes | [openrouter.ai/keys](https://openrouter.ai/keys) |
| Google Gemini | Yes | [aistudio.google.com](https://aistudio.google.com) |
| Groq | Yes | [console.groq.com](https://console.groq.com) |
| ModelScope | Yes | [modelscope.ai](https://www.modelscope.ai) |
| Ollama | Free (Local) | [ollama.com](https://ollama.com) |
| LM Studio | Free (Local) | [lmstudio.ai](https://lmstudio.ai) |

---

## 🧠 The 4 Agent Modes

- **ASK**: The AI answers questions but cannot touch your files.
- **PLAN**: The AI can read files and describe a plan, but cannot edit.
- **AGENT**: The AI edits files, but asks for your approval before each change. (Default)
- **AUTO**: The AI edits files automatically, runs the scene, and debugs its own code.

---

## 🩺 The Autonomous Debug Loop

With the new **Editor Tools**, the AI can debug itself. Just tell it:
> *"Create a player script, run the game, and fix any errors."*

The AI will:
1. Write the code.
2. Run the game via `run_scene`.
3. Read the crash log via `get_errors`.
4. Patch the bug.
5. Repeat until the game runs smoothly, then stop.

---

## 🛠️ The 31 Available Tools

**Project (6):** `get_project_info`, `list_files`, `search_files`, `read_file`, `write_file`, `patch_file`
**Scene (12):** `list_scenes`, `get_scene_tree`, `create_scene`, `open_scene`, `save_scene`, `get_node`, `add_node`, `remove_node`, `rename_node`, `move_node`, `set_node_property`, `get_node_property`
**Script (5):** `create_script`, `read_script`, `validate_script`, `get_script_symbols`, `attach_script`
**Editor (4):** `run_scene`, `stop_scene`, `get_errors`, `open_in_editor`
**Signal (4):** `connect_signal`, `disconnect_signal`, `add_to_group`, `remove_from_group`

---

## 🛡️ The 7-Layer Safety Chain

1. **Path Guard**: Blocks edits to `project.godot` and the `.godot/` folder.
2. **Read-Before-Edit**: The AI must read a file before it can change it.
3. **Backups**: Every write saves a backup to `user://backups/`.
4. **Verification**: Every file is parsed and linted after saving.
5. **Rollback**: If verification fails, the backup is automatically restored.
6. **Approval Gate**: In AGENT mode, you approve changes before they happen.
7. **Checkpoints**: Click the **⟲ Undo** button to revert an entire AI turn.

---

## ❤️ Support

GD AI Assistant is free and open source. If it saves you time, you can send crypto — see [DONATE.md](DONATE.md).

## 📄 License
MIT. See [LICENSE](LICENSE).
