@tool
class_name GDASettings
extends RefCounted

## GD AI Assistant — Settings Store
##
## Reads/writes user://gd_ai_assistant.cfg. NEVER touches res://.
## API keys live here and here only. Nothing in this file ever gets
## committed to the repo.
##
## Save is explicit: mutating setters mark dirty, callers call
## save_settings() when a change is committed (not on every keystroke).
## On Android, that keeps file I/O off the hot path.

const SETTINGS_PATH: String = "user://gd_ai_assistant.cfg"
const SCHEMA_VERSION: int = 1

const SECTION_GENERAL: String = "general"
const SECTION_AGENT: String = "agent"
const SECTION_PROVIDERS: String = "providers"

const DEFAULT_PROVIDER_ID: String = "openrouter"
const DEFAULT_MODE_OVERRIDE: String = "auto"  # "auto" | "mobile" | "desktop"
const DEFAULT_AGENT_MODE: String = "agent"    # "ask" | "plan" | "agent" | "auto"
const DEFAULT_TEMPERATURE: float = 0.7
const DEFAULT_MAX_RETRIES: int = 3


var _config: ConfigFile = ConfigFile.new()
var _dirty: bool = false
var _loaded: bool = false


# --- Lifecycle ---------------------------------------------------------

func load_settings() -> void:
	_config = ConfigFile.new()
	var err: Error = _config.load(SETTINGS_PATH)
	if err != OK and err != ERR_FILE_NOT_FOUND:
		push_warning(
			"GD AI Assistant: could not load settings (error %d). Using defaults." % err
		)
	_migrate_if_needed()
	_loaded = true
	_dirty = false


func save_settings() -> Error:
	if not _loaded:
		push_warning("GD AI Assistant: save_settings called before load_settings.")
	var err: Error = _config.save(SETTINGS_PATH)
	if err == OK:
		_dirty = false
	else:
		push_error(
			"GD AI Assistant: could not save settings (error %d)." % err
		)
	return err


func is_dirty() -> bool:
	return _dirty


func is_loaded() -> bool:
	return _loaded


# --- General -----------------------------------------------------------

func get_active_provider() -> String:
	return str(
		_config.get_value(SECTION_GENERAL, "active_provider", DEFAULT_PROVIDER_ID)
	)


func set_active_provider(provider_id: String) -> void:
	_config.set_value(SECTION_GENERAL, "active_provider", provider_id)
	_dirty = true


func get_mode_override() -> String:
	return str(
		_config.get_value(SECTION_GENERAL, "mode_override", DEFAULT_MODE_OVERRIDE)
	)


func set_mode_override(value: String) -> void:
	_config.set_value(SECTION_GENERAL, "mode_override", value)
	_dirty = true


func get_desktop_features_enabled() -> bool:
	# Default: on for desktop OSes, off for mobile.
	var default_value: bool = GDAPlatform.is_desktop_os()
	return bool(
		_config.get_value(SECTION_GENERAL, "desktop_features", default_value)
	)


func set_desktop_features_enabled(value: bool) -> void:
	_config.set_value(SECTION_GENERAL, "desktop_features", value)
	_dirty = true


# --- Per-provider ------------------------------------------------------
# Keys and models are namespaced by provider id, e.g.:
#   [providers]
#   openrouter_api_key = "sk-or-..."
#   openrouter_model   = "openai/gpt-4o-mini"
#   ollama_endpoint    = "http://127.0.0.1:11434/v1"

func get_api_key(provider_id: String) -> String:
	return str(
		_config.get_value(SECTION_PROVIDERS, provider_id + "_api_key", "")
	)


func set_api_key(provider_id: String, key: String) -> void:
	_config.set_value(SECTION_PROVIDERS, provider_id + "_api_key", key)
	_dirty = true


func get_provider_model(provider_id: String) -> String:
	return str(
		_config.get_value(SECTION_PROVIDERS, provider_id + "_model", "")
	)


func set_provider_model(provider_id: String, model: String) -> void:
	_config.set_value(SECTION_PROVIDERS, provider_id + "_model", model)
	_dirty = true


func get_custom_endpoint(provider_id: String) -> String:
	return str(
		_config.get_value(SECTION_PROVIDERS, provider_id + "_endpoint", "")
	)


func set_custom_endpoint(provider_id: String, url: String) -> void:
	_config.set_value(SECTION_PROVIDERS, provider_id + "_endpoint", url)
	_dirty = true


func forget_api_key(provider_id: String) -> void:
	var key: String = provider_id + "_api_key"
	if _config.has_section_key(SECTION_PROVIDERS, key):
		_config.erase_section_key(SECTION_PROVIDERS, key)
		_dirty = true


func forget_all_api_keys() -> void:
	if not _config.has_section(SECTION_PROVIDERS):
		return
	for key: String in _config.get_section_keys(SECTION_PROVIDERS):
		if key.ends_with("_api_key"):
			_config.erase_section_key(SECTION_PROVIDERS, key)
	_dirty = true


func has_any_api_key() -> bool:
	if not _config.has_section(SECTION_PROVIDERS):
		return false
	for key: String in _config.get_section_keys(SECTION_PROVIDERS):
		if key.ends_with("_api_key"):
			var value: String = str(
				_config.get_value(SECTION_PROVIDERS, key, "")
			)
			if not value.is_empty():
				return true
	return false


# --- Agent -------------------------------------------------------------

func get_agent_mode() -> String:
	return str(
		_config.get_value(SECTION_AGENT, "mode", DEFAULT_AGENT_MODE)
	)


func set_agent_mode(mode: String) -> void:
	_config.set_value(SECTION_AGENT, "mode", mode)
	_dirty = true


func get_temperature() -> float:
	return float(
		_config.get_value(SECTION_AGENT, "temperature", DEFAULT_TEMPERATURE)
	)


func set_temperature(value: float) -> void:
	_config.set_value(SECTION_AGENT, "temperature", value)
	_dirty = true


func get_max_retries() -> int:
	return int(
		_config.get_value(SECTION_AGENT, "max_retries", DEFAULT_MAX_RETRIES)
	)


func set_max_retries(value: int) -> void:
	_config.set_value(SECTION_AGENT, "max_retries", value)
	_dirty = true


func get_ponytail_mode() -> bool:
	return bool(_config.get_value(SECTION_AGENT, "ponytail", false))


func set_ponytail_mode(value: bool) -> void:
	_config.set_value(SECTION_AGENT, "ponytail", value)
	_dirty = true


func get_eco_mode() -> bool:
	return bool(_config.get_value(SECTION_AGENT, "eco", false))


func set_eco_mode(value: bool) -> void:
	_config.set_value(SECTION_AGENT, "eco", value)
	_dirty = true


# --- Migration ---------------------------------------------------------

func _migrate_if_needed() -> void:
	var stored: int = int(
		_config.get_value(SECTION_GENERAL, "schema_version", 0)
	)
	if stored == 0:
		# Fresh file or pre-versioning format. Stamp current version.
		_config.set_value(SECTION_GENERAL, "schema_version", SCHEMA_VERSION)
		_dirty = true
	elif stored < SCHEMA_VERSION:
		# Future migrations go here, one branch per version step.
		# Example:
		# if stored < 2:
		#     <move some key>
		_config.set_value(SECTION_GENERAL, "schema_version", SCHEMA_VERSION)
		_dirty = true
	# stored > SCHEMA_VERSION: file is from a newer plugin version. Leave
	# it alone. The user gets defaults for unknown keys, but nothing is
	# destroyed — they can downgrade safely.
