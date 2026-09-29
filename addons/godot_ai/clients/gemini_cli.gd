@tool
extends McpClient


func _init() -> void:
	id = "gemini_cli"
	display_name = "Gemini CLI"
	config_type = "json"
	path_template = {
		"unix": "~/.gemini/settings.json",
		"windows": "$USERPROFILE/.gemini/settings.json",
	}
	server_key_path = PackedStringArray(["mcpServers"])
	entry_url_field = "httpUrl"
	## Attach migration (#838). Gemini CLI stdio entries are flat
	## command/args/env(+cwd); the config is one-of `command` | `url` (SSE) |
	## `httpUrl` (docs/tools/mcp-server.md), so BOTH URL keys are legacy next
	## to a command. `trust` bypasses tool confirmations — never seed it.
	command_shape = McpClient.CommandShape.FLAT
	command_legacy_keys = PackedStringArray(["httpUrl", "url"])
	command_user_fields = PackedStringArray([
		"timeout", "trust", "includeTools", "excludeTools", "env", "cwd",
	])
	command_timeout_fields = PackedStringArray(["timeout"])
