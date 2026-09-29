@tool
class_name McpCustomToolSpec
extends RefCounted

## Descriptor for one custom tool registered by an addon. Mirrors the
## clients/_base.gd data-only descriptor pattern: fields are set by the
## caller, NO Callables (handler instance is materialized lazily by the
## dispatcher from script_path + method, so hot-reload can't SEGV a
## worker mid-call — same rationale as McpClient, issue #229).
##
## Construction: instantiate and set fields, then pass to
## McpToolRegistry.register(spec). Do NOT subclass — custom tools are
## dynamic (one addon may register several), not file-system-scanned
## like clients.

# --- identity ---
var name: String = ""                    ## tool name, e.g. "gdunit_run". Must not shadow a built-in.
var description: String = ""             ## shown to the agent by the MCP server
var params_schema: Dictionary = {}       ## JSON Schema; advertised to the agent for shaping calls. Params are forwarded UNVALIDATED — the handler must validate its own input.

# --- handler resolution (lazy materialization by dispatcher) ---
var script_path: String = ""             ## "res://addons/.../handler.gd"; load()ed on first call
var method: StringName = &""             ## method on the handler; signature: (params: Dictionary, ctx: McpCallContext) -> Dictionary

# --- source identity (https://github.com/hi-godot/godot-ai/issues/781#issuecomment-5036376599 #8) ---
var source_path: String = ""             ## "plugin.cfg" path: "res://addons/gdunit4_mcp/plugin.cfg". Same path = same addon (replace allowed); different path colliding = reject + dock warning. NOTE: self-declared — a collision/ownership policy for cooperating addons, NOT a security boundary (any in-editor code can claim any path).
var source: String = ""                  ## display: "gdunit4_mcp". If empty, registry reads [plugin] name from source_path.

# --- exposure ---
var promoted: bool = false               ## opt-in: ask the server to ALSO register this tool as a first-class MCP tool ("custom_<name>") with params_schema attached, so agents get native schemas/validation instead of the custom_manage indirection. The server caps promoted count; overflow stays reachable via custom_manage.

# --- execution contract ---
var timeout_ms: int = 4500               ## deferred timeout → DEFERRED_TIMEOUT_MS_BY_COMMAND["custom:<name>"]
var deferred: bool = false               ## true → handler may return DEFERRED_RESPONSE, push later via ctx.send_deferred(payload)
var requires_writable: bool = false      ## https://github.com/hi-godot/godot-ai/issues/781#issuecomment-5036376599 #1: readiness gate. false → reads run any time; true → blocks during play/import
var undoable: bool = false               ## https://github.com/hi-godot/godot-ai/issues/781#issuecomment-5036376599 #6: must be true to participate in undo=true batch_execute

# --- budgets (https://github.com/hi-godot/godot-ai/issues/781#issuecomment-5036376599 #5, enforced at register time) ---
const MAX_DESCRIPTION_CHARS := 600
const MAX_SCHEMA_BYTES := 8192
const MAX_TIMEOUT_MS := 120000
const MIN_TIMEOUT_MS := 500


## Returns an array of human-readable validation errors (empty = valid).
## Called by McpToolRegistry.register() and usable standalone for early
## feedback in addon _enter_tree before the registry is even live.
func validate() -> Array[String]:
	var errors: Array[String] = []
	if name.is_empty():
		errors.append("name is empty\n")
	if not name.is_valid_ascii_identifier():
		errors.append("name '%s' is not a valid identifier\n" % name)
	if description.length() > MAX_DESCRIPTION_CHARS:
		errors.append("description exceeds %d chars\n" % MAX_DESCRIPTION_CHARS)
	if JSON.stringify(params_schema).to_utf8_buffer().size() > MAX_SCHEMA_BYTES:
		errors.append("params_schema exceeds %d bytes\n" % MAX_SCHEMA_BYTES)
	if script_path.is_empty() or not ResourceLoader.exists(script_path):
		errors.append("script_path '%s' does not exist" % script_path)
	if method.is_empty():
		errors.append("method is empty")
	if timeout_ms < MIN_TIMEOUT_MS or timeout_ms > MAX_TIMEOUT_MS:
		errors.append("timeout_ms %d out of range [%d, %d]" % [timeout_ms, MIN_TIMEOUT_MS, MAX_TIMEOUT_MS])
	if source_path.is_empty() or not source_path.ends_with("plugin.cfg") or not FileAccess.file_exists(source_path):
		errors.append("source_path '%s' must be an existing plugin.cfg path" % source_path)
	return errors
