@tool
class_name GDAToolProject
extends RefCounted

## GD AI Assistant — Project Tools
##
## Six tools in one file, exposed as inner classes that extend
## GDAToolBase. The registry (core/tool_registry.gd) instantiates each
## one and adds them to the tool list.
##
##   get_project_info  — project name, main scene, top-level entries
##   list_files        — list a directory (files + subdirs), one level
##   search_files      — substring search across text files in a folder
##   read_file         — read a text file (capped)
##   write_file        — safe write (backup -> verify -> rollback)
##   patch_file        — safe patch (unique match, backup -> verify -> rollback)
##
## Read-before-edit is NOT enforced here. That is agent-turn state and
## lives in the harness (core/harness.gd). Tools just execute.

const MAX_READ_BYTES: int = 512 * 1024
const MAX_WRITE_BYTES: int = 512 * 1024
const MAX_SEARCH_RESULTS: int = 100
const MAX_SEARCH_BYTES_PER_FILE: int = 256 * 1024
const MAX_LINE_PREVIEW: int = 200

# File extensions we treat as text for search. Anything else is skipped.
const TEXT_EXTS: Array[String] = [
	".gd", ".tscn", ".tres", ".res", ".json", ".cfg", ".ini",
	".txt", ".md", ".csv", ".xml", ".yaml", ".yml", ".shader",
	".gdshader", ".gdshaderinc", ".import", ".uid",
]


# ============================================================
# get_project_info
# ============================================================

class GetProjectInfo extends GDAToolBase:
	func get_name() -> String:
		return "get_project_info"

	func get_description() -> String:
		return (
			"Return basic information about the Godot project: name, "
			+ "main scene, and top-level files/folders under res://."
		)

	func get_parameters_schema() -> Dictionary:
		return {"type": "object", "properties": {}, "required": []}

	func execute(_args: Dictionary, _context: Dictionary) -> Dictionary:
		var proj_name: String = str(
			ProjectSettings.get_setting("application/config/name", "Unnamed")
		)
		var main_scene: String = str(
			ProjectSettings.get_setting("application/run/main_scene", "")
		)

		var top: Array = []
		var dir: DirAccess = DirAccess.open("res://")
		if dir != null:
			dir.list_dir_begin()
			var n: String = dir.get_next()
			while not n.is_empty():
				if not n.begins_with("."):
					top.append(n + ("/" if dir.current_is_dir() else ""))
				n = dir.get_next()
			dir.list_dir_end()

		return ok("", {
			"name": proj_name,
			"main_scene": main_scene,
			"top_level": top,
		})


# ============================================================
# list_files
# ============================================================

class ListFiles extends GDAToolBase:
	func get_name() -> String:
		return "list_files"

	func get_description() -> String:
		return (
			"List the immediate contents of a res:// directory. Returns "
			+ "files and subdirectories. Does not recurse."
		)

	func get_parameters_schema() -> Dictionary:
		return {
			"type": "object",
			"properties": {
				"path": {
					"type": "string",
					"description": "res:// directory path. Use res:// for project root.",
				},
			},
			"required": ["path"],
		}

	func execute(args: Dictionary, _context: Dictionary) -> Dictionary:
		var err: String = require_strings(args, ["path"])
		if not err.is_empty():
			return fail(err)

		var path: String = GDAPathGuard.normalize(str(args["path"]))
		if not path.begins_with("res://"):
			return fail("Only res:// paths are allowed.")
		if not path.ends_with("/"):
			path += "/"

		var dir: DirAccess = DirAccess.open(path)
		if dir == null:
			return fail("Cannot open directory: " + path)

		var files: Array = []
		var dirs: Array = []
		dir.list_dir_begin()
		var n: String = dir.get_next()
		while not n.is_empty():
			if not n.begins_with("."):
				if dir.current_is_dir():
					dirs.append(n + "/")
				else:
					files.append(n)
			n = dir.get_next()
		dir.list_dir_end()

		files.sort()
		dirs.sort()

		return ok("", {"path": path, "dirs": dirs, "files": files})


# ============================================================
# search_files
# ============================================================

class SearchFiles extends GDAToolBase:
	func get_name() -> String:
		return "search_files"

	func get_description() -> String:
		return (
			"Search for a plain substring across text files under a "
			+ "res:// directory. Recurses. Returns up to %d matches."
			% MAX_SEARCH_RESULTS
		)

	func get_parameters_schema() -> Dictionary:
		return {
			"type": "object",
			"properties": {
				"path": {
					"type": "string",
					"description": "res:// directory to search.",
				},
				"query": {
					"type": "string",
					"description": "Substring to look for (case-sensitive).",
				},
			},
			"required": ["path", "query"],
		}

	func execute(args: Dictionary, _context: Dictionary) -> Dictionary:
		var err: String = require_strings(args, ["path", "query"])
		if not err.is_empty():
			return fail(err)

		var root: String = GDAPathGuard.normalize(str(args["path"]))
		var query: String = str(args["query"])
		if not root.begins_with("res://"):
			return fail("Only res:// paths are allowed.")
		if not root.ends_with("/"):
			root += "/"
		if query.is_empty():
			return fail("Query is empty.")

		var matches: Array = []
		var truncated: bool = false
		_scan(root, query, matches, [truncated])
		truncated = bool(matches.back()) if (
			not matches.is_empty() and matches.back() is bool
		) else false
		# Remove the sentinel that _scan may have appended.
		if not matches.is_empty() and matches.back() is bool:
			matches.pop_back()

		return ok("", {
			"path": root,
			"query": query,
			"matches": matches,
			"truncated": truncated,
		})

	func _scan(dir_path: String, query: String, out: Array, flags: Array) -> void:
		if bool(flags[0]):
			return
		var dir: DirAccess = DirAccess.open(dir_path)
		if dir == null:
			return
		dir.list_dir_begin()
		var n: String = dir.get_next()
		while not n.is_empty():
			if bool(flags[0]):
				dir.list_dir_end()
				return
			if not n.begins_with("."):
				var full: String = dir_path.path_join(n)
				if dir.current_is_dir():
					if n != ".godot" and n != ".git":
						_scan(full, query, out, flags)
				else:
					_search_one(full, query, out, flags)
			n = dir.get_next()
		dir.list_dir_end()

	func _search_one(file_path: String, query: String, out: Array, flags: Array) -> void:
		var lower: String = file_path.to_lower()
		var is_text: bool = false
		for ext: String in TEXT_EXTS:
			if lower.ends_with(ext):
				is_text = true
				break
		if not is_text:
			return

		var f: FileAccess = FileAccess.open(file_path, FileAccess.READ)
		if f == null:
			return
		if f.get_length() > MAX_SEARCH_BYTES_PER_FILE:
			f.close()
			return

		var content: String = f.get_as_text()
		f.close()

		if not content.contains(query):
			return

		var lines: PackedStringArray = content.split("\n")
		for i: int in range(lines.size()):
			if out.size() >= MAX_SEARCH_RESULTS:
				flags[0] = true
				return
			var line: String = lines[i]
			if line.contains(query):
				var preview: String = line.strip_edges()
				if preview.length() > MAX_LINE_PREVIEW:
					preview = preview.substr(0, MAX_LINE_PREVIEW) + "..."
				out.append({
					"file": file_path,
					"line": i + 1,
					"preview": preview,
				})


# ============================================================
# read_file
# ============================================================

class ReadFile extends GDAToolBase:
	func get_name() -> String:
		return "read_file"

	func get_description() -> String:
		return (
			"Read a res:// text file. Returns its content and size. "
			+ "Fails on files larger than %d bytes." % MAX_READ_BYTES
		)

	func get_parameters_schema() -> Dictionary:
		return {
			"type": "object",
			"properties": {
				"path": {"type": "string", "description": "res:// file path."},
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
			return fail("File not found: " + path)

		var f: FileAccess = FileAccess.open(path, FileAccess.READ)
		if f == null:
			return fail("Cannot open: " + path)
		var length: int = f.get_length()
		if length > MAX_READ_BYTES:
			f.close()
			return fail(
				"File too large to read (%d > %d bytes): %s"
				% [length, MAX_READ_BYTES, path]
			)
		var content: String = f.get_as_text()
		f.close()

		return ok("", {
			"path": path,
			"content": content,
			"size": length,
		})


# ============================================================
# write_file
# ============================================================

class WriteFile extends GDAToolBase:
	func get_name() -> String:
		return "write_file"

	func get_description() -> String:
		return (
			"Write full text content to a res:// file. Backs up any "
			+ "existing file, verifies the result, and rolls back on "
			+ "failure. Refuses .tscn and protected paths."
		)

	func get_parameters_schema() -> Dictionary:
		return {
			"type": "object",
			"properties": {
				"path": {"type": "string", "description": "res:// file path."},
				"content": {"type": "string", "description": "Full text to write."},
			},
			"required": ["path", "content"],
		}

	func is_mutating() -> bool:
		return true

	func execute(args: Dictionary, _context: Dictionary) -> Dictionary:
		var err: String = require_strings(args, ["path", "content"])
		if not err.is_empty():
			return fail(err)

		var path: String = GDAPathGuard.normalize(str(args["path"]))
		var content: String = str(args["content"])

		var guard: Dictionary = GDAPathGuard.validate_text_write_path(path)
		if not bool(guard["ok"]):
			return fail(str(guard["message"]))

		if content.is_empty():
			return fail("Empty content is not allowed.")

		var byte_size: int = content.to_utf8_buffer().size()
		if byte_size > MAX_WRITE_BYTES:
			return fail(
				"Content too large (%d > %d bytes)."
				% [byte_size, MAX_WRITE_BYTES]
			)

		var existed: bool = FileAccess.file_exists(path)
		var backup_path: String = ""
		if existed:
			var backup_result: Dictionary = GDABackup.create_backup(path)
			if not bool(backup_result["ok"]):
				return fail(
					"Backup failed: " + str(backup_result["message"])
				)
			backup_path = str(backup_result["data"].get("backup_path", ""))

		var writer: FileAccess = FileAccess.open(path, FileAccess.WRITE)
		if writer == null:
			if existed and not backup_path.is_empty():
				GDABackup.restore_backup(path, backup_path)
			return fail("Cannot open for write: " + path)
		writer.store_string(content)
		writer.close()

		var verify_result: Dictionary = GDAVerify.verify_file(path)
		if not bool(verify_result["ok"]):
			var restored: bool = _rollback(path, existed, backup_path)
			return fail(
				"Verification failed: %s%s"
				% [
					str(verify_result["message"]),
					" (rolled back)" if restored else " (ROLLBACK FAILED)",
				]
			)

		if existed and not backup_path.is_empty():
			GDABackup.delete_backup(backup_path)

		return ok(
			"Written and verified.",
			{"path": path, "bytes": byte_size, "existed": existed}
		)

	func _rollback(path: String, existed: bool, backup_path: String) -> bool:
		if existed and not backup_path.is_empty():
			var r: Dictionary = GDABackup.restore_backup(path, backup_path)
			return bool(r["ok"])
		# New file: delete it to undo.
		return (
			DirAccess.remove_absolute(
				ProjectSettings.globalize_path(path)
			) == OK
		)


# ============================================================
# patch_file
# ============================================================

class PatchFile extends GDAToolBase:
	func get_name() -> String:
		return "patch_file"

	func get_description() -> String:
		return (
			"Replace a unique substring in an existing res:// file. The "
			+ "old_text must occur exactly once. Reads the file, patches, "
			+ "backups, verifies, and rolls back on failure. Refuses .tscn "
			+ "and protected paths. Use this instead of write_file for "
			+ "small surgical edits."
		)

	func get_parameters_schema() -> Dictionary:
		return {
			"type": "object",
			"properties": {
				"path": {"type": "string", "description": "res:// file path."},
				"old_text": {
					"type": "string",
					"description": "Exact text to find. Must occur exactly once.",
				},
				"new_text": {
					"type": "string",
					"description": "Replacement text.",
				},
			},
			"required": ["path", "old_text", "new_text"],
		}

	func is_mutating() -> bool:
		return true

	func execute(args: Dictionary, _context: Dictionary) -> Dictionary:
		var err: String = require_strings(args, ["path", "old_text", "new_text"])
		if not err.is_empty():
			return fail(err)

		var path: String = GDAPathGuard.normalize(str(args["path"]))
		var old_text: String = str(args["old_text"])
		var new_text: String = str(args["new_text"])

		var guard: Dictionary = GDAPathGuard.validate_text_write_path(path)
		if not bool(guard["ok"]):
			return fail(str(guard["message"]))

		if not FileAccess.file_exists(path):
			return fail("File not found: " + path)

		if old_text == new_text:
			return fail("old_text and new_text are identical.")

		var reader: FileAccess = FileAccess.open(path, FileAccess.READ)
		if reader == null:
			return fail("Cannot read file: " + path)
		if reader.get_length() > MAX_READ_BYTES:
			reader.close()
			return fail("File too large to patch safely.")
		var original: String = reader.get_as_text()
		reader.close()

		var count: int = _count_occurrences(original, old_text)
		if count == 0:
			return fail(
				"old_text was not found. Read the file first and copy "
				+ "the exact text."
			)
		if count > 1:
			return fail(
				"old_text occurs %d times. Make the match more specific."
				% count
			)

		var updated: String = original.replace(old_text, new_text)
		if updated == original:
			return fail("Patch produced no change.")

		var byte_size: int = updated.to_utf8_buffer().size()
		if byte_size > MAX_WRITE_BYTES:
			return fail("Result too large (%d bytes)." % byte_size)

		var backup_result: Dictionary = GDABackup.create_backup(path)
		if not bool(backup_result["ok"]):
			return fail("Backup failed: " + str(backup_result["message"]))
		var backup_path: String = str(
			backup_result["data"].get("backup_path", "")
		)

		var writer: FileAccess = FileAccess.open(path, FileAccess.WRITE)
		if writer == null:
			GDABackup.restore_backup(path, backup_path)
			return fail("Cannot open for write: " + path)
		writer.store_string(updated)
		writer.close()

		var verify_result: Dictionary = GDAVerify.verify_file(path)
		if not bool(verify_result["ok"]):
			var r: Dictionary = GDABackup.restore_backup(path, backup_path)
			var restored: bool = bool(r["ok"])
			return fail(
				"Verification failed: %s%s"
				% [
					str(verify_result["message"]),
					" (rolled back)" if restored else " (ROLLBACK FAILED)",
				]
			)

		GDABackup.delete_backup(backup_path)

		return ok(
			"Patched and verified (1 replacement).",
			{"path": path, "bytes": byte_size}
		)

	func _count_occurrences(text: String, target: String) -> int:
		if target.is_empty():
			return 0
		var count: int = 0
		var offset: int = 0
		while true:
			var idx: int = text.find(target, offset)
			if idx == -1:
				break
			count += 1
			offset = idx + target.length()
		return count


# ============================================================
# Registration helper
# ============================================================

## Return fresh instances of every project tool. Called by
## core/tool_registry.gd. One call = one set of tool objects.
static func build_all() -> Array:
	return [
		GetProjectInfo.new(),
		ListFiles.new(),
		SearchFiles.new(),
		ReadFile.new(),
		WriteFile.new(),
		PatchFile.new(),
	]
