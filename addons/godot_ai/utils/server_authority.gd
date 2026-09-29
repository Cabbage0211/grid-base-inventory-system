@tool
extends RefCounted

const TransportCapability := preload("res://addons/godot_ai/utils/transport_capability.gd")

## Capability and process-control values used by the lifecycle owner.  None of
## these objects performs work or retains another owner.  Keeping the three
## grants distinct makes it impossible to turn "I can talk to this server"
## into "I may kill or replace it" by accident.


class TransportAuthority:
	extends RefCounted

	var _http_port: int
	var _ws_port: int
	var _server_instance_id: String
	var _http_capability: String
	var _ws_capability: String


	func _init(
		p_http_port: int,
		p_ws_port: int,
		p_server_instance_id: String,
		p_http_capability: String,
		p_ws_capability: String,
	) -> void:
		_http_port = p_http_port
		_ws_port = p_ws_port
		_server_instance_id = p_server_instance_id
		_http_capability = p_http_capability
		_ws_capability = p_ws_capability


	func is_valid() -> bool:
		return (
			_http_port > 0
			and _http_port <= 65535
			and _ws_port > 0
			and _ws_port <= 65535
			and TransportCapability.is_lower_hex(_server_instance_id, 32)
			and TransportCapability.is_http_capability(_http_capability)
			and TransportCapability.is_lower_hex(_ws_capability, 64)
			and _http_capability != _ws_capability
		)


	func http_capability() -> String:
		return _http_capability


	func ws_capability() -> String:
		return _ws_capability


	func http_port() -> int:
		return _http_port


	func ws_port() -> int:
		return _ws_port


	func server_instance_id() -> String:
		return _server_instance_id


	## Safe for UI/status fanout: secrets never leave the lifecycle/connection
	## boundary through a generic Dictionary snapshot.
	func public_snapshot() -> Dictionary:
		return {
			"http_port": _http_port,
			"ws_port": _ws_port,
			"server_instance_id": _server_instance_id,
		}


class OwnedProcessGrant:
	extends RefCounted

	var _pid: int
	var _process_fingerprint: String
	var _issued_at_msec: int


	func _init(
		p_pid: int,
		p_process_fingerprint: String,
		p_issued_at_msec: int,
	) -> void:
		_pid = p_pid
		_process_fingerprint = p_process_fingerprint
		_issued_at_msec = p_issued_at_msec


	func is_valid() -> bool:
		return (
			_pid > 1
			and _pid != OS.get_process_id()
			and not _process_fingerprint.is_empty()
			and _issued_at_msec > 0
		)


	func process_id() -> int:
		return _pid


	func matches(p_pid: int, p_fingerprint: String) -> bool:
		return (
			is_valid()
			and _pid == p_pid
			and _process_fingerprint == p_fingerprint
		)


class ReplacementAuthorization:
	extends RefCounted

	var _target_instance_id: String
	var _target_version: String
	var _target_port: int
	var _expires_at_msec: int
	var _spent := false


	func _init(
		p_target_instance_id: String,
		p_target_version: String,
		p_target_port: int,
		p_expires_at_msec: int,
	) -> void:
		_target_instance_id = p_target_instance_id
		_target_version = p_target_version
		_target_port = p_target_port
		_expires_at_msec = p_expires_at_msec


	func is_available(now_msec: int) -> bool:
		return (
			not _spent
			and now_msec <= _expires_at_msec
			and _target_port > 0
			and not _target_instance_id.is_empty()
			and not _target_version.is_empty()
		)


	## Spend is intentionally binding and destructive.  A caller cannot probe
	## one target and then reuse the same click-authority against another.
	func spend(
		now_msec: int,
		p_target_instance_id: String,
		p_target_version: String,
		p_target_port: int,
	) -> bool:
		if not is_available(now_msec):
			return false
		if (
			_target_instance_id != p_target_instance_id
			or _target_version != p_target_version
			or _target_port != p_target_port
		):
			return false
		_spent = true
		return true


	func is_spent() -> bool:
		return _spent
