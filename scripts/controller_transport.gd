class_name ControllerTransport
extends Node
## Explicit opt-in loopback transport for the external development controller.
var url: String = ""
var token: String = ""
var pending_events: Array[Dictionary] = []
var post: HTTPRequest
var poll: HTTPRequest
var posting: bool = false
var polling: bool = false
var cursor: int = 0
var post_delay: float = 0
var poll_delay: float = 0
var backoff: float = 0.5
var started: bool = false
var fatal: bool = false

func configure(path: String) -> String:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	if not parsed is Dictionary or not parsed.get("url") is String or not parsed.get("session_id") is String or not parsed.get("token") is String:
		return "Controller configuration is missing or invalid. Create a fresh development session and restart."
	var pattern := RegEx.new()
	pattern.compile("^http://(127\\.0\\.0\\.1|localhost):[0-9]{1,5}$")
	if pattern.search(parsed.url) == null or parsed.token.length() < 16 or parsed.session_id.is_empty():
		return "Only an explicit local controller session is supported. Check the session configuration."
	url = parsed.url
	token = parsed.token
	ApiClient.controller_session_id = parsed.session_id
	ApiClient.preview_enabled = parsed.get("preview", false) == true
	if parsed.get("output", "laptop") not in ["laptop", "bridge_simulator", "reachy_lite", "reachy_wireless", "reachy_mujoco", "reachy_control_simulator"]:
		return "Unsupported companion output route. Create a fresh session."
	ApiClient.companion_output = parsed.get("output", "laptop")
	ApiClient.microphone_enabled = parsed.get("speech", false) == true
	ApiClient.conversation_enabled = parsed.get("conversation", false) == true
	ApiClient.session_id = parsed.session_id
	started = true  # Poll safety commands even while the game is on its title screen.
	ApiClient.status = "EXTERNAL MOCK CONTROLLER · connecting · no robot"
	return ""

func _ready() -> void:
	post = HTTPRequest.new()
	post.timeout = 2.0
	post.body_size_limit = 65536
	add_child(post)
	post.request_completed.connect(_posted)
	poll = HTTPRequest.new()
	poll.timeout = 2.0
	poll.body_size_limit = 65536
	add_child(poll)
	poll.request_completed.connect(_polled)
	ApiClient.event_emitted.connect(_enqueue)

func _enqueue(event: Dictionary) -> void:
	if fatal:
		return
	if event.event_type == "SESSION_READY":
		started = true
	if pending_events.size() >= 10000:
		_failure(true)
		return
	pending_events.append(event.duplicate(true))

func _headers() -> PackedStringArray:
	return PackedStringArray(["Content-Type: application/json", "X-Echo-Session-Token: " + token])

func _process(delta: float) -> void:
	if not started or fatal or url.is_empty():
		return
	post_delay -= delta
	poll_delay -= delta
	if not posting and not pending_events.is_empty() and post_delay <= 0:
		posting = true
		if post.request(url + "/game/event", _headers(), HTTPClient.METHOD_POST, JSON.stringify(pending_events[0])) != OK:
			posting = false
			_failure()
	if not polling and poll_delay <= 0:
		polling = true
		var endpoint := "%s/game/commands?session_id=%s&after=%d" % [url, ApiClient.session_id.uri_encode(), cursor]
		if poll.request(endpoint, _headers()) != OK:
			polling = false
			_failure()

func _posted(result: int, code: int, _headers_received: PackedStringArray, body: PackedByteArray) -> void:
	posting = false
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_failure(code >= 400 and code < 500)
		return
	var ack = JSON.parse_string(body.get_string_from_utf8())
	if not ack is Dictionary or pending_events.is_empty() or ack.get("accepted") != true or ack.get("event_id") != pending_events[0].event_id:
		_failure(true)
		return
	pending_events.pop_front()
	backoff = 0.5
	if ApiClient.companion_output == "bridge_simulator":
		ApiClient.status = "SILENT BRIDGE SIMULATOR · no physical robot or microphone"
	elif ApiClient.companion_output == "reachy_lite":
		ApiClient.status = "REACHY LITE OUTPUT SELECTED · use captions if unavailable"
	elif ApiClient.companion_output == "reachy_wireless":
		ApiClient.status = "WIRELESS OUTPUT SELECTED · remote worker required · use captions if unavailable"
	elif ApiClient.companion_output == "reachy_mujoco":
		ApiClient.status = "OFFICIAL REACHY MUJOCO · SDK motion + laptop voice · no hardware"
	elif ApiClient.companion_output == "reachy_control_simulator":
		ApiClient.status = "REACHY MINI CONTROL SIMULATOR · SDK motion + laptop voice · no hardware"
	else:
		ApiClient.status = "REACHY DRAFT REHEARSAL · laptop voice · no robot" if ApiClient.preview_enabled else "EXTERNAL MOCK CONTROLLER · connected · no robot"

func _polled(result: int, code: int, _headers_received: PackedStringArray, body: PackedByteArray) -> void:
	if result == HTTPRequest.RESULT_SUCCESS and code == 200:
		ApiClient.last_controller_contact = Time.get_ticks_msec()
	polling = false
	poll_delay = 0.2
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_failure(code >= 400 and code < 500)
		return
	var response = JSON.parse_string(body.get_string_from_utf8())
	if not response is Dictionary or not response.get("commands") is Array or response.get("mode") != "mock":
		_failure(true)
		return
	for envelope in response.commands:
		if not envelope is Dictionary or not envelope.get("command") is Dictionary or not envelope.get("cursor") is float:
			_failure(true)
			return
		var next_cursor := int(envelope.cursor)
		if next_cursor != cursor + 1 or envelope.command.get("session_id") != ApiClient.session_id:
			_failure(true)
			return
		ApiClient.receive_command(envelope.command)
		cursor = next_cursor
	if response.get("microphone") is Dictionary:
		ApiClient.update_microphone_meter(response.microphone)
	if response.get("speech_caption") is Dictionary and response.get("session_name", "") is String:
		ApiClient.update_private_speech(response.speech_caption, response.get("session_name", ""))

func change_nickname(value: String) -> void:
	var request := HTTPRequest.new()
	add_child(request)
	request.timeout = 3.0
	request.request_completed.connect(func(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray):
		if result == HTTPRequest.RESULT_SUCCESS and code == 200:
			var response = JSON.parse_string(body.get_string_from_utf8())
			if response is Dictionary and response.get("name") is String:
				ApiClient.session_nickname = response.name
				ApiClient.voice_release(true)
				var game = get_parent()
				if game.checkpoint.active and game.checkpoint.current_id == "NAME" and game.checkpoint.playback_done:
					game.checkpoint._resolve("ACKNOWLEDGED")
		request.queue_free()
	)
	request.request(url + "/session/name?session_id=" + ApiClient.session_id, PackedStringArray(["Content-Type: application/json", "X-Echo-Session-Token: " + token]), HTTPClient.METHOD_POST, JSON.stringify({"name":value.left(32)}))

func _failure(permanent: bool = false) -> void:
	ApiClient.clear_microphone_meter()
	if permanent:
		fatal = true
		ApiClient.status = "CONTROLLER SESSION ERROR · restart with a fresh session"
	else:
		ApiClient.status = "CONTROLLER DISCONNECTED · retrying · Resume remains available"
		post_delay = backoff
		poll_delay = backoff
		backoff = minf(backoff * 2, 8.0)
