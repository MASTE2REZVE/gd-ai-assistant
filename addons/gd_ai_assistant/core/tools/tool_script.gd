@tool
class_name GDAToolScript
extends RefCounted

## GD AI Assistant — Script Tools

const MAX_SCRIPT_BYTES: int = 512 * 1024


static func _snapshot_if_checkpointed(context: Dictionary, path: String) -> String:
	if not context.has("checkpoint_id"):
		return ""
	var ckpt_id: String = str(context["checkpoint_id"])
	if ckpt_id.is_empty():
		return ""
	var r: Dictionary = GDACheckpoint.snapshot_file(ckpt_id, path)
	if bool(r.get("ok", false)):
		return ""
	return str(r.get("message", "Unknown checkpoint error"))


static func _editor_from_context(context: Dictionary):
	return context.get("editor_interface", null)


static func _is_scene_open(scene_path: String, editor) -> bool:
	if editor == null:
		return false
	var root: Node = editor.get_edited_scene_root()
	if root == null:
		return false
	return root.scene_file_path == scene_path


static func _load_scene(scene_path: String) -> PackedScene:
	return ResourceLoader.load(
		scene_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE
	) as PackedScene


static func _save_scene_to_disk(root: Node, scene_path: String) -> Dictionary:
	var packed: PackedScene = PackedScene.new()
	var pack_err: Error = packed.pack(root)
	if pack_err != OK:
		return { "ok": false, "message": "pack() failed (%d)." % pack_err }
	var save_err: Error = ResourceSaver.save(packed, scene_path)
	if save_err != OK:
		return { "ok": false, "message": "ResourceSaver.save failed (%d)." % save_err }
	return { "ok": true, "message": "", "data": {} }


static func _resolve_node(root: Node, path: String) -> Node:
	if path.is_empty() or path == ".":
		return root
	return root.get_node_or_null(path)


class CreateScript extends GDAToolBase:
	func get_name() -> String:
		return "create_script"

	func get_description() -> String:
		return (
			"Create a new .gd GDScript file at a res:// path. Refuses "
			+ "if the file already exists; use write_file to replace."
		)

	func get_parameters_schema() -> Dictionary:
		return {
			"type": "object",
			"properties": {
				"path": {"type": "string"},
				"content": {"type": "string"},
			},
			"required": ["path", "content"],
		}

	func is_mutating() -> bool:
		return true

	func execute(args: Dictionary, context: Dictionary) -> Dictionary:
		var err: String = require_strings(args, ["path", "content"])
		if not err.is_empty():
			return fail(err)
		var path: String = GDAPathGuard.normalize(str(args["path"]))
		var content: String = str(args["content"])

		if not path.to_lower().ends_with(".gd"):
			return fail("path must end in .gd: " + path)
		var guard: Dictionary = GDAPathGuard.validate_text_write_path(path)
		if not bool(guard["ok"]):
			return fail(str(guard["message"]))
		if FileAccess.file_exists(path):
			return fail("Script already exists: " + path + " (use write_file to replace)")
		if content.is_empty():
			return fail("content is empty.")
		var size: int = content.to_utf8_buffer().size()
		if size > MAX_SCRIPT_BYTES:
			return fail("Script too large (%d bytes)." % size)

		var ckpt_err: String = GDAToolScript._snapshot_if_checkpointed(context, path)
		if not ckpt_err.is_empty():
			return fail("Checkpoint failed: " + ckpt_err)

		var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
		if f == null:
			return fail("Cannot open for write: " + path)
		f.store_string(content)
		f.close()

		var v: Dictionary = GDAVerify.verify_file(path)
		if not bool(v["ok"]):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
			return fail("Verification failed: " + str(v["message"]))

		return ok("Script created.", {"path": path, "bytes": size})


class ReadScript extends GDAToolBase:
	func get_name() -> String:
		return "read_script"

	func get_description() -> String:
		return "Read a .gd GDScript file. Returns its source text and size."

	func get_parameters_schema() -> Dictionary:
		return {
			"type": "object",
			"properties": {
				"path": {"type": "string"},
			},
			"required": ["path"],
		}

	func execute(args: Dictionary, _context: Dictionary) -> Dictionary:
		var err: String = require_strings(args, ["path"])
		if not err.is_empty():
			return fail(err)
		var path: String = GDAPathGuard.normalize(str(args["path"]))
		var guard: Dictionary = GDAPathGuard.validate_read_path(path)
		if not bool(guard["ok"]):
			return fail(str(guard["message"]))
		if not FileAccess.file_exists(path):
			return fail("Script not found: " + path)
		if not path.to_lower().ends_with(".gd"):
			return fail("Not a .gd file: " + path)

		var f: FileAccess = FileAccess.open(path, FileAccess.READ)
		if f == null:
			return fail("Cannot open: " + path)
		var length: int = f.get_length()
		if length > MAX_SCRIPT_BYTES:
			f.close()
			return fail("Script too large (%d bytes)." % length)
		var content: String = f.get_as_text()
		f.close()
		return ok("", {"path": path, "content": content, "size": length})


class ValidateScript extends GDAToolBase:
	func get_name() -> String:
		return "validate_script"

	func get_description() -> String:
		return "Validate a .gd file by parsing it. Returns whether it loads."

	func get_parameters_schema() -> Dictionary:
		return {
			"type": "object",
			"properties": {
				"path": {"type": "string"},
			},
			"required": ["path"],
		}

	func execute(args: Dictionary, _context: Dictionary) -> Dictionary:
		var err: String = require_strings(args, ["path"])
		if not err.is_empty():
			return fail(err)
		var path: String = GDAPathGuard.normalize(str(args["path"]))
		var guard: Dictionary = GDAPathGuard.validate_read_path(path)
		if not bool(guard["ok"]):
			return fail(str(guard["message"]))
		if not FileAccess.file_exists(path):
			return fail("Script not found: " + path)
		if not path.to_lower().ends_with(".gd"):
			return fail("Not a .gd file: " + path)

		var loaded: Resource = ResourceLoader.load(
			path, "GDScript", ResourceLoader.CACHE_MODE_IGNORE
		)
		if loaded == null or not (loaded is GDScript):
			return ok("Script does not parse.", {
				"path": path,
				"valid": false,
			})
		return ok("Script parses.", {
			"path": path,
			"valid": true,
			"base_class": (loaded as GDScript).get_instance_base_type(),
		})


class GetScriptSymbols extends GDAToolBase:
	func get_name() -> String:
		return "get_script_symbols"

	func get_description() -> String:
		return (
			"Parse a .gd file and return its base class, methods, "
			+ "signals, exported properties, and constants."
		)

	func get_parameters_schema() -> Dictionary:
		return {
			"type": "object",
			"properties": {
				"path": {"type": "string"},
			},
			"required": ["path"],
		}

	func execute(args: Dictionary, _context: Dictionary) -> Dictionary:
		var err: String = require_strings(args, ["path"])
		if not err.is_empty():
			return fail(err)
		var path: String = GDAPathGuard.normalize(str(args["path"]))
		var guard: Dictionary = GDAPathGuard.validate_read_path(path)
		if not bool(guard["ok"]):
			return fail(str(guard["message"]))
		if not FileAccess.file_exists(path):
			return fail("Script not found: " + path)
		if not path.to_lower().ends_with(".gd"):
			return fail("Not a .gd file: " + path)

		var loaded: Resource = ResourceLoader.load(
			path, "GDScript", ResourceLoader.CACHE_MODE_IGNORE
		)
		if loaded == null or not (loaded is GDScript):
			return fail("Script failed to parse: " + path)
		var script: GDScript = loaded as GDScript

		var methods: Array[String] = []
		for m: Dictionary in script.get_script_method_list():
			var name: String = str(m.get("name", ""))
			if name.begins_with("@"):
				continue
			if name.begins_with("_"):
				continue
			if name in ["get", "set", "init", "notification"]:
				continue
			methods.append(name)

		var signals: Array[String] = []
		for s: Dictionary in script.get_script_signal_list():
			signals.append(str(s.get("name", "")))

		var exports: Array[String] = []
		for p: Dictionary in script.get_script_property_list():
			var usage: int = int(p.get("usage", 0))
			if (usage & 4096) == 0:
				continue
			var pname: String = str(p.get("name", ""))
			if pname.begins_with("_"):
				continue
			var ptype: int = int(p.get("type", 0))
			exports.append("%s: %s" % [pname, type_string(ptype)])

		var constants: Array[String] = []
		var cmap: Dictionary = script.get_script_constant_map()
		for k: Variant in cmap.keys():
			var kn: String = str(k)
			if kn.begins_with("_"):
				continue
			constants.append(kn)

		var base_class: String = script.get_instance_base_type()

		return ok("", {
			"path": path,
			"base_class": base_class,
			"methods": methods,
			"signals": signals,
			"properties": exports,
			"constants": constants,
		})


class AttachScript extends GDAToolBase:
	func get_name() -> String:
		return "attach_script"

	func get_description() -> String:
		return (
			"Attach a .gd script to a node inside a .tscn scene. Both "
			+ "files must already exist. Refuses if the scene is open "
			+ "in the editor."
		)

	func get_parameters_schema() -> Dictionary:
		return {
			"type": "object",
			"properties": {
				"scene_path": {"type": "string"},
				"node_path": {"type": "string"},
				"script_path": {"type": "string"},
			},
			"required": ["scene_path", "node_path", "script_path"],
		}

	func is_mutating() -> bool:
		return true

	func execute(args: Dictionary, context: Dictionary) -> Dictionary:
		var err: String = require_strings(
			args, ["scene_path", "node_path", "script_path"]
		)
		if not err.is_empty():
			return fail(err)
		var scene_path: String = GDAPathGuard.normalize(str(args["scene_path"]))
		var node_path: String = str(args["node_path"])
		var script_path: String = GDAPathGuard.normalize(str(args["script_path"]))

		var scene_guard: Dictionary = GDAPathGuard.validate_scene_path(scene_path)
		if not bool(scene_guard["ok"]):
			return fail(str(scene_guard["message"]))
		if not FileAccess.file_exists(scene_path):
			return fail("Scene not found: " + scene_path)
		if not FileAccess.file_exists(script_path):
			return fail("Script not found: " + script_path)
		if not script_path.to_lower().ends_with(".gd"):
			return fail("script_path must end in .gd.")

		var ei = GDAToolScript._editor_from_context(context)
		if GDAToolScript._is_scene_open(scene_path, ei):
			return fail("Scene is open in the editor. Close it first.")

		var script_resource: Resource = ResourceLoader.load(
			script_path, "GDScript", ResourceLoader.CACHE_MODE_IGNORE
		)
		if script_resource == null or not (script_resource is Script):
			return fail("Script failed to load: " + script_path)

		var packed: PackedScene = GDAToolScript._load_scene(scene_path)
		if packed == null:
			return fail("Failed to load scene: " + scene_path)
		var root: Node = packed.instantiate()
		if root == null:
			return fail("Failed to instantiate scene.")
		var node: Node = GDAToolScript._resolve_node(root, node_path)
		if node == null:
			root.free()
			return fail("Node not found: " + node_path)

		node.set_script(script_resource as Script)

		var ckpt_err: String = GDAToolScript._snapshot_if_checkpointed(context, scene_path)
		if not ckpt_err.is_empty():
			root.free()
			return fail("Checkpoint failed: " + ckpt_err)
		var backup: Dictionary = GDABackup.create_backup(scene_path)
		if not bool(backup["ok"]):
			root.free()
			return fail("Backup failed: " + str(backup["message"]))
		var backup_path: String = str(backup["data"].get("backup_path", ""))

		var save_result: Dictionary = GDAToolScript._save_scene_to_disk(root, scene_path)
		root.free()
		if not bool(save_result["ok"]):
			GDABackup.restore_backup(scene_path, backup_path)
			return fail("Save failed: " + str(save_result["message"]))
		var v: Dictionary = GDAVerify.verify_file(scene_path)
		if not bool(v["ok"]):
			GDABackup.restore_backup(scene_path, backup_path)
			return fail("Verification failed: " + str(v["message"]))
		GDABackup.delete_backup(backup_path)

		return ok("Script attached.", {
			"scene_path": scene_path,
			"node_path": node_path,
			"script_path": script_path,
		})


static func build_all() -> Array:
	return [
		CreateScript.new(),
		ReadScript.new(),
		ValidateScript.new(),
		GetScriptSymbols.new(),
		AttachScript.new(),
	]
