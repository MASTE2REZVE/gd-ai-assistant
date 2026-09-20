@tool
class_name GDAToolScene
extends RefCounted

const MAX_SCENE_BYTES: int = 4 * 1024 * 1024
const MAX_TREE_DEPTH: int = 6
const MAX_TREE_LINES: int = 300


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


## Validate a class name for use as a node. Returns {ok, message, is_instantiable}.
## If the class exists but is abstract, includes concrete subclass hints.
static func _validate_node_class(class_name_str: String) -> Dictionary:
	if not ClassDB.class_exists(class_name_str):
		return { "ok": false, "message": "Unknown class: " + class_name_str }
	if not ClassDB.is_parent_class(class_name_str, "Node"):
		return { "ok": false, "message": "Not a Node class: " + class_name_str }
	if not ClassDB.can_instantiate(class_name_str):
		var hints: Array[String] = []
		for child: String in ClassDB.get_inheriters_from_class(class_name_str):
			if ClassDB.can_instantiate(child) and ClassDB.is_parent_class(child, "Node"):
				hints.append(child)
			if hints.size() >= 4:
				break
		var msg: String = "'%s' is abstract and cannot be instantiated." % class_name_str
		if not hints.is_empty():
			msg += " Concrete subclasses: " + ", ".join(hints) + "."
		return { "ok": false, "message": msg }
	return { "ok": true, "message": "" }


# ============================================================
# list_scenes
# ============================================================

class ListScenes extends GDAToolBase:
	func get_name() -> String:
		return "list_scenes"

	func get_description() -> String:
		return "List all .tscn scene files under a res:// directory. Recurses."

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
		var root: String = GDAPathGuard.normalize(str(args["path"]))
		if not root.begins_with("res://"):
			return fail("Only res:// paths are allowed.")
		if not root.ends_with("/"):
			root += "/"
		var out: Array = []
		_scan(root, out)
		out.sort()
		return ok("", {"path": root, "scenes": out})

	func _scan(dir_path: String, out: Array) -> void:
		if out.size() >= 500:
			return
		var dir: DirAccess = DirAccess.open(dir_path)
		if dir == null:
			return
		dir.list_dir_begin()
		var n: String = dir.get_next()
		while not n.is_empty():
			if not n.begins_with("."):
				var full: String = dir_path.path_join(n)
				if dir.current_is_dir():
					if n != ".godot" and n != ".git":
						_scan(full, out)
				elif n.to_lower().ends_with(".tscn"):
					out.append(full)
			n = dir.get_next()
		dir.list_dir_end()


# ============================================================
# get_scene_tree
# ============================================================

class GetSceneTree extends GDAToolBase:
	func get_name() -> String:
		return "get_scene_tree"

	func get_description() -> String:
		return "Return a text tree of a scene's node hierarchy (name + type per node)."

	func get_parameters_schema() -> Dictionary:
		return {
			"type": "object",
			"properties": {
				"path": {"type": "string"},
				"max_depth": {"type": "integer"},
			},
			"required": ["path"],
		}

	func execute(args: Dictionary, _context: Dictionary) -> Dictionary:
		var err: String = require_strings(args, ["path"])
		if not err.is_empty():
			return fail(err)
		var path: String = GDAPathGuard.normalize(str(args["path"]))
		var guard: Dictionary = GDAPathGuard.validate_scene_path(path)
		if not bool(guard["ok"]):
			return fail(str(guard["message"]))
		if not FileAccess.file_exists(path):
			return fail("Scene not found: " + path)

		var packed: PackedScene = GDAToolScene._load_scene(path)
		if packed == null:
			return fail("Failed to load scene: " + path)
		var root: Node = packed.instantiate()
		if root == null:
			return fail("Failed to instantiate scene: " + path)

		var max_depth: int = int(args.get("max_depth", 4))
		if max_depth < 0:
			max_depth = 0
		if max_depth > MAX_TREE_DEPTH:
			max_depth = MAX_TREE_DEPTH

		var lines: Array[String] = []
		_gather(root, lines, 0, max_depth)
		root.free()

		var text: String = "\n".join(lines)
		if lines.size() >= MAX_TREE_LINES:
			text += "\n...[truncated]..."
		return ok("", {"path": path, "tree": text, "line_count": lines.size()})

	func _gather(node: Node, lines: Array[String], depth: int, max_depth: int) -> void:
		if lines.size() >= MAX_TREE_LINES:
			return
		var indent: String = "  ".repeat(depth)
		var line: String = "%s%s (%s)" % [indent, node.name, node.get_class()]
		var scr: Script = node.get_script() as Script
		if scr != null and not scr.resource_path.is_empty():
			line += "  [script: " + scr.resource_path + "]"
		lines.append(line)
		if depth >= max_depth:
			var child_count: int = node.get_child_count()
			if child_count > 0:
				lines.append(indent + "  ...(%d more)" % child_count)
			return
		for child: Node in node.get_children():
			_gather(child, lines, depth + 1, max_depth)


# ============================================================
# create_scene
# ============================================================

class CreateScene extends GDAToolBase:
	func get_name() -> String:
		return "create_scene"

	func get_description() -> String:
		return "Create a new .tscn file at res:// path with a single root node."

	func get_parameters_schema() -> Dictionary:
		return {
			"type": "object",
			"properties": {
				"path": {"type": "string"},
				"root_type": {"type": "string"},
				"root_name": {"type": "string"},
			},
			"required": ["path", "root_type"],
		}

	func is_mutating() -> bool:
		return true

	func execute(args: Dictionary, context: Dictionary) -> Dictionary:
		var err: String = require_strings(args, ["path", "root_type"])
		if not err.is_empty():
			return fail(err)
		var path: String = GDAPathGuard.normalize(str(args["path"]))
		var root_type: String = str(args["root_type"]).strip_edges()
		var root_name: String = str(args.get("root_name", root_type)).strip_edges()
		if root_name.is_empty():
			root_name = root_type

		var guard: Dictionary = GDAPathGuard.validate_scene_path(path)
		if not bool(guard["ok"]):
			return fail(str(guard["message"]))
		if FileAccess.file_exists(path):
			return fail("Scene already exists: " + path)

		var class_check: Dictionary = GDAToolScene._validate_node_class(root_type)
		if not bool(class_check["ok"]):
			return fail(str(class_check["message"]))

		var root_obj: Object = ClassDB.instantiate(root_type)
		if root_obj == null or not (root_obj is Node):
			return fail("Could not instantiate: " + root_type)
		var root: Node = root_obj as Node
		root.name = root_name

		var ckpt_err: String = GDAToolScene._snapshot_if_checkpointed(context, path)
		if not ckpt_err.is_empty():
			root.free()
			return fail("Checkpoint failed: " + ckpt_err)

		var save_result: Dictionary = GDAToolScene._save_scene_to_disk(root, path)
		root.free()
		if not bool(save_result["ok"]):
			return fail("Save failed: " + str(save_result["message"]))

		var v: Dictionary = GDAVerify.verify_file(path)
		if not bool(v["ok"]):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
			return fail("Verification failed: " + str(v["message"]))

		return ok("Scene created.", {"path": path, "root_type": root_type})


# ============================================================
# open_scene
# ============================================================

class OpenScene extends GDAToolBase:
	func get_name() -> String:
		return "open_scene"

	func get_description() -> String:
		return "Open a .tscn file in the Godot editor."

	func get_parameters_schema() -> Dictionary:
		return {
			"type": "object",
			"properties": {
				"path": {"type": "string"},
			},
			"required": ["path"],
		}

	func needs_editor() -> bool:
		return true

	func execute(args: Dictionary, context: Dictionary) -> Dictionary:
		var err: String = require_strings(args, ["path"])
		if not err.is_empty():
			return fail(err)
		var path: String = GDAPathGuard.normalize(str(args["path"]))
		var guard: Dictionary = GDAPathGuard.validate_scene_path(path)
		if not bool(guard["ok"]):
			return fail(str(guard["message"]))
		if not FileAccess.file_exists(path):
			return fail("Scene not found: " + path)

		var ei = GDAToolScene._editor_from_context(context)
		if ei == null:
			return fail("EditorInterface unavailable.")

		ei.open_scene_from_path(path)
		ei.set_main_screen_editor("3D")
		return ok("Scene opened.", {"path": path})


# ============================================================
# save_scene
# ============================================================

class SaveScene extends GDAToolBase:
	func get_name() -> String:
		return "save_scene"

	func get_description() -> String:
		return "Save the currently-open scene in the editor to disk."

	func get_parameters_schema() -> Dictionary:
		return {"type": "object", "properties": {}, "required": []}

	func needs_editor() -> bool:
		return true

	func is_mutating() -> bool:
		return true

	func execute(_args: Dictionary, context: Dictionary) -> Dictionary:
		var ei = GDAToolScene._editor_from_context(context)
		if ei == null:
			return fail("EditorInterface unavailable.")
		var root: Node = ei.get_edited_scene_root()
		if root == null:
			return fail("No scene is currently open.")
		var path: String = root.scene_file_path
		if path.is_empty():
			return fail("Open scene has no resource path (unsaved).")
		ei.save_scene()
		return ok("Scene saved.", {"path": path})


# ============================================================
# get_node
# ============================================================

class GetNode extends GDAToolBase:
	func get_name() -> String:
		return "get_node"

	func get_description() -> String:
		return "Return basic info about a node inside a scene."

	func get_parameters_schema() -> Dictionary:
		return {
			"type": "object",
			"properties": {
				"scene_path": {"type": "string"},
				"node_path": {"type": "string"},
			},
			"required": ["scene_path", "node_path"],
		}

	func execute(args: Dictionary, _context: Dictionary) -> Dictionary:
		var err: String = require_strings(args, ["scene_path", "node_path"])
		if not err.is_empty():
			return fail(err)
		var scene_path: String = GDAPathGuard.normalize(str(args["scene_path"]))
		var node_path: String = str(args["node_path"])
		var guard: Dictionary = GDAPathGuard.validate_scene_path(scene_path)
		if not bool(guard["ok"]):
			return fail(str(guard["message"]))

		var packed: PackedScene = GDAToolScene._load_scene(scene_path)
		if packed == null:
			return fail("Failed to load scene: " + scene_path)
		var root: Node = packed.instantiate()
		if root == null:
			return fail("Failed to instantiate scene: " + scene_path)
		var node: Node = GDAToolScene._resolve_node(root, node_path)
		if node == null:
			root.free()
			return fail("Node not found: " + node_path)
		var info: Dictionary = {
			"name": node.name,
			"type": node.get_class(),
			"child_count": node.get_child_count(),
			"path": str(root.get_path_to(node)),
		}
		var scr: Script = node.get_script() as Script
		if scr != null:
			info["script"] = scr.resource_path
		root.free()
		return ok("", info)


# ============================================================
# add_node
# ============================================================

class AddNode extends GDAToolBase:
	func get_name() -> String:
		return "add_node"

	func get_description() -> String:
		return "Add a new child node of the given Godot class under parent_node_path."

	func get_parameters_schema() -> Dictionary:
		return {
			"type": "object",
			"properties": {
				"scene_path": {"type": "string"},
				"parent_node_path": {"type": "string"},
				"node_name": {"type": "string"},
				"node_type": {"type": "string"},
			},
			"required": ["scene_path", "parent_node_path", "node_name", "node_type"],
		}

	func is_mutating() -> bool:
		return true

	func execute(args: Dictionary, context: Dictionary) -> Dictionary:
		var err: String = require_strings(
			args, ["scene_path", "parent_node_path", "node_name", "node_type"]
		)
		if not err.is_empty():
			return fail(err)
		var scene_path: String = GDAPathGuard.normalize(str(args["scene_path"]))
		var parent_path: String = str(args["parent_node_path"])
		var node_name: String = str(args["node_name"]).strip_edges()
		var node_type: String = str(args["node_type"]).strip_edges()

		var guard: Dictionary = GDAPathGuard.validate_scene_path(scene_path)
		if not bool(guard["ok"]):
			return fail(str(guard["message"]))
		if not FileAccess.file_exists(scene_path):
			return fail("Scene not found: " + scene_path)
		var ei = GDAToolScene._editor_from_context(context)
		if GDAToolScene._is_scene_open(scene_path, ei):
			return fail("Scene is open in the editor. Close it first, or use the editor directly.")
		if node_name.is_empty():
			return fail("node_name is required.")

		var class_check: Dictionary = GDAToolScene._validate_node_class(node_type)
		if not bool(class_check["ok"]):
			return fail(str(class_check["message"]))

		var packed: PackedScene = GDAToolScene._load_scene(scene_path)
		if packed == null:
			return fail("Failed to load scene.")
		var root: Node = packed.instantiate()
		if root == null:
			return fail("Failed to instantiate scene.")
		var parent: Node = GDAToolScene._resolve_node(root, parent_path)
		if parent == null:
			root.free()
			return fail("Parent not found: " + parent_path)
		if parent.has_node(NodePath(node_name)):
			root.free()
			return fail("Child name already used under parent: " + node_name)

		var new_obj: Object = ClassDB.instantiate(node_type)
		if new_obj == null or not (new_obj is Node):
			root.free()
			return fail("Could not instantiate: " + node_type)
		var child: Node = new_obj as Node
		child.name = node_name
		parent.add_child(child)
		child.owner = root

		var ckpt_err: String = GDAToolScene._snapshot_if_checkpointed(context, scene_path)
		if not ckpt_err.is_empty():
			root.free()
			return fail("Checkpoint failed: " + ckpt_err)

		var backup: Dictionary = GDABackup.create_backup(scene_path)
		if not bool(backup["ok"]):
			root.free()
			return fail("Backup failed: " + str(backup["message"]))
		var backup_path: String = str(backup["data"].get("backup_path", ""))

		var save_result: Dictionary = GDAToolScene._save_scene_to_disk(root, scene_path)
		root.free()
		if not bool(save_result["ok"]):
			GDABackup.restore_backup(scene_path, backup_path)
			return fail("Save failed: " + str(save_result["message"]))

		var v: Dictionary = GDAVerify.verify_file(scene_path)
		if not bool(v["ok"]):
			GDABackup.restore_backup(scene_path, backup_path)
			return fail("Verification failed: " + str(v["message"]))

		GDABackup.delete_backup(backup_path)
		return ok(
			"Node added.",
			{"scene_path": scene_path, "parent": parent_path, "name": node_name, "type": node_type}
		)


# ============================================================
# remove_node
# ============================================================

class RemoveNode extends GDAToolBase:
	func get_name() -> String:
		return "remove_node"

	func get_description() -> String:
		return "Remove a node (and its children) from a scene. Cannot remove the root."

	func get_parameters_schema() -> Dictionary:
		return {
			"type": "object",
			"properties": {
				"scene_path": {"type": "string"},
				"node_path": {"type": "string"},
			},
			"required": ["scene_path", "node_path"],
		}

	func is_mutating() -> bool:
		return true

	func execute(args: Dictionary, context: Dictionary) -> Dictionary:
		var err: String = require_strings(args, ["scene_path", "node_path"])
		if not err.is_empty():
			return fail(err)
		var scene_path: String = GDAPathGuard.normalize(str(args["scene_path"]))
		var node_path: String = str(args["node_path"])

		var guard: Dictionary = GDAPathGuard.validate_scene_path(scene_path)
		if not bool(guard["ok"]):
			return fail(str(guard["message"]))
		if not FileAccess.file_exists(scene_path):
			return fail("Scene not found: " + scene_path)
		var ei = GDAToolScene._editor_from_context(context)
		if GDAToolScene._is_scene_open(scene_path, ei):
			return fail("Scene is open in the editor. Close it first.")
		if node_path.is_empty() or node_path == ".":
			return fail("Cannot remove the scene root.")

		var packed: PackedScene = GDAToolScene._load_scene(scene_path)
		if packed == null:
			return fail("Failed to load scene.")
		var root: Node = packed.instantiate()
		if root == null:
			return fail("Failed to instantiate scene.")
		var node: Node = GDAToolScene._resolve_node(root, node_path)
		if node == null:
			root.free()
			return fail("Node not found: " + node_path)
		var parent: Node = node.get_parent()
		if parent == null:
			root.free()
			return fail("Node has no parent.")

		parent.remove_child(node)
		node.free()

		var ckpt_err: String = GDAToolScene._snapshot_if_checkpointed(context, scene_path)
		if not ckpt_err.is_empty():
			root.free()
			return fail("Checkpoint failed: " + ckpt_err)

		var backup: Dictionary = GDABackup.create_backup(scene_path)
		if not bool(backup["ok"]):
			root.free()
			return fail("Backup failed: " + str(backup["message"]))
		var backup_path: String = str(backup["data"].get("backup_path", ""))

		var save_result: Dictionary = GDAToolScene._save_scene_to_disk(root, scene_path)
		root.free()
		if not bool(save_result["ok"]):
			GDABackup.restore_backup(scene_path, backup_path)
			return fail("Save failed: " + str(save_result["message"]))

		var v: Dictionary = GDAVerify.verify_file(scene_path)
		if not bool(v["ok"]):
			GDABackup.restore_backup(scene_path, backup_path)
			return fail("Verification failed: " + str(v["message"]))

		GDABackup.delete_backup(backup_path)
		return ok("Node removed.", {"scene_path": scene_path, "removed": node_path})


# ============================================================
# rename_node
# ============================================================

class RenameNode extends GDAToolBase:
	func get_name() -> String:
		return "rename_node"

	func get_description() -> String:
		return "Rename a node inside a scene."

	func get_parameters_schema() -> Dictionary:
		return {
			"type": "object",
			"properties": {
				"scene_path": {"type": "string"},
				"node_path": {"type": "string"},
				"new_name": {"type": "string"},
			},
			"required": ["scene_path", "node_path", "new_name"],
		}

	func is_mutating() -> bool:
		return true

	func execute(args: Dictionary, context: Dictionary) -> Dictionary:
		var err: String = require_strings(args, ["scene_path", "node_path", "new_name"])
		if not err.is_empty():
			return fail(err)
		var scene_path: String = GDAPathGuard.normalize(str(args["scene_path"]))
		var node_path: String = str(args["node_path"])
		var new_name: String = str(args["new_name"]).strip_edges()

		var guard: Dictionary = GDAPathGuard.validate_scene_path(scene_path)
		if not bool(guard["ok"]):
			return fail(str(guard["message"]))
		if not FileAccess.file_exists(scene_path):
			return fail("Scene not found: " + scene_path)
		var ei = GDAToolScene._editor_from_context(context)
		if GDAToolScene._is_scene_open(scene_path, ei):
			return fail("Scene is open in the editor. Close it first.")
		if new_name.is_empty():
			return fail("new_name is required.")

		var packed: PackedScene = GDAToolScene._load_scene(scene_path)
		if packed == null:
			return fail("Failed to load scene.")
		var root: Node = packed.instantiate()
		if root == null:
			return fail("Failed to instantiate scene.")
		var node: Node = GDAToolScene._resolve_node(root, node_path)
		if node == null:
			root.free()
			return fail("Node not found: " + node_path)

		node.name = new_name

		var ckpt_err: String = GDAToolScene._snapshot_if_checkpointed(context, scene_path)
		if not ckpt_err.is_empty():
			root.free()
			return fail("Checkpoint failed: " + ckpt_err)
		var backup: Dictionary = GDABackup.create_backup(scene_path)
		if not bool(backup["ok"]):
			root.free()
			return fail("Backup failed: " + str(backup["message"]))
		var backup_path: String = str(backup["data"].get("backup_path", ""))

		var save_result: Dictionary = GDAToolScene._save_scene_to_disk(root, scene_path)
		root.free()
		if not bool(save_result["ok"]):
			GDABackup.restore_backup(scene_path, backup_path)
			return fail("Save failed: " + str(save_result["message"]))
		var v: Dictionary = GDAVerify.verify_file(scene_path)
		if not bool(v["ok"]):
			GDABackup.restore_backup(scene_path, backup_path)
			return fail("Verification failed: " + str(v["message"]))
		GDABackup.delete_backup(backup_path)
		return ok("Node renamed.", {"scene_path": scene_path, "new_name": new_name})


# ============================================================
# move_node
# ============================================================

class MoveNode extends GDAToolBase:
	func get_name() -> String:
		return "move_node"

	func get_description() -> String:
		return "Reparent a node under a different node in the same scene."

	func get_parameters_schema() -> Dictionary:
		return {
			"type": "object",
			"properties": {
				"scene_path": {"type": "string"},
				"node_path": {"type": "string"},
				"new_parent_path": {"type": "string"},
			},
			"required": ["scene_path", "node_path", "new_parent_path"],
		}

	func is_mutating() -> bool:
		return true

	func execute(args: Dictionary, context: Dictionary) -> Dictionary:
		var err: String = require_strings(
			args, ["scene_path", "node_path", "new_parent_path"]
		)
		if not err.is_empty():
			return fail(err)
		var scene_path: String = GDAPathGuard.normalize(str(args["scene_path"]))
		var node_path: String = str(args["node_path"])
		var new_parent_path: String = str(args["new_parent_path"])

		var guard: Dictionary = GDAPathGuard.validate_scene_path(scene_path)
		if not bool(guard["ok"]):
			return fail(str(guard["message"]))
		if not FileAccess.file_exists(scene_path):
			return fail("Scene not found: " + scene_path)
		var ei = GDAToolScene._editor_from_context(context)
		if GDAToolScene._is_scene_open(scene_path, ei):
			return fail("Scene is open in the editor. Close it first.")
		if node_path.is_empty() or node_path == ".":
			return fail("Cannot move the scene root.")

		var packed: PackedScene = GDAToolScene._load_scene(scene_path)
		if packed == null:
			return fail("Failed to load scene.")
		var root: Node = packed.instantiate()
		if root == null:
			return fail("Failed to instantiate scene.")
		var node: Node = GDAToolScene._resolve_node(root, node_path)
		if node == null:
			root.free()
			return fail("Node not found: " + node_path)
		var new_parent: Node = GDAToolScene._resolve_node(root, new_parent_path)
		if new_parent == null:
			root.free()
			return fail("New parent not found: " + new_parent_path)
		if new_parent == node or node.is_ancestor_of(new_parent):
			root.free()
			return fail("Cannot move a node under its own descendant.")

		var old_parent: Node = node.get_parent()
		if old_parent != null:
			old_parent.remove_child(node)
		new_parent.add_child(node)
		node.owner = root

		var ckpt_err: String = GDAToolScene._snapshot_if_checkpointed(context, scene_path)
		if not ckpt_err.is_empty():
			root.free()
			return fail("Checkpoint failed: " + ckpt_err)
		var backup: Dictionary = GDABackup.create_backup(scene_path)
		if not bool(backup["ok"]):
			root.free()
			return fail("Backup failed: " + str(backup["message"]))
		var backup_path: String = str(backup["data"].get("backup_path", ""))

		var save_result: Dictionary = GDAToolScene._save_scene_to_disk(root, scene_path)
		root.free()
		if not bool(save_result["ok"]):
			GDABackup.restore_backup(scene_path, backup_path)
			return fail("Save failed: " + str(save_result["message"]))
		var v: Dictionary = GDAVerify.verify_file(scene_path)
		if not bool(v["ok"]):
			GDABackup.restore_backup(scene_path, backup_path)
			return fail("Verification failed: " + str(v["message"]))
		GDABackup.delete_backup(backup_path)
		return ok("Node moved.", {"scene_path": scene_path, "to": new_parent_path})


# ============================================================
# set_node_property
# ============================================================

class SetNodeProperty extends GDAToolBase:
	func get_name() -> String:
		return "set_node_property"

	func get_description() -> String:
		return (
			"Set one or more properties on a node. Value can be a primitive, "
			+ "a {x,y,z} or {x,y} dict for Vector types, or a "
			+ "{r,g,b,a} dict for Color."
		)

	func get_parameters_schema() -> Dictionary:
		return {
			"type": "object",
			"properties": {
				"scene_path": {"type": "string"},
				"node_path": {"type": "string"},
				"properties": {"type": "object"},
			},
			"required": ["scene_path", "node_path", "properties"],
		}

	func is_mutating() -> bool:
		return true

	func execute(args: Dictionary, context: Dictionary) -> Dictionary:
		var err: String = require_strings(args, ["scene_path", "node_path"])
		if not err.is_empty():
			return fail(err)
		var scene_path: String = GDAPathGuard.normalize(str(args["scene_path"]))
		var node_path: String = str(args["node_path"])
		var props_raw: Variant = args.get("properties", null)
		if not (props_raw is Dictionary) or (props_raw as Dictionary).is_empty():
			return fail("properties must be a non-empty object.")

		var guard: Dictionary = GDAPathGuard.validate_scene_path(scene_path)
		if not bool(guard["ok"]):
			return fail(str(guard["message"]))
		if not FileAccess.file_exists(scene_path):
			return fail("Scene not found: " + scene_path)
		var ei = GDAToolScene._editor_from_context(context)
		if GDAToolScene._is_scene_open(scene_path, ei):
			return fail("Scene is open in the editor. Close it first.")

		var packed: PackedScene = GDAToolScene._load_scene(scene_path)
		if packed == null:
			return fail("Failed to load scene.")
		var root: Node = packed.instantiate()
		if root == null:
			return fail("Failed to instantiate scene.")
		var node: Node = GDAToolScene._resolve_node(root, node_path)
		if node == null:
			root.free()
			return fail("Node not found: " + node_path)

		var props: Dictionary = props_raw
		var applied: Array = []
		var failed_props: Array = []
		for key_v: Variant in props.keys():
			var key: String = str(key_v)
			if not _has_property(node, key):
				failed_props.append({"name": key, "reason": "no such property"})
				continue
			var coerced: Dictionary = _coerce(props[key_v])
			if not bool(coerced["ok"]):
				failed_props.append({"name": key, "reason": str(coerced["message"])})
				continue
			node.set(key, coerced["value"])
			applied.append(key)

		if applied.is_empty():
			root.free()
			return fail("No properties were applied. " + JSON.stringify(failed_props))

		var ckpt_err: String = GDAToolScene._snapshot_if_checkpointed(context, scene_path)
		if not ckpt_err.is_empty():
			root.free()
			return fail("Checkpoint failed: " + ckpt_err)
		var backup: Dictionary = GDABackup.create_backup(scene_path)
		if not bool(backup["ok"]):
			root.free()
			return fail("Backup failed: " + str(backup["message"]))
		var backup_path: String = str(backup["data"].get("backup_path", ""))

		var save_result: Dictionary = GDAToolScene._save_scene_to_disk(root, scene_path)
		root.free()
		if not bool(save_result["ok"]):
			GDABackup.restore_backup(scene_path, backup_path)
			return fail("Save failed: " + str(save_result["message"]))
		var v: Dictionary = GDAVerify.verify_file(scene_path)
		if not bool(v["ok"]):
			GDABackup.restore_backup(scene_path, backup_path)
			return fail("Verification failed: " + str(v["message"]))
		GDABackup.delete_backup(backup_path)

		return ok("Properties set.", {
			"scene_path": scene_path,
			"node_path": node_path,
			"applied": applied,
			"failed": failed_props,
		})

	func _has_property(node: Node, prop: String) -> bool:
		for p: Dictionary in node.get_property_list():
			if str(p.get("name", "")) == prop:
				return true
		return false

	func _coerce(raw: Variant) -> Dictionary:
		if raw is Dictionary:
			var d: Dictionary = raw
			if d.has("x") and d.has("y") and d.has("z"):
				return { "ok": true, "value": Vector3(
					float(d["x"]), float(d["y"]), float(d["z"])
				) }
			if d.has("x") and d.has("y"):
				return { "ok": true, "value": Vector2(
					float(d["x"]), float(d["y"])
				) }
			if d.has("r") and d.has("g") and d.has("b"):
				var a: float = float(d.get("a", 1.0))
				return { "ok": true, "value": Color(
					float(d["r"]), float(d["g"]), float(d["b"]), a
				) }
			return { "ok": false, "message": "unrecognized dict shape for property" }
		return { "ok": true, "value": raw }


# ============================================================
# get_node_property
# ============================================================

class GetNodeProperty extends GDAToolBase:
	func get_name() -> String:
		return "get_node_property"

	func get_description() -> String:
		return "Read a single property from a node in a scene."

	func get_parameters_schema() -> Dictionary:
		return {
			"type": "object",
			"properties": {
				"scene_path": {"type": "string"},
				"node_path": {"type": "string"},
				"property": {"type": "string"},
			},
			"required": ["scene_path", "node_path", "property"],
		}

	func execute(args: Dictionary, _context: Dictionary) -> Dictionary:
		var err: String = require_strings(
			args, ["scene_path", "node_path", "property"]
		)
		if not err.is_empty():
			return fail(err)
		var scene_path: String = GDAPathGuard.normalize(str(args["scene_path"]))
		var node_path: String = str(args["node_path"])
		var prop: String = str(args["property"])

		var guard: Dictionary = GDAPathGuard.validate_scene_path(scene_path)
		if not bool(guard["ok"]):
			return fail(str(guard["message"]))

		var packed: PackedScene = GDAToolScene._load_scene(scene_path)
		if packed == null:
			return fail("Failed to load scene.")
		var root: Node = packed.instantiate()
		if root == null:
			return fail("Failed to instantiate scene.")
		var node: Node = GDAToolScene._resolve_node(root, node_path)
		if node == null:
			root.free()
			return fail("Node not found: " + node_path)

		var value: Variant = node.get(prop)
		var value_str: String = str(value)
		root.free()
		return ok("", {
			"scene_path": scene_path,
			"node_path": node_path,
			"property": prop,
			"value": value_str,
		})


static func build_all() -> Array:
	return [
		ListScenes.new(),
		GetSceneTree.new(),
		CreateScene.new(),
		OpenScene.new(),
		SaveScene.new(),
		GetNode.new(),
		AddNode.new(),
		RemoveNode.new(),
		RenameNode.new(),
		MoveNode.new(),
		SetNodeProperty.new(),
		GetNodeProperty.new(),
	]
