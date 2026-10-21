@tool
class_name GDAToolEditor
extends RefCounted

## GD AI Assistant — Editor Tools


class RunScene extends GDAToolBase:
	func get_name() -> String:
		return "run_scene"

	func get_description() -> String:
		return "Run the currently open scene, or the main scene if no path is provided."

	func get_parameters_schema() -> Dictionary:
		return {
			"type": "object",
			"properties": {
				"path": {
					"type": "string",
					"description": "Optional res:// path to scene.",
				},
			},
			"required": [],
		}

	func needs_editor() -> bool:
		return true

	func execute(args: Dictionary, context: Dictionary) -> Dictionary:
		var editor_interface: Variant = context.get("editor_interface", null)
		if editor_interface == null:
			return fail("EditorInterface unavailable.")
		var path: String = str(args.get("path", "")).strip_edges()
		if path.is_empty():
			editor_interface.play_main_scene()
			return ok("Playing main scene.", {"path": ""})
		editor_interface.play_custom_scene(path)
		return ok("Playing scene: " + path, {"path": path})


class StopScene extends GDAToolBase:
	func get_name() -> String:
		return "stop_scene"

	func get_description() -> String:
		return "Stop the currently running scene in the editor."

	func get_parameters_schema() -> Dictionary:
		return {"type": "object", "properties": {}, "required": []}

	func needs_editor() -> bool:
		return true

	func execute(_args: Dictionary, context: Dictionary) -> Dictionary:
		var editor_interface: Variant = context.get("editor_interface", null)
		if editor_interface == null:
			return fail("EditorInterface unavailable.")
		editor_interface.stop_playing_scene()
		return ok("Stopped playing scene.", {})


class GetErrors extends GDAToolBase:
	func get_name() -> String:
		return "get_errors"

	func get_description() -> String:
		return (
			"Read the Godot engine log and return the most recent errors. "
			+ "Use this after running a scene to check for runtime errors."
		)

	func get_parameters_schema() -> Dictionary:
		return {
			"type": "object",
			"properties": {
				"max_lines": {
					"type": "integer",
					"description": "Max errors to return. Default 25.",
				},
			},
			"required": [],
		}

	func execute(args: Dictionary, _context: Dictionary) -> Dictionary:
		var log_path: String = OS.get_user_data_dir().path_join("logs/godot.log")
		if not FileAccess.file_exists(log_path):
			return ok("", {"errors": ""})
		var f: FileAccess = FileAccess.open(log_path, FileAccess.READ)
		if f == null:
			return ok("", {"errors": ""})
		var max_lines: int = int(args.get("max_lines", 25))
		if max_lines < 1:
			max_lines = 25
		var errors: Array[String] = []
		while not f.eof_reached():
			var line: String = f.get_line()
			if (
				line.contains("ERROR:")
				or line.contains("SCRIPT ERROR:")
				or line.contains("Parse Error:")
			):
				errors.append(line)
		f.close()
		var recent: Array = []
		if errors.size() > max_lines:
			recent = errors.slice(errors.size() - max_lines)
		else:
			recent = errors
		var text: String = "\n".join(recent)
		return ok("", {"errors": text, "count": recent.size()})


class OpenInEditor extends GDAToolBase:
	func get_name() -> String:
		return "open_in_editor"

	func get_description() -> String:
		return "Open a specific file in the Godot editor (script or scene)."

	func get_parameters_schema() -> Dictionary:
		return {
			"type": "object",
			"properties": {
				"path": {
					"type": "string",
					"description": "res:// path to the file.",
				},
			},
			"required": ["path"],
		}

	func needs_editor() -> bool:
		return true

	func execute(args: Dictionary, context: Dictionary) -> Dictionary:
		var err: String = require_strings(args, ["path"])
		if not err.is_empty():
			return fail(err)
		var editor_interface: Variant = context.get("editor_interface", null)
		if editor_interface == null:
			return fail("EditorInterface unavailable.")
		var path: String = GDAPathGuard.normalize(str(args["path"]))
		if not path.begins_with("res://"):
			return fail("Only res:// paths are allowed.")
		if not FileAccess.file_exists(path):
			return fail("File not found: " + path)
		if path.to_lower().ends_with(".gd"):
			var script: Script = load(path) as Script
			if script == null:
				return fail("Failed to load script: " + path)
			editor_interface.edit_script(script)
			return ok("Opened script: " + path, {"path": path})
		if path.to_lower().ends_with(".tscn"):
			editor_interface.open_scene_from_path(path)
			return ok("Opened scene: " + path, {"path": path})
		return fail("Only .gd and .tscn files can be opened: " + path)


static func build_all() -> Array:
	return [
		RunScene.new(),
		StopScene.new(),
		GetErrors.new(),
		OpenInEditor.new(),
	]
