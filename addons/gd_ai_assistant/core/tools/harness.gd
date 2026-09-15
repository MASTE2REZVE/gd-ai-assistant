@tool
class_name GDAHarness
extends RefCounted

## GD AI Assistant — Agent Harness
##
## The loop. Turns a user message into: request -> response ->
## (tool calls -> responses)* -> final text. Enforces:
##   - agent mode gating (ASK / PLAN / AGENT / AUTO)
##   - read-before-edit (anchor safety layer 2)
##   - token budget trimming (anchor token rules 2, 7)
##   - step cap and cancellation
##   - HTTP retry with a short error-context message (rule 8)
##
## The harness OWNS the conversation history for the session. It does
## NOT own the system prompt string — that is passed in at configure
## time so this file has no dependency on how the prompt is built.
##
## Async contract: start_turn() is a coroutine. Callers must `await`
## it OR connect to turn_finished. Both work.
##
## HTTP: uses an HTTPRequest added to _host. _host must be a Node in
## the tree (the panel provides itself).

# --- Signals (UI observes these) --------------------------------------
signal turn_started
signal turn_finished(ok: bool, message: String)
signal assistant_message(text: String)
signal tool_call_started(tool_name: String, args: Dictionary)
signal tool_call_finished(tool_name: String, ok: bool, message: String)
signal approval_required(tool_name: String, args: Dictionary)
signal error_occurred(message: String)

# Internal signal the panel emits back through resolve_approval().
signal approval_resolved(approved: bool)


const RETRY_DELAY_SEC: float = 1.2
const DEFAULT_MAX_STEPS: int = 40
const MOBILE_MAX_STEPS: int = 20

# --- Configuration ----------------------------------------------------
var _settings: GDASettings = null
var _registry: GDAToolRegistry = null
var _host: Node = null
var _editor_interface: EditorInterface = null
var _provider: GDAProviderBase = null
var _system_prompt: String = ""

# --- Runtime state ----------------------------------------------------
var _running: bool = false
var _cancelled: bool = false
var _step_count: int = 0
var _history: Array = []          # conversation, EXCLUDING the system message
var _inspected: Dictionary = {}   # normalized res:// path -> true
var _active_http: HTTPRequest = null
var _approval_responded: bool = false
var _approval_result: bool = false


# --- Configuration API ------------------------------------------------

func configure(
	settings: GDASettings,
	registry: GDAToolRegistry,
	host: Node,
	editor_interface: EditorInterface,
	provider: GDAProviderBase,
	system_prompt: String
) -> void:
	_settings = settings
	_registry = registry
	_host = host
	_editor_interface = editor_interface
	_provider = provider
	_system_prompt = system_prompt


func set_provider(provider: GDAProviderBase) -> void:
	_provider = provider


func set_system_prompt(prompt: String) -> void:
	_system_prompt = prompt


func is_running() -> bool:
	return _running


func get_history_size() -> int:
	return _history.size()


func clear_history() -> void:
	_history.clear()
	_inspected.clear()


# --- Approval callback (called by the panel) --------------------------

func resolve_approval(approved: bool) -> void:
	_approval_result = approved
	_approval_responded = true
	approval_resolved.emit(approved)


# --- Cancellation -----------------------------------------------------

func cancel() -> void:
	_cancelled = true
	if _active_http != null and is_instance_valid(_active_http):
		_active_http.cancel_request()


# --- Main entry -------------------------------------------------------

func start_turn(user_text: String) -> void:
	if _running:
		error_occurred.emit("A turn is already running.")
		return
	if _provider == null:
		error_occurred.emit("No AI provider is configured.")
		return
	if _settings == null or _registry == null or _host == null:
		error_occurred.emit("Harness is not configured.")
		return

	var trimmed_input: String = user_text.strip_edges()
	if trimmed_input.is_empty():
		error_occurred.emit("Empty message.")
		return

	_running = true
	_cancelled = false
	_step_count = 0
	_inspected.clear()

	_history.append({ "role": "user", "content": trimmed_input })
	turn_started.emit()

	var result: Dictionary = await _run_loop()

	_running = false
	var ok: bool = bool(result.get("ok", false))
	var msg: String = str(result.get("message", ""))
	turn_finished.emit(ok, msg)


# --- The loop ---------------------------------------------------------

func _run_loop() -> Dictionary:
	var retries_used: int = 0
	var max_retries: int = _settings.get_max_retries()
	var agent_mode: String = _settings.get_agent_mode()
	var limits: Dictionary = GDAPlatform.effective_limits(
		GDAPlatform.resolve_mode(_settings.get_mode_override()),
		_settings.get_desktop_features_enabled()
	)
	var token_budget: int = int(limits.get("token_budget", 4000))
	var max_steps: int = (
		MOBILE_MAX_STEPS if GDAPlatform.is_mobile_os() else DEFAULT_MAX_STEPS
	)

	while not _cancelled:
		_step_count += 1
		if _step_count > max_steps:
			return _fail("Step limit reached (%d)." % max_steps)

		var tools_canonical: Array = _registry.to_canonical_array()
		var tools_cost: int = GDATokenCounter.estimate_tools(tools_canonical)

		var full_history: Array = _build_full_history()
		var trimmed: Array = GDATokenCounter.trim_history(
			full_history, token_budget, tools_cost
		)
		var estimate: int = GDATokenCounter.estimate_request(
			"", trimmed, tools_canonical
		)
		# If the request cannot even fit within the budget, refuse.
		if estimate > token_budget:
			return _fail(
				"Request too large for token budget (%d > %d)."
				% [estimate, token_budget]
			)

		var response: Dictionary = await _send_request(trimmed, tools_canonical)

		if _cancelled:
			return _fail("Cancelled.")

		if not bool(response.get("ok", false)):
			retries_used += 1
			if retries_used > max_retries:
				return _fail(str(response.get("message", "Unknown error.")))
			_history.append({
				"role": "user",
				"content": (
					"Error from previous attempt: "
					+ str(response.get("message", ""))
					+ ". Continue carefully. If this concerns a file, "
					+ "read it first before editing."
				),
			})
			await _wait(RETRY_DELAY_SEC)
			continue

		retries_used = 0
		var data: Dictionary = response.get("data", {})
		var content: String = str(data.get("content", ""))
		var tool_calls: Array = data.get("tool_calls", [])

		if tool_calls.is_empty():
			_history.append({ "role": "assistant", "content": content })
			if not content.is_empty():
				assistant_message.emit(content)
			return { "ok": true, "message": content }

		# Assistant turn with tool calls. Keep the calls in history so
		# the provider can pair them with the tool results we append next.
		_history.append({
			"role": "assistant",
			"content": content,
			"tool_calls": tool_calls,
		})

		for tc: Variant in tool_calls:
			if _cancelled:
				return _fail("Cancelled.")
			if not (tc is Dictionary):
				continue
			var result: Dictionary = await _execute_tool_call(tc as Dictionary)
			_history.append({
				"role": "tool",
				"tool_call_id": str((tc as Dictionary).get("id", "")),
				"content": JSON.stringify({
					"ok": bool(result.get("ok", false)),
					"message": str(result.get("message", "")),
					"data": result.get("data", {}),
				}),
			})
		# Loop back for the model's next reply.

	return _fail("Cancelled.")


# --- Provider request -------------------------------------------------

func _send_request(messages: Array, tools_canonical: Array) -> Dictionary:
	var provider: GDAProviderBase = _provider
	if provider == null:
		return _fail("No provider.")
	if not provider.supports_tools() and not tools_canonical.is_empty():
		tools_canonical = []

	var provider_id: String = provider.get_id()
	var api_key: String = _settings.get_api_key(provider_id)
	var endpoint_override: String = _settings.get_custom_endpoint(provider_id)
	var model: String = _settings.get_provider_model(provider_id)
	if model.is_empty():
		model = GDAProviderRegistry.get_default_model(provider_id)

	var url: String = provider.get_chat_url(endpoint_override)
	if url.is_empty():
		return _fail("Provider URL is empty. Configure an endpoint.")

	var headers: PackedStringArray = provider.build_headers(api_key)
	var temperature: float = _settings.get_temperature()
	var body: Dictionary = provider.build_request(
		model, messages, tools_canonical, temperature
	)
	var body_json: String = JSON.stringify(body)

	var http: HTTPRequest = HTTPRequest.new()
	var limits: Dictionary = GDAPlatform.effective_limits(
		GDAPlatform.resolve_mode(_settings.get_mode_override()),
		_settings.get_desktop_features_enabled()
	)
	http.timeout = float(limits.get("http_timeout_sec", 30.0))
	_host.add_child(http)
	_active_http = http

	var err: Error = http.request(
		url, headers, HTTPClient.METHOD_POST, body_json
	)
	if err != OK:
		http.queue_free()
		_active_http = null
		return _fail("HTTP request could not start (error %d)." % err)

	var response: Array = await http.request_completed

	_active_http = null
	if is_instance_valid(http):
		http.queue_free()

	if response.size() < 4:
		return _fail("Malformed HTTP response.")

	var result_code: int = int(response[0])
	var status: int = int(response[1])
	var body_bytes: PackedByteArray = response[3]

	if result_code != HTTPRequest.RESULT_SUCCESS:
		if result_code == HTTPRequest.RESULT_REQUEST_FAILED:
			return _fail("Network error: could not reach the provider.")
		return _fail("HTTP request failed (result %d)." % result_code)

	if status < 200 or status >= 300:
		return _fail(provider.parse_error_response(status, body_bytes))

	return provider.parse_chat_response(body_bytes)


# --- Tool execution ---------------------------------------------------

func _execute_tool_call(tc: Dictionary) -> Dictionary:
	var tool_name: String = str(tc.get("name", ""))
	var args: Variant = tc.get("arguments", {})
	if not (args is Dictionary):
		args = {}
	var args_dict: Dictionary = args

	if not _registry.has_tool(tool_name):
		return _fail("Unknown tool: " + tool_name)

	var tool: GDAToolBase = _registry.get_tool(tool_name)
	if tool == null:
		return _fail("Tool lookup failed: " + tool_name)

	var gate: Dictionary = await _gate_tool(tool, args_dict)
	if not bool(gate.get("ok", false)):
		tool_call_finished.emit(tool_name, false, str(gate.get("message", "")))
		return gate

	tool_call_started.emit(tool_name, args_dict)
	var result: Dictionary = await tool.execute(args_dict, _build_context())

	# Track read_file for read-before-edit (only successful reads count).
	if tool_name == "read_file" and bool(result.get("ok", false)):
		var path: String = str(args_dict.get("path", ""))
		if not path.is_empty():
			_inspected[GDAPathGuard.normalize(path)] = true

	var ok: bool = bool(result.get("ok", false))
	var msg: String = str(result.get("message", ""))
	tool_call_finished.emit(tool_name, ok, msg)
	return result


func _gate_tool(tool: GDAToolBase, args: Dictionary) -> Dictionary:
	var mode: String = _settings.get_agent_mode()

	if mode == "ask":
		return _fail("Agent is in ASK mode. Tools are disabled.")

	if mode == "plan" and tool.is_mutating():
		return _fail("Agent is in PLAN mode. Write operations are disabled.")

	if tool.needs_editor() and _editor_interface == null:
		return _fail("This tool requires the Godot editor context.")

	if tool.is_mutating():
		var target: String = _extract_target_path(args)
		if not target.is_empty() and FileAccess.file_exists(target):
			if not _inspected.has(target):
				return _fail(
					"Read-before-edit: read '%s' before modifying it." % target
				)

	if mode == "agent" and tool.is_mutating():
		_approval_responded = false
		approval_required.emit(tool.get_name(), args)
		if not _approval_responded:
			await approval_resolved
		if not _approval_result:
			return _fail("User declined this change.")

	return { "ok": true, "message": "", "data": {} }


# --- Helpers ----------------------------------------------------------

func _build_full_history() -> Array:
	var out: Array = []
	if not _system_prompt.is_empty():
		out.append({ "role": "system", "content": _system_prompt })
	out.append_array(_history)
	return out


func _extract_target_path(args: Dictionary) -> String:
	# Both write_file and patch_file use "path". Scene tools (Phase 2)
	# will use "scene_path". Check both.
	for key: String in ["path", "scene_path", "file_path"]:
		var v: Variant = args.get(key, null)
		if v != null:
			var s: String = str(v).strip_edges()
			if not s.is_empty():
				return GDAPathGuard.normalize(s)
	return ""


func _build_context() -> Dictionary:
	return {
		"settings": _settings,
		"editor_interface": _editor_interface,
		"plugin_root": "res://addons/gd_ai_assistant/",
		"agent_mode": _settings.get_agent_mode(),
	}


func _wait(seconds: float) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree != null:
		await tree.create_timer(seconds).timeout


func _fail(message: String) -> Dictionary:
	return { "ok": false, "message": message, "data": {} }
