@tool
extends McpClient

## CodeBuddy IDE: https://www.codebuddy.ai/docs/zh/ide/User-guide/MCP
## Official docs specify mcpServers + type:stdio + command/args/env.
## Global ~/.codebuddy/mcp.json was verified by the reporter in #941.
## This descriptor uses the global user scope,
## matching the registry's absolute user-path contract; project configuration
## remains available manually in CodeBuddy's MCP settings.


func _init() -> void:
	id = "codebuddy"
	display_name = "CodeBuddy"
	config_type = "json"
	path_template = {
		"unix": "~/.codebuddy/mcp.json",
		"windows": "$USERPROFILE/.codebuddy/mcp.json",
	}
	server_key_path = PackedStringArray(["mcpServers"])
	command_shape = McpClient.CommandShape.FLAT
	command_transport_key = "type"
	command_transport_value = "stdio"
	command_legacy_keys = PackedStringArray(["url", "headers"])
	command_user_fields = PackedStringArray(["env", "description"])
