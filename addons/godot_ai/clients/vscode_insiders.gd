@tool
extends McpClient


func _init() -> void:
	id = "vscode_insiders"
	display_name = "VS Code Insiders"
	config_type = "json"
	path_template = {
		"darwin": "~/Library/Application Support/Code - Insiders/User/mcp.json",
		"windows": "$APPDATA/Code - Insiders/User/mcp.json",
		"linux": "$XDG_CONFIG_HOME/Code - Insiders/User/mcp.json",
	}
	server_key_path = PackedStringArray(["servers"])
	entry_extra_fields = {"type": "http"}
	## Attach migration (#838). Identical format to vscode.gd — Insiders ships
	## the same mcpConfiguration.ts schema; see that descriptor for citations.
	command_shape = McpClient.CommandShape.FLAT
	command_transport_key = "type"
	command_transport_value = "stdio"
	command_legacy_keys = PackedStringArray(["url", "headers"])
	command_user_fields = PackedStringArray(["env", "envFile", "cwd", "sandboxEnabled", "dev"])
