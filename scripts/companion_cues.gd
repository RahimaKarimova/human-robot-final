class_name CompanionCues
extends Node
## Fixed laptop-only hint playback. Shares the game's single speech channel.
var game: Node3D
var pending: Array[Dictionary] = []
var active: Dictionary = {}

func setup(owner_game: Node3D) -> void:
	game = owner_game
	EventBus.command_received.connect(func(command: Dictionary):
		if command.get("type") == "COMPANION_CUE":
			pending.append(command.duplicate(true))
		elif command.get("type") == "COMPANION_OUTPUT_RESULT" and not active.is_empty() and command.get("utterance_id") == active.utterance_id:
			active = {}
	)
	game.speech.finished.connect(func(id: String):
		if not active.is_empty() and id == active.audio_id:
			_complete(active, "audio_completed")
			active = {}
	)

func _complete(command: Dictionary, completion: String) -> void:
	if ApiClient.companion_output == "laptop":
		ApiClient.emit_event("COMPANION_PLAYBACK_COMPLETED", {"utterance_id": command.utterance_id, "completion": completion}, command.stage_id)
	else:
		ApiClient.external_ready(command)
		ApiClient.cancel_external()

func _process(_delta: float) -> void:
	if GameState.stopped:
		pending.clear()
		active = {}
		return
	if GameState.paused:
		return
	var stage_id: String = Content.stage(GameState.stage_index).id
	if not active.is_empty():
		if ApiClient.companion_output != "laptop":
			if ApiClient.external_utterance_id.is_empty():
				active = {}
		elif not game.speech.busy or game.speech.active_line != active.audio_id:
			_complete(active, "cancelled")
			active = {}
	if pending.is_empty() or not active.is_empty():
		return
	var command: Dictionary = pending[0]
	if game.reader.active:
		return
	if game.speech.busy:
		return
	pending.pop_front()
	active = command
	game.ui.caption_name.text = "Reachy · " + ("laptop rehearsal" if ApiClient.companion_output == "laptop" else "external output") + " · " + command.motion_id.to_lower()
	game.ui.caption_line.text = command.text
	game.caption_until = Time.get_ticks_msec() / 1000.0 + 7.0
	if ApiClient.companion_output != "laptop":
		ApiClient.external_ready(command)
	elif not game.speech.catalogue.has(command.audio_id) or game.speech.catalogue[command.audio_id].text != command.text or not game.speech.play_line(command.audio_id):
		_complete(command, "technical_failure")
		active = {}
