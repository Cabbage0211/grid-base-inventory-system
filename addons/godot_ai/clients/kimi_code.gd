@tool
extends McpClient


func _init() -> void:
	id = "kimi_code"
	display_name = "Kimi Code"
	## Kimi Code has no `mcp` CLI subcommand (verified against v0.28.1 —
	## `kimi mcp` falls through to the root --help, and the docs at
	## moonshotai.github.io/kimi-code/en/customization/mcp confirm servers are
	## managed via ~/.kimi-code/mcp.json, not a CLI verb). JSON is therefore
	## the only working config method, not a fallback.
	config_type = "json"
	path_template = {"unix": "~/.kimi-code/mcp.json", "windows": "~/.kimi-code/mcp.json"}
	server_key_path = PackedStringArray(["mcpServers"])
	entry_extra_fields = {"transport": "http"}
	## Documented: `$KIMI_CODE_HOME/mcp.json` relocates the config
	## (moonshotai.github.io/kimi-code/en/customization/mcp) — same
	## false-success-write class as CODEX_HOME (#617).
	config_home_env = "KIMI_CODE_HOME"
	config_home_env_subpath = "mcp.json"
	## Attach migration (#838). Kimi Code stdio entries are flat
	## command/args/env(+cwd): "Entries with a `command` field are stdio
	## servers". `transport` is only defined for SSE-with-url, so the legacy
	## `transport: "http"` must be removed alongside `url`. Timeout fields are
	## camelCase, unlike Codex's snake_case.
	command_shape = McpClient.CommandShape.FLAT
	command_legacy_keys = PackedStringArray(["url", "transport"])
	command_user_fields = PackedStringArray([
		"enabled", "startupTimeoutMs", "toolTimeoutMs", "enabledTools",
		"disabledTools", "env", "cwd",
	])
	command_timeout_fields = PackedStringArray(["startupTimeoutMs", "toolTimeoutMs"])
