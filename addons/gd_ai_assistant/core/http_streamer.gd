@tool
class_name GDAHttpStreamer
extends RefCounted

## Streams SSE responses from OpenAI-compatible chat endpoints.
## Calls an on_token callback for each text delta.
##
## Usage:
##   var streamer := GDAHttpStreamer.new()
##   var result: Dictionary = await streamer.run(url, headers, body, cb, host)
##   result = {ok, status, data:{content, tool_calls, finish_reason, usage}}

var _cancelled: bool = false
var _client: HTTPClient = null


func cancel() -> void:
	_cancelled = true
	if _client != null:
		_client.close()


func run(
	url: String,
	headers: PackedStringArray,
	body_json: String,
	on_token: Callable,
	host_node: Node
) -> Dictionary:
	var parts: Dictionary = _parse_url(url)
	if parts.is_empty():
		return _fail("Invalid URL: " + url)

	var tree: SceneTree = host_node.get_tree()
	if tree == null:
		return _fail("No SceneTree available.")

	var client: HTTPClient = HTTPClient.new()
	_client = client
	if bool(parts["tls"]):
		client.set_tls_options(TLSOptions.client())

	var connect_err: Error = client.connect_to_host(
		str(parts["host"]), int(parts["port"])
	)
	if connect_err != OK:
		_client = null
		return _fail("connect_to_host failed (%d)" % connect_err)

	while (
		client.get_status() == HTTPClient.STATUS_CONNECTING
		or client.get_status() == HTTPClient.STATUS_RESOLVING
	):
		if _cancelled:
			client.close()
			_client = null
			return _fail("Cancelled.")
		client.poll()
		await tree.process_frame

	if client.get_status() != HTTPClient.STATUS_CONNECTED:
		client.close()
		_client = null
		return _fail("Connection failed.")

	var req_err: Error = client.request(
		HTTPClient.METHOD_POST, str(parts["path"]), headers, body_json
	)
	if req_err != OK:
		client.close()
		_client = null
		return _fail("request() failed (%d)" % req_err)

	while client.get_status() == HTTPClient.STATUS_REQUESTING:
		if _cancelled:
			client.close()
			_client = null
			return _fail("Cancelled.")
		client.poll()
		await tree.process_frame

	if not client.has_response():
		client.close()
		_client = null
		return _fail("No response received.")

	var response_code: int = client.get_response_code()

	if response_code < 200 or response_code >= 300:
		var err_body: PackedByteArray = PackedByteArray()
		while client.get_status() == HTTPClient.STATUS_BODY:
			client.poll()
			var chunk_err: PackedByteArray = client.read_response_body_chunk()
			if chunk_err.size() > 0:
				err_body.append_array(chunk_err)
			await tree.process_frame
		client.close()
		_client = null
		return {
			"ok": false,
			"status": response_code,
			"error_body": err_body,
			"message": "HTTP %d" % response_code,
		}

	var state: Dictionary = {
		"content": "",
		"tool_calls": {},
		"finish_reason": "",
		"usage": {
			"prompt_tokens": 0,
			"completion_tokens": 0,
			"total_tokens": 0,
		},
	}

	var buffer: String = ""
	while client.get_status() == HTTPClient.STATUS_BODY:
		if _cancelled:
			client.close()
			_client = null
			return _fail("Cancelled.")
		client.poll()
		var chunk: PackedByteArray = client.read_response_body_chunk()
		if chunk.size() > 0:
			buffer += chunk.get_string_from_utf8()
			while true:
				var sep: int = buffer.find("\n\n")
				if sep == -1:
					break
				var event: String = buffer.substr(0, sep)
				buffer = buffer.substr(sep + 2)
				_process_event(event, on_token, state)
		await tree.process_frame

	client.close()
	_client = null

	if not buffer.strip_edges().is_empty():
		_process_event(buffer, on_token, state)

	var tool_calls_out: Array = []
	var indices: Array = (state["tool_calls"] as Dictionary).keys()
	indices.sort()
	for idx_v: Variant in indices:
		var entry: Dictionary = (state["tool_calls"] as Dictionary)[idx_v]
		var args_str: String = str(entry.get("arguments", "")).strip_edges()
		var args_parsed: Dictionary = {}
		if not args_str.is_empty():
			var parsed: Variant = JSON.parse_string(args_str)
			if parsed is Dictionary:
				args_parsed = parsed
		tool_calls_out.append({
			"id": str(entry.get("id", "")),
			"name": str(entry.get("name", "")),
			"arguments": args_parsed,
		})

	return {
		"ok": true,
		"status": response_code,
		"data": {
			"content": str(state["content"]),
			"tool_calls": tool_calls_out,
			"finish_reason": str(state["finish_reason"]),
			"usage": state["usage"],
		},
	}


func _process_event(event: String, on_token: Callable, state: Dictionary) -> void:
	for line_v: String in event.split("\n"):
		var line: String = line_v.strip_edges()
		if not line.begins_with("data:"):
			continue
		var payload: String = line.substr(5).strip_edges()
		if payload == "[DONE]":
			return
		if payload.is_empty():
			continue
		_process_delta(payload, on_token, state)


func _process_delta(payload: String, on_token: Callable, state: Dictionary) -> void:
	var parsed: Variant = JSON.parse_string(payload)
	if not (parsed is Dictionary):
		return
	var root: Dictionary = parsed

	var usage_raw: Variant = root.get("usage", null)
	if usage_raw is Dictionary:
		state["usage"] = {
			"prompt_tokens": int((usage_raw as Dictionary).get("prompt_tokens", 0)),
			"completion_tokens": int((usage_raw as Dictionary).get("completion_tokens", 0)),
			"total_tokens": int((usage_raw as Dictionary).get("total_tokens", 0)),
		}

	var choices: Variant = root.get("choices", null)
	if not (choices is Array) or (choices as Array).is_empty():
		return
	var first: Variant = (choices as Array)[0]
	if not (first is Dictionary):
		return
	var choice: Dictionary = first

	var fr: String = str(choice.get("finish_reason", ""))
	if not fr.is_empty() and fr != "null":
		state["finish_reason"] = fr

	var delta_raw: Variant = choice.get("delta", null)
	if not (delta_raw is Dictionary):
		return
	var delta: Dictionary = delta_raw

	var content: String = str(delta.get("content", ""))
	if not content.is_empty():
		state["content"] = str(state["content"]) + content
		if on_token.is_valid():
			on_token.call(content)

	var tc_raw: Variant = delta.get("tool_calls", null)
	if not (tc_raw is Array):
		return
	var tc_map: Dictionary = state["tool_calls"]
	for tc_v: Variant in (tc_raw as Array):
		if not (tc_v is Dictionary):
			continue
		var tc: Dictionary = tc_v
		var idx: int = int(tc.get("index", 0))
		if not tc_map.has(idx):
			tc_map[idx] = {"id": "", "name": "", "arguments": ""}
		var entry: Dictionary = tc_map[idx]

		var id: String = str(tc.get("id", ""))
		if not id.is_empty():
			entry["id"] = id

		var fn_raw: Variant = tc.get("function", null)
		if fn_raw is Dictionary:
			var fn_dict: Dictionary = fn_raw
			var fname: String = str(fn_dict.get("name", ""))
			if not fname.is_empty():
				entry["name"] = fname
			var arg_chunk: String = str(fn_dict.get("arguments", ""))
			if not arg_chunk.is_empty():
				entry["arguments"] = str(entry["arguments"]) + arg_chunk
		tc_map[idx] = entry
	state["tool_calls"] = tc_map


static func _parse_url(url: String) -> Dictionary:
	var tls: bool = false
	var rest: String = url
	if rest.begins_with("https://"):
		tls = true
		rest = rest.substr(8)
	elif rest.begins_with("http://"):
		rest = rest.substr(7)
	else:
		return {}

	var slash_idx: int = rest.find("/")
	var hostport: String = rest if slash_idx == -1 else rest.substr(0, slash_idx)
	var path: String = "/" if slash_idx == -1 else rest.substr(slash_idx)

	var host: String = hostport
	var port: int = 443 if tls else 80
	var colon_idx: int = hostport.find(":")
	if colon_idx != -1:
		host = hostport.substr(0, colon_idx)
		port = int(hostport.substr(colon_idx + 1))

	return {"host": host, "port": port, "path": path, "tls": tls}


static func _fail(message: String) -> Dictionary:
	return { "ok": false, "message": message }
