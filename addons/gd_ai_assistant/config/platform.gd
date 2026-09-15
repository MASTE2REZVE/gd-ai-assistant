@tool
class_name GDAPlatform
extends RefCounted

## GD AI Assistant — Platform Detection & Mode Defaults
##
## Detects the current OS and returns runtime limits appropriate for it.
## Android-first: mobile mode is applied by default on Android / iOS.
## Desktop features are available but capped lower on mobile unless the
## user explicitly overrides (see config/settings.gd).
##
## This file never reads or writes settings — it only computes defaults
## and per-mode limits. Callers merge user overrides on top.

enum OSKind { ANDROID, IOS, WINDOWS, MACOS, LINUX, WEB, UNKNOWN }
enum Mode { MOBILE, DESKTOP }


# --- Detection ---------------------------------------------------------

static func detect_os() -> OSKind:
	match OS.get_name():
		"Android":
			return OSKind.ANDROID
		"iOS":
			return OSKind.IOS
		"Windows":
			return OSKind.WINDOWS
		"macOS":
			return OSKind.MACOS
		"Linux":
			return OSKind.LINUX
		"Web":
			return OSKind.WEB
		_:
			return OSKind.UNKNOWN


static func is_android() -> bool:
	return detect_os() == OSKind.ANDROID


static func is_ios() -> bool:
	return detect_os() == OSKind.IOS


static func is_mobile_os() -> bool:
	var kind: OSKind = detect_os()
	return kind == OSKind.ANDROID or kind == OSKind.IOS


static func is_desktop_os() -> bool:
	var kind: OSKind = detect_os()
	return (
		kind == OSKind.WINDOWS
		or kind == OSKind.MACOS
		or kind == OSKind.LINUX
	)


static func is_editor() -> bool:
	return Engine.is_editor_hint()


# --- Mode defaults -----------------------------------------------------

## What mode does this OS default to, ignoring any user override?
static func default_mode() -> Mode:
	return Mode.MOBILE if is_mobile_os() else Mode.DESKTOP


## Resolve the effective mode given a user override string.
## Accepts: "auto", "mobile", "desktop". Anything else means auto.
static func resolve_mode(user_override: String) -> Mode:
	match user_override.to_lower():
		"mobile":
			return Mode.MOBILE
		"desktop":
			return Mode.DESKTOP
		_:
			return default_mode()


# --- Runtime limits per mode ------------------------------------------

## Returns the runtime limits for a mode. Every key is always present
## so callers never need to guess. Do not add keys that only some modes
## understand — the shapes must match.
static func limits_for(mode: Mode) -> Dictionary:
	if mode == Mode.MOBILE:
		return {
			"history_turns": 8,
			"tool_result_chars": 2000,
			"token_budget": 4000,
			"streaming": false,
			"diff_preview_animated": false,
			"api_injector": false,
			"gotchas": false,
			"web_search": false,
			"http_timeout_sec": 30.0,
			"chat_repaint_ms": 100,
		}
	return {
		"history_turns": 20,
		"tool_result_chars": 8000,
		"token_budget": 12000,
		"streaming": true,
		"diff_preview_animated": true,
		"api_injector": true,
		"gotchas": true,
		"web_search": true,
		"http_timeout_sec": 60.0,
		"chat_repaint_ms": 0,
	}


## Effective limits after merging a resolved mode with the user's
## desktop-features toggle. If desktop features are enabled while the
## resolved mode is MOBILE, the desktop-only flags are forced on.
## Caps that affect memory / CPU (history_turns, tool_result_chars,
## token_budget) are intentionally NOT raised — those stay capped so a
## tablet cannot be talked into running a desktop-sized context.
static func effective_limits(
	mode: Mode,
	desktop_features_enabled: bool
) -> Dictionary:
	var limits: Dictionary = limits_for(mode)
	if desktop_features_enabled and mode == Mode.MOBILE:
		limits["streaming"] = true
		limits["diff_preview_animated"] = true
		limits["api_injector"] = true
		limits["gotchas"] = true
		limits["web_search"] = true
	return limits


# --- Human-readable helpers -------------------------------------------

static func os_name() -> String:
	return OS.get_name()


static func mode_name(mode: Mode) -> String:
	return "Mobile" if mode == Mode.MOBILE else "Desktop"


## True if the current mobile device looks phone-class rather than
## tablet-class, based on the shorter screen dimension. Used only to
## emit a warning — the plugin still works on phones.
static func is_phone_class() -> bool:
	if not is_mobile_os():
		return false
	var size: Vector2i = DisplayServer.screen_get_size()
	var min_dim: int = mini(size.x, size.y)
	return min_dim < 600
