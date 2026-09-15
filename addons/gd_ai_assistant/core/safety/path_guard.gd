@tool
class_name GDAPathGuard
extends RefCounted

## GD AI Assistant — Path Guard
##
## Safety layer 1 of 7. Every file operation in the plugin — read, write,
## patch, delete, scene save — must pass through a validate_* method here
## before any FileAccess / DirAccess / ResourceSaver call is made.
##
## Rules enforced:
##   - Paths must be inside res:// and inside the user's project
##   - ".." is forbidden anywhere in the path
##   - Trailing slash means "directory" and is rejected
##   - A block list prevents the AI from editing project.godot, Godot's
##     own caches, .uid / .import files, or the plugin's own source
##
## This file is pure. No I/O, no editor APIs, no state.
## Return shape is the anchor's canonical tool shape minus "data":
##   { "ok": bool, "message": String }


const RES_PREFIX: String = "res://"
const PLUGIN_ROOT: String = "res://addons/gd_ai_assistant/"

# Exact paths that can never be touched by the AI.
const PROTECTED_EXACT: Array[String] = [
	"res://project.godot",
]

# Prefixes — any path that starts with one of these is protected.
# All stored lowercase; comparisons are case-insensitive.
const PROTECTED_PREFIXES: Array[String] = [
	"res://.godot/",
	"res://.git/",
	"res://.import/",
	"res://addons/gd_ai_assistant/",
]

# Suffixes — any path that ends with one of these is protected.
const PROTECTED_SUFFIXES: Array[String] = [
	".uid",
	".import",
]


# --- Public: validation entry points ----------------------------------

## For read operations. Lenient: only enforces res:// + no "..".
## Existence is the caller's concern (readers check before opening).
static func validate_read_path(path: String) -> Dictionary:
	var norm: String = normalize(path)
	var base_error: String = _check_base(norm)
	if not base_error.is_empty():
		return _fail(base_error)
	return _ok()


## For text writes (scripts, .json, .cfg files inside the project).
## Blocks protected paths and .tscn (which must use scene_ops).
static func validate_text_write_path(path: String) -> Dictionary:
	var norm: String = normalize(path)
	var base_error: String = _check_base(norm)
	if not base_error.is_empty():
		return _fail(base_error)
	if is_protected(norm):
		return _fail("Path is protected: " + norm)
	if is_tscn(norm):
		return _fail(
			".tscn files cannot be written as text. Use scene tools instead."
		)
	return _ok()


## For scene operations (PackedScene load/save). Requires .tscn.
static func validate_scene_path(path: String) -> Dictionary:
	var norm: String = normalize(path)
	var base_error: String = _check_base(norm)
	if not base_error.is_empty():
		return _fail(base_error)
	if not is_tscn(norm):
		return _fail("Scene path must end with .tscn: " + norm)
	if is_protected(norm):
		return _fail("Path is protected: " + norm)
	return _ok()


## For delete operations. Same constraints as text writes.
static func validate_delete_path(path: String) -> Dictionary:
	return validate_text_write_path(path)


# --- Public: predicates -----------------------------------------------

static func normalize(path: String) -> String:
	return path.strip_edges().replace("\\", "/")


static func is_tscn(path: String) -> bool:
	return normalize(path).to_lower().ends_with(".tscn")


static func is_gdscript(path: String) -> bool:
	return normalize(path).to_lower().ends_with(".gd")


static func is_inside_plugin(path: String) -> bool:
	return normalize(path).to_lower().begins_with(PLUGIN_ROOT)


static func is_protected(path: String) -> bool:
	var norm: String = normalize(path).to_lower()

	for exact: String in PROTECTED_EXACT:
		if norm == exact:
			return true

	for prefix: String in PROTECTED_PREFIXES:
		if norm.begins_with(prefix):
			return true

	for suffix: String in PROTECTED_SUFFIXES:
		if norm.ends_with(suffix):
			return true

	return false


# --- Internal ---------------------------------------------------------

## Shared checks used by every validate_*. Returns "" on success or a
## human-readable error on the first violation found. The order of
## checks is deliberate: cheapest and most general first.
static func _check_base(norm: String) -> String:
	if norm.is_empty():
		return "Empty path."
	if not norm.begins_with(RES_PREFIX):
		return "Only res:// paths are allowed."
	if norm.contains(".."):
		return "Parent-directory paths are forbidden."
	if norm.ends_with("/"):
		return "Expected a file, not a directory."
	if norm == RES_PREFIX:
		return "Path resolves to the project root, not a file."
	return ""


static func _ok() -> Dictionary:
	return { "ok": true, "message": "" }


static func _fail(message: String) -> Dictionary:
	return { "ok": false, "message": message }
