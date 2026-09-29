@tool
extends McpClient


func _init() -> void:
	id = "trae"
	display_name = "Trae"
	config_type = "json"
	path_template = {
		"darwin": "~/Library/Application Support/Trae/User/mcp.json",
		"windows": "$APPDATA/Trae/User/mcp.json",
		"linux": "$XDG_CONFIG_HOME/Trae/User/mcp.json",
	}
	server_key_path = PackedStringArray(["mcpServers"])
	## Attach migration (#838). Trae stdio entries are flat command/args/env
	## with no type discriminator (docs.trae.cn/ide/add-mcp-servers); transport
	## is inferred from `command` vs `url`, so url/headers are legacy next to a
	## command. Entry stays minimal — Trae manages enable/disable in its UI,
	## and its startup/run timeouts ride user-owned env vars, which survive.
	command_shape = McpClient.CommandShape.FLAT
	command_legacy_keys = PackedStringArray(["url", "headers"])
	command_user_fields = PackedStringArray(["env"])
