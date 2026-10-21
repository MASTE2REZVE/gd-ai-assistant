@tool
class_name GDAToolSignal
extends RefCounted

## GD AI Assistant — Signal & group tools.


static func _commit_scene(root: Node, scene_path: String, context: Dictionary) -> Dictionary:
	var ckpt_err: String = GDAToolScene._snapshot_if_checkpointed(context, scene_path)
	if not ckpt_err.is_empty():
		root.free()
		return { "ok": false, "message": "Checkpoint failed: " + ckpt_err }
	var backup: Dictionary = GDABackup.create_backup(scene_path)
	if not bool(backup["ok"]):
		root.free()
		return { "ok": false, "message": "Backup failed: " + str(backup["message"]) }
	var backup_path: String = str(backup["data"].get("backup_path", ""))

	var save_result: Dictionary = GDAToolScene._save_scene_to_disk(root, scene_path)
	root.free()
	if not bool(save_result["ok"]):
		GDABackup.restore_backup(scene_path, backup_path)
		return { "ok": false, "message": "Save failed: " + str(save_result["message"]) }
	var v: Dictionary = GDAVerify.verify_file(scene_path)
	if not bool(v["ok"]):
		GDABackup.restore_backup(scene_path, backup_path)
		return { "ok": false, "message": "Verification failed: " + str(v["message"]) }
	GDABackup.delete_backup(backup_path)
	return { "ok": true, "message": "" }


# ============================================================
# connect_signal
# ============================================================

class ConnectSignal extends GDAToolBase:
	func get_name() -> String:
		return "connect_signal"

	func get_description() -> String:
		return "Connect a signal from one node to a method on another node within a scene."

	func get_parameters_schema() -> Dictionary:
		return {
			"type": "object",
			"properties": {
				"scene_path": {"type": "string"},
				"source_node_path": {"type": "string"},
				"signal_name": {"type": "string"},
				"target_node_path": {"type": "string"},
				"method_name": {"type": "string"},
			},
			"required": [
				"scene_path", "source_node_path", "signal_name",
				"target_node_path", "method_name",
			],
		}

	func is_mutating() -> bool:
		return true

	func execute(args: Dictionary, context: Dictionary) -> Dictionary:
		var err: String = require_strings(args, [
			"scene_path", "source_node_path", "signal_name",
			"target_node_path", "method_name",
		])
		if not err.is_empty():
			return fail(err)
		var scene_path: String = GDAPathGuard.normalize(str(args["scene_path"]))
		var source_path: String = str(args["source_node_path"])
		var signal_name: String = str(args["signal_name"]).strip_edges()
		var target_path: String = str(args["target_node_path"])
		var method_name: String = str(args["method_name"]).strip_edges()

		var guard: Dictionary = GDAPathGuard.validate_scene_path(scene_path)
		if not bool(guard["ok"]):
			return fail(str(guard["message"]))
		if not FileAccess.file_exists(scene_path):
			return fail("Scene not found: " + scene_path)
		var ei: EditorInterface = GDAToolScene._editor_from_context(context)
		if GDAToolScene._is_scene_open(scene_path, ei):
			return fail("Scene is open in the editor. Close it first.")

		var packed: PackedScene = GDAToolScene._load_scene(scene_path)
		if packed == null:
			return fail("Failed to load scene.")
		var root: Node = packed.instantiate()
		if root == null:
			return fail("Failed to instantiate scene.")
		var source: Node = GDAToolScene._resolve_node(root, source_path)
		if source == null:
			root.free()
			return fail("Source node not found: " + source_path)
		var target: Node = GDAToolScene._resolve_node(root, target_path)
		if target == null:
			root.free()
			return fail("Target node not found: " + target_path)
		if not source.has_signal(signal_name):
			root.free()
			return fail("Signal not found on source node: " + signal_name)
		if not target.has_method(method_name):
			root.free()
			return fail("Method not found on target node: " + method_name)

		var callable: Callable = Callable(target, method_name)
		if source.is_connected(signal_name, callable):
			root.free()
			return ok("Signal already connected.", {
				"scene_path": scene_path,
				"source_node_path": source_path,
				"signal_name": signal_name,
				"target_node_path": target_path,
				"method_name": method_name,
				"already_connected": true,
			})

		var connect_err: Error = source.connect(
			signal_name, callable, Object.CONNECT_PERSIST
		)
		if connect_err != OK:
			root.free()
			return fail("connect() failed (%d)." % connect_err)

		var commit: Dictionary = GDAToolSignal._commit_scene(root, scene_path, context)
		if not bool(commit["ok"]):
			return fail(str(commit["message"]))
		return ok("Signal connected.", {
			"scene_path": scene_path,
			"source_node_path": source_path,
			"signal_name": signal_name,
			"target_node_path": target_path,
			"method_name": method_name,
		})


# ============================================================
# disconnect_signal
# ============================================================

class DisconnectSignal extends GDAToolBase:
	func get_name() -> String:
		return "disconnect_signal"

	func get_description() -> String:
		return "Disconnect a signal between two nodes in a scene."

	func get_parameters_schema() -> Dictionary:
		return {
			"type": "object",
			"properties": {
				"scene_path": {"type": "string"},
				"source_node_path": {"type": "string"},
				"signal_name": {"type": "string"},
				"target_node_path": {"type": "string"},
				"method_name": {"type": "string"},
			},
			"required": [
				"scene_path", "source_node_path", "signal_name",
				"target_node_path", "method_name",
			],
		}

	func is_mutating() -> bool:
		return true

	func execute(args: Dictionary, context: Dictionary) -> Dictionary:
		var err: String = require_strings(args, [
			"scene_path", "source_node_path", "signal_name",
			"target_node_path", "method_name",
		])
		if not err.is_empty():
			return fail(err)
		var scene_path: String = GDAPathGuard.normalize(str(args["scene_path"]))
		var source_path: String = str(args["source_node_path"])
		var signal_name: String = str(args["signal_name"]).strip_edges()
		var target_path: String = str(args["target_node_path"])
		var method_name: String = str(args["method_name"]).strip_edges()

		var guard: Dictionary = GDAPathGuard.validate_scene_path(scene_path)
		if not bool(guard["ok"]):
			return fail(str(guard["message"]))
		if not FileAccess.file_exists(scene_path):
			return fail("Scene not found: " + scene_path)
		var ei: EditorInterface = GDAToolScene._editor_from_context(context)
		if GDAToolScene._is_scene_open(scene_path, ei):
			return fail("Scene is open in the editor. Close it first.")

		var packed: PackedScene = GDAToolScene._load_scene(scene_path)
		if packed == null:
			return fail("Failed to load scene.")
		var root: Node = packed.instantiate()
		if root == null:
			return fail("Failed to instantiate scene.")
		var source: Node = GDAToolScene._resolve_node(root, source_path)
		if source == null:
			root.free()
			return fail("Source node not found: " + source_path)
		var target: Node = GDAToolScene._resolve_node(root, target_path)
		if target == null:
			root.free()
			return fail("Target node not found: " + target_path)
		if not source.has_signal(signal_name):
			root.free()
			return fail("Signal not found on source node: " + signal_name)

		var callable: Callable = Callable(target, method_name)
		if not source.is_connected(signal_name, callable):
			root.free()
			return ok("Signal was not connected.", {
				"scene_path": scene_path,
				"source_node_path": source_path,
				"signal_name": signal_name,
				"target_node_path": target_path,
				"method_name": method_name,
				"was_connected": false,
			})

		source.disconnect(signal_name, callable)

		var commit: Dictionary = GDAToolSignal._commit_scene(root, scene_path, context)
		if not bool(commit["ok"]):
			return fail(str(commit["message"]))
		return ok("Signal disconnected.", {
			"scene_path": scene_path,
			"source_node_path": source_path,
			"signal_name": signal_name,
			"target_node_path": target_path,
			"method_name": method_name,
		})


# ============================================================
# add_to_group
# ============================================================

class AddToGroup extends GDAToolBase:
	func get_name() -> String:
		return "add_to_group"

	func get_description() -> String:
		return "Add a node to a group within a scene."

	func get_parameters_schema() -> Dictionary:
		return {
			"type": "object",
			"properties": {
				"scene_path": {"type": "string"},
				"node_path": {"type": "string"},
				"group_name": {"type": "string"},
			},
			"required": ["scene_path", "node_path", "group_name"],
		}

	func is_mutating() -> bool:
		return true

	func execute(args: Dictionary, context: Dictionary) -> Dictionary:
		var err: String = require_strings(args, ["scene_path", "node_path", "group_name"])
		if not err.is_empty():
			return fail(err)
		var scene_path: String = GDAPathGuard.normalize(str(args["scene_path"]))
		var node_path: String = str(args["node_path"])
		var group_name: String = str(args["group_name"]).strip_edges()

		var guard: Dictionary = GDAPathGuard.validate_scene_path(scene_path)
		if not bool(guard["ok"]):
			return fail(str(guard["message"]))
		if not FileAccess.file_exists(scene_path):
			return fail("Scene not found: " + scene_path)
		var ei: EditorInterface = GDAToolScene._editor_from_context(context)
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
		if node.is_in_group(group_name):
			root.free()
			return ok("Node is already in group.", {
				"scene_path": scene_path,
				"node_path": node_path,
				"group_name": group_name,
				"already_in_group": true,
			})

		node.add_to_group(group_name, true)

		var commit: Dictionary = GDAToolSignal._commit_scene(root, scene_path, context)
		if not bool(commit["ok"]):
			return fail(str(commit["message"]))
		return ok("Node added to group.", {
			"scene_path": scene_path,
			"node_path": node_path,
			"group_name": group_name,
		})


# ============================================================
# remove_from_group
# ============================================================

class RemoveFromGroup extends GDAToolBase:
	func get_name() -> String:
		return "remove_from_group"

	func get_description() -> String:
		return "Remove a node from a group within a scene."

	func get_parameters_schema() -> Dictionary:
		return {
			"type": "object",
			"properties": {
				"scene_path": {"type": "string"},
				"node_path": {"type": "string"},
				"group_name": {"type": "string"},
			},
			"required": ["scene_path", "node_path", "group_name"],
		}

	func is_mutating() -> bool:
		return true

	func execute(args: Dictionary, context: Dictionary) -> Dictionary:
		var err: String = require_strings(args, ["scene_path", "node_path", "group_name"])
		if not err.is_empty():
			return fail(err)
		var scene_path: String = GDAPathGuard.normalize(str(args["scene_path"]))
		var node_path: String = str(args["node_path"])
		var group_name: String = str(args["group_name"]).strip_edges()

		var guard: Dictionary = GDAPathGuard.validate_scene_path(scene_path)
		if not bool(guard["ok"]):
			return fail(str(guard["message"]))
		if not FileAccess.file_exists(scene_path):
			return fail("Scene not found: " + scene_path)
		var ei: EditorInterface = GDAToolScene._editor_from_context(context)
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
		if not node.is_in_group(group_name):
			root.free()
			return ok("Node was not in group.", {
				"scene_path": scene_path,
				"node_path": node_path,
				"group_name": group_name,
				"was_in_group": false,
			})

		node.remove_from_group(group_name)

		var commit: Dictionary = GDAToolSignal._commit_scene(root, scene_path, context)
		if not bool(commit["ok"]):
			return fail(str(commit["message"]))
		return ok("Node removed from group.", {
			"scene_path": scene_path,
			"node_path": node_path,
			"group_name": group_name,
		})


static func build_all() -> Array:
	return [
		ConnectSignal.new(),
		DisconnectSignal.new(),
		AddToGroup.new(),
		RemoveFromGroup.new(),
	]
