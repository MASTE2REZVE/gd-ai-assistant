@tool
class_name GDAOpenAICompat
extends GDAProviderBase

const DEFAULT_CHAT_PATH: String = "/chat/completions"
const DEFAULT_MODELS_PATH: String = "/models"
const DEFAULT_MAX_TOKENS: int = 4096
const FREE_THRESHOLD_PER_TOK: float = 0.0000001


var _id: String = ""
var _display_name: String = ""
var _endpoint: String = ""
var _chat_path: String = DEFAULT_CHAT_PATH
var _models_path: String = DEFAULT_MODELS_PATH
var _extra_headers: PackedStringArray = PackedStringArray()
var _is_local: bool = false
var _requires_key: bool = true
var _supports_tools_flag: bool = true
var _supports_models_flag: bool = true


func configure(preset: Dictionary) -> void:
	_id = str(preset.get("id", ""))
	_display_name = str(preset.get("display_name", _id))
	_endpoint = str(preset.get("endpoint", "")).rstrip("/")
	_chat_path = str(preset.get("chat_path", DEFAULT_CHAT_PATH))
	_models_path = str(preset.get("models_path", DEFAULT_MODELS_PATH))
	_is_local = bool(preset.get("is_local", false))
	_requires_key = bool(preset.get("requires_key", not _is_local))
	_supports_tools_flag = bool(preset.get("supports_tools", true))
	_supports_models_flag = bool(preset.get("supports_models", true))

	var extra: Variant = preset.get("extra_headers", PackedStringArray())
	if extra is PackedStringArray:
		_extra_headers = extra
	elif extra is Array:
		var buf: PackedStringArray = PackedStringArray()
		for h: Variant in extra:
			buf.append(str(h))
		_extra_headers = buf


func get_id() -> String:
	return _id


func get_display_name() -> String:
	return _display_name


func is_local() -> bool:
	return _is_local


func requires_api_key() -> bool:
	return _requires_key


func supports_tools() -> bool:
	return _supports_tools_flag


func supports_model_listing() -> bool:
	return _supports_models_flag


func get_default_endpoint() -> String:
	return _endpoint


func build_headers(api_key: String) -> PackedStringArray:
	var headers: PackedStringArray = PackedStringArray()
	headers.append("Content-Type: application/json")
	headers.append("Accept: application/json")
	if _requires_key and not api_key.is_empty():
		headers.append("Authorization: Bearer " + api_key)
	elif _requires_key and api_key.is_empty():
		push_warning(
			"GDAOpenAICompat[%s]: no API key saved for this provider. 401 likely."
			% _id
		)
	for h: String in _extra_headers:
		headers.append(h)
	return headers


func get_chat_url(endpoint_override: String = "") -> String:
	var base: String = (
		endpoint_override.rstrip("/")
		if not endpoint_override.is_empty()
		else _endpoint
	)
	if base.is_empty():
		return ""
	if base.ends_with(DEFAULT_CHAT_PATH):
		return base
	return base + _chat_path


func get_models_url(endpoint_override: String = "") -> String:
	var base: String = (
		endpoint_override.rstrip("/")
		if not endpoint_override.is_empty()
		else _endpoint
	)
	if base.is_empty():
		return ""
	if base.ends_with(DEFAULT_MODELS_PATH):
		return base
	if base.ends_with(DEFAULT_CHAT_PATH):
		base = base.substr(0, base.length() - DEFAULT_CHAT_PATH.length())
	return base + _models_path


func build_request(
	model: String,
	messages: Array,
	tools: Array,
	temperature: float
) -> Dictionary:
	return _build_request_internal(model, messages, tools, temperature)


func build_request_without_tools(
	model: String,
	messages: Array,
	temperature: float
) -> Dictionary:
	return _build_request_internal(model, messages, [], temperature)


func _build_request_internal(
	model: String,
	messages: Array,
	tools: Array,
	temperature: float
) -> Dictionary:
	var body: Dictionary = {
		"model": model,
		"messages": messages,
		"temperature": temperature,
		"stream": false,
		"max_tokens": DEFAULT_MAX_TOKENS,
	}
	if not tools.is_empty() and _supports_tools_flag:
		body["tools"] = canonical_tools_to_openai(tools)
		body["tool_choice"] = "auto"
	return body


func parse_chat_response(body: PackedByteArray) -> Dictionary:
	var text: String = body.get_string_from_utf8()
	var json: JSON = JSON.new()
	var err: Error = json.parse(text)
	if err != OK:
		return {
			"ok": false,
			"message": "Invalid JSON from provider: " + json.get_error_message(),
		}

	var root: Variant = json.data
	if not (root is Dictionary):
		return { "ok": false, "message": "Provider returned non-object JSON." }

	var root_dict: Dictionary = root
	var choices: Variant = root_dict.get("choices", null)
	if not (choices is Array) or (choices as Array).is_empty():
		return { "ok": false, "message": "Provider returned no choices." }

	var first: Variant = (choices as Array)[0]
	if not (first is Dictionary):
		return { "ok": false, "message": "Malformed choice entry." }

	var message: Variant = (first as Dictionary).get("message", {})
	if not (message is Dictionary):
		return { "ok": false, "message": "Malformed message entry." }

	var msg_dict: Dictionary = message
	var content_raw: Variant = msg_dict.get("content", "")
	var content: String = "" if content_raw == null else str(content_raw)

	var tool_calls_canonical: Array = []
	var tool_calls_raw: Variant = msg_dict.get("tool_calls", null)
	if tool_calls_raw is Array:
		for tc: Variant in (tool_calls_raw as Array):
			if not (tc is Dictionary):
				continue
			var parsed_tc: Dictionary = _parse_single_tool_call(tc)
			if parsed_tc.is_empty():
				continue
			tool_calls_canonical.append(parsed_tc)

	var finish: String = str((first as Dictionary).get("finish_reason", ""))

	var usage_canonical: Dictionary = _parse_usage(root_dict)

	return {
		"ok": true,
		"data": {
			"content": content,
			"tool_calls": tool_calls_canonical,
			"finish_reason": finish,
			"usage": usage_canonical,
		},
	}


func parse_error_response(status_code: int, body: PackedByteArray) -> String:
	var text: String = body.get_string_from_utf8()
	var json: JSON = JSON.new()
	if json.parse(text) == OK and json.data is Dictionary:
		var err_field: Variant = (json.data as Dictionary).get("error", null)
		if err_field is Dictionary:
			var msg: String = str((err_field as Dictionary).get("message", ""))
			if not msg.is_empty():
				return "HTTP %d: %s" % [status_code, msg]
		elif err_field is String and not (err_field as String).is_empty():
			return "HTTP %d: %s" % [status_code, err_field]
	if text.length() > 500:
		text = text.substr(0, 500) + "...[truncated]"
	return "HTTP %d: %s" % [status_code, text]


func list_models(api_key: String, endpoint_override: String = "") -> Array:
	var url: String = get_models_url(endpoint_override)
	if url.is_empty():
		push_warning("GDAOpenAICompat[%s]: models URL empty." % _id)
		return []
	var http: HTTPRequest = HTTPRequest.new()
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return []
	tree.root.add_child(http)

	var headers: PackedStringArray = build_headers(api_key)
	var err: Error = http.request(url, headers, HTTPClient.METHOD_GET)
	if err != OK:
		http.queue_free()
		push_warning("GDAOpenAICompat[%s]: request failed (%d)." % [_id, err])
		return []

	var response: Array = await http.request_completed
	http.queue_free()

	if response.size() < 4:
		return []
	var result_code: int = int(response[0])
	var status: int = int(response[1])
	var body: PackedByteArray = response[3]

	if result_code != HTTPRequest.RESULT_SUCCESS:
		push_warning("GDAOpenAICompat[%s]: network error (result %d)." % [_id, result_code])
		return []

	if status < 200 or status >= 300:
		var err_text: String = body.get_string_from_utf8()
		if err_text.length() > 300:
			err_text = err_text.substr(0, 300)
		push_warning("GDAOpenAICompat[%s]: HTTP %d from %s -- %s" % [_id, status, url, err_text])
		return []

	var text: String = body.get_string_from_utf8()
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		push_warning("GDAOpenAICompat[%s]: cannot parse models response." % _id)
		return []
	var root: Variant = json.data
	if not (root is Dictionary):
		return []
	var data: Variant = (root as Dictionary).get("data", null)
	if not (data is Array):
		return []

	var out: Array = []
	for entry: Variant in (data as Array):
		if not (entry is Dictionary):
			continue
		var entry_dict: Dictionary = entry
		var model_id: String = str(entry_dict.get("id", "")).strip_edges()
		if model_id.is_empty():
			continue

		var record: Dictionary = {
			"id": model_id,
			"name": str(entry_dict.get("name", model_id)),
			"is_free": false,
			"effective_cost": -1.0,
		}

		var pricing: Variant = entry_dict.get("pricing", null)
		if pricing is Dictionary:
			var p: Dictionary = pricing
			var prompt_per_tok: float = _safe_float(p.get("prompt", "0"))
			var completion_per_tok: float = _safe_float(p.get("completion", "0"))
			var total_per_tok: float = prompt_per_tok + completion_per_tok
			record["effective_cost"] = total_per_tok * 1000000.0
			record["is_free"] = total_per_tok <= FREE_THRESHOLD_PER_TOK

		if model_id.ends_with(":free"):
			record["is_free"] = true

		out.append(record)
	return out


func _parse_single_tool_call(raw: Dictionary) -> Dictionary:
	var call_id: String = str(raw.get("id", "")).strip_edges()
	var fn_raw: Variant = raw.get("function", null)
	if not (fn_raw is Dictionary):
		return {}
	var fn_dict: Dictionary = fn_raw
	var name: String = str(fn_dict.get("name", "")).strip_edges()
	if name.is_empty():
		return {}

	var args_raw: Variant = fn_dict.get("arguments", "")
	var args: Dictionary = {}
	if args_raw is Dictionary:
		args = args_raw
	elif args_raw is String:
		var s: String = (args_raw as String).strip_edges()
		if not s.is_empty():
			var parsed: Variant = JSON.parse_string(s)
			if parsed is Dictionary:
				args = parsed

	return {
		"id": call_id,
		"name": name,
		"arguments": args,
	}


func _parse_usage(root: Dictionary) -> Dictionary:
	var usage_raw: Variant = root.get("usage", null)
	if not (usage_raw is Dictionary):
		return {
			"prompt_tokens": 0,
			"completion_tokens": 0,
			"total_tokens": 0,
		}
	var u: Dictionary = usage_raw
	return {
		"prompt_tokens": int(u.get("prompt_tokens", 0)),
		"completion_tokens": int(u.get("completion_tokens", 0)),
		"total_tokens": int(u.get("total_tokens", 0)),
	}


func _safe_float(v: Variant) -> float:
	if v is float:
		return v
	if v is int:
		return float(v)
	if v is String:
		return (v as String).to_float()
	return 0.0
