@tool
extends RefCounted

## One policy for every production uvx launch. Package identity JSON is a
## compatibility check, not authentication: production code is resolved only
## from the canonical PyPI index, with config files and installed tool envs
## disabled. The explicit process-local qualification switch is the sole path
## that leaves index selection to the qualification environment.

const PathTemplate := preload("res://addons/godot_ai/clients/_path_template.gd")
const PUBLIC_INDEX := "https://pypi.org/simple"
const PUBLIC_FLAT_INDEX := "https://pypi.org/simple/godot-ai/"
const QUALIFICATION_INDEX_ENV := "GODOT_AI_QUALIFICATION_PYTHON_INDEX"
const _BASE_ARGS := [
	"--isolated",
	"--no-config",
	"--no-env-file",
	"--no-sources",
	"--no-build",
	"--index-strategy", "first-index",
	"--keyring-provider", "disabled",
]

## Known uv inputs capable of changing package source, candidate selection,
## interpreter, or cache. Production processes spawned by Godot temporarily
## clear them under the global process-spawn mutex; command-line policy remains
## pinned as a second boundary and for client-owned attach launches.
const _RESOLUTION_ENVIRONMENT := [
	"UV_INDEX", "UV_DEFAULT_INDEX", "UV_INDEX_URL", "UV_EXTRA_INDEX_URL",
	"UV_FIND_LINKS", "UV_INDEX_STRATEGY", "UV_KEYRING_PROVIDER",
	"UV_CONFIG_FILE", "UV_CONSTRAINT", "UV_BUILD_CONSTRAINT", "UV_OVERRIDE",
	"UV_NO_CONFIG", "UV_NO_SOURCES", "UV_NO_BUILD", "UV_NO_BINARY",
	"UV_NO_BINARY_PACKAGE", "UV_NO_VERIFY_HASHES", "UV_PRERELEASE",
	"UV_RESOLUTION", "UV_FORK_STRATEGY", "UV_EXCLUDE_NEWER",
	"UV_EXCLUDE_NEWER_PACKAGE", "UV_INSECURE_HOST", "UV_SYSTEM_CERTS",
	"UV_NATIVE_TLS", "UV_PYTHON", "UV_PYTHON_DOWNLOADS", "UV_PROJECT",
	"UV_WORKING_DIR", "UV_ENV_FILE", "UV_CACHE_DIR", "UV_TOOL_DIR",
	"UV_TOOL_BIN_DIR", "UV_LINK_MODE", "UV_REFRESH", "UV_REFRESH_PACKAGE",
	"UV_REINSTALL", "UV_REINSTALL_PACKAGE",
]


static func warm_environment() -> void:
	PathTemplate.warm_env_snapshot(PackedStringArray([QUALIFICATION_INDEX_ENV]))


static func qualification_authorized() -> bool:
	return PathTemplate.env_lookup(QUALIFICATION_INDEX_ENV) == "1"


static func args() -> Array[String]:
	var result: Array[String] = []
	result.assign(_BASE_ARGS)
	if not qualification_authorized():
		result.append_array([
			"--index", PUBLIC_INDEX,
			"--default-index", PUBLIC_INDEX,
			"--find-links", PUBLIC_FLAT_INDEX,
		])
	return result


static func is_production_command(command: Array) -> bool:
	if command.is_empty() or not str(command[0]).get_file().begins_with("uvx"):
		return false
	return (
		_option_equals(command, "--index", PUBLIC_INDEX)
		and _option_equals(command, "--default-index", PUBLIC_INDEX)
		and _option_equals(command, "--find-links", PUBLIC_FLAT_INDEX)
	)


## Call only while the process-spawn mutex is held. Qualification commands do
## not reach this function: their explicitly authorized UV_INDEX and credentials
## must remain process-local and are never rendered into persisted argv.
static func isolate_environment() -> Dictionary:
	var previous := {}
	for key in _RESOLUTION_ENVIRONMENT:
		previous[key] = {
			"present": OS.has_environment(key),
			"value": OS.get_environment(key),
		}
		OS.unset_environment(key)
	return previous


static func restore_environment(previous: Dictionary) -> void:
	for key in previous:
		if bool(previous[key].present):
			OS.set_environment(key, str(previous[key].value))
		else:
			OS.unset_environment(key)


static func _option_equals(command: Array, option: String, expected: String) -> bool:
	var index := command.find(option)
	return index >= 0 and index + 1 < command.size() and str(command[index + 1]) == expected
