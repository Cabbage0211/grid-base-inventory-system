@tool
extends McpClient


func _init() -> void:
	id = "claude_code"
	display_name = "Claude Code"
	config_type = "cli"
	cli_names = PackedStringArray(["claude", "claude.exe"] if OS.get_name() == "Windows" else ["claude"])
	## Stdio registration through the client-owned `godot-ai attach` bridge
	## (#838). `--` stops claude's own flag parsing so the attach argv passes
	## through verbatim; stdio is the CLI's default transport. Scope comes from
	## the `godot_ai/mcp_client_scope` EditorSetting via the `{scope}` token; it
	## defaults to `user` — the same ~/.claude.json the pre-attach HTTP entry
	## lived in — and can be set to `project` to write <project>/.mcp.json so the
	## server is not loaded in every unrelated workspace.
	cli_register_template = PackedStringArray(
		["mcp", "add", "--scope", "{scope}", "{name}", "--", "{command}", "{args...}"]
	)
	## Explicit scope: an unscoped `mcp remove` deletes from whichever scope
	## matches first, so the flag keeps each removal aimed at one known place.
	## Note what that does and does not protect (#877): the dock's **Remove**
	## button runs this once, at the selected scope only. **Configure** runs it
	## once per scope in `CLIENT_SCOPES` before registering, so a Configure at
	## any setting does delete a `godot-ai` entry from <cwd>/.mcp.json if one is
	## there — see the cwd caveat below for which directory that actually is.
	cli_unregister_template = PackedStringArray(["mcp", "remove", "--scope", "{scope}", "{name}"])
	## Scope caveat: `--scope project` resolves `.mcp.json` against the
	## *spawned CLI's* working directory, which is whatever the editor process
	## inherited at launch — not necessarily `res://`. Godot has no API to set
	## a child's cwd (`OS.execute_with_pipe` takes none), so this is an
	## accepted limitation rather than something the descriptor can pin. It is
	## self-consistent: `cli_status_args` runs from the same cwd, so the
	## read-back finds whatever the register wrote (see
	## `_scope_diverges_from_json_fallback` in client_configurator.gd).
	cli_status_args = PackedStringArray(["mcp", "list"])
	## `mcp list` prints the resolved entry for the cwd without saying which
	## scope won, so it cannot tell "registered at project scope" from "an old
	## user-scope entry is shadowing an empty project scope". `mcp get` prints
	## both the command and a `Scope: …` line, in the same single subprocess,
	## so scope-token clients probe with it instead (#872). Verified against
	## claude 2.1.241, which prints one of:
	##   Scope: User config (available in all your projects)
	##   Scope: Project config (shared via .mcp.json)
	##   Scope: Local config (private to you in this project)
	## and exits 1 with "No MCP server named …" when the entry is absent.
	cli_scope_status_template = PackedStringArray(["mcp", "get", "{name}"])
	## #463: JSON fallback for when the `claude` binary isn't on PATH — e.g.
	## Claude Code installed only as a VS Code / Cursor extension. The CLI is
	## still preferred for Configure whenever it resolves; this is what gets
	## written otherwise. `claude mcp add --scope user <name> -- <cmd> <args>`
	## produces exactly this shape under `mcpServers` in ~/.claude.json
	## (verified live against claude CLI in an isolated CLAUDE_CONFIG_DIR):
	##   "godot-ai": { "type": "stdio", "command": "<cmd>", "args": [...], "env": {} }
	## The fallback writer omits the empty `env`; the verifier accepts both.
	## Status reads this file only while the selected scope is still `user` —
	## it is the CLI's own store for that scope, and file reads give exact
	## launch-drift detection that `mcp list` stdout scanning cannot. At
	## `project`/`local` the entry is somewhere `path_template` cannot see, so
	## `_scope_diverges_from_json_fallback` (client_configurator.gd) routes
	## status to `cli_scope_status_template` instead and this file is not read.
	path_template = {"unix": "~/.claude.json", "windows": "~/.claude.json"}
	server_key_path = PackedStringArray(["mcpServers"])
	## Legacy HTTP entries used this shape; command rendering repins it to stdio.
	entry_extra_fields = {"type": "http"}
	command_shape = McpClient.CommandShape.FLAT
	command_transport_key = "type"
	command_transport_value = "stdio"
	## Legacy HTTP entries carried a `url`; Claude Code rejects an entry mixing
	## url with command fields, and the stale `type: "http"` is repinned to
	## "stdio" by the transport key above.
	command_legacy_keys = PackedStringArray(["url"])
	command_user_fields = PackedStringArray(["env"])
	## Documented: $CLAUDE_CONFIG_DIR relocates Claude Code's config home,
	## including .claude.json ($CLAUDE_CONFIG_DIR/.claude.json). The preferred
	## CLI path needs no help — the spawned `claude` binary inherits the
	## editor's environment and resolves the dir itself — but the JSON
	## fallback above would otherwise write ~/.claude.json that a relocated
	## install never reads (#617).
	config_home_env = "CLAUDE_CONFIG_DIR"
	config_home_env_subpath = ".claude.json"
