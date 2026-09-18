@tool
extends EditorPlugin

## GD AI Assistant — Editor Plugin Entry Point
##
## Loads the bottom-panel UI and wires it to the editor.
## Deliberately tolerant of missing UI during Phase 1 development:
## if ui/panel.tscn is absent, the plugin enables in "headless mode"
## instead of erroring. Once the panel exists, it mounts automatically.

const PANEL_SCENE_PATH: String = "res://addons/gd_ai_assistant/ui/panel.tscn"
const PANEL_TITLE: String = "GD AI Assistant"
const PLUGIN_VERSION: String = "0.1.0"


var _panel: Control = null


func _enter_tree() -> void:
	_load_panel()


func _exit_tree() -> void:
	_unload_panel()


func _load_panel() -> void:
	if not ResourceLoader.exists(PANEL_SCENE_PATH):
		push_warning(
			"GD AI Assistant: %s not found yet. Plugin is active in headless mode."
			% PANEL_SCENE_PATH
		)
		return

	var packed: PackedScene = load(PANEL_SCENE_PATH) as PackedScene
	if packed == null:
		push_error(
			"GD AI Assistant: failed to load panel scene at %s."
			% PANEL_SCENE_PATH
		)
		return

	var instance: Node = packed.instantiate()
	if instance == null or not (instance is Control):
		push_error(
			"GD AI Assistant: panel scene root must be a Control."
		)
		if instance != null:
			instance.free()
		return

	_panel = instance as Control

	if _panel.has_method("set_editor_interface"):
		_panel.call("set_editor_interface", get_editor_interface())

	add_control_to_bottom_panel(_panel, PANEL_TITLE)


func _unload_panel() -> void:
	if _panel == null:
		return

	remove_control_from_bottom_panel(_panel)
	_panel.queue_free()
	_panel = null


func get_plugin_version() -> String:
	return PLUGIN_VERSION
