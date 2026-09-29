@tool
class_name McpUpdateManager
extends Node

## v4-only release discovery and download preparation. Python authenticates
## and extracts the three canonical assets before this manager asks the root to
## quiesce or disable anything; the transaction actor alone mutates live code.

const RELEASES_URL := "https://api.github.com/repos/hi-godot/godot-ai/releases/latest"
const RELEASES_PAGE := "https://github.com/hi-godot/godot-ai/releases/latest"
const REPOSITORY := "hi-godot/godot-ai"
const ASSET_NAME := "godot-ai-v4-plugin.zip"
const MANIFEST_NAME := "godot-ai-v4-plugin.manifest.json"
const SIGNATURE_NAME := "godot-ai-v4-plugin.manifest.sig"
const LEGACY_ASSET_NAME := "godot-ai-plugin.zip"
const LEGACY_CHECKSUM_NAME := "godot-ai-plugin.zip.sha256"
const LEGACY_SIGNATURE_NAME := "godot-ai-plugin.zip.sha256.sig"
const MAX_RELEASE_METADATA_BYTES := 1024 * 1024
const MAX_ARCHIVE_SIZE_BYTES := 64 * 1024 * 1024
const MAX_MANIFEST_SIZE_BYTES := 1024 * 1024
const MAX_REDIRECTS := 5
const QUALIFICATION_SWITCH_ENV := "GODOT_AI_QUALIFICATION_RELEASE"
const QUALIFICATION_URL_ENV := "GODOT_AI_QUALIFICATION_RELEASE_URL"
const QUALIFICATION_ASSET_PREFIX_ENV := "GODOT_AI_QUALIFICATION_ASSET_PREFIX"
const QUALIFICATION_TOKEN_ENV := "GODOT_AI_QUALIFICATION_TOKEN"
const _ASSET_LIMITS := {
	ASSET_NAME: MAX_ARCHIVE_SIZE_BYTES,
	MANIFEST_NAME: MAX_MANIFEST_SIZE_BYTES,
	SIGNATURE_NAME: 512,
}
## Stable releases also carry one signed, temporary v3 migration capsule.
## v4 never downloads it, but requires the exact six-name release envelope so
## an unexpected extra executable asset remains a fail-closed condition.
const _RELEASE_ASSET_LIMITS := {
	ASSET_NAME: MAX_ARCHIVE_SIZE_BYTES,
	MANIFEST_NAME: MAX_MANIFEST_SIZE_BYTES,
	SIGNATURE_NAME: 512,
	LEGACY_ASSET_NAME: 66 * 1024 * 1024,
	LEGACY_CHECKSUM_NAME: 1024,
	LEGACY_SIGNATURE_NAME: 512,
}
const ClientConfigurator := preload("res://addons/godot_ai/client_configurator.gd")
const TransportCapability := preload("res://addons/godot_ai/utils/transport_capability.gd")

## Kept byte-for-byte aligned with src/godot_ai/release_verify.py and the
## standalone verifier. Python performs the mandatory strict verification;
## embedding it here also lets release packaging fail on trust-anchor drift.
const RELEASE_SIGNING_PUBLIC_KEY_PEM := """-----BEGIN PUBLIC KEY-----
MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAr4OmbONFTONGFcXSUQ2p
e54YaUhWDA75wxeDWhOc476vsdo53YnXEFT7EPr2hUKqeNxv++LqKOkFuAsxSNZy
wBe6P1tmQA4Og6Ezv4CGnZdEj1uhlDJFK9ShQ29oWfC6bf/84625SvvBxZos2Br9
yPKl7h5wzqDoeUSpv+f0ynTiC0i/HAUo/NQBlkgGwkomK2Fr3pP1VDxxq2xvgHSk
lU6Qcomr9WjJxI+HkDN5tRPPn0pDrg6YFx2J18OfD8KIa/kMGxuXOcHlPyRYpjyu
qTtg2oL0NyUIG+1TmJ3DcN4GlKC55eOrkfJ04vudS5pxdnUIFRmkGBXZLdaetoPc
ixtlD4w6gi8KIH1CTG+/TtHP1KVdOogCWDcjRCAmMJPFZe6eEKXmGQUZDb9wfnbx
h++XiVe5tq83BTLWmaFTy+fZbNo12uhNCNS1LJ42/yj+S1xvo0yMbkkNr1hIYk0P
584XnBQeBSVJDf3667NZXaxnWv94K9zbb+1OvOvPwhbOdgi2Ymcw5QEOQIavtg86
XLLcWzG+SJsycz1imikjv6sStWh8WHneKSTMq6A7V6PBj7oJyEJp10696BDw287k
YlH+9VGqowPEMXpWX57wOBKiWb4K1kw1LfxjT8W1e/pcX9pJqiv0DkjTXUxo9CDG
1X1+ZXBBR3MkGuFAOCjy0x8CAwEAAQ==
-----END PUBLIC KEY-----
"""

const _TRUSTED_PATHS := {
	"github.com": "/hi-godot/godot-ai/releases/download/",
	"www.github.com": "/hi-godot/godot-ai/releases/download/",
	"api.github.com": "/repos/hi-godot/godot-ai/releases/assets/",
	"objects.githubusercontent.com": "/github-production-release-asset-",
	"release-assets.githubusercontent.com": "/github-production-release-asset-",
}

signal update_check_completed(result: Dictionary)
signal install_state_changed(state: Dictionary)
signal activation_requested(package: Dictionary)

var _check_request: HTTPRequest
var _asset_request: HTTPRequest
var _release: Dictionary = {}
var _queue: Array[String] = []
var _active_asset := ""
var _redirect_count := 0
var _qualification: Dictionary = {}
var _download_root := ""


func check_for_updates() -> void:
	_release.clear()
	_qualification = _qualification_from_environment()
	if bool(_qualification.get("invalid", false)):
		_qualification.clear()
		push_error("MCP | invalid private qualification release capability")
		return
	if ClientConfigurator.is_dev_checkout():
		return
	if _check_request != null:
		_check_request.queue_free()
	_check_request = HTTPRequest.new()
	_check_request.max_redirects = 0
	_check_request.body_size_limit = MAX_RELEASE_METADATA_BYTES
	_check_request.request_completed.connect(_on_check_completed)
	add_child(_check_request)
	var url := str(_qualification.get("release_url", RELEASES_URL))
	if _check_request.request(url, _request_headers(url, _qualification, true)) != OK:
		_check_request.queue_free()
		_check_request = null


func start_install(preflight: Dictionary) -> void:
	if is_install_in_flight():
		install_state_changed.emit({
			"status_text": "Update already in progress",
			"button_disabled": true,
		})
		return
	if _release.is_empty():
		OS.shell_open(RELEASES_PAGE)
		return
	if not bool(preflight.get("ok", false)):
		install_state_changed.emit({
			"install_in_flight": false,
			"status_text": "Update blocked — resolve recovery state",
			"button_disabled": false,
		})
		return
	var directory := str(preflight.get("download_root", ""))
	if (
		directory.is_empty()
		or not directory.is_absolute_path()
		or not _directory_is_empty(directory)
	):
		install_state_changed.emit({
			"install_in_flight": false,
			"status_text": "Update blocked — private download directory unavailable",
			"button_disabled": false,
		})
		return
	_download_root = directory
	_queue.assign([ASSET_NAME, MANIFEST_NAME, SIGNATURE_NAME])
	install_state_changed.emit({
		"install_in_flight": true,
		"status_text": "Downloading…",
		"button_disabled": true,
	})
	_download_next()


func is_install_in_flight() -> bool:
	return _asset_request != null or not _download_root.is_empty()


func has_install_candidate() -> bool:
	return not is_install_in_flight() and not _release.is_empty()


static func _directory_is_empty(path: String) -> bool:
	var directory := DirAccess.open(path)
	if directory == null:
		return false
	directory.list_dir_begin()
	var first := directory.get_next()
	directory.list_dir_end()
	return first.is_empty()


func cancel_install() -> void:
	if _asset_request != null:
		_asset_request.cancel_request()
		_asset_request.queue_free()
		_asset_request = null
	_queue.clear()
	_qualification.clear()
	discard_downloads()


func _exit_tree() -> void:
	cancel_install()


## Download roots are exclusively allocated by the Python transaction actor.
## This manager never creates, reuses, or recursively deletes a predictable
## user:// namespace; it removes only the three exact files it requested and
## then the now-empty transaction directory.
func discard_downloads() -> void:
	if _download_root.is_empty():
		return
	for name in [ASSET_NAME, MANIFEST_NAME, SIGNATURE_NAME]:
		DirAccess.remove_absolute(_download_root.path_join(name))
	DirAccess.remove_absolute(_download_root)
	_download_root = ""


func _download_path(name: String) -> String:
	if _download_root.is_empty() or not _ASSET_LIMITS.has(name):
		return ""
	return _download_root.path_join(name)


static func parse_releases_response(
	result: int,
	response_code: int,
	body: PackedByteArray,
	local_version: String = "",
	qualification: Dictionary = {},
) -> Dictionary:
	var empty := {
		"has_update": false,
		"version": "",
		"tag": "",
		"channel": "",
		"label_text": "",
		"urls": {},
		"sizes": {},
	}
	if (
		result != HTTPRequest.RESULT_SUCCESS
		or response_code != 200
		or body.size() > MAX_RELEASE_METADATA_BYTES
	):
		return empty
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not parsed is Dictionary:
		return empty
	var tag := str(parsed.get("tag_name", ""))
	var version := tag.trim_prefix("v")
	var local := local_version if not local_version.is_empty() else ClientConfigurator.get_plugin_version()
	if not tag.begins_with("v4.") or not _is_newer(version, local):
		return empty
	var assets: Variant = parsed.get("assets", [])
	if not assets is Array or assets.size() != _RELEASE_ASSET_LIMITS.size():
		return empty
	var urls := {}
	var sizes := {}
	for value in assets:
		if not value is Dictionary:
			return empty
		var name := str(value.get("name", ""))
		if not _RELEASE_ASSET_LIMITS.has(name) or sizes.has(name):
			return empty
		var size := int(value.get("size", -1))
		if size <= 0 or size > int(_RELEASE_ASSET_LIMITS[name]):
			return empty
		if name in [SIGNATURE_NAME, LEGACY_SIGNATURE_NAME] and size != 512:
			return empty
		var url := str(value.get("browser_download_url", ""))
		if not _is_trusted_download_url(url, qualification):
			return empty
		sizes[name] = size
		if _ASSET_LIMITS.has(name):
			urls[name] = url
	if urls.size() != 3:
		return empty
	return {
		"has_update": true,
		"version": version,
		"tag": tag,
		"channel": "stable",
		"label_text": "Update available: %s" % tag,
		"urls": urls,
		"sizes": sizes,
	}


static func _is_newer(remote: String, local: String) -> bool:
	var remote_parts := _version_parts(remote)
	var local_parts := _version_parts(local)
	if remote_parts.is_empty() or local_parts.is_empty():
		return false
	for index in 3:
		if remote_parts[index] != local_parts[index]:
			return remote_parts[index] > local_parts[index]
	return false


static func _version_parts(version: String) -> Array[int]:
	var expression := RegEx.new()
	if expression.compile("^4\\.(\\d+)\\.(\\d+)$") != OK:
		return []
	var found := expression.search(version)
	if found == null:
		return []
	return [4, int(found.get_string(1)), int(found.get_string(2))]


static func _https_url_parts(url: String) -> Dictionary:
	const SCHEME := "https://"
	if not url.begins_with(SCHEME) or url.contains("\\") or url.contains("#"):
		return {}
	for index in url.length():
		var code: int = url.unicode_at(index)
		if code <= 0x20 or code == 0x7f:
			return {}
	var rest := url.substr(SCHEME.length())
	var slash := rest.find("/")
	if slash < 0:
		return {}
	var authority := rest.substr(0, slash)
	var path := rest.substr(slash)
	if authority.is_empty() or authority.contains("@") or authority.count(":") > 1:
		return {}
	var host := authority
	var colon := authority.find(":")
	if colon >= 0:
		if authority.substr(colon + 1) != "443":
			return {}
		host = authority.substr(0, colon)
	if (
		host.is_empty()
		or host != host.to_lower()
		or host.begins_with(".")
		or host.ends_with(".")
		or host.contains("..")
	):
		return {}
	for index in host.length():
		var code := host.unicode_at(index)
		if not (code >= 97 and code <= 122) and not (code >= 48 and code <= 57) and code not in [45, 46]:
			return {}
	var query := path.find("?")
	if query >= 0:
		path = path.substr(0, query)
	var lower := path.to_lower()
	for needle in ["/../", "/..", "%2e", "%2f", "%5c"]:
		if lower.contains(needle):
			return {}
	return {"host": host, "origin": SCHEME + host, "path": path}


static func _is_trusted_download_url(url: String, qualification: Dictionary = {}) -> bool:
	var parts := _https_url_parts(url)
	if parts.is_empty():
		return false
	## Current GitHub release assets use a slash-delimited repository ID;
	## retain the older CDN namespace below for existing release URLs.
	if (
		parts.host == "release-assets.githubusercontent.com"
		and str(parts.path).begins_with("/github-production-release-asset/1208239711/")
	):
		return true
	if (
		str(parts.origin) == str(qualification.get("asset_origin", ""))
		and str(parts.path).begins_with(str(qualification.get("asset_path", "")))
		and not str(qualification.get("asset_path", "")).is_empty()
	):
		return true
	return _TRUSTED_PATHS.has(parts.host) and str(parts.path).begins_with(
		str(_TRUSTED_PATHS[parts.host])
	)


static func _qualification_config(
	enabled: String, release_url: String, asset_prefix: String, token: String
) -> Dictionary:
	if enabled.is_empty() and release_url.is_empty() and asset_prefix.is_empty() and token.is_empty():
		return {}
	var release := _https_url_parts(release_url)
	var assets := _https_url_parts(asset_prefix)
	if (
		enabled != "1"
		or release.is_empty()
		or assets.is_empty()
		or not asset_prefix.ends_with("/")
		or asset_prefix.contains("?")
		or release.origin != assets.origin
		or not TransportCapability.is_http_capability(token)
	):
		return {"invalid": true}
	return {
		"asset_origin": str(assets.origin),
		"asset_path": str(assets.path),
		"release_url": release_url,
		"token": token,
	}


static func _qualification_from_environment() -> Dictionary:
	return _qualification_config(
		OS.get_environment(QUALIFICATION_SWITCH_ENV),
		OS.get_environment(QUALIFICATION_URL_ENV),
		OS.get_environment(QUALIFICATION_ASSET_PREFIX_ENV),
		OS.get_environment(QUALIFICATION_TOKEN_ENV),
	)


static func _request_headers(
	url: String, qualification: Dictionary, metadata: bool = false
) -> PackedStringArray:
	var headers := PackedStringArray(["Accept: application/vnd.github+json"] if metadata else [])
	var authorized := url == str(qualification.get("release_url", ""))
	if not authorized:
		var parts := _https_url_parts(url)
		authorized = (
			not parts.is_empty()
			and parts.origin == qualification.get("asset_origin", "")
			and str(parts.path).begins_with(str(qualification.get("asset_path", "")))
			and not str(qualification.get("asset_path", "")).is_empty()
		)
	if authorized:
		headers.append("Authorization: Bearer " + str(qualification.token))
	return headers


static func _redirect_url(headers: PackedStringArray) -> String:
	var location := ""
	for header in headers:
		var colon := header.find(":")
		if colon < 0 or header.substr(0, colon).strip_edges().to_lower() != "location":
			continue
		if not location.is_empty():
			return ""
		location = header.substr(colon + 1).strip_edges()
	return location


func _on_check_completed(
	result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray
) -> void:
	if _check_request != null:
		_check_request.queue_free()
		_check_request = null
	var release := parse_releases_response(result, response_code, body, "", _qualification)
	if not bool(release.get("has_update", false)):
		_release.clear()
		_qualification.clear()
		return
	_release = release.duplicate(true)
	update_check_completed.emit(release.duplicate(true))


func _download_next() -> void:
	if _queue.is_empty():
		_finish_downloads()
		return
	_active_asset = _queue.pop_front()
	_redirect_count = 0
	_request_active_asset(str((_release.get("urls", {}) as Dictionary).get(_active_asset, "")))


func _request_active_asset(url: String) -> void:
	_asset_request = HTTPRequest.new()
	## Follow redirects ourselves so every hop remains inside the pinned GitHub
	## release/CDN namespace; HTTPRequest's automatic mode exposes no hop hook.
	_asset_request.max_redirects = 0
	_asset_request.body_size_limit = int((_release.get("sizes", {}) as Dictionary).get(_active_asset, 0))
	_asset_request.download_file = _download_path(_active_asset)
	_asset_request.request_completed.connect(_on_asset_completed)
	add_child(_asset_request)
	if _asset_request.request(url, _request_headers(url, _qualification)) != OK:
		_fail_download("request failed")


func _on_asset_completed(
	result: int,
	response_code: int,
	headers: PackedStringArray,
	_body: PackedByteArray
) -> void:
	if _asset_request != null:
		_asset_request.queue_free()
		_asset_request = null
	## With max_redirects = 0 Godot returns REDIRECT_LIMIT_REACHED on the
	## first redirect, including its status and Location. Validate that hop
	## ourselves; other transport failures must still fail closed.
	if (
		result in [HTTPRequest.RESULT_SUCCESS, HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED]
		and response_code in [301, 302, 303, 307, 308]
	):
		var redirect := _redirect_url(headers)
		DirAccess.remove_absolute(_download_path(_active_asset))
		if (
			_redirect_count >= MAX_REDIRECTS
			or not _is_trusted_download_url(redirect, _qualification)
		):
			_fail_download("untrusted or excessive redirect")
			return
		_redirect_count += 1
		_request_active_asset(redirect)
		return
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		_fail_download("download failed (%d)" % response_code)
		return
	var path := _download_path(_active_asset)
	var file := FileAccess.open(path, FileAccess.READ)
	var expected := int((_release.get("sizes", {}) as Dictionary).get(_active_asset, -1))
	if file == null:
		_fail_download("downloaded asset size differs from release metadata")
		return
	var actual_size := file.get_length()
	file.close()
	if actual_size != expected:
		_fail_download("downloaded asset size differs from release metadata")
		return
	_download_next()


func _finish_downloads() -> void:
	var directory := _download_root
	var manifest_path := directory.path_join(MANIFEST_NAME)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if not parsed is Dictionary or str(parsed.get("source_commit", "")).is_empty():
		_fail_download("manifest is unreadable")
		return
	activation_requested.emit({
		"archive": directory.path_join(ASSET_NAME),
		"manifest": manifest_path,
		"signature": directory.path_join(SIGNATURE_NAME),
		"repository": REPOSITORY,
		"channel": str(_release.channel),
		"tag": str(_release.tag),
		"version": str(_release.version),
		"source": str(parsed.source_commit),
		"download_root": directory,
	})
	_qualification.clear()


func _fail_download(reason: String) -> void:
	if _asset_request != null:
		_asset_request.queue_free()
		_asset_request = null
	_queue.clear()
	_qualification.clear()
	discard_downloads()
	push_error("MCP | v4 update preparation failed: %s" % reason)
	## The click-time lock and any quiesced client work are the plugin's to
	## release, and it only does so when it hears the install is over.
	install_state_changed.emit({
		"install_in_flight": false,
		"status_text": "Update preparation failed",
		"button_disabled": false,
	})
