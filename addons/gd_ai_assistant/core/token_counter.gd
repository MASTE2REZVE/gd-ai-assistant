@tool
class_name GDATokenCounter
extends RefCounted

## GD AI Assistant — Token Estimator
##
## Static class. No state. Used by the harness to enforce the anchor's
## token-efficiency rules: trim history before send, warn before
## exceeding context, never spam the provider with an oversized request.
##
## Accuracy disclaimer
## -------------------
## Real providers use byte-pair encoders (BPE). GDScript has no BPE
## library. This estimator uses character-class heuristics:
##
##   - ASCII letters/digits/punct: ~4 chars per token (English prose)
##   - Code density (many symbols): ~3 chars per token
##   - Non-ASCII (CJK, Bengali, emoji): ~2 tokens per char
##
## The heuristic deliberately over-estimates so we trim earlier rather
## than later. Do NOT use these numbers for billing — they exist to
## gate requests against a context-window limit, nothing more.
##
## Calibration: A 4000-char English message estimates to ~1000 tokens.
## Real BPE for the same message is typically 900-1100 tokens. Close
## enough for gating.

const CHARS_PER_TOKEN_ASCII: float = 3.5
const NON_ASCII_TOKEN_WEIGHT: int = 2
const MESSAGE_OVERHEAD_TOKENS: int = 4
const TOOL_OVERHEAD_TOKENS: int = 12


# --- Text ------------------------------------------------------------

## Estimate tokens in a plain string.
static func estimate_text(text: String) -> int:
	if text.is_empty():
		return 0

	var ascii_chars: int = 0
	var non_ascii_chars: int = 0

	for i: int in range(text.length()):
		var c: int = text.unicode_at(i)
		if c < 128:
			ascii_chars += 1
		else:
			non_ascii_chars += 1

	var ascii_tokens: float = (
		float(ascii_chars) / CHARS_PER_TOKEN_ASCII
	)
	var non_ascii_tokens: int = non_ascii_chars * NON_ASCII_TOKEN_WEIGHT

	return int(ceil(ascii_tokens)) + non_ascii_tokens


# --- Messages --------------------------------------------------------

## Estimate tokens for one canonical message dict.
## Structure: { role: String, content: String, tool_calls?: Array,
##              tool_call_id?: String, name?: String }
static func estimate_message(msg: Dictionary) -> int:
	var total: int = MESSAGE_OVERHEAD_TOKENS

	total += estimate_text(str(msg.get("role", "")))
	total += estimate_text(str(msg.get("content", "")))

	var tool_call_id: String = str(msg.get("tool_call_id", ""))
	if not tool_call_id.is_empty():
		total += estimate_text(tool_call_id)

	var name: String = str(msg.get("name", ""))
	if not name.is_empty():
		total += estimate_text(name)

	var tool_calls: Variant = msg.get("tool_calls", null)
	if tool_calls is Array:
		for tc: Variant in (tool_calls as Array):
			if not (tc is Dictionary):
				continue
			total += TOOL_OVERHEAD_TOKENS
			var tcd: Dictionary = tc
			total += estimate_text(str(tcd.get("id", "")))
			total += estimate_text(str(tcd.get("name", "")))
			var args: Variant = tcd.get("arguments", null)
			if args is Dictionary:
				total += estimate_text(JSON.stringify(args))
			elif args is String:
				total += estimate_text(args)

	return total


## Estimate tokens for an array of canonical messages.
static func estimate_messages(messages: Array) -> int:
	var total: int = 0
	for m: Variant in messages:
		if m is Dictionary:
			total += estimate_message(m)
	return total


# --- Tools -----------------------------------------------------------

## Estimate tokens for the canonical tool array (from
## tool_registry.to_canonical_array()). Each tool contributes its
## name, description, and JSON Schema size plus a fixed overhead.
static func estimate_tools(tools: Array) -> int:
	var total: int = 0
	for t: Variant in tools:
		if not (t is Dictionary):
			continue
		total += TOOL_OVERHEAD_TOKENS
		var td: Dictionary = t
		total += estimate_text(str(td.get("name", "")))
		total += estimate_text(str(td.get("description", "")))
		var params: Variant = td.get("parameters", null)
		if params is Dictionary:
			total += estimate_text(JSON.stringify(params))
	return total


# --- Full request ----------------------------------------------------

## Total estimated tokens for a full chat request: system prompt,
## messages, and tools. This is what we compare against the model's
## context window.
static func estimate_request(
	system_prompt: String,
	messages: Array,
	tools: Array
) -> int:
	var total: int = 0
	total += MESSAGE_OVERHEAD_TOKENS
	total += estimate_text(system_prompt)
	total += estimate_messages(messages)
	total += estimate_tools(tools)
	return total


# --- Trimming --------------------------------------------------------

## Return a copy of `messages` that fits within `token_budget` for the
## non-tool portion (system_prompt + history + tool definitions).
##
## Rules (anchor token-efficiency §2):
##   - Always keep messages[0] if it is a system message.
##   - Always keep the last message (it is the newest user turn).
##   - Drop middle messages oldest-first until under budget.
##   - If even the minimum does not fit, return the minimum — the
##     caller is responsible for refusing the request.
##
## This does not mutate the input array.
static func trim_history(
	messages: Array,
	token_budget: int,
	reserved_for_tools: int = 0
) -> Array:
	if messages.is_empty():
		return []

	var available: int = token_budget - reserved_for_tools
	if available <= 0:
		# Budget cannot even hold tools. Return only the last message.
		return [messages[messages.size() - 1]]

	# Identify the pinned head (system prompt) and the working middle.
	var has_system: bool = (
		messages.size() > 0
		and messages[0] is Dictionary
		and str((messages[0] as Dictionary).get("role", "")) == "system"
	)

	var head: Array = []
	var middle_start: int = 0
	if has_system:
		head.append(messages[0])
		middle_start = 1

	# Last message is always kept.
	var last_idx: int = messages.size() - 1
	if last_idx < middle_start:
		return head

	var last_msg: Variant = messages[last_idx]

	# Middle range is [middle_start, last_idx).
	var middle: Array = []
	for i: int in range(middle_start, last_idx):
		middle.append(messages[i])

	# Cost of everything we must keep.
	var must_keep: Array = head.duplicate()
	must_keep.append(last_msg)
	var must_cost: int = estimate_messages(must_keep)

	if must_cost > available:
		# Cannot even fit the minimum. Return it anyway and let the
		# caller decide.
		return must_keep

	# Add middle messages newest-first until the budget is exceeded.
	var chosen: Array = []
	var running: int = must_cost
	for i: int in range(middle.size() - 1, -1, -1):
		var m: Variant = middle[i]
		var m_cost: int = 0
		if m is Dictionary:
			m_cost = estimate_message(m)
		if running + m_cost > available:
			break
		chosen.append(m)
		running += m_cost

	# Rebuild in original order: head + chosen (reversed) + last.
	chosen.reverse()
	var out: Array = head.duplicate()
	out.append_array(chosen)
	out.append(last_msg)
	return out


# --- Reporting -------------------------------------------------------

## Human-readable token estimate for status displays.
## Example: "~1.2k tokens" or "~847 tokens".
static func format_estimate(tokens: int) -> String:
	if tokens < 1000:
		return "~%d tokens" % tokens
	var k: float = float(tokens) / 1000.0
	return "~%.1fk tokens" % k


## True if the estimate is close enough to a context window to warrant
## a warning. Threshold: 90% of window. Anchor token-efficiency §7.
static func exceeds_warning_threshold(tokens: int, window: int) -> bool:
	if window <= 0:
		return false
	return float(tokens) >= float(window) * 0.9
