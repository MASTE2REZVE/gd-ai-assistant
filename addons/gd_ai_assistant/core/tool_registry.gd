@tool
class_name GDAToolRegistry
extends RefCounted

## GD AI Assistant — Tool Registry

var _tools: Array = []
var _by_name: Dictionary = {}
var _built: bool = false


func build() -> void:
	if _built:
		return
	_register_all()
	_built = true


func is_built() -> bool:
	return _built


func get_all_tools() -> Array:
	return _tools.duplicate()


func get_all_names() -> Array:
	return _by_name.keys()


func get_tool(tool_name: String) -> GDAToolBase:
	var t: Variant = _by_name.get(tool_name, null)
	if t is GDAToolBase:
		return t
	return null


func has_tool(tool_name: String) -> bool:
	return _by_name.has(tool_name)


func size() -> int:
	return _tools.size()


func to_canonical_array() -> Array:
	var out: Array = []
	for t: Variant in _tools:
		if t is GDAToolBase:
			out.append((t as GDAToolBase).to_canonical())
	return out


func _register_all() -> void:
	# Project tools
	for t: Variant in GDAToolProject.build_all():
		_register(t)

	# Scene tools
	for t: Variant in GDAToolScene.build_all():
		_register(t)

	# Script tools
	for t: Variant in GDAToolScript.build_all():
		_register(t)

	# Signal tools:
	#   for t in GDAToolSignals.build_all():
	#       _register(t)

	# Resource tools:
	#   for t in GDAToolResources.build_all():
	#       _register(t)

	# Editor tools:
	#   for t in GDAToolEditor.build_all():
	#       _register(t)

	# Utility tools:
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
