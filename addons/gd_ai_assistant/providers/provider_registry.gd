@tool
class_name GDAProviderRegistry
extends RefCounted

## GD AI Assistant — Provider Registry

const PRESETS: Dictionary = {
	"openrouter": {
		"kind": "openai_compat",
		"display_name": "OpenRouter",
		"endpoint": "https://openrouter.ai/api/v1",
		"is_local": false,
		"requires_key": true,
		"supports_tools": true,
		"supports_models": true,
		"extra_headers": [
			"HTTP-Referer: https://github.com/gd-ai-assistant",
			"X-Title: GD AI Assistant",
		],
		"default_model": "openai/gpt-4o-mini",
	},
	"modelscope": {
		"kind": "openai_compat",
		"display_name": "ModelScope",
		"endpoint": "https://api-inference.modelscope.ai/v1",
		"is_local": false,
		"requires_key": true,
		"supports_tools": true,
		"supports_models": true,
		"default_model": "Qwen/Qwen3-30B-A3B-Instruct-2507",
	},
	"openai": {
		"kind": "openai_compat",
		"display_name": "OpenAI",
		"endpoint": "https://api.openai.com/v1",
		"is_local": false,
		"requires_key": true,
		"supports_tools": true,
		"supports_models": true,
		"default_model": "gpt-4o-mini",
	},
	"anthropic": {
		"kind": "native",
		"display_name": "Anthropic",
		"endpoint": "https://api.anthropic.com/v1",
		"is_local": false,
		"requires_key": true,
		"supports_tools": true,
		"supports_models": false,
		"default_model": "claude-3-5-sonnet-latest",
	},
	"gemini": {
		"kind": "openai_compat",
		"display_name": "Google Gemini",
		"endpoint": "https://generativelanguage.googleapis.com/v1beta/openai",
		"is_local": false,
		"requires_key": true,
		"supports_tools": true,
		"supports_models": true,
		"default_model": "gemini-2.0-flash",
	},
	"groq": {
		"kind": "openai_compat",
		"display_name": "Groq",
		"endpoint": "https://api.groq.com/openai/v1",
		"is_local": false,
		"requires_key": true,
		"supports_tools": true,
		"supports_models": true,
		"default_model": "llama-3.3-70b-versatile",
	},
	"deepseek": {
		"kind": "openai_compat",
		"display_name": "DeepSeek",
		"endpoint": "https://api.deepseek.com/v1",
		"is_local": false,
		"requires_key": true,
		"supports_tools": true,
		"supports_models": true,
		"default_model": "deepseek-chat",
	},
	"mistral": {
		"kind": "openai_compat",
		"display_name": "Mistral",
		"endpoint": "https://api.mistral.ai/v1",
		"is_local": false,
		"requires_key": true,
		"supports_tools": true,
		"supports_models": true,
		"default_model": "mistral-large-latest",
	},
	"xai": {
		"kind": "openai_compat",
		"display_name": "xAI Grok",
		"endpoint": "https://api.x.ai/v1",
		"is_local": false,
		"requires_key": true,
		"supports_tools": true,
		"supports_models": true,
		"default_model": "grok-2-latest",
	},
	"ollama": {
		"kind": "openai_compat",
		"display_name": "Ollama (local)",
		"endpoint": "http://127.0.0.1:11434/v1",
		"is_local": true,
		"requires_key": false,
		"supports_tools": true,
		"supports_models": true,
		"default_model": "qwen2.5:3b",
	},
	"lmstudio": {
		"kind": "openai_compat",
		"display_name": "LM Studio (local)",
		"endpoint": "http://127.0.0.1:1234/v1",
		"is_local": true,
		"requires_key": false,
		"supports_tools": true,
		"supports_models": true,
		"default_model": "local-model",
	},
	"custom": {
		"kind": "openai_compat",
		"display_name": "Custom",
		"endpoint": "",
		"is_local": false,
		"requires_key": false,
		"supports_tools": true,
		"supports_models": true,
		"default_model": "",
	},
}


static func get_all_ids() -> Array:
	return PRESETS.keys()


static func has_provider(id: String) -> bool:
	return PRESETS.has(id)


static func get_preset(id: String) -> Dictionary:
	var raw: Variant = PRESETS.get(id, null)
	if raw is Dictionary:
		return (raw as Dictionary).duplicate(true)
	return {}


static func get_display_name(id: String) -> String:
	var preset: Dictionary = get_preset(id)
	if preset.is_empty():
		return id
	return str(preset.get("display_name", id))


static func get_default_model(id: String) -> String:
	var preset: Dictionary = get_preset(id)
	if preset.is_empty():
		return ""
	return str(preset.get("default_model", ""))


static func is_local(id: String) -> bool:
	var preset: Dictionary = get_preset(id)
	return bool(preset.get("is_local", false))


static func requires_api_key(id: String) -> bool:
	var preset: Dictionary = get_preset(id)
	return bool(preset.get("requires_key", true))


static func is_native(id: String) -> bool:
	var preset: Dictionary = get_preset(id)
	return str(preset.get("kind", "")) == "native"


static func is_available(id: String) -> bool:
	if not has_provider(id):
		return false
	if is_native(id):
		return false
	return true


static func get_ui_entries() -> Array:
	var out: Array = []
	for id: String in PRESETS.keys():
		out.append({
			"id": id,
			"name": get_display_name(id),
			"is_local": is_local(id),
			"available": is_available(id),
		})
	return out


static func build_provider(
	id: String,
	settings: GDASettings
) -> GDAProviderBase:
	if not has_provider(id):
		push_error("GDAProviderRegistry: unknown provider id '%s'." % id)
		return null

	if is_native(id):
		push_warning(
			"GDAProviderRegistry: provider '%s' is native and not "
			+ "implemented yet (Phase 3)." % id
		)
		return null

	var preset: Dictionary = get_preset(id)
	preset["id"] = id

	var endpoint_override: String = ""
	if settings != null:
		endpoint_override = settings.get_custom_endpoint(id)
	if not endpoint_override.is_empty():
		preset["endpoint"] = endpoint_override

	var instance: GDAOpenAICompat = GDAOpenAICompat.new()
	instance.configure(preset)
	return instance


static func fetch_models(
	id: String,
	settings: GDASettings
) -> Array:
	if not is_available(id):
		return []
	var provider: GDAProviderBase = build_provider(id, settings)
	if provider == null:
		return []
	if not provider.supports_model_listing():
		return []

	var api_key: String = ""
	var endpoint_override: String = ""
	if settings != null:
		api_key = settings.get_api_key(id)
		endpoint_override = settings.get_custom_endpoint(id)

	return await provider.list_models(api_key, endpoint_override)
