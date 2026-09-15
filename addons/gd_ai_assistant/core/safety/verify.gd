@tool
class_name GDAVerify
extends RefCounted

## GD AI Assistant — File Verification
##
## Safety layer 3 of 7. Runs after every write, before the change is
## kept. Returns {ok, message, data}. On failure the caller is expected
## to roll back using the backup created in safety layer 2.
##
## Dispatch by extension:
##   .gd            -> ResourceLoader.load + senior-style linter
##   .tscn          -> PackedScene load + instantiate test
##   .tres / .res   -> Resource load
##   everything else-> basic checks (exists, non-empty, size)
##
## All checks are synchronous. Verification is expected to be fast —
## resource loading for a single small file is milliseconds, not seconds.
##
## File size limits:
##   MAX_FILE_BYTES  — hard cap for any verified file
##   MAX_SCENE_BYTES — scenes are bigger than scripts; separate cap
## Both are checked BEFORE any load, so a huge file never hits the
## resource loader.

const MAX_FILE_BYTES: int = 512 * 1024
const MAX_SCENE_BYTES: int = 4 * 1024 * 1024

# Godot 3 classes. Appearance in a Godot 4 project means a real mistake.
const DEPRECATED_CLASSES: Array[String] = [
	"KinematicBody",
	"KinematicBody2D",
	"KinematicBody3D",
	"Spatial",
	"Position2D",
	"Position3D",
]


# --- Public: main entry -----------------------------------------------

## Verify the file at `path`. Caller is expected to have already written
## it and to have a backup ready if this returns ok=false.
static func verify_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _fail("File does not exist after write: " + path)

	var lower: String = path.to_lower()

	if lower.ends_with(".gd"):
		return _verify_gdscript(path)
	if lower.ends_with(".tscn"):
		return _verify_scene(path)
	if lower.ends_with(".tres") or lower.ends_with(".res"):
		return _verify_resource(path)
	return _verify_basic(path)


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


# --- Public: source-level linter --------------------------------------
# Exposed so future tools (e.g. a "dry run" checker) can call it
# without writing a file first.

## Conservative checks on GDScript source text. Returns {ok, message, data}.
## Only rejects definite Godot 4 mistakes. Does NOT attempt to catch
## subtler issues — those are Godot's parser's job.
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


# --- Internal: linter rules -------------------------------------------
# Each rule is a small function so it can be tested in isolation.

static func _uses_deprecated_class(source: String, class_name_str: String) -> bool:
	# Match "extends Spatial", "extends KinematicBody2D", etc.,
	# or type hints ": Spatial", ": KinematicBody2D" — with word
	# boundaries so "SpatialThing" does not match "Spatial".
	if _has_word_sequence(source, "extends " + class_name_str):
		return true
	if _has_word_sequence(source, ": " + class_name_str):
		return true
	return false


static func _has_move_and_slide_delta_bug(source: String) -> bool:
	if not source.contains("move_and_slide("):
		return false
	# The bug: velocity being multiplied by delta before the call.
	# We look for both the inline and compound-assignment forms.
	if source.contains("velocity * delta"):
		return true
	if source.contains("velocity *= delta"):
		return true
	return false


static func _has_string_signal_connect(source: String) -> bool:
	# Matches .connect(" and .connect(' — the Godot 3 pattern.
	# Godot 4 uses .connect(callable).
	if source.contains(".connect(\""):
		return true
	if source.contains(".connect('"):
		return true
	return false


## True if `needle` appears in `source` and is not part of a longer
## identifier. Cheap approximation: checks the char before/after.
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
	# 0-9, A-Z, a-z, _
	if c >= 48 and c <= 57:
		return true
	if c >= 65 and c <= 90:
		return true
	if c >= 97 and c <= 122:
		return true
	if c == 95:
		return true
	return false


# --- Internal: helpers -------------------------------------------------

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
