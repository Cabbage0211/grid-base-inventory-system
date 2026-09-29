@tool
extends McpClient


func _init() -> void:
	# #623: Windsurf was rebranded to Devin Desktop by Cognition (June 2026).
	# The id stays "windsurf" — it is the stable registry key used for
	# configured-status lookups. The MCP config path is unchanged by the
	# rebrand: per the official docs (docs.devin.ai/desktop/cascade/mcp) the
	# global config still lives under the platform's `.codeium/windsurf/`
	# directory (~/.codeium/windsurf/ on unix, $USERPROFILE/.codeium/windsurf/
	# on Windows), and migrated installs carry their settings over in place.
	id = "windsurf"
	display_name = "Devin Desktop (Windsurf)"
	config_type = "json"
	path_template = {
		"unix": "~/.codeium/windsurf/mcp_config.json",
		"windows": "$USERPROFILE/.codeium/windsurf/mcp_config.json",
	}
	server_key_path = PackedStringArray(["mcpServers"])
	entry_url_field = "serverUrl"
	## Attach migration (#838). Stdio entries are flat command/args/env
	## (docs.devin.ai/desktop/cascade/mcp); transport is inferred from
	## `command` vs `serverUrl` presence and no type field is documented —
	## do not write one.
	command_shape = McpClient.CommandShape.FLAT
	command_legacy_keys = PackedStringArray(["serverUrl"])
	command_user_fields = PackedStringArray(["env"])
