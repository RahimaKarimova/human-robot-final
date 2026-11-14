extends Node
var game: Node3D
var assertions := 0
var heard_statuses: Array[String] = []
var heard_cues: Array[String] = []
var asked_questions: Array[String] = []
var negative_book_reply := false
var captions_seen := false
var output_completions: Array[String] = []

func _process(_delta: float) -> void:
	if not ApiClient.speech_caption.is_empty(): captions_seen = true

func check(value: bool, description: String) -> void:
	assertions += 1
	if not value:
		push_error("FAIL: " + description)
		get_tree().quit(1)

func until(predicate: Callable, description: String) -> bool:
	var deadline := Time.get_ticks_msec() + 65000
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	var okay: bool = predicate.call()
	if not okay:
		print("Conversation diagnostic: view=", game.view, " line=", game.checkpoint.current_id, " status=", ApiClient.voice_status, " paused=", GameState.paused, " capture_empty=", ApiClient.voice_capture_id.is_empty(), " statuses=", heard_statuses, " output=", output_completions)
	check(okay, description)
	return okay

func _ready() -> void:
	AudioServer.set_bus_mute(0, true)
	get_tree().create_timer(220).timeout.connect(func():
		push_error("FAIL: natural conversation watchdog")
		get_tree().quit(1)
	)
	GameState.reset()
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	EventBus.command_received.connect(func(command: Dictionary):
		if command.type == "COMPANION_OUTPUT_RESULT": output_completions.append(command.completion)
		if command.type == "VOICE_CONTROL_STATUS": heard_statuses.append(command.status)
		if command.type == "COMPANION_CUE": heard_cues.append(command.audio_id)
		if command.type == "SHOW_DIALOGUE": asked_questions.append(command.line_id)
		if command.type == "SHOW_DIALOGUE" and command.line_id == "G1_ACK" and "Not a book fan" in command.text:
			negative_book_reply = true
	)
	check(ApiClient.conversation_enabled and ApiClient.microphone_enabled, "natural conversations explicitly enabled")
	check(ApiClient.voice_capture_id.is_empty(), "launch opens no microphone")
	game._begin()
	if not await until(func(): return game.checkpoint.current_id == "WELCOME", "actual SDK welcome arrives"):
		return
	check(ApiClient.voice_capture_id.is_empty(), "microphone closed while Reachy speaks")
	if not await until(func(): return game.view == "tutorial", "welcome reaches tutorial without a name question"):
		return
	check(not asked_questions.has("NAME") and not asked_questions.has("NAME_ACK"), "opening does not ask for or acknowledge a name")
	check(ApiClient.voice_capture_id.is_empty(), "opening and tutorial keep the microphone closed")
	game.ui.close_modal()
	game.view = "explore"
	GameState.tutorial_done = true
	game.player.position = game.world.targets[0].global_position
	game._interact()
	if not await until(func(): return game.reader.active, "letter opens without microphone interference"):
		return
	check(ApiClient.voice_capture_id.is_empty(), "letter narration owns audio")
	game.reader._skip()
	game.reader._close()
	if not await until(func(): return game.checkpoint.current_id == "G1" and ApiClient.voice_status == "LISTENING", "first planned question opens listening after full introduction and playback"):
		return
	check(ApiClient.voice_automatic, "LISTENING was adopted without V or B")
	game._toggle_pause()
	if not await until(func(): return ApiClient.voice_capture_id.is_empty(), "pause closes automatic capture"):
		return
	await get_tree().create_timer(.4).timeout
	check(game.checkpoint.current_id == "G1", "cancelled input cannot answer the first question")
	check(GameState.paused, "automatic listening does not resume a paused game")
	game._resume()
	if not await until(func(): return game.puzzle_panel.active, "planned Library conversation answers naturally and releases puzzle"):
		return
	check(heard_statuses.has("PROCESSING") and heard_statuses.has("SENT"), "complete automatic recognition pipeline reported")
	check(heard_cues.has("companion_notice_development_privacy"), "spoken privacy request gets fixed voiced response without advancing question")
	check(not game.controller.fatal, "natural turns preserve the game protocol")
	check(heard_cues.has("companion_notice_waiting"), "spoken wait request gives time and a voiced response")
	check(asked_questions.count("G1") == 2, "spoken repeat asks the same question once")
	check(negative_book_reply, "negative book preference selects contextual reply instead of generic thanks")
	check(captions_seen, "recognised speech is visible in the game")
	GameState.stop()
	if not await until(func(): return game.controller.pending_events.is_empty() and ApiClient.voice_capture_id.is_empty(), "terminal stop drains and leaves microphone off"):
		return
	print("ECHO NATURAL CONVERSATION: %d assertions, 0 failures" % assertions)
	get_tree().quit(0)
