extends Node
## Event contract. Offline by default; optional transport lives in ControllerTransport.
signal event_emitted(event: Dictionary)
const ALLOWED_COMMANDS := ["SHOW_DIALOGUE", "RESUME_GAME", "PAUSE_GAME", "STOP_SESSION", "SESSION_STOP", "SHOW_OBJECTIVE", "RESUME_PLAY", "COMPANION_CHECKPOINT_ACTION", "REQUEST_HINT", "COMPANION_NOTICE", "COMPANION_CUE", "COMPANION_OUTPUT_RESULT"]
var preview_enabled: bool = false
var companion_output: String = "laptop"
var external_utterance_id: String = ""
var external_stage_id: String = "library"
var external_cancel_at: int = 0
var microphone_enabled: bool = false
var conversation_enabled: bool = false
var voice_automatic: bool = false
var last_controller_contact: int = 0
var microphone_level: float = 0.0
var microphone_live: bool = false
var microphone_sequence: int = 0
var microphone_meter_at: int = 0
var speech_caption: String = ""
var speech_caption_final: bool = false
var recent_capture_id: String = ""
var session_nickname: String = ""

func update_private_speech(data: Dictionary, nickname: String) -> void:
	if not conversation_enabled or GameState.stopped:
		speech_caption = ""
		session_nickname = ""
		return
	session_nickname = nickname.left(32)
	if data.is_empty():
		speech_caption = ""
		return
	if data.get("capture_id", "") == recent_capture_id and data.get("text") is String:
		speech_caption = data.text.left(400)
		speech_caption_final = data.get("final", false) == true

func clear_microphone_meter() -> void:
	microphone_level = 0.0
	microphone_live = false
	microphone_sequence = 0
	microphone_meter_at = 0

func update_microphone_meter(data: Dictionary) -> void:
	if not microphone_enabled or voice_status != "LISTENING" or data.get("capture_id", "") != voice_capture_id or data.get("live", false) != true:
		clear_microphone_meter()
		return
	if not data.get("level") is float or not data.get("sequence") is float or not is_finite(data.level) or data.level < 0.0 or data.level > 1.0:
		return
	microphone_level = data.level
	microphone_sequence = int(data.sequence)
	microphone_live = true
	microphone_meter_at = Time.get_ticks_msec()
var voice_capture_id: String = ""
var voice_ended_at: int = 0
var voice_status: String = "IDLE"
var voice_cancel_sent: bool = false
const VOICE_TEXT := {"IDLE": "Mic off · Hold V for controls · Hold B to reply during a question", "STARTING": "Opening microphone…", "LISTENING": "LISTENING · Speak, then release the held key", "PROCESSING": "Microphone off · Recognizing speech…", "SENT": "Voice input handled · Microphone off", "NO_COMMAND": "Speech not recognized · Microphone off · Try again or use buttons", "CANCELLED": "Voice input cancelled · Microphone off", "UNAVAILABLE": "Voice controls unavailable · Use the game buttons"}

func voice_start(purpose: String = "control") -> void:
	if not microphone_enabled or not voice_capture_id.is_empty() or GameState.stopped or not GameState.started:
		return
	voice_capture_id = Crypto.new().generate_random_bytes(12).hex_encode()
	recent_capture_id = voice_capture_id
	speech_caption = ""
	voice_status = "STARTING"
	voice_ended_at = 0
	voice_cancel_sent = false
	emit_event("VOICE_CONTROL_REQUESTED", {"capture_id":voice_capture_id, "purpose":purpose})

func voice_release(cancel: bool = false) -> void:
	if voice_capture_id.is_empty() or GameState.stopped or (voice_ended_at > 0 and (not cancel or voice_cancel_sent)):
		return
	voice_ended_at = Time.get_ticks_msec()
	voice_cancel_sent = cancel
	emit_event("VOICE_CONTROL_RELEASED", {"capture_id":voice_capture_id, "cancel":cancel})

func external_ready(command: Dictionary) -> void:
	external_utterance_id = command.utterance_id
	external_stage_id = command.stage_id
	external_cancel_at = 0
	emit_event("COMPANION_PLAYBACK_READY", {"utterance_id": command.utterance_id}, command.stage_id)

func cancel_external() -> void:
	# Panel navigation must not truncate Reachy or release the audio gate early.
	# Session Stop and worker/game disconnects own terminal cancellation.
	pass

func _process(_delta: float) -> void:
	if GameState.stopped:
		session_nickname = ""
		speech_caption = ""
	if voice_status != "LISTENING" or GameState.stopped or Time.get_ticks_msec() - microphone_meter_at > 800:
		clear_microphone_meter()
	if voice_automatic and last_controller_contact > 0 and Time.get_ticks_msec() - last_controller_contact > 4000:
		voice_release(true)
		voice_capture_id = ""
		voice_automatic = false
		voice_status = "UNAVAILABLE"
	var voice_timeout := 35000 if voice_status == "PROCESSING" else 5000
	if GameState.stopped or (voice_ended_at > 0 and Time.get_ticks_msec() - voice_ended_at > voice_timeout):
		voice_capture_id = ""
		voice_ended_at = 0
		voice_status = "UNAVAILABLE" if not GameState.stopped else "IDLE"
	# A lost controller must not hold local gameplay forever. The bridge has a
	# shorter local connection timeout and a separate game-poll lease.
	if GameState.stopped or (not external_utterance_id.is_empty() and last_controller_contact > 0 and Time.get_ticks_msec() - last_controller_contact > 5000):
		external_utterance_id = ""
		external_cancel_at = 0
var session_id: String = ""
var event_number: int = 0
var seen_commands: Dictionary = {}
var status: String = "MOCK ROBOT · offline · no microphone or hardware"
var controller_session_id: String = ""
var event_run_id: String = ""

func begin() -> void:
	GameState.demo = true
	session_id = controller_session_id if not controller_session_id.is_empty() else "demo-" + Crypto.new().generate_random_bytes(12).hex_encode()
	event_run_id = Crypto.new().generate_random_bytes(6).hex_encode()
	event_number = 0
	seen_commands.clear()
	emit_event("SESSION_READY")

func emit_event(kind: String, payload: Dictionary = {}, stage_override: String = "") -> void:
	if session_id.is_empty():
		return
	event_number += 1
	var event := {"version": 1, "session_id": session_id, "event_id": "%s-%s-%d" % [session_id, event_run_id, event_number],
		"stage_id": Content.stage(GameState.stage_index).id if stage_override.is_empty() else stage_override, "event_type": kind, "payload": payload.duplicate(true)}
	event_emitted.emit(event)

func receive_command(command: Dictionary) -> bool:
	var id := str(command.get("command_id", ""))
	if id.is_empty() or command.get("session_id") != session_id or seen_commands.has(id):
		return false
	if (command.get("type") not in ALLOWED_COMMANDS and command.get("type") != "VOICE_CONTROL_STATUS") or GameState.stopped:
		return false
	if command.get("type") in ["SHOW_DIALOGUE", "RESUME_GAME"]:
		if not command.get("checkpoint_id") is String:
			return false
	if command.get("type") == "SHOW_DIALOGUE":
		if not command.get("line_id") is String or not command.get("text") is String:
			return false
	if command.get("preview", false) or command.get("type") == "COMPANION_CUE":
		if not preview_enabled or command.get("preview") != true:
			return false
		for field in ["audio_id", "utterance_id", "motion_id", "text", "stage_id"]:
			if not command.get(field) is String:
				return false
		if not command.audio_id.begins_with("companion_") or command.motion_id not in ["WAVE", "NOD", "LISTEN", "POINT", "CELEBRATE"]:
			return false
		if command.get("output_route", "laptop") != companion_output:
			return false
	if command.get("type") == "RESUME_PLAY" and not command.get("pause_id") is String:
		return false
	if command.get("type") == "REQUEST_HINT" and not command.get("stage_id") is String:
		return false
	if command.get("type") == "COMPANION_CHECKPOINT_ACTION":
		if not command.get("checkpoint_id") is String or not command.get("line_id") is String or command.get("action") not in ["skip", "repeat", "no_recall", "ack"]:
			return false
	if command.get("type") == "COMPANION_NOTICE" and not CompanionNotices.TEXTS.has(command.get("notice_id", "")):
		return false
	if command.get("type") == "VOICE_CONTROL_STATUS":
		if conversation_enabled and microphone_enabled and command.get("automatic", false) == true and command.get("status") == "STARTING" and voice_capture_id.is_empty():
			voice_capture_id = command.capture_id
			recent_capture_id = voice_capture_id
			speech_caption = ""
			voice_automatic = true
			voice_ended_at = 0
			voice_cancel_sent = false
		if not microphone_enabled or command.get("capture_id") != voice_capture_id or not VOICE_TEXT.has(command.get("status", "")):
			return false
		voice_status = command.status
		if voice_status not in ["STARTING", "LISTENING", "PROCESSING"]:
			voice_capture_id = ""
			voice_ended_at = 0
			voice_automatic = false
	if command.get("type") == "COMPANION_OUTPUT_RESULT":
		if companion_output == "laptop" or not command.get("utterance_id") is String or not command.get("stage_id") is String or command.get("completion") not in ["audio_completed", "simulated_completed", "cancelled", "technical_failure"]:
			return false
		if command.completion == "audio_completed" and companion_output not in ["reachy_lite", "reachy_wireless"]:
			return false
		if command.completion == "simulated_completed" and companion_output not in ["bridge_simulator", "reachy_mujoco", "reachy_control_simulator"]:
			return false
		if command.utterance_id == external_utterance_id:
			external_utterance_id = ""
			external_cancel_at = 0
		emit_event("COMPANION_PLAYBACK_COMPLETED", {"utterance_id": command.utterance_id, "completion": command.completion}, command.stage_id)
	seen_commands[id] = true
	if command.type in ["STOP_SESSION", "SESSION_STOP"]:
		GameState.stop()
	else:
		EventBus.command_received.emit(command.duplicate(true))
	return true
