class_name MockRobotAdapter
extends Node
## No personal questions, experimental speech, hardware or network dependencies.
var seen_events: Dictionary = {}
var checkpoints: Dictionary = {}
var command_number: int = 0
var narrator_ready: Dictionary = {}
var enabled: bool = true

func _ready() -> void:
	ApiClient.event_emitted.connect(accept_event)

func accept_event(event: Dictionary) -> void:
	if not enabled:
		return
	if seen_events.has(event.event_id):
		return
	seen_events[event.event_id] = true
	if GameState.stopped:
		return
	var data: Dictionary = Content.stage(GameState.stage_index)
	var payload: Dictionary = event.payload
	match event.event_type:
		"LETTER_OPENED":
			narrator_ready[event.stage_id] = false
		"LETTER_NARRATION_COMPLETED":
			narrator_ready[event.stage_id] = true
		"CONVERSATION_CHECKPOINT_REQUESTED":
			var phase: String = str(payload.get("phase", ""))
			if phase not in ["entry", "before", "after"] or data.id != event.stage_id:
				return
			if phase != "entry" and not narrator_ready.get(event.stage_id, false):
				return
			var key: String = payload.checkpoint_id
			if checkpoints.has(key):
				return
			checkpoints[key] = {"lines": data[phase].duplicate(), "index": 0}
			_send_next.call_deferred(key)
		"CHECKPOINT_ITEM_COMPLETED":
			var key: String = payload.get("checkpoint_id", "")
			if not checkpoints.has(key):
				return
			var state: Dictionary = checkpoints[key]
			if state.index >= state.lines.size() or state.lines[state.index] != payload.get("line_id"):
				return
			state.index += 1
			_send_next.call_deferred(key)

func _send_next(key: String) -> void:
	if GameState.stopped:
		return
	var state: Dictionary = checkpoints[key]
	if state.index >= state.lines.size():
		_command({"type": "RESUME_GAME", "checkpoint_id": key})
		return
	var id: String = state.lines[state.index]
	var value := "Mock comment checkpoint %s. No experimental humour is delivered. Acknowledge to continue the adventure." % id
	if not id.begins_with("H"):
		value = "Mock optional conversation checkpoint %s. No personal question is being asked, and no answer is collected. Try acknowledge, skip or repeat to test the game flow." % id
	_command({"type": "SHOW_DIALOGUE", "checkpoint_id": key, "line_id": id, "text": value, "question": not id.begins_with("H")})

func _command(value: Dictionary) -> void:
	command_number += 1
	value["command_id"] = "mock-%d" % command_number
	value["session_id"] = ApiClient.session_id
	ApiClient.receive_command(value)
