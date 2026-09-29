@tool
extends McpClient


func _init() -> void:
	id = "antigravity"
	display_name = "Antigravity"
	config_type = "json"
	## Antigravity moved its shared MCP config from `~/.gemini/antigravity/`
	## to `~/.gemini/config/` (IDE + CLI now read the same file there); the
	## old path is left in `detect_paths` below so an existing install is
	## still recognized, but new/updated entries write to the current path.
	path_template = {
		"unix": "~/.gemini/config/mcp_config.json",
		"windows": "$USERPROFILE/.gemini/config/mcp_config.json",
	}
	server_key_path = PackedStringArray(["mcpServers"])
	entry_url_field = "serverUrl"
	## `disabled` is user-state (they may have flipped the entry off in the
	## UI); seeded on first Configure but preserved across reconfigure.
	entry_initial_fields = {"disabled": false}
	## Attach migration (#838). Antigravity stdio entries are flat
	## command/args/env with no type discriminator — transport is inferred
	## from `command` vs `serverUrl` presence (antigravity.google/docs/mcp),
	## so the legacy `serverUrl` must not survive next to a command.
	command_shape = McpClient.CommandShape.FLAT
	command_legacy_keys = PackedStringArray(["serverUrl"])
	command_initial_fields = {"disabled": false}
	command_user_fields = PackedStringArray(["disabled", "disabledTools", "authProviderType", "env"])
	## Antigravity's spawner hangs stdio tool calls when the entry launches a
	## GUI-subsystem pythonw.exe (#863), and it hides child console windows
	## itself, so the visible-terminal problem the bootstrap solves (#827)
	## never applies. Write the plain console launcher on Windows.
	needs_consoleless_launcher = false
	detect_paths = PackedStringArray(path_template.values() + [
		"~/.gemini/antigravity/mcp_config.json",
		"$USERPROFILE/.gemini/antigravity/mcp_config.json",
	])
