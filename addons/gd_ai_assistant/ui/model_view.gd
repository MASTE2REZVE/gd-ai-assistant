@tool
class_name GDAModelView
extends RefCounted

## GD AI Assistant — Model List Filtering / Sorting
##
## Pure static helpers used by the panel to build and organize the
## model dropdown. No UI nodes, no state. Testable in isolation.
##
## Sort heuristics for "Best for coding" and "Smartest" are keyword
## matches against model name + id. They are useful for finding
## obvious picks (models named *coder*, *deepseek*, *opus*) but are
## not real benchmark rankings.

const CODING_KEYWORDS: Array[String] = [
	"coder", "code", "codestral", "deepseek", "devstral",
	"sonnet", "claude", "qwen", "gpt-4o", "o1", "o3", "opus"
]
const SMART_KEYWORDS: Array[String] = [
	"opus", "405b", "70b", "r1", "thinking", "reasoning",
	"o1", "o3", "pro", "sonnet-4", "sonnet-3.5", "sonnet-3.7"
]


## Filter records by "all" | "free" | "paid". Returns a new array.
static func filter(models: Array, filter_id: String) -> Array:
	if filter_id == "all":
		return models.duplicate()
	var want_free: bool = filter_id == "free"
	var out: Array = []
	for m: Variant in models:
		if not (m is Dictionary):
			continue
		var is_free: bool = bool((m as Dictionary).get("is_free", false))
		if is_free == want_free:
			out.append(m)
	return out


## Sort records in place by sort_id.
## Valid ids: "alphabetical" | "cheap" | "expensive" | "coding" | "smart".
static func sort(models: Array, sort_id: String) -> void:
	match sort_id:
		"cheap":
			models.sort_custom(_cmp_cheap)
		"expensive":
			models.sort_custom(_cmp_expensive)
		"coding":
			models.sort_custom(_cmp_coding)
		"smart":
			models.sort_custom(_cmp_smart)
		_:
			models.sort_custom(_cmp_alpha)


## Format a single record as a display label for the dropdown.
## "[FREE] name" for free models, "[$X.XX/1M] name" for priced,
## "name" for unknown-price.
static func format_label(record: Dictionary) -> String:
	var name: String = str(record.get("name", record.get("id", "")))
	if bool(record.get("is_free", false)):
		return "[FREE] " + name
	var cost: float = float(record.get("effective_cost", -1.0))
	if cost > 0.0:
		return "[$%.2f/1M] %s" % [cost, name]
	return name


## Build a [ { label: String, id: String }, ... ] array ready for the
## panel to feed into an OptionButton. Filters out malformed records.
static func build_entries(models: Array) -> Array:
	var out: Array = []
	for m: Variant in models:
		if not (m is Dictionary):
			continue
		var md: Dictionary = m
		var mid: String = str(md.get("id", ""))
		if mid.is_empty():
			continue
		out.append({
			"id": mid,
			"label": format_label(md),
		})
	return out


# --- Comparators ------------------------------------------------------

static func _cmp_alpha(a: Dictionary, b: Dictionary) -> bool:
	var an: String = str(a.get("name", a.get("id", ""))).to_lower()
	var bn: String = str(b.get("name", b.get("id", ""))).to_lower()
	return an < bn


static func _cmp_cheap(a: Dictionary, b: Dictionary) -> bool:
	var ac: float = float(a.get("effective_cost", -1.0))
	var bc: float = float(b.get("effective_cost", -1.0))
	if ac < 0.0 and bc < 0.0:
		return _cmp_alpha(a, b)
	if ac < 0.0:
		return false
	if bc < 0.0:
		return true
	if not is_equal_approx(ac, bc):
		return ac < bc
	return _cmp_alpha(a, b)


static func _cmp_expensive(a: Dictionary, b: Dictionary) -> bool:
	return not _cmp_cheap(a, b)


static func _cmp_coding(a: Dictionary, b: Dictionary) -> bool:
	return _keyword_score(a) > _keyword_score(b)


static func _cmp_smart(a: Dictionary, b: Dictionary) -> bool:
	return _smart_score(a) > _smart_score(b)


static func _keyword_score(m: Dictionary) -> int:
	var hay: String = (
		str(m.get("name", "")) + " " + str(m.get("id", ""))
	).to_lower()
	var score: int = 0
	for kw: String in CODING_KEYWORDS:
		if kw in hay:
			score += 1
	return score


static func _smart_score(m: Dictionary) -> int:
	var hay: String = (
		str(m.get("name", "")) + " " + str(m.get("id", ""))
	).to_lower()
	var score: int = 0
	for kw: String in SMART_KEYWORDS:
		if kw in hay:
			score += 1
	return score
