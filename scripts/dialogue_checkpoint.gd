class_name DialogueCheckpoint
extends Node
signal completed
var ui: IslandUI
var speech: IslandSpeech
var active: bool = false
var key: String = ""
var current_id: String = ""
var current_text: String = ""
var resolving: bool = false
var pending_commands: Array[Dictionary] = []
var notice_label: Label
var preview_line: bool = false
var utterance_id: String = ""
var audio_id: String = ""
var playback_done: bool = true
var question: bool = false
var acknowledge_button: Button
var heard_caption: Label
var nickname_input: LineEdit
var nickname_badge: Label
var nickname_synced: bool = false
var after_speech_action: String = ""
var requested_at: int = 0

func _wait_for_speech(action: String) -> bool:
	if not preview_line or playback_done:
		return false
	if after_speech_action.is_empty():
		after_speech_action = action
	if is_instance_valid(notice_label):
		notice_label.text = "Reachy will finish speaking, then continue."
		notice_label.show()
	return true

func _run_after_speech() -> void:
	var action := after_speech_action
	after_speech_action = ""
	if action == "bypass": _bypass()
	elif action == "repeat": _repeat_preview()
	elif not action.is_empty(): _resolve(action)

func _process(_delta: float) -> void:
	if active and not GameState.stopped and not GameState.paused and after_speech_action == "bypass" and current_id.is_empty() and Time.get_ticks_msec() - requested_at > 5000 and Time.get_ticks_msec() - ApiClient.last_controller_contact > 5000 and not speech.busy and ApiClient.external_utterance_id.is_empty():
		after_speech_action = ""
		ApiClient.emit_event("MOCK_CHECKPOINT_BYPASSED", {"checkpoint_id": key})
		_finish()
	if is_instance_valid(heard_caption):
		heard_caption.visible = not ApiClient.speech_caption.is_empty()
		heard_caption.text = ("You said: " if ApiClient.speech_caption_final else "You (live, may change): ") + ApiClient.speech_caption
	if is_instance_valid(nickname_badge):
		nickname_badge.text = "Your name this session: " + (ApiClient.session_nickname if not ApiClient.session_nickname.is_empty() else "not set")
		if not nickname_synced and is_instance_valid(nickname_input) and not nickname_input.has_focus() and not ApiClient.session_nickname.is_empty():
			nickname_input.text = ApiClient.session_nickname
			nickname_synced = true
	if preview_line and ApiClient.companion_output == "laptop" and not playback_done and not GameState.paused and not GameState.stopped and (not speech.busy or speech.active_line != audio_id):
		_playback_completed("cancelled")
	if not GameState.paused and not GameState.stopped and not pending_commands.is_empty():
		_command(pending_commands.pop_front())

func setup(interface: IslandUI, voice: IslandSpeech) -> void:
	ui = interface
	speech = voice
	EventBus.command_received.connect(_command)
	speech.finished.connect(func(id: String):
		if active and preview_line and id == audio_id and not playback_done:
			_playback_completed("audio_completed")
			if not question and after_speech_action.is_empty():
				_resolve("ACKNOWLEDGED")
	)

func begin(stage: Dictionary, phase: String) -> void:
	key = stage.id + "_" + phase
	if GameState.checkpoints.has(key):
		completed.emit()
		return
	active = true
	resolving = false
	current_id = ""
	requested_at = Time.get_ticks_msec()
	after_speech_action = ""
	preview_line = false
	var panel := ui.show_modal("Mock companion adapter", "Companion checkpoint", "Development simulation · no hardware, microphone or personal answers")
	IslandUI.text(panel, "Waiting for the companion controller. If it is unavailable, explicitly resume without it; puzzle rewards do not depend on this checkpoint.", 20)
	IslandUI.button(panel, "Resume game", _bypass)
	ApiClient.emit_event("CONVERSATION_CHECKPOINT_REQUESTED", {"checkpoint_id": key, "phase": phase})

func _show(command: Dictionary) -> void:
	current_id = command.line_id
	current_text = command.text
	resolving = false
	preview_line = command.get("preview", false)
	if preview_line:
		_show_preview(command)
		return
	var panel := ui.show_modal("MOCK ROBOT · DEVELOPMENT ONLY", "A moment with your companion", "Conversation simulation · your choices never affect the treasure")
	IslandUI.text(panel, current_text, 24)
	_add_speech_feedback(panel)
	var actions := IslandUI.row(panel)
	IslandUI.button(actions, "Mock acknowledgement", func(): _resolve("ACKNOWLEDGED"))
	if command.get("question", false):
		IslandUI.button(actions, "Skip", func(): _resolve("SKIPPED"))
		IslandUI.button(actions, "Cannot recall", func(): _resolve("NO_RECALL"))
	IslandUI.button(actions, "Repeat", func():
		ApiClient.emit_event("MOCK_REPEAT_REQUESTED", {"checkpoint_id": key, "line_id": current_id})
		speech.speak(current_text)
	)
	var options := IslandUI.row(panel)
	IslandUI.button(options, "Wait / silence", func(): speech.stop())
	IslandUI.button(options, "Mock technical failure · resume", func(): _resolve("TECHNICAL_FAILURE"))
	IslandUI.button(options, "Resume game", _bypass)
	IslandUI.text(panel, "Pause or stop at any time. These controls are test fixtures, not a study dialogue system.", 17, IslandUI.MUTED)
	notice_label = IslandUI.text(panel, "", 17, IslandUI.GOLD)
	notice_label.hide()

func _show_preview(command: Dictionary) -> void:
	utterance_id = command.utterance_id
	audio_id = command.audio_id
	question = command.get("question", false)
	playback_done = false
	var description := "Laptop voice + animated mock · no robot or microphone connected"
	if ApiClient.companion_output == "bridge_simulator":
		description = "Silent bridge simulator + animated mock · no physical robot or microphone"
	elif ApiClient.companion_output == "reachy_lite":
		description = "Reachy Lite output selected · captions remain available · no microphone input"
	elif ApiClient.companion_output == "reachy_wireless":
		description = "Wireless robot output selected · remote worker required · captions remain available"
	elif ApiClient.companion_output == "reachy_mujoco":
		description = "Official Reachy Mini MuJoCo · SDK animation in the 3D robot window · laptop voice"
	elif ApiClient.companion_output == "reachy_control_simulator":
		description = "Reachy Mini Control · built-in simulator · laptop voice · microphone off"
	if ApiClient.microphone_enabled:
		description = "Hold B to give a reply · Hold V for skip, repeat, pause or another control · release to send"
	if ApiClient.conversation_enabled:
		description = "Reachy listens after speaking · Answer naturally, then pause · Say skip, repeat or stop"
	var panel := ui.show_modal("REACHY REHEARSAL · DRAFT", "A moment with Reachy", description)
	var face := CompanionFace.new()
	face.motion_id = command.motion_id
	panel.add_child(face)
	IslandUI.text(panel, current_text, 24)
	_add_speech_feedback(panel)
	if command.get("provenance") == "proposed_development_addition":
		IslandUI.text(panel, "Proposed welcome / celebration wording for development review.", 16, IslandUI.MUTED)
	var actions := IslandUI.row(panel)
	var label := "Mock reply given · continue" if question else "Continue after reading"
	if question and ApiClient.microphone_enabled:
		label = "Complete reply"
	acknowledge_button = IslandUI.button(actions, label, func(): _resolve("ACKNOWLEDGED"))
	acknowledge_button.disabled = true
	if question:
		IslandUI.button(actions, "Skip question", func(): _resolve("SKIPPED"))
		IslandUI.button(actions, "Repeat after speech", _repeat_preview)
	IslandUI.button(panel, "Return to game after speech", _bypass)
	var privacy := "Replies are optional. Voice input is handled locally and discarded; no audio or reply transcript is saved." if ApiClient.microphone_enabled else "No reply text or name is entered, recorded or inferred. Wait as long as you like, or skip. Pause and stop remain available."
	IslandUI.text(panel, privacy, 17, IslandUI.MUTED)
	notice_label = IslandUI.text(panel, "", 17, IslandUI.GOLD)
	notice_label.hide()
	if ApiClient.companion_output != "laptop":
		ApiClient.external_ready(command)
	elif not speech.catalogue.has(audio_id) or speech.catalogue[audio_id].text != current_text or not speech.play_line(audio_id):
		_playback_completed("technical_failure")
		show_preview_failure()

func show_preview_failure() -> void:
	if is_instance_valid(notice_label):
		notice_label.text = "Companion voice is muted or unavailable. Read the caption and continue, or skip."
		notice_label.show()

func _playback_completed(completion: String) -> void:
	if playback_done or utterance_id.is_empty():
		return
	playback_done = true
	if ApiClient.companion_output == "laptop":
		ApiClient.emit_event("COMPANION_PLAYBACK_COMPLETED", {"utterance_id": utterance_id, "completion": completion})
	elif completion not in ["audio_completed", "simulated_completed", "technical_failure"]:
		ApiClient.cancel_external()
	if is_instance_valid(acknowledge_button):
		acknowledge_button.disabled = false
	if not after_speech_action.is_empty():
		_run_after_speech.call_deferred()

func _repeat_preview() -> void:
	if not active or resolving or GameState.stopped or not question:
		return
	if _wait_for_speech("repeat"):
		return
	_playback_completed("cancelled")
	speech.stop()
	resolving = true
	ApiClient.emit_event("MOCK_REPEAT_REQUESTED", {"checkpoint_id": key, "line_id": current_id})

func show_notice(notice_id: String) -> void:
	if is_instance_valid(notice_label) and CompanionNotices.TEXTS.has(notice_id):
		notice_label.text = CompanionNotices.TEXTS[notice_id]
		notice_label.show()

func _resolve(outcome: String) -> void:
	if not active or resolving or GameState.stopped:
		return
	if _wait_for_speech(outcome):
		return
	if preview_line and outcome == "ACKNOWLEDGED" and not playback_done:
		return
	if preview_line:
		_playback_completed("explicit_skip" if outcome != "ACKNOWLEDGED" else "technical_failure")
	resolving = true
	speech.stop()
	ApiClient.emit_event("CHECKPOINT_ITEM_COMPLETED", {"checkpoint_id": key, "line_id": current_id, "status": outcome, "mock": true})

func _bypass() -> void:
	if not active or GameState.stopped:
		return
	if ApiClient.preview_enabled and current_id.is_empty():
		after_speech_action = "bypass"
		return
	if _wait_for_speech("bypass"):
		return
	if preview_line:
		_playback_completed("explicit_skip")
	ApiClient.emit_event("MOCK_CHECKPOINT_BYPASSED", {"checkpoint_id": key})
	_finish()

func _command(command: Dictionary) -> void:
	if not active or GameState.stopped or command.get("checkpoint_id", "") != key:
		return
	if GameState.paused:
		pending_commands.append(command.duplicate(true))
		return
	if command.get("type") == "COMPANION_OUTPUT_RESULT":
		if command.get("utterance_id") != utterance_id:
			return
		_playback_completed(command.completion)
		if command.completion in ["audio_completed", "simulated_completed"] and not question and not resolving and after_speech_action.is_empty():
			_resolve("ACKNOWLEDGED")
		elif command.completion == "technical_failure":
			show_preview_failure()
		return
	if command.get("type") == "COMPANION_CHECKPOINT_ACTION":
		if command.get("line_id") != current_id or resolving:
			return
		match command.action:
			"ack":
				if preview_line and question and playback_done:
					_resolve("ACKNOWLEDGED")
			"skip": _resolve("SKIPPED")
			"no_recall": _resolve("NO_RECALL")
			"repeat":
				if preview_line:
					_repeat_preview()
				else:
					ApiClient.emit_event("MOCK_REPEAT_REQUESTED", {"checkpoint_id": key, "line_id": current_id})
		return
	if command.get("type") == "SHOW_DIALOGUE":
		_show(command)
	elif command.get("type") == "RESUME_GAME":
		_finish()

func _finish() -> void:
	active = false
	after_speech_action = ""
	preview_line = false
	speech.stop()
	GameState.checkpoints[key] = true
	completed.emit()

func _add_speech_feedback(panel: VBoxContainer) -> void:
	if not ApiClient.conversation_enabled:
		return
	heard_caption = IslandUI.text(panel, "", 17, Color("91edce"))
	heard_caption.hide()
	if current_id in ["NAME", "NAME_ACK"]:
		nickname_synced = false
		nickname_badge = IslandUI.text(panel, "", 14, IslandUI.MUTED)
		var name_row := IslandUI.row(panel)
		nickname_input = LineEdit.new()
		nickname_input.placeholder_text = "Correct your name here if needed"
		nickname_input.max_length = 32
		nickname_input.text = ApiClient.session_nickname
		nickname_input.custom_minimum_size = Vector2(270, 38)
		name_row.add_child(nickname_input)
		IslandUI.button(name_row, "Use this name", func():
			var transport = get_parent().get("controller")
			if transport: transport.change_nickname(nickname_input.text)
		)
