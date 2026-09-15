@tool
class_name GDAToolRegistry
extends RefCounted

## GD AI Assistant — Tool Registry
##
## Owns every tool the harness can call. Built once per session and
## reused across turns. Never re-instantiates tools on the hot path.
##
## Phase 1 ships 6 tools (all Project category). Phases 2–4 add more
## by extending _register_all() — no logic here changes.
##
## Lookup by name is O(1) via the _by_name cache.
##
## Tool instances are stateless. Sharing one instance across turns is
## safe. Tools that need per-turn state get it from the context dict
## passed to execute(), not from instance vars.


var _tools: Array = []            # Array[GDAToolBase], order = UI/model order
var _by_name: Dictionary = {}     # name -> GDAToolBase
var _built: bool = false


# --- Lifecycle --------------------------------------------------------

## Build the registry. Safe to call multiple times — subsequent calls
## are no-ops. Call this once when the panel is created.
func build() -> void:
	if _built:
		return
	_register_all()
	_built = true


func is_built() -> bool:
	return _built


# --- Queries ----------------------------------------------------------

## All registered tool instances, in registration order.
func get_all_tools() -> Array:
	return _tools.duplicate()


## Tool names as a plain array. Useful for diagnostics.
func get_all_names() -> Array:
	return _by_name.keys()


## Look up a tool by name. Returns null if not registered.
func get_tool(tool_name: String) -> GDAToolBase:
	var t: Variant = _by_name.get(tool_name, null)
	if t is GDAToolBase:
		return t
	return null


func has_tool(tool_name: String) -> bool:
	return _by_name.has(tool_name)


func size() -> int:
	return _tools.size()


# --- Canonical conversion (for providers) -----------------------------

## Produce the canonical tool array that provider_base.gd expects.
## Passes through each tool's to_canonical(). Called by the harness
## before every chat request.
func to_canonical_array() -> Array:
	var out: Array = []
	for t: Variant in _tools:
		if t is GDAToolBase:
			out.append((t as GDAToolBase).to_canonical())
	return out


# --- Internal ---------------------------------------------------------

func _register_all() -> void:
	# Phase 1 — Project tools (read/search/write/patch/info/list)
	for t: Variant in GDAToolProject.build_all():
		_register(t)

	# Phase 2 — Scene tools (add here when ready):
	#   for t in GDAToolScene.build_all():
	#       _register(t)

	# Phase 2 — Script tools:
	#   for t in GDAToolScript.build_all():
	#       _register(t)

	# Phase 3 — Signal tools:
	#   for t in GDAToolSignals.build_all():
	#       _register(t)

	# Phase 3 — Resource tools:
	#   for t in GDAToolResources.build_all():
	#       _register(t)

	# Phase 3 — Editor tools:
	#   for t in GDAToolEditor.build_all():
	#       _register(t)

	# Phase 4 — Utility tools (web_search, manage_tasks, remember_note):
	#   for t in GDAToolUtility.build_all():
	#       _register(t)


func _register(t: Variant) -> void:
	if not (t is GDAToolBase):
		push_error(
			"GDAToolRegistry: registration rejected — object is not a GDAToolBase."
		)
		return

	var tool: GDAToolBase = t
	var tool_name: String = tool.get_name()

	if tool_name.is_empty():
		push_error(
			"GDAToolRegistry: registration rejected — tool has an empty name (%s)."
			% tool.get_script().resource_path
		)
		return

	if _by_name.has(tool_name):
		push_error(
			"GDAToolRegistry: duplicate tool name '%s'. Second registration ignored."
			% tool_name
		)
		return

	_tools.append(tool)
	_by_name[tool_name] = tool
