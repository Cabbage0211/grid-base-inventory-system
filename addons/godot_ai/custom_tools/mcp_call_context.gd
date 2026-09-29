@tool
class_name McpCallContext
extends RefCounted

## Per-call context handed to addon handlers.
##
## STABLE addon-facing surface (see AGENTS.md — published class_names are
## permanent compat surface): `request_id`, `session_id`, `deadline_msec`,
## `spec` (read-only), `is_expired()`, `send_deferred()`. Anything
## underscore-prefixed is internal wiring owned by the wrapper and may
## change between releases — addons must not reach into it. Keeping this
## surface narrow now is deliberate: it is much cheaper than breaking
## published addons later (#875 review).

var request_id: String = ""
var session_id: String = ""
var deadline_msec: int = 0
var spec: McpCustomToolSpec = null

## Internal — injected by custom_tool_wrapper via attach_locator(). Do not
## use from addon code; the capability methods below are the contract.
var _locator: McpServiceLocator = null


## Internal — called by the wrapper during ctx construction.
func attach_locator(locator: McpServiceLocator) -> void:
	_locator = locator


func is_expired() -> bool:
	if deadline_msec == 0:
		return false
	return Time.get_ticks_msec() > deadline_msec


func send_deferred(payload: Dictionary) -> void:
	if _locator == null:
		push_error("McpCallContext: cannot send deferred response, locator is null")
		return
	var conn := _locator.get_connection()
	if conn == null:
		push_error("McpCallContext: cannot send deferred response, connection is null")
		return
	conn.send_deferred_response(request_id, payload)
