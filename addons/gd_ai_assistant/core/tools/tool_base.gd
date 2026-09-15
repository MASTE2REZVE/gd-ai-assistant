@tool
class_name GDAToolBase
extends RefCounted

## GD AI Assistant — Tool Base Class
##
## Every tool (read_file, create_scene, run_scene, ...) implements this
## interface. The harness talks to tools ONLY through these methods.
##
## Canonical tool shape produced by to_canonical():
##   { "name": String,
##     "description": String,
##     "parameters": Dictionary (JSON Schema, type=object) }
##
## Canonical execute() return shape:
##   { "ok": bool, "message": String, "data": Variant }
## On failure:  ok=false, message=reason, data={}
## On success:  ok=true,  message may be "", data may be any payload
##
## The context dictionary
## ---------------------
## Tools receive a context Dictionary on every execute() call. It is
## built once per agent turn by the harness and must contain at least:
##
##   "settings"          : GDASettings
##   "editor_interface"  : EditorInterface (may be null in tests)
##   "plugin_root"       : String  — res://addons/gd_ai_assistant/
##   "agent_mode"        : String  — "ask" | "plan" | "agent" | "auto"
##
## Tools may read any of these. Tools must NOT write to them.
##
## Async
## -----
## execute() is expected to be a coroutine when the tool needs to await
## (HTTP, timers). Tools that do not await can return a Dictionary
## directly — GDScript treats both the same at the call site if the
## caller uses `await tool.execute(...)`.
##
## Adding a tool
## -------------
## 1. Extend GDAToolBase
## 2. Override get_name, get_description, get_parameters_schema
## 3. Override execute
## 4. Register the new tool in core/tool_registry.gd
## That's it. The harness discovers tools via the registry and never
## needs to change.


# --- Identity (must override) ----------------------------------------

## Snake_case, stable. This is the name the model sees in the tool
## list. Changing it is a breaking change for saved conversations.
func get_name() -> String:
	_abstract("get_name")
	return ""


## One or two sentences, written for the model. Should explain WHEN to
## use the tool, not just WHAT it does. Vague descriptions cause the
## model to call the wrong tool.
func get_description() -> String:
	_abstract("get_description")
	return ""


# --- Schema (must override) ------------------------------------------

## JSON Schema for the tool's parameters. Must be an object schema
## with a "properties" map. Example:
##   {
##     "type": "object",
##     "properties": {
##       "path": { "type": "string", "description": "res:// path" }
##     },
##     "required": ["path"]
##   }
func get_parameters_schema() -> Dictionary:
	_abstract("get_parameters_schema")
	return { "type": "object", "properties": {}, "required": [] }


# --- Capabilities (override as needed) -------------------------------

## True if this tool mutates the user's project (files, scenes, editor
## state). The harness uses this to enforce agent-mode gating:
##   - PLAN mode blocks all mutating tools
##   - AGENT mode asks the user before mutating tools
##   - AUTO mode runs mutating tools without asking
##   - ASK mode blocks all tools
func is_mutating() -> bool:
	return false


## True if this tool needs the EditorInterface to be non-null. The
## harness refuses to run such a tool in headless contexts.
func needs_editor() -> bool:
	return false


# --- Execution (must override) ---------------------------------------

## Run the tool. See file header for the return shape and context keys.
## May be a coroutine; callers should use `await`.
func execute(_args: Dictionary, _context: Dictionary) -> Dictionary:
	_abstract("execute")
	return fail("execute() not implemented")


# --- Canonical conversion --------------------------------------------

## Produce the canonical { name, description, parameters } shape that
## provider_base.gd expects. Called by the harness before every request.
func to_canonical() -> Dictionary:
	return {
		"name": get_name(),
		"description": get_description(),
		"parameters": get_parameters_schema(),
	}


# --- Validation helpers (available to subclasses) --------------------

## Validate that required string args are present and non-empty.
## Returns "" on success or a short error naming the first missing key.
func require_strings(args: Dictionary, keys: Array) -> String:
	for key: Variant in keys:
		var k: String = str(key)
		var v: Variant = args.get(k, null)
		if v == null:
			return "Missing required argument: " + k
		var s: String = str(v).strip_edges()
		if s.is_empty():
			return "Argument '%s' must be a non-empty string." % k
	return ""


## Validate that required int args are present. Bools/strings that
## coerce cleanly are accepted (JSON has no integer type).
func require_ints(args: Dictionary, keys: Array) -> String:
	for key: Variant in keys:
		var k: String = str(key)
		if not args.has(k):
			return "Missing required argument: " + k
		var v: Variant = args[k]
		if not (v is int or v is float or v is bool):
			return "Argument '%s' must be an integer." % k
	return ""


# --- Return helpers (available to subclasses) ------------------------

func ok(message: String = "", data: Variant = {}) -> Dictionary:
	return { "ok": true, "message": message, "data": data }


func fail(message: String) -> Dictionary:
	return { "ok": false, "message": message, "data": {} }


# --- Internal --------------------------------------------------------

func _abstract(method_name: String) -> void:
	var path: String = ""
	if get_script() != null:
		path = get_script().resource_path
	push_error(
		"GDAToolBase: %s() must be overridden by subclass %s."
		% [method_name, path]
	)
