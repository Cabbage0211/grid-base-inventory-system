@tool
extends McpClient


func _init() -> void:
	id = "grok"
	display_name = "Grok Build"
	config_type = "toml"
	# Grok Build reads MCP servers from ~/.grok/config.toml
	# (https://x.ai / Grok user guide: MCP servers section).
	path_template = {
		"unix": "~/.grok/config.toml",
		"windows": "$USERPROFILE/.grok/config.toml",
	}
	toml_section_path = PackedStringArray(["mcp_servers", "godot-ai"])
	# Some docs / older notes used an underscore form.
	toml_legacy_section_aliases = PackedStringArray(["mcp_servers.godot_ai"])
	## Attach migration (#838). Grok's stdio sections are flat command/args/env
	## with no type discriminator (docs.x.ai/build/features/mcp-servers);
	## url/headers are the HTTP form and must not survive next to a command.
	## Docs default startup_timeout_sec to 30 — a cold `uvx` install of the
	## pinned package can exceed that, so new entries seed 60 (preserved once
	## the user tunes it). tool_timeout_sec's documented 6000s default already
	## clears test_run's 300s budget, so it is left alone. The old body
	## template's `enabled = true` line was never documented for Grok — it is
	## no longer seeded, and an existing value survives as a user key.
	command_shape = McpClient.CommandShape.COMMAND_ARRAY
	command_legacy_keys = PackedStringArray(["url", "headers"])
	command_initial_fields = {"startup_timeout_sec": 60}
	command_user_fields = PackedStringArray([
		"env", "enabled", "startup_timeout_sec", "tool_timeout_sec",
	])
	command_timeout_fields = PackedStringArray(["startup_timeout_sec", "tool_timeout_sec"])
	detect_paths = PackedStringArray(path_template.values())
