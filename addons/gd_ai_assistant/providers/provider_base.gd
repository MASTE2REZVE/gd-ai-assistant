@tool
class_name GDAProviderBase
extends RefCounted

## GD AI Assistant — Provider Base Class
##
## Every AI provider implements this interface. The harness talks to
## providers ONLY through these methods — it never knows which concrete
## provider it is using.
##
## Canonical message format (what this interface accepts and returns):
##   { "role": "system"|"user"|"assistant"|"tool",
##     "content": String,
##     "tool_calls": Array (optional, assistant only),
##     "tool_call_id": String (optional, tool role only),
##     "name": String (optional) }
##
## Canonical tool format (what this interface accepts):
##   { "name": String,
##     "description": String,
##     "parameters": Dictionary (JSON Schema) }
##
## Canonical chat response (what send_chat returns in "data"):
##   { "content": String,
##     "tool_calls": Array of { "id": String,
##                              "name": String,
##                              "arguments": Dictionary },
##     "finish_reason": String,
##     "usage": { "prompt_tokens": int, "completion_tokens": int,
##                "total_tokens": int } }
##
## Subclasses translate canonical -> native and native -> canonical.
## They do NOT talk to HTTP, files, or the editor. That is the
## harness's job (core/harness.gd).


# --- Identity (must override) -----------------------------------------

## Short stable id, lowercase, snake_case. Used as a settings key,
## as a registry key, and as the [providers] section prefix.
## Example: "openrouter", "openai", "ollama".
func get_id() -> String:
	_abstract("get_id")
	return ""


## Human-readable name shown in the provider dropdown.
func get_display_name() -> String:
	_abstract("get_display_name")
	return ""


# --- Capabilities (override as needed) --------------------------------

## True for local providers (Ollama, LM Studio). The UI uses this to
## hide the API-key field.
func is_local() -> bool:
	return false


## True if an API key is required. Local providers typically return false.
func requires_api_key() -> bool:
	return true


## True if this provider supports function/tool calling. Providers that
## do not will have tools ignored by the harness.
func supports_tools() -> bool:
	return true


## True if this provider supports streaming. v1 does not stream, but the
## harness will consult this once streaming is added (Phase 4).
func supports_streaming() -> bool:
	return false


# --- Endpoint & headers (must override) -------------------------------

## Default base URL for this provider. Users may override this in
## settings (e.g. for Custom or self-hosted). Return an empty string
## if the provider is not usable without a user-supplied endpoint.
func get_default_endpoint() -> String:
	_abstract("get_default_endpoint")
	return ""


## Build the HTTP headers for a chat request. api_key may be empty for
## local providers. Never log or echo this dictionary's contents.
func build_headers(_api_key: String) -> PackedStringArray:
	_abstract("build_headers")
	return PackedStringArray()


# --- Request building (must override) ---------------------------------

## Build the JSON request body. model is the model id, messages and
## tools are in canonical format, temperature is a float.
##
## Returns a Dictionary ready to be JSON.stringify'd by the harness.
func build_request(
	_model: String,
	_messages: Array,
	_tools: Array,
	_temperature: float
) -> Dictionary:
	_abstract("build_request")
	return {}


## Full URL for a chat completion request. Default combines
## get_default_endpoint() with the provider's chat path. Subclasses
## may override if the URL is non-standard.
func get_chat_url(endpoint_override: String = "") -> String:
	var base: String = (
		endpoint_override if not endpoint_override.is_empty()
		else get_default_endpoint()
	)
	return base


# --- Response parsing (must override) ---------------------------------

## Parse a successful HTTP response into the canonical response shape.
## body is the raw response bytes. The harness guarantees the HTTP
## status code was 2xx before calling this.
##
## Return:
##   { "ok": true,  "data": <canonical response> }
## or on parse failure:
##   { "ok": false, "message": String }
func parse_chat_response(_body: PackedByteArray) -> Dictionary:
	_abstract("parse_chat_response")
	return { "ok": false, "message": "not implemented" }


## Parse an error HTTP response into a human-readable message. Should
## surface provider-specific error fields when present. Return a short
## string — it will be shown to the user and possibly sent back to the
## model as context.
func parse_error_response(_status_code: int, _body: PackedByteArray) -> String:
	var text: String = _body.get_string_from_utf8()
	if text.length() > 500:
		text = text.substr(0, 500) + "...[truncated]"
	return "HTTP %d: %s" % [_status_code, text]


# --- Model listing (optional) -----------------------------------------

## True if this provider can list its available models via API.
func supports_model_listing() -> bool:
	return false


## Return a list of { "id": String, "name": String } dictionaries.
## Only called if supports_model_listing() returns true. Return an
## empty array to indicate "known, but currently none available".
func list_models(_api_key: String, _endpoint_override: String = "") -> Array:
	return []


## URL to hit for model listing. Only used when supports_model_listing()
## returns true.
func get_models_url(_endpoint_override: String = "") -> String:
	return ""


# --- Translation helpers (available to subclasses) --------------------

## Wrap a canonical tool dict in the OpenAI-compatible shape.
## OpenAI, OpenRouter, Groq, DeepSeek, Mistral, xAI, Ollama, and
## LM Studio all use this exact shape.
func canonical_tool_to_openai(tool: Dictionary) -> Dictionary:
	return {
		"type": "function",
		"function": {
			"name": str(tool.get("name", "")),
			"description": str(tool.get("description", "")),
			"parameters": tool.get("parameters", {}),
		},
	}


## Wrap an array of canonical tools using the OpenAI-compatible shape.
func canonical_tools_to_openai(tools: Array) -> Array:
	var out: Array = []
	for t: Variant in tools:
		if t is Dictionary:
			out.append(canonical_tool_to_openai(t))
	return out


# --- Internal ----------------------------------------------------------

func _abstract(method_name: String) -> void:
	push_error(
		"GDAProviderBase: %s() must be overridden by subclass %s."
		% [method_name, get_script().resource_path]
	)
