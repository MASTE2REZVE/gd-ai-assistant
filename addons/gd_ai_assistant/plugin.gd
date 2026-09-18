@tool
extends Control

const MODE_ORDER: Array[String] = ["ask", "plan", "agent", "auto"]
const FILTER_ORDER: Array[String] = ["all", "free", "paid"]
const SORT_ORDER: Array[String] = [
	"alphabetical", "cheap", "expensive", "coding", "smart"
]


var _settings: GDASettings = null
var _registry: GDAToolRegistry = null
var _harness: GDAHarness = null
var _provider: GDAProviderBase = null
var _editor_interface: EditorInterface = null

var _provider_dd: OptionButton
var _model_input: LineEdit
var _model_list_dd: OptionButton
var _refresh_models_btn: Button
var _fast_check: CheckBox
var _mode_dd: OptionButton
var _settings_btn: Button
var _filter_dd: OptionButton
var _sort_dd: OptionButton
var _model_filter_bar: Control
var _settings_bar: Container
var _api_key_input: LineEdit
var _save_key_btn: Button
var _desktop_features_check: CheckBox
var _chat: RichTextLabel
var _message_input: LineEdit
var _send_btn: Button
var _stop_btn: Button
var _copy_latest_btn: Button
var _copy_all_btn: Button
var _status_label: Label
var _token_label: Label
var _undo_btn: Button
var _approval_bar: Container
var _approval_label: Label
var _approve_btn: Button
var _reject_btn: Button

var _all_models: Array = []
var _last_assistant_reply: String = ""
var _streaming_reply: String = ""
var _streaming_in_progress: bool = false


func set_editor_interface(iface: EditorInterface) -> void:
	_editor_interface = iface


func _ready() -> void:
	if not _cache_nodes():
		return
	_build_services()
	_wire_harness_signals()
	_wire_ui()
	_populate_provider_dropdown()
	_populate_mode_dropdown()
	_populate_filter_dropdown()
	_populate_sort_dropdown()
	var active_id: String = _settings.get_active_provider()
	if not GDAProviderRegistry.has_provider(active_id):
		active_id = "openrouter"
	_select_provider_by_id(active_id)
	_select_mode_by_id(_settings.get_agent_mode())
	_select_filter_by_id("all")
	_select_sort_by_id("alphabetical")
	_desktop_features_check.button_pressed = _settings.get_desktop_features_enabled()
	_fast_check.button_pressed = _settings.get_fast_mode()
	_refresh_api_key_field()
	_refresh_model_field()
	_refresh_undo_button()
	_set_status("Ready")
	_append_system("GD AI Assistant ready. Type a message and press Send.")


func _cache_nodes() -> bool:
	_provider_dd = get_node_or_null("TopBar/ProviderDropdown") as OptionButton
	_model_input = get_node_or_null("TopBar/ModelInput") as LineEdit
	_model_list_dd = get_node_or_null("TopBar/ModelListDropdown") as OptionButton
	_refresh_models_btn = get_node_or_null("TopBar/RefreshModelsBtn") as Button
	_fast_check = get_node_or_null("TopBar/FastCheck") as CheckBox
	_mode_dd = get_node_or_null("TopBar/ModeDropdown") as OptionButton
	_settings_btn = get_node_or_null("TopBar/SettingsBtn") as Button
	_model_filter_bar = get_node_or_null("ModelFilterBar") as Control
	_filter_dd = get_node_or_null("ModelFilterBar/FilterDropdown") as OptionButton
	_sort_dd = get_node_or_null("ModelFilterBar/SortDropdown") as OptionButton
	_settings_bar = get_node_or_null("SettingsBar") as Container
	_api_key_input = get_node_or_null("SettingsBar/APIKeyInput") as LineEdit
	_save_key_btn = get_node_or_null("SettingsBar/SaveKeyBtn") as Button
	_desktop_features_check = get_node_or_null("SettingsBar/DesktopFeaturesCheck") as CheckBox
	_chat = get_node_or_null("ChatHistory") as RichTextLabel
	_message_input = get_node_or_null("InputBar/MessageInput") as LineEdit
	_send_btn = get_node_or_null("InputBar/SendBtn") as Button
	_stop_btn = get_node_or_null("InputBar/StopBtn") as Button
	_copy_latest_btn = get_node_or_null("InputBar/CopyLatestBtn") as Button
	_copy_all_btn = get_node_or_null("InputBar/CopyAllBtn") as Button
	_status_label = get_node_or_null("StatusBar/StatusLabel") as Label
	_token_label = get_node_or_null("StatusBar/TokenLabel") as Label
	_undo_btn = get_node_or_null("StatusBar/UndoBtn") as Button
	_approval_bar = get_node_or_null("ApprovalBar") as Container
	_approval_label = get_node_or_null("ApprovalBar/ApprovalLabel") as Label
	_approve_btn = get_node_or_null("ApprovalBar/ApproveBtn") as Button
	_reject_btn = get_node_or_null("ApprovalBar/RejectBtn") as Button

	var missing: Array[String] = []
	if _provider_dd == null: missing.append("ProviderDropdown")
	if _model_input == null: missing.append("ModelInput")
	if _model_list_dd == null: missing.append("ModelListDropdown")
	if _refresh_models_btn == null: missing.append("RefreshModelsBtn")
	if _fast_check == null: missing.append("FastCheck")
	if _mode_dd == null: missing.append("ModeDropdown")
	if _settings_btn == null: missing.append("SettingsBtn")
	if _model_filter_bar == null: missing.append("ModelFilterBar")
	if _filter_dd == null: missing.append("FilterDropdown")
	if _sort_dd == null: missing.append("SortDropdown")
	if _settings_bar == null: missing.append("SettingsBar")
	if _api_key_input == null: missing.append("APIKeyInput")
	if _save_key_btn == null: missing.append("SaveKeyBtn")
	if _desktop_features_check == null: missing.append("DesktopFeaturesCheck")
	if _chat == null: missing.append("ChatHistory")
	if _message_input == null: missing.append("MessageInput")
	if _send_btn == null: missing.append("SendBtn")
	if _stop_btn == null: missing.append("StopBtn")
	if _copy_latest_btn == null: missing.append("CopyLatestBtn")
	if _copy_all_btn == null: missing.append("CopyAllBtn")
	if _status_label == null: missing.append("StatusLabel")
	if _token_label == null: missing.append("TokenLabel")
	if _undo_btn == null: missing.append("UndoBtn")
	if _approval_bar == null: missing.append("ApprovalBar")
	if _approval_label == null: missing.append("ApprovalLabel")
	if _approve_btn == null: missing.append("ApproveBtn")
	if _reject_btn == null: missing.append("RejectBtn")

	if not missing.is_empty():
		push_error("GD AI Assistant: panel nodes missing: " + ", ".join(missing))
		return false
	return true


func _wire_ui() -> void:
	_send_btn.pressed.connect(_on_send_pressed)
	_stop_btn.pressed.connect(_on_stop_pressed)
	_settings_btn.pressed.connect(_on_settings_toggled)
	_refresh_models_btn.pressed.connect(_on_refresh_models_pressed)
	_save_key_btn.pressed.connect(_on_save_key_pressed)
	_copy_latest_btn.pressed.connect(_on_copy_latest_pressed)
	_copy_all_btn.pressed.connect(_on_copy_all_pressed)
	_undo_btn.pressed.connect(_on_undo_pressed)
	_provider_dd.item_selected.connect(_on_provider_selected)
	_mode_dd.item_selected.connect(_on_mode_selected)
	_model_list_dd.item_selected.connect(_on_model_from_list_selected)
	_filter_dd.item_selected.connect(_on_filter_changed)
	_sort_dd.item_selected.connect(_on_sort_changed)
	_message_input.text_submitted.connect(_on_message_submitted)
	_api_key_input.text_submitted.connect(_on_api_key_submitted)
	_model_input.text_submitted.connect(_on_model_submitted)
	_desktop_features_check.toggled.connect(_on_desktop_features_toggled)
	_fast_check.toggled.connect(_on_fast_toggled)
	_approve_btn.pressed.connect(_on_approve_pressed)
	_reject_btn.pressed.connect(_on_reject_pressed)


func _wire_harness_signals() -> void:
	_harness.turn_started.connect(_on_turn_started)
	_harness.turn_finished.connect(_on_turn_finished)
	_harness.assistant_message.connect(_on_assistant_message)
	_harness.assistant_token.connect(_on_assistant_token)
	_harness.error_occurred.connect(_on_error_occurred)
	_harness.tool_call_started.connect(_on_tool_call_started)
	_harness.tool_call_finished.connect(_on_tool_call_finished)
	_harness.approval_required.connect(_on_approval_required)
	_harness.checkpoint_created.connect(_on_checkpoint_created)
	_harness.status_changed.connect(_on_status_changed)


func _build_services() -> void:
	_settings = GDASettings.new()
	_settings.load_settings()
	_registry = GDAToolRegistry.new()
	_registry.build()
	_harness = GDAHarness.new()
	_rebuild_provider()
	var prompt: String = GDASystemPrompt.build(
		_mode_string_from_settings(), "", _settings.get_fast_mode()
	)
	_harness.configure(_settings, _registry, self, _editor_interface, _provider, prompt)
	if _settings.is_dirty():
		_settings.save_settings()


func _rebuild_provider() -> void:
	var id: String = _settings.get_active_provider()
	if not GDAProviderRegistry.is_available(id):
		id = "openrouter"
		_settings.set_active_provider(id)
	_provider = GDAProviderRegistry.build_provider(id, _settings)
	_harness.set_provider(_provider)


func _mode_string_from_settings() -> String:
	if _settings.get_eco_mode():
		return "eco"
	if _settings.get_ponytail_mode():
		return "ponytail"
	return "standard"


func _populate_provider_dropdown() -> void:
	_provider_dd.clear()
	var ids: Array = GDAProviderRegistry.get_ui_ids()
	var i: int = 0
	for id_v: Variant in ids:
		var id: String = str(id_v)
		_provider_dd.add_item(GDAProviderRegistry.get_display_name(id), i)
		_provider_dd.set_item_metadata(i, id)
		i += 1


func _populate_mode_dropdown() -> void:
	_mode_dd.clear()
	var labels: Array[String] = ["ASK (no tools)", "PLAN (read only)", "AGENT (ask first)", "AUTO (auto edit)"]
	for i: int in range(MODE_ORDER.size()):
		_mode_dd.add_item(labels[i], i)
		_mode_dd.set_item_metadata(i, MODE_ORDER[i])


func _populate_filter_dropdown() -> void:
	_filter_dd.clear()
	var labels: Array[String] = ["All models", "Free only", "Paid only"]
	for i: int in range(FILTER_ORDER.size()):
		_filter_dd.add_item(labels[i], i)
		_filter_dd.set_item_metadata(i, FILTER_ORDER[i])


func _populate_sort_dropdown() -> void:
	_sort_dd.clear()
	var labels: Array[String] = ["A → Z", "Cheapest first", "Most expensive", "Best for coding", "Smartest (heuristic)"]
	for i: int in range(SORT_ORDER.size()):
		_sort_dd.add_item(labels[i], i)
		_sort_dd.set_item_metadata(i, SORT_ORDER[i])


func _select_provider_by_id(id: String) -> void:
	_select_by_metadata(_provider_dd, id)


func _select_mode_by_id(mode: String) -> void:
	_select_by_metadata(_mode_dd, mode)


func _select_filter_by_id(id: String) -> void:
	_select_by_metadata(_filter_dd, id)


func _select_sort_by_id(id: String) -> void:
	_select_by_metadata(_sort_dd, id)


func _select_by_metadata(dd: OptionButton, value: String) -> void:
	for i: int in range(dd.item_count):
		if str(dd.get_item_metadata(i)) == value:
			dd.select(i)
			return


func _selected_provider_id() -> String:
	var idx: int = _provider_dd.selected
	if idx < 0:
		return "openrouter"
	return str(_provider_dd.get_item_metadata(idx))


func _selected_mode_id() -> String:
	var idx: int = _mode_dd.selected
	if idx < 0:
		return "agent"
	return str(_mode_dd.get_item_metadata(idx))


func _selected_filter_id() -> String:
	var idx: int = _filter_dd.selected
	if idx < 0:
		return "all"
	return str(_filter_dd.get_item_metadata(idx))


func _selected_sort_id() -> String:
	var idx: int = _sort_dd.selected
	if idx < 0:
		return "alphabetical"
	return str(_sort_dd.get_item_metadata(idx))


func _on_provider_selected(_idx: int) -> void:
	var id: String = _selected_provider_id()
	_settings.set_active_provider(id)
	_settings.save_settings()
	_rebuild_provider()
	_all_models.clear()
	_model_list_dd.clear()
	_model_filter_bar.visible = false
	_refresh_api_key_field()
	_refresh_model_field()
	_refresh_prompt()
	_append_system("Provider: " + GDAProviderRegistry.get_display_name(id))


func _on_mode_selected(_idx: int) -> void:
	var mode: String = _selected_mode_id()
	_settings.set_agent_mode(mode)
	_settings.save_settings()
	_refresh_prompt()
	_append_system("Mode: " + mode.to_upper())


func _on_settings_toggled() -> void:
	_settings_bar.visible = not _settings_bar.visible


func _on_fast_toggled(pressed: bool) -> void:
	_settings.set_fast_mode(pressed)
	_settings.save_settings()
	_refresh_prompt()
	if pressed:
		_append_system("⚡ Fast mode ON — the AI will skip exploration. Fewer tool calls, faster replies, less careful.")
	else:
		_append_system("Fast mode off — full exploration and inspection.")


func _on_desktop_features_toggled(pressed: bool) -> void:
	_settings.set_desktop_features_enabled(pressed)
	_settings.save_settings()
	_refresh_prompt()
	if pressed:
		_append_system("Desktop features ENABLED.")
	else:
		_append_system("Desktop features disabled (mobile defaults).")


func _on_api_key_submitted(_text: String) -> void:
	_on_save_key_pressed()


func _on_save_key_pressed() -> void:
	var id: String = _settings.get_active_provider()
	var key: String = _api_key_input.text.strip_edges()
	# Ignore the placeholder — it isn't a real key.
	if key == "••••••••••••••••":
		return
	_settings.set_api_key(id, key)
	_settings.save_settings()
	_rebuild_provider()
	if key.is_empty():
		_set_status("API key cleared for " + id)
	else:
		_set_status("API key saved for " + id)
	_refresh_api_key_field()


func _on_model_submitted(text: String) -> void:
	var id: String = _settings.get_active_provider()
	var model: String = text.strip_edges()
	_settings.set_provider_model(id, model)
	_settings.save_settings()
	_set_status("Model set to " + model)


func _on_model_from_list_selected(idx: int) -> void:
	if idx < 0:
		return
	var model_id: String = str(_model_list_dd.get_item_metadata(idx))
	if model_id.is_empty():
		return
	var id: String = _settings.get_active_provider()
	_settings.set_provider_model(id, model_id)
	_settings.save_settings()
	_model_input.text = model_id
	_set_status("Model set to " + model_id)


func _on_filter_changed(_idx: int) -> void:
	_apply_model_view()


func _on_sort_changed(_idx: int) -> void:
	_apply_model_view()


func _on_refresh_models_pressed() -> void:
	var id: String = _settings.get_active_provider()
	if not GDAProviderRegistry.is_available(id):
		_set_status("Provider unavailable.")
		return
	_refresh_models_btn.disabled = true
	_set_status("Fetching models...")
	var models: Array = await GDAProviderRegistry.fetch_models(id, _settings)
	_refresh_models_btn.disabled = false
	if models.is_empty():
		_set_status("No models returned (check Output for errors).")
		_append_system("Model fetch returned 0. Check the Output panel for HTTP errors.")
		return
	_all_models = models
	_model_filter_bar.visible = true
	_apply_model_view()
	_set_status("Loaded %d models." % models.size())


func _apply_model_view() -> void:
	var filtered: Array = GDAModelView.filter(_all_models, _selected_filter_id())
	GDAModelView.sort(filtered, _selected_sort_id())
	var entries: Array = GDAModelView.build_entries(filtered)
	_model_list_dd.clear()
	var i: int = 0
	for e_v: Variant in entries:
		if not (e_v is Dictionary):
			continue
		var e: Dictionary = e_v
		_model_list_dd.add_item(str(e["label"]), i)
		_model_list_dd.set_item_metadata(i, str(e["id"]))
		i += 1


func _on_message_submitted(_text: String) -> void:
	_on_send_pressed()


func _on_send_pressed() -> void:
	if _harness.is_running():
		return
	var text: String = _message_input.text.strip_edges()
	if text.is_empty():
		return
	_message_input.clear()

	if text == "@clear":
		_harness.clear_history()
		_chat.clear()
		_last_assistant_reply = ""
		_append_system("History cleared.")
		return
	if text == "@errors":
		_append_system(_fetch_recent_errors())
		return
	if text == "@undo":
		_on_undo_pressed()
		return

	_append_user(text)
	_send_btn.disabled = true
	_set_status("Working...")
	_harness.start_turn(text)


func _on_stop_pressed() -> void:
	if not _harness.is_running():
		return
	_harness.cancel()
	_set_status("Cancelled")


func _on_undo_pressed() -> void:
	if _harness.is_running():
		_set_status("Cannot undo while running.")
		return
	var r: Dictionary = _harness.undo_last()
	if bool(r.get("ok", false)):
		_append_system("⟲ " + str(r.get("message", "Undone.")))
		_last_assistant_reply = ""
		_refresh_undo_button()
	else:
		_append_system("Undo failed: " + str(r.get("message", "")))
		_set_status("Undo failed.")


func _on_copy_latest_pressed() -> void:
	if _last_assistant_reply.is_empty():
		_set_status("Nothing to copy.")
		return
	DisplayServer.clipboard_set(_last_assistant_reply)
	_set_status("Copied latest reply.")


func _on_copy_all_pressed() -> void:
	var text_to_copy: String = _chat.get_parsed_text()
	if text_to_copy.strip_edges().is_empty():
		_set_status("Chat is empty.")
		return
	DisplayServer.clipboard_set(text_to_copy)
	_set_status("Copied full chat.")


func _on_approve_pressed() -> void:
	_approval_bar.visible = false
	_harness.resolve_approval(true)


func _on_reject_pressed() -> void:
	_approval_bar.visible = false
	_harness.resolve_approval(false)


func _on_turn_started() -> void:
	_stop_btn.disabled = false
	_streaming_reply = ""
	_streaming_in_progress = false


func _on_turn_finished(ok: bool, message: String) -> void:
	_send_btn.disabled = false
	_stop_btn.disabled = true
	_approval_bar.visible = false
	if _streaming_in_progress:
		_append_line("\n")
		_streaming_in_progress = false
	if ok:
		_set_status("Ready")
	else:
		_set_status("Turn ended: " + message)
	_refresh_token_estimate()
	_refresh_undo_button()


func _on_assistant_token(token: String) -> void:
	if not _streaming_in_progress:
		_chat.append_text("\n[AI] ")
		_streaming_in_progress = true
	_streaming_reply += token
	_chat.append_text(token)
	var bar: VScrollBar = _chat.get_v_scroll_bar()
	if bar != null:
		bar.value = bar.max_value


func _on_assistant_message(text: String) -> void:
	_last_assistant_reply = text
	if _streaming_in_progress:
		_streaming_reply = text
		_streaming_in_progress = false
		_append_line("\n")
	else:
		_append_assistant(text)


func _on_error_occurred(message: String) -> void:
	_append_system("Error: " + message)
	_set_status("Error")
	_send_btn.disabled = false
	_stop_btn.disabled = true
	_streaming_in_progress = false


func _on_tool_call_started(tool_name: String, args: Dictionary) -> void:
	_append_tool("→ %s %s" % [tool_name, _short_args(args)])


func _on_tool_call_finished(tool_name: String, ok: bool, message: String) -> void:
	var marker: String = "✓" if ok else "✗"
	var short_msg: String = message.strip_edges()
	if short_msg.length() > 200:
		short_msg = short_msg.substr(0, 200) + "..."
	_append_tool("  %s %s: %s" % [marker, tool_name, short_msg])


func _on_approval_required(tool_name: String, args: Dictionary) -> void:
	_approval_label.text = "Approve %s %s?" % [tool_name, _short_args(args)]
	_approval_bar.visible = true


func _on_checkpoint_created(_id: String, _label: String) -> void:
	_refresh_undo_button()


func _on_status_changed(text: String) -> void:
	_set_status(text)


func _refresh_prompt() -> void:
	var prompt: String = GDASystemPrompt.build(
		_mode_string_from_settings(), "", _settings.get_fast_mode()
	)
	_harness.set_system_prompt(prompt)


func _refresh_api_key_field() -> void:
	var id: String = _settings.get_active_provider()
	var key: String = _settings.get_api_key(id)
	# NEVER put the real key back into the field. If Godot saves the
	# scene, whatever is in this LineEdit.text gets baked into the .tscn
	# file — and if the user commits their project, the key leaks.
	# Show a placeholder instead. The real key lives only in
	# user://gd_ai_assistant.cfg.
	if key.is_empty():
		_api_key_input.text = ""
	else:
		_api_key_input.text = "••••••••••••••••"
		_api_key_input.placeholder_text = "Key saved. Type a new key to replace."
	var show_settings: bool = (GDAProviderRegistry.requires_api_key(id) and key.is_empty())
	_settings_bar.visible = show_settings


func _refresh_model_field() -> void:
	var id: String = _settings.get_active_provider()
	var model: String = _settings.get_provider_model(id)
	if model.is_empty():
		model = GDAProviderRegistry.get_default_model(id)
	_model_input.text = model


func _refresh_undo_button() -> void:
	if _undo_btn == null:
		return
	_undo_btn.disabled = not _harness.can_undo()


func _refresh_token_estimate() -> void:
	var tools_canonical: Array = _registry.to_canonical_array()
	var tools_cost: int = GDATokenCounter.estimate_tools(tools_canonical)
	var prompt_cost: int = GDATokenCounter.estimate_text(
		GDASystemPrompt.build(
			_mode_string_from_settings(), "", _settings.get_fast_mode()
		)
	)
	var total: int = tools_cost + prompt_cost
	_token_label.text = GDATokenCounter.format_estimate(total)


func _append_user(text: String) -> void:
	_append_line("\n[You] " + text + "\n")


func _append_assistant(text: String) -> void:
	_append_line("\n[AI] " + text + "\n")


func _append_tool(text: String) -> void:
	_append_line("[tool] " + text + "\n")


func _append_system(text: String) -> void:
	_append_line("[system] " + text + "\n")


func _append_line(text: String) -> void:
	_chat.append_text(text)
	var bar: VScrollBar = _chat.get_v_scroll_bar()
	if bar != null:
		bar.value = bar.max_value


func _set_status(text: String) -> void:
	_status_label.text = text


func _short_args(args: Dictionary) -> String:
	if args.is_empty():
		return ""
	var parts: Array[String] = []
	var keys: Array = args.keys()
	keys.sort()
	for k: String in keys:
		if parts.size() >= 2:
			break
		var v: Variant = args[k]
		var s: String = str(v)
		if s.length() > 40:
			s = s.substr(0, 40) + "…"
		parts.append("%s=%s" % [k, s])
	return "(" + ", ".join(parts) + ")"


func _fetch_recent_errors() -> String:
	var log_path: String = OS.get_user_data_dir().path_join("logs/godot.log")
	if not FileAccess.file_exists(log_path):
		return "No godot.log found."
	var f: FileAccess = FileAccess.open(log_path, FileAccess.READ)
	if f == null:
		return "Cannot read godot.log."
	var out: Array[String] = []
	while not f.eof_reached():
		var line: String = f.get_line()
		if ("ERROR:" in line or "SCRIPT ERROR:" in line or "Parse Error:" in line):
			out.append(line)
	f.close()
	if out.is_empty():
		return "No recent errors in godot.log."
	if out.size() > 30:
		out = out.slice(out.size() - 30)
	return "\n".join(out)
