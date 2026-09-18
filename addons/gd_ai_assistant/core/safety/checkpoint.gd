@tool
class_name GDACheckpoint
extends RefCounted

const CHECKPOINT_DIR: String = "user://gd_ai_assistant_checkpoints"
const MAX_CHECKPOINTS: int = 30
const RES_PREFIX: String = "res://"


static func begin(label: String, created_by: String = "agent") -> String:
	if not _ensure_dir():
		return ""
	var id: String = _make_id()
	var dir: String = _checkpoint_dir(id)
	var mkdir_err: Error = DirAccess.make_dir_recursive_absolute(dir)
	if mkdir_err != OK:
		return ""
	var meta: Dictionary = {
		"id": id,
		"label": label,
		"created_by": created_by,
		"timestamp": int(Time.get_unix_time_from_system()),
		"files": [],
	}
	if not _write_meta(id, meta):
		return ""
	return id


static func snapshot_file(checkpoint_id: String, path: String) -> Dictionary:
	if checkpoint_id.is_empty():
		return _fail("Empty checkpoint id.")
	if not path.begins_with(RES_PREFIX):
		return _fail("Only res:// paths can be snapshotted.")
	var meta: Dictionary = _read_meta(checkpoint_id)
	if meta.is_empty():
		return _fail("Checkpoint not found: " + checkpoint_id)
	var files: Array = meta.get("files", [])
	var normalized: String = _normalize(path)
	for entry: Variant in files:
		if entry is Dictionary and str(entry.get("path", "")) == normalized:
			return _ok({"path": normalized, "already": true})
	var snap_name: String = _snap_name(normalized)
	var snap_path: String = _checkpoint_dir(checkpoint_id).path_join(snap_name)
	if FileAccess.file_exists(path):
		var src: FileAccess = FileAccess.open(path, FileAccess.READ)
		if src == null:
			return _fail("Cannot read file to snapshot: " + path)
		var bytes: PackedByteArray = src.get_buffer(src.get_length())
		src.close()
		var dst: FileAccess = FileAccess.open(snap_path, FileAccess.WRITE)
		if dst == null:
			return _fail("Cannot write snapshot: " + snap_path)
		dst.store_buffer(bytes)
		dst.close()
		files.append({"path": normalized, "existed": true, "snapshot": snap_name})
	else:
		files.append({"path": normalized, "existed": false, "snapshot": ""})
	meta["files"] = files
	if not _write_meta(checkpoint_id, meta):
		return _fail("Failed to update checkpoint metadata.")
	return _ok({"path": normalized, "already": false})


static func restore(checkpoint_id: String) -> Dictionary:
	var meta: Dictionary = _read_meta(checkpoint_id)
	if meta.is_empty():
		return _fail("Checkpoint not found: " + checkpoint_id)
	var files: Array = meta.get("files", [])
	var restored: Array = []
	var failed: Array = []
	for entry_v: Variant in files:
		if not (entry_v is Dictionary):
			continue
		var entry: Dictionary = entry_v
		var path: String = str(entry.get("path", ""))
		if not path.begins_with(RES_PREFIX):
			failed.append({"path": path, "reason": "not a res:// path"})
			continue
		var existed: bool = bool(entry.get("existed", false))
		if not existed:
			if FileAccess.file_exists(path):
				var err: Error = DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
				if err == OK:
					restored.append(path)
				else:
					failed.append({"path": path, "reason": "delete failed"})
			else:
				restored.append(path)
			continue
		var snap_name: String = str(entry.get("snapshot", ""))
		if snap_name.is_empty():
			failed.append({"path": path, "reason": "missing snapshot"})
			continue
		var snap_path: String = _checkpoint_dir(checkpoint_id).path_join(snap_name)
		if not FileAccess.file_exists(snap_path):
			failed.append({"path": path, "reason": "snapshot file missing"})
			continue
		var src: FileAccess = FileAccess.open(snap_path, FileAccess.READ)
		if src == null:
			failed.append({"path": path, "reason": "cannot read snapshot"})
			continue
		var bytes: PackedByteArray = src.get_buffer(src.get_length())
		src.close()
		var dst: FileAccess = FileAccess.open(path, FileAccess.WRITE)
		if dst == null:
			failed.append({"path": path, "reason": "cannot write target"})
			continue
		dst.store_buffer(bytes)
		dst.close()
		restored.append(path)
	return _ok({"restored": restored, "failed": failed, "total": restored.size() + failed.size()})


static func discard(checkpoint_id: String) -> Dictionary:
	if checkpoint_id.is_empty():
		return _ok({})
	var meta_path: String = _meta_path(checkpoint_id)
	var dir_path: String = _checkpoint_dir(checkpoint_id)
	if FileAccess.file_exists(meta_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(meta_path))
	_remove_dir_recursive(dir_path)
	return _ok({})


static func list_ids() -> Array:
	var out: Array = []
	var dir: DirAccess = DirAccess.open(CHECKPOINT_DIR)
	if dir == null:
		return out
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while not name.is_empty():
		if not dir.current_is_dir() and name.ends_with(".json"):
			out.append(name.trim_suffix(".json"))
		name = dir.get_next()
	dir.list_dir_end()
	out.sort()
	out.reverse()
	return out


static func get_checkpoint_meta(checkpoint_id: String) -> Dictionary:
	return _read_meta(checkpoint_id)


static func latest_id() -> String:
	var ids: Array = list_ids()
	if ids.is_empty():
		return ""
	return str(ids[0])


static func cleanup_old() -> void:
	var ids: Array = list_ids()
	if ids.size() <= MAX_CHECKPOINTS:
		return
	var to_remove: int = ids.size() - MAX_CHECKPOINTS
	for i: int in range(to_remove):
		var id: String = str(ids[ids.size() - 1 - i])
		discard(id)


static func _meta_path(checkpoint_id: String) -> String:
	return CHECKPOINT_DIR.path_join(checkpoint_id + ".json")


static func _checkpoint_dir(checkpoint_id: String) -> String:
	return CHECKPOINT_DIR.path_join(checkpoint_id)


static func _snap_name(path: String) -> String:
	var trimmed: String = path.trim_prefix(RES_PREFIX)
	var sanitized: String = trimmed.replace("/", "__").replace(".", "_")
	return sanitized + "_h" + str(path.hash()) + ".bin"


static func _normalize(path: String) -> String:
	return path.strip_edges().replace("\\", "/")


static func _make_id() -> String:
	var ms: int = int(Time.get_unix_time_from_system() * 1000.0)
	var suffix: int = randi() % 10000
	return "%d_%04d" % [ms, suffix]


static func _ensure_dir() -> bool:
	if DirAccess.dir_exists_absolute(CHECKPOINT_DIR):
		return true
	return DirAccess.make_dir_recursive_absolute(CHECKPOINT_DIR) == OK


static func _read_meta(checkpoint_id: String) -> Dictionary:
	var p: String = _meta_path(checkpoint_id)
	if not FileAccess.file_exists(p):
		return {}
	var f: FileAccess = FileAccess.open(p, FileAccess.READ)
	if f == null:
		return {}
	var text: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		return parsed
	return {}


static func _write_meta(checkpoint_id: String, meta: Dictionary) -> bool:
	var p: String = _meta_path(checkpoint_id)
	var f: FileAccess = FileAccess.open(p, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(meta, "\t"))
	f.close()
	return true


static func _remove_dir_recursive(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var n: String = dir.get_next()
	while not n.is_empty():
		var full: String = path.path_join(n)
		if dir.current_is_dir():
			_remove_dir_recursive(full)
		else:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(full))
		n = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


static func _ok(data: Variant = {}) -> Dictionary:
	return { "ok": true, "message": "", "data": data }


static func _fail(message: String) -> Dictionary:
	return { "ok": false, "message": message, "data": {} }
