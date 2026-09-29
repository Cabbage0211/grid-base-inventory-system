@tool
extends McpClient


func _init() -> void:
	id = "cursor"
	display_name = "Cursor"
	config_type = "json"
	path_template = {"unix": "~/.cursor/mcp.json", "windows": "$USERPROFILE/.cursor/mcp.json"}
	server_key_path = PackedStringArray(["mcpServers"])
	## Attach migration (#838). Cursor's stdio entries are flat command/args/env
	## (cursor.com/docs/context/mcp). The docs' reference table documents
	## `type: "stdio"`; pinning it also repins any hand-added `type: "http"`
	## left on the legacy URL entry, which would otherwise survive the
	## deep-copy migration and misroute the transport.
	command_shape = McpClient.CommandShape.FLAT
	command_transport_key = "type"
	command_transport_value = "stdio"
	command_legacy_keys = PackedStringArray(["url"])
	command_user_fields = PackedStringArray(["env", "envFile"])
