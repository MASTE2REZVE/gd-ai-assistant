@tool
class_name GDAVerify
extends RefCounted

## GD AI Assistant — File Verification
##
## Safety layer 4 of 7. Runs after every write, before the change is
## kept. Returns {ok, message, data}. On failure the caller is expected
## to roll back using the backup created in safety layer 3.
##
## Dispatch by extension:
##   .gd            -> ResourceLoader.load + senior-style linter
##   .tscn          -> PackedScene load + instantiate test
##   .tres / .res   -> Resource load
##   everything else-> basic checks (exists, non-empty, size)
##
## After a successful verification we ask Godot's EditorFileSystem to
## rescan so new/changed files appear in the FileSystem dock and
## class_name declarations register immediately — no project reload
## required. The scan is deferred so it runs after the current
## write/verify call unwinds, never mid-operation.

const MAX_FILE_BYTES: int = 512 * 1024
const MAX_SCENE_BYTES: int = 4 * 1024 * 1024

const DEPRECATED_CLASSES: Array[String] = [
	"KinematicBody",
	"KinematicBody2D",
	"KinematicBody3D",
	"Spatial",
	"Position2D",
	"Position3D",
]


static func verify_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _fail("File does not exist after write: " + path)

	var lower: String = path.to_lower()
	var result: Dictionary

	if lower.ends_with(".gd"):
		result = _verify_gdscript(path)
	elif lower.ends_with(".tscn"):
		result = _verify_scene(path)
	elif lower.ends_with(".tres") or lower.ends_with(".res"):
		result = _verify_resource(path)
	else:
		result = _verify_basic(path)

	if bool(result.get("ok", false)):
		_refresh_editor_filesystem(path)

	return result


## Ask Godot's editor to rescan so the written file is visible
## immediately. Safe to call from any editor context; no-op outside the
## editor. Uses call_deferred so the scan happens after this call
## returns — avoids re-entrant file operations during a write.
static func _refresh_editor_filesystem(path: String) -> void:
	if not Engine.is_editor_hint():
		return
	var fs: EditorFileSystem = EditorInterface.get_resource_filesystem()
	if fs == null:
		return
	# update_file is the lightweight path for a known file; scan() is
	# the full-tree rescan. We try update_file first, then scan, so
	# both new files (not yet in the tree) and changed files (already
	# known) end up correct.
	if FileAccess.file_exists(path):
		fs.call_deferred("update_file", path)
	fs.call_deferred("scan")


# --- Per-type verifiers -----------------------------------------------

static func _verify_gdscript(path: String) -> Dictionary:
	var size_check: Dictionary = _check_size(path, MAX_FILE_BYTES)
	if not bool(size_check.get("ok", false)):
		return size_check

	var loaded: Resource = ResourceLoader.load(
		path, "GDScript", ResourceLoader.CACHE_MODE_IGNORE
	)
	if loaded == null or not (loaded is GDScript):
		return _fail(
			"GDScript failed to load. Likely a parse error: " + path
		)

	var text: String = _read_all_text(path)
	if text.is_empty():
		return _fail("GDScript became empty after write: " + path)

	var lint: Dictionary = lint_gdscript_source(text)
	if not bool(lint.get("ok", false)):
		return lint

	return _ok("GDScript verified: " + path)


static func _verify_scene(path: String) -> Dictionary:
	var size_check: Dictionary = _check_size(path, MAX_SCENE_BYTES)
	if not bool(size_check.get("ok", false)):
		return size_check

	var packed: Resource = ResourceLoader.load(
		path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE
	)
	if packed == null or not (packed is PackedScene):
		return _fail("PackedScene failed to load: " + path)

	var instance: Node = (packed as PackedScene).instantiate()
	if instance == null:
		return _fail("PackedScene failed to instantiate: " + path)
	instance.free()

	return _ok("Scene verified: " + path)


static func _verify_resource(path: String) -> Dictionary:
	var size_check: Dictionary = _check_size(path, MAX_FILE_BYTES)
	if not bool(size_check.get("ok", false)):
		return size_check

	var res: Resource = ResourceLoader.load(
		path, "Resource", ResourceLoader.CACHE_MODE_IGNORE
	)
	if res == null:
		return _fail("Resource failed to load: " + path)

	return _ok("Resource verified: " + path)


static func _verify_basic(path: String) -> Dictionary:
	var size_check: Dictionary = _check_size(path, MAX_FILE_BYTES)
	if not bool(size_check.get("ok", false)):
		return size_check

	var text: String = _read_all_text(path)
	if text.is_empty():
		return _fail("File is empty after write: " + path)

	return _ok("File verified (basic): " + path)


# --- Linter -----------------------------------------------------------

static func lint_gdscript_source(source: String) -> Dictionary:
	for deprecated: String in DEPRECATED_CLASSES:
		if _uses_deprecated_class(source, deprecated):
			return _fail(
				"Linter rejected: Godot 3 class '%s' used. Use the Godot 4 equivalent."
				% deprecated
			)

	if _has_move_and_slide_delta_bug(source):
		return _fail(
			"Linter rejected: move_and_slide() already applies delta. "
			+ "Do not multiply velocity by delta before calling it."
		)

	if _has_string_signal_connect(source):
		return _fail(
			"Linter rejected: string-based signal connection detected. "
			+ "Use signal_name.connect(callable) in Godot 4."
		)

	return _ok("Linter passed.")


static func _uses_deprecated_class(source: String, class_name_str: String) -> bool:
	if _has_word_sequence(source, "extends " + class_name_str):
		return true
	if _has_word_sequence(source, ": " + class_name_str):
		return true
	return false


static func _has_move_and_slide_delta_bug(source: String) -> bool:
	if not source.contains("move_and_slide("):
		return false
	if source.contains("velocity * delta"):
		return true
	if source.contains("velocity *= delta"):
		return true
	return false


static func _has_string_signal_connect(source: String) -> bool:
	if source.contains(".connect(\""):
		return true
	if source.contains(".connect('"):
		return true
	return false


static func _has_word_sequence(source: String, needle: String) -> bool:
	var start: int = 0
	while true:
		var idx: int = source.find(needle, start)
		if idx == -1:
			return false
		var end_idx: int = idx + needle.length()
		var before_ok: bool = (
			idx == 0
			or not _is_word_char(source.unicode_at(idx - 1))
		)
		var after_ok: bool = (
			end_idx >= source.length()
			or not _is_word_char(source.unicode_at(end_idx))
		)
		if before_ok and after_ok:
			return true
		start = idx + 1
	return false


static func _is_word_char(c: int) -> bool:
	if c >= 48 and c <= 57:
		return true
	if c >= 65 and c <= 90:
		return true
	if c >= 97 and c <= 122:
		return true
	if c == 95:
		return true
	return false


# --- Helpers ----------------------------------------------------------

static func _check_size(path: String, max_bytes: int) -> Dictionary:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return _fail("Cannot reopen file for size check: " + path)
	var size: int = f.get_length()
	f.close()
	if size > max_bytes:
		return _fail(
			"File exceeds size limit (%d > %d bytes): %s"
			% [size, max_bytes, path]
		)
	return _ok()


static func _read_all_text(path: String) -> String:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var text: String = f.get_as_text()
	f.close()
	return text


static func _ok(message: String = "") -> Dictionary:
	return { "ok": true, "message": message, "data": {} }


static func _fail(message: String) -> Dictionary:
	return { "ok": false, "message": message, "data": {} }
