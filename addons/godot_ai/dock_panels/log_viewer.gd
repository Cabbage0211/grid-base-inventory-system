@tool
extends VBoxContainer

## Dock subpanel — renders the MCP request/response log buffer. Owns its own
## UI subtree, the line-count cursor, and the display-visibility toggle. It
## receives copied `{sequence, reset, lines}` values; neither this view nor its
## parent Dock retains the root-owned log buffer.
##
## Extracted from mcp_dock.gd as part of audit-v2 #360 — see the comment at
## the top of mcp_dock.gd for the broader extraction story.

signal logging_enabled_changed(enabled: bool)

const Dock := preload("res://addons/godot_ai/mcp_dock.gd")
const Settings := preload("res://addons/godot_ai/utils/settings.gd")

var _log_display: RichTextLabel
var _log_toggle: CheckButton
## Last `McpLogBuffer.total_logged()` value painted into the display. Tracking
## the buffer's monotonic sequence (rather than its bounded `total_count()`)
## keeps the viewer painting once the ring fills — a size-based cursor would
## freeze at MAX_LINES on every subsequent append. See PR #392 for the bug.
var _last_log_seq := 0


## Build the UI synchronously here so callers (and detached-tree tests that
## instantiate the dock with `McpDockScript.new()` and never enter the tree)
## can interact with the panel's controls right after `setup()`. Mirrors the
## pre-extraction inline-build behavior that test_dock.gd relies on.
##
## Idempotent: `_log_display == null` covers an unlikely double-`setup()` call
## without rebuilding (which would orphan the prior controls).
func setup() -> void:
	if _log_display == null:
		_build_ui()


func _build_ui() -> void:
	add_child(HSeparator.new())

	var log_header_row := HBoxContainer.new()
	var log_header := Dock._make_header("MCP Log")
	log_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_header_row.add_child(log_header)

	_log_toggle = CheckButton.new()
	_log_toggle.text = "Log"
	## Restore the persisted choice — a hardcoded `true` here meant the
	## toggle reset to noisy on every editor restart (#626).
	_log_toggle.button_pressed = Settings.mcp_logging_enabled()
	_log_toggle.toggled.connect(_on_log_toggled)
	log_header_row.add_child(_log_toggle)

	add_child(log_header_row)

	_log_display = RichTextLabel.new()
	_log_display.custom_minimum_size = Vector2(0, 80)
	_log_display.scroll_following = true
	_log_display.bbcode_enabled = false
	_log_display.selection_enabled = true
	_log_display.visible = _log_toggle.button_pressed
	add_child(_log_display)


func sequence() -> int:
	return _last_log_seq


func present_snapshot(snapshot: Dictionary) -> void:
	if _log_display == null:
		return
	var seq := int(snapshot.get("sequence", _last_log_seq))
	if bool(snapshot.get("reset", false)) or seq < _last_log_seq:
		_log_display.clear()
		_last_log_seq = 0
	var lines: Array[String] = []
	lines.assign(snapshot.get("lines", []))
	for line in lines:
		_log_display.add_text(line + "\n")
	_last_log_seq = seq


func _on_log_toggled(enabled: bool) -> void:
	Settings.set_mcp_logging_enabled(enabled)
	_log_display.visible = enabled
	logging_enabled_changed.emit(enabled)
