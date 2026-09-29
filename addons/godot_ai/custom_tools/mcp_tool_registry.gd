@tool
class_name McpToolRegistry
extends RefCounted

## Central registry for custom tools. INSTANCE SINGLETON (not static) —
## unlike McpClientRegistry which is read-only/loaded-once/query-only (static
## is fine there), this registry is MUTABLE, has LIFECYCLE (clear on teardown),
## must EMIT SIGNALS to multiple consumers, and needs DEPENDENCY INJECTION
## (dispatcher, locator). Static funcs can't emit instance signals in GDScript,
## and static vars create #46 freed-instance regressions across reloads.
##
## plugin.gd owns the instance (new + setup + clear). Addons access it via
## get_instance() so they don't hold a reference. Source identity is
## spec.source_path (explicit plugin.cfg path, https://github.com/hi-godot/godot-ai/issues/781#issuecomment-5036376599 #8) — same source_path
## = same addon (hot-reload replace); different source_path colliding on
## a name = reject + dock warning.

## singleton instance
static var _instance: McpToolRegistry = null

## Singleton accessor for addons. Returns null if Godot AI isn't loaded.
static func get_instance() -> McpToolRegistry:
	return _instance


## Instance fields (NOT static — lifecycle tied to plugin.gd)
var _specs: Dictionary = {}              # name -> McpCustomToolSpec
var _by_source_path: Dictionary = {}     # source_path -> Array[McpCustomToolSpec] (batch unregister index)
var _dispatcher: McpDispatcher = null    # injected by plugin.gd via setup()
var _locator: McpServiceLocator = null   # injected by plugin.gd via setup()
var _ready: bool = false
var _promoted_cnt = 0

## Instance signals (LEGAL — instance funcs can emit these). Multiple consumers
## (plugin.gd, dock, addons) can connect.
signal tools_changed                             # triggers custom_tools_changed push to server
signal registry_ready                            # https://github.com/hi-godot/godot-ai/issues/781#issuecomment-5036376599 #8: emit after Godot AI reload so addons can re-register


## Called by plugin.gd in _enter_tree. Injects live dependencies and registers
## the singleton. Addons can now reach the registry via get_instance().
func setup(dispatcher: McpDispatcher, locator: McpServiceLocator) -> void:
	_dispatcher = dispatcher
	_locator = locator
	_load_disabled_tools()
	_instance = self


func register(spec: McpCustomToolSpec) -> bool:
	if not _validate_one(spec):
		return false
	_commit_one(spec)
	tools_changed.emit()
	return true


## Atomic batch registration: validate ALL specs first (phase 1, zero
## mutation), then commit ALL (phase 2, cannot fail), then emit ONCE.
## A phase-1 failure leaves the registry AND dispatcher untouched — a
## per-spec register-then-bail loop would leave earlier specs committed
## and dispatchable while the server's tool list never hears about them.
func batch_register(specs: Array[McpCustomToolSpec]) -> bool:
	if specs.is_empty():
		return true
	## Phase 1 — validate only. Also reject duplicate names WITHIN the
	## batch: _validate_one checks against committed state (nothing from
	## this batch is committed yet), and silently letting the last
	## duplicate win would hide an addon packaging bug.
	var batch_names := {}
	for spec in specs:
		if not _validate_one(spec):
			return false
		if batch_names.has(spec.name):
			push_warning("McpToolRegistry: duplicate name '%s' within batch — rejected" % spec.name)
			return false
		batch_names[spec.name] = true
	## Phase 2 — commit everything, emit once.
	for spec in specs:
		_commit_one(spec)
	tools_changed.emit()
	return true


## Phase 1 helper: validation + collision policy. NO registry/dispatcher
## mutation — the only side effect is filling the display-source fallback
## on the spec itself, which is harmless on reject.
func _validate_one(spec: McpCustomToolSpec) -> bool:
	var errors := spec.validate()
	if not errors.is_empty():
		push_error("McpToolRegistry: rejecting spec '%s': %s" % [spec.name, ", ".join(errors)])
		return false
	## Fill display source from plugin.cfg if addon left it empty.
	if spec.source.is_empty():
		spec.source = _read_plugin_name(spec.source_path)
	## reject-on-collision: same source_path (hot-reload) replaces, different rejects
	var existing: McpCustomToolSpec= _specs.get(spec.name)
	if existing != null and existing.source_path != spec.source_path:
		push_warning("McpToolRegistry: name '%s' collision between %s and %s — rejected" % [spec.name, existing.source_path, spec.source_path])
		return false
	return true


## Phase 2 helper: commit one ALREADY-VALIDATED spec. Handles the
## hot-reload replace (same source_path — guaranteed by _validate_one).
## Never fails, never emits — callers own the tools_changed emit.
func _commit_one(spec: McpCustomToolSpec) -> void:
	var existing: McpCustomToolSpec = _specs.get(spec.name)
	if existing != null:
		## Replace: purge the OLD registration from all four dispatcher
		## dicts. Command name is "custom_tool:<name>" — passing the bare
		## name would leave a materialized Callable in _handlers and the
		## hot-reloaded spec would silently never take effect.
		_dispatcher.unregister("custom_tool:" + existing.name, "custom:" + existing.name)
		_erase_from_source_path_index_locked(existing)
	_specs[spec.name] = spec
	_by_source_path.get_or_add(spec.source_path, []).append(spec)
	## Bridge to dispatcher lazy registration: register_lazy_handler + register_lazy.
	## handler_key = "custom:<name>"; wrapper is CustomToolWrapper (https://github.com/hi-godot/godot-ai/issues/781#issuecomment-5036376599 #2).

	var handler_key := "custom:" + spec.name
	var wrapper_path := "res://addons/godot_ai/custom_tools/custom_tool_wrapper.gd"
	_dispatcher.register_lazy_handler(handler_key, wrapper_path, [spec, _locator])
	_dispatcher.register_lazy("custom_tool:" + spec.name, handler_key, &"invoke")


func unregister(name: String) -> bool:
	var spec: McpCustomToolSpec = _specs.get(name)
	if spec == null:
		return false
	if _dispatcher != null:
		_dispatcher.unregister("custom_tool:" + name, "custom:" + name)
	_specs.erase(name)
	_erase_from_source_path_index_locked(spec)
	tools_changed.emit()
	return true


## https://github.com/hi-godot/godot-ai/issues/781#issuecomment-5036376599 #8: batch-unregister all tools from one addon. Pass the source_path
## (plugin.cfg path) — the registry removes every spec whose source_path matches.
func unregister_source(source_path: String) -> int:
	var specs: Array = _by_source_path.get(source_path, [])
	var count := specs.size()
	for spec in specs.duplicate():
		if _dispatcher != null:
			_dispatcher.unregister("custom_tool:" + spec.name, "custom:" + spec.name)
		_specs.erase(spec.name)
	_by_source_path.erase(source_path)
	if count > 0:
		tools_changed.emit()
	return count


func all() -> Array[McpCustomToolSpec]:
	var out: Array[McpCustomToolSpec] = []
	for spec in _specs.values():
		out.append(spec)
	return out


## Enabled specs only — the catalog-push source. Disabled tools stay
## registered (the dock still lists them for re-enabling) but are never
## advertised to the server and are rejected at dispatch.
func enabled() -> Array[McpCustomToolSpec]:
	var out: Array[McpCustomToolSpec] = []
	for spec in _specs.values():
		if is_tool_enabled(spec.name):
			out.append(spec)
	return out


# --- per-tool enable state (dock UI) ---
## Persisted per-project via EditorSettings project metadata (the same
## store the editor uses for per-project UI state — no project.godot
## churn, no cross-project bleed). Applies LIVE: toggling re-emits
## tools_changed, which re-pushes the filtered catalog to the server.

const _META_SECTION := "godot_ai"
const _META_KEY_DISABLED := "disabled_custom_tools"

var _disabled_tools: Dictionary = {}  # name -> true


func is_tool_enabled(name: String) -> bool:
	return not _disabled_tools.has(name)


func set_tool_enabled(name: String, tool_enabled: bool) -> void:
	if tool_enabled:
		if not _disabled_tools.has(name):
			return
		_disabled_tools.erase(name)
	else:
		if _disabled_tools.has(name):
			return
		_disabled_tools[name] = true
	_save_disabled_tools()
	tools_changed.emit()


func _load_disabled_tools() -> void:
	_disabled_tools.clear()
	var es := _editor_settings()
	if es == null:
		return
	var stored: Variant = es.get_project_metadata(_META_SECTION, _META_KEY_DISABLED, PackedStringArray())
	for name in PackedStringArray(stored):
		_disabled_tools[String(name)] = true


func _save_disabled_tools() -> void:
	var es := _editor_settings()
	if es == null:
		return
	var names := PackedStringArray()
	for name in _disabled_tools.keys():
		names.append(String(name))
	es.set_project_metadata(_META_SECTION, _META_KEY_DISABLED, names)


static func _editor_settings() -> EditorSettings:
	if not Engine.is_editor_hint():
		return null
	return EditorInterface.get_editor_settings()


func get_spec(name: String) -> McpCustomToolSpec:
	var out: McpCustomToolSpec = _specs.get(name)
	return out


func is_ready() -> bool:
	return _ready


## Called from plugin.gd teardown — wipes everything so stale specs/Callables
## don't survive a Godot AI reload (#46 regression class). Signals die with
## the instance (consumers disconnect via plugin.gd's own teardown).
func clear() -> void:
	_specs.clear()
	_by_source_path.clear()
	_disabled_tools.clear()  # in-memory only; persistence reloads on next setup()
	_ready = false
	_dispatcher = null
	_locator = null
	_instance = null


## Called from plugin.gd _enter_tree after setup(). Addons that missed
## _enter_tree during a Godot AI reload listen for registry_ready (via
## get_instance().registry_ready.connect(...)) and re-register deterministically.
func mark_ready() -> void:
	_ready = true
	registry_ready.emit()


# --- internal helpers ---

func _erase_from_source_path_index_locked(spec: McpCustomToolSpec) -> void:
	var specs: Array = _by_source_path.get(spec.source_path, [])
	specs.erase(spec)
	if specs.is_empty():
		_by_source_path.erase(spec.source_path)


## Read [plugin] name from a plugin.cfg for display purposes.
## Returns "" on any error — display source is best-effort.
static func _read_plugin_name(plugin_cfg_path: String) -> String:
	var cfg := ConfigFile.new()
	if cfg.load(plugin_cfg_path) != OK:
		return ""
	return cfg.get_value("plugin", "name", "")

static func _get_command_name(spec: McpCustomToolSpec) -> String:
	return "custom_tool:" + spec.name

static func _get_handler_name(spec: McpCustomToolSpec) -> String:
	return "custom:" + spec.name
