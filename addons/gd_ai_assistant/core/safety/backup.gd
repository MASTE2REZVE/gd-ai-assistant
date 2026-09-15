@tool
class_name GDABackup
extends RefCounted

## GD AI Assistant — Backup Engine
##
## Safety layer 2 of 7. Callers must validate the path with GDAPathGuard
## BEFORE calling create_backup(). This class trusts its inputs and
## performs the minimal sanity check described below.
##
## Backups live in user:// — never in res://, so they never pollute the
## user's project or get committed to git.
##
## Filename format:
##   <unix_ms>__<sanitized>_h<hash>.bak
##   - fixed-width unix_ms prefix -> lexicographic sort == chronological
##   - sanitized path (res:// stripped, / -> __, . -> _)
##   - hash suffix avoids collisions between paths that sanitize alike
##
## A ring buffer keeps at most MAX_BACKUPS files on disk. Oldest are
## evicted by filename sort when a new backup pushes the count over.

const BACKUP_DIR: String = "user://gd_ai_assistant_backups"
const MAX_BACKUPS: int = 20
const RES_PREFIX: String = "res://"
const USER_PREFIX: String = "user://"


# --- Public: create / restore / delete --------------------------------

## Snapshot the file at `path` into a new backup. Returns the backup
## path in data.backup_path on success.
static func create_backup(path: String) -> Dictionary:
	if not path.begins_with(RES_PREFIX):
		return _fail("Backup target must be a res:// path.")
	if not FileAccess.file_exists(path):
		return _fail("File does not exist: " + path)
	if not _ensure_dir():
		return _fail("Cannot create backup directory.")

	var src: FileAccess = FileAccess.open(path, FileAccess.READ)
	if src == null:
		return _fail("Cannot open source for backup: " + path)

	var bytes: PackedByteArray = src.get_buffer(src.get_length())
	src.close()

	var backup_path: String = _make_backup_path(path)
	var dst: FileAccess = FileAccess.open(backup_path, FileAccess.WRITE)
	if dst == null:
		return _fail("Cannot open backup for writing: " + backup_path)

	dst.store_buffer(bytes)
	dst.close()

	cleanup_old_backups()

	return {
		"ok": true,
		"message": "",
		"data": { "backup_path": backup_path },
	}


## Copy the backup back over the target path. The target's res:// prefix
## is enforced as a final safety check; full path validation remains the
## caller's responsibility.
static func restore_backup(target_path: String, backup_path: String) -> Dictionary:
	if not target_path.begins_with(RES_PREFIX):
		return _fail("Restore target must be a res:// path.")
	if not backup_path.begins_with(USER_PREFIX):
		return _fail("Backup path must be a user:// path.")
	if not FileAccess.file_exists(backup_path):
		return _fail("Backup does not exist: " + backup_path)

	var src: FileAccess = FileAccess.open(backup_path, FileAccess.READ)
	if src == null:
		return _fail("Cannot read backup: " + backup_path)
	var bytes: PackedByteArray = src.get_buffer(src.get_length())
	src.close()

	var dst: FileAccess = FileAccess.open(target_path, FileAccess.WRITE)
	if dst == null:
		return _fail("Cannot write restore target: " + target_path)
	dst.store_buffer(bytes)
	dst.close()

	return _ok()


## Remove a single backup file. Silent success if it is already gone.
static func delete_backup(backup_path: String) -> Dictionary:
	if not backup_path.begins_with(USER_PREFIX):
		return _fail("Not a backup path: " + backup_path)
	if not FileAccess.file_exists(backup_path):
		return _ok()
	var err: Error = DirAccess.remove_absolute(
		ProjectSettings.globalize_path(backup_path)
	)
	if err != OK:
		return _fail("Could not delete backup: " + backup_path)
	return _ok()


# --- Public: queries --------------------------------------------------

## All backups for a given res:// path, oldest first.
static func list_backups_for(path: String) -> Array:
	var suffix: String = "__" + _backup_key(path) + ".bak"
	var out: Array = []
	var dir: DirAccess = DirAccess.open(BACKUP_DIR)
	if dir == null:
		return out
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while not name.is_empty():
		if not dir.current_is_dir() and name.ends_with(suffix):
			out.append(BACKUP_DIR.path_join(name))
		name = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return out


## Newest backup for a res:// path, or "" if none exist.
static func get_latest_backup(path: String) -> String:
	var list: Array = list_backups_for(path)
	if list.is_empty():
		return ""
	return str(list[list.size() - 1])


## Number of backup files on disk right now.
static func count_backups() -> int:
	var dir: DirAccess = DirAccess.open(BACKUP_DIR)
	if dir == null:
		return 0
	var n: int = 0
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while not name.is_empty():
		if not dir.current_is_dir() and name.ends_with(".bak"):
			n += 1
		name = dir.get_next()
	dir.list_dir_end()
	return n


# --- Public: maintenance ----------------------------------------------

## Enforce MAX_BACKUPS. Called automatically after every successful
## create_backup(). Safe to call anytime.
static func cleanup_old_backups() -> void:
	var dir: DirAccess = DirAccess.open(BACKUP_DIR)
	if dir == null:
		return
	var files: Array[String] = []
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while not name.is_empty():
		if not dir.current_is_dir() and name.ends_with(".bak"):
			files.append(name)
		name = dir.get_next()
	dir.list_dir_end()

	if files.size() <= MAX_BACKUPS:
		return

	files.sort()
	var to_remove: int = files.size() - MAX_BACKUPS
	for i: int in range(to_remove):
		var full_path: String = BACKUP_DIR.path_join(files[i])
		DirAccess.remove_absolute(ProjectSettings.globalize_path(full_path))


# --- Internal ---------------------------------------------------------

static func _ensure_dir() -> bool:
	if DirAccess.dir_exists_absolute(BACKUP_DIR):
		return true
	return DirAccess.make_dir_recursive_absolute(BACKUP_DIR) == OK


static func _make_backup_path(path: String) -> String:
	var ts_ms: int = int(Time.get_unix_time_from_system() * 1000.0)
	var filename: String = "%d__%s.bak" % [ts_ms, _backup_key(path)]
	return BACKUP_DIR.path_join(filename)


## Deterministic, filename-safe key for a path. Not reversible — do not
## try to reconstruct the original path from this. The hash suffix
## ensures distinct paths never share a key even after sanitization.
static func _backup_key(path: String) -> String:
	var normalized: String = (
		path.strip_edges().replace("\\", "/").trim_prefix(RES_PREFIX)
	)
	var sanitized: String = (
		normalized.replace("/", "__").replace(".", "_")
	)
	return sanitized + "_h" + str(path.hash())


static func _ok() -> Dictionary:
	return { "ok": true, "message": "", "data": {} }


static func _fail(message: String) -> Dictionary:
	return { "ok": false, "message": message, "data": {} }
