extends Node
## Rehearsal through the actual HTTP controller and bundled WAV playback callbacks.
var game: Node3D
var assertions: int = 0
var lines: Array[String] = []
var playback_outcomes: Array[Dictionary] = []

func check(value: bool, description: String) -> void:
	assertions += 1
	if not value:
		push_error("FAIL: " + description)
		get_tree().quit(1)

func until(predicate: Callable, description: String) -> bool:
	var deadline := Time.get_ticks_msec() + 16000
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	var success: bool = predicate.call()
	check(success, description)
	return success

func capture(filename: String) -> void:
	if "--capture-preview" not in OS.get_cmdline_user_args():
		return
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://artifacts/companion-preview")
	DirAccess.make_dir_recursive_absolute(folder)
	check(get_viewport().get_texture().get_image().save_png(folder.path_join(filename + ".png")) == OK, "rendered preview screenshot saved: " + filename)

func _ready() -> void:
	# Rendered checks still run real playback callbacks, but must never play
	# accelerated test speech through the user's speakers.
	AudioServer.set_bus_mute(0, true)
	get_tree().create_timer(90).timeout.connect(func():
		push_error("FAIL: preview test watchdog timed out")
		get_tree().quit(1)
	)
	GameState.reset()
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	EventBus.command_received.connect(func(command: Dictionary):
		if command.get("type") == "SHOW_DIALOGUE":
			lines.append(command.line_id)
	)
	ApiClient.event_emitted.connect(func(event: Dictionary):
		if event.event_type == "COMPANION_PLAYBACK_COMPLETED":
			playback_outcomes.append(event.payload)
	)
	check(ApiClient.preview_enabled and not game.mock_robot.enabled, "explicit rehearsal uses external controller")
	check(is_equal_approx(game.speech.playback.pitch_scale, 1.0), "normal play initializes speech at natural pitch and speed")
	check(AudioServer.is_bus_mute(0), "accelerated test speech cannot reach physical speakers")
	game.speech.enabled = false  # Skip only the already-tested island intro.
	game._begin()
	game.speech.enabled = true
	game.speech.playback.pitch_scale = 4.0  # Accelerate real AudioStreamPlayer callbacks in tests only.
	if not await until(func(): return game.checkpoint.current_id == "WELCOME" and game.speech.busy, "welcome plays its bundled voice"):
		return
	check(game.speech.active_line == "companion_welcome", "welcome has its own companion voice asset")
	check(game.checkpoint.acknowledge_button.disabled, "continue waits for real playback completion")
	game.ui.close_modal()
	check(game.speech.busy and game.speech.active_line == "companion_welcome", "closing the conversation panel preserves the whole welcome")
	check(not game.speech.play_line("greeting_library"), "an incidental greeting cannot replace Reachy mid-sentence")
	check(game.speech.active_line == "companion_welcome", "incidental click leaves the current voice intact")
	game._toggle_pause()
	check(GameState.paused and game.speech.playback.stream_paused, "pause freezes companion audio")
	var paused_line: String = game.checkpoint.current_id
	await get_tree().create_timer(0.2).timeout
	check(game.checkpoint.current_id == paused_line, "paused speech cannot advance the script")
	game._resume()
	if not await until(func(): return game.view == "tutorial", "welcome releases the tutorial without a name question"):
		return
	check(not lines.has("NAME") and not lines.has("NAME_ACK"), "opening contains no name exchange")
	game.speech.enabled = true
	game.ui.close_modal()
	game.view = "explore"
	GameState.tutorial_done = true
	game.player.position = game.world.targets[0].global_position
	game._interact()
	if not await until(func(): return game.reader.active, "Library entry reaches Elara's letter"):
		return
	check(game.speech.active_line == "L1", "narrator owns the voice channel while reading")
	game.reader._skip()
	game.reader._close()
	var jokes_on := not "--test-jokes-off" in OS.get_cmdline_user_args()
	if jokes_on:
		if not await until(func(): return game.checkpoint.current_id == "H1" and game.speech.busy, "letter completion releases H1"):
			return
		check(not game.checkpoint.current_text.begins_with("External mock"), "rehearsal uses the supplied script")
		game.checkpoint._resolve("ACKNOWLEDGED")
		check(game.checkpoint.current_id == "H1" and not game.checkpoint.resolving, "early acknowledgement cannot truncate a comment")
	if not await until(func(): return game.checkpoint.current_id == "G1" and game.checkpoint.playback_done, "H1 completion releases the exact Library question"):
		return
	check(game.checkpoint.current_text.ends_with("What kind of stories or books do you enjoy?"), "G1 keeps the question after Reachy's introduction")
	await get_tree().create_timer(0.2).timeout
	check(game.checkpoint.current_id == "G1", "silence is never treated as a reply")
	await capture("library-question")
	game.checkpoint._repeat_preview()
	if not await until(func(): return lines.count("G1") == 2 and game.checkpoint.playback_done, "repeat replays only the current question"):
		return
	check(lines.count("H1") == (1 if jokes_on else 0), "repeating G1 preserves the selected joke mode")
	game.speech.enabled = false
	game.checkpoint._resolve("SKIPPED")
	if not await until(func(): return game.checkpoint.current_id == "G1_ACK", "skip receives the shared acknowledgement"):
		return
	check(game.checkpoint.current_text == Content.catalogue.skip_acknowledgement, "skip acknowledgement matches the source")
	if not await until(func(): return game.checkpoint.playback_done, "muted acknowledgement falls back to captions"):
		return
	check(game.checkpoint.notice_label.visible and not game.checkpoint.acknowledge_button.disabled, "voice failure exposes an explicit continue button")
	game.checkpoint._resolve("ACKNOWLEDGED")
	game.speech.enabled = true
	if not await until(func(): return game.puzzle_panel.active, "question skip releases the physical bookshelf"):
		return
	game._hint()
	if not await until(func(): return game.speech.active_line == "companion_hint_1", "first hint is voiced using the game hint ladder"):
		return
	check(game.ui.caption_line.text == Content.stage(0).hints[0], "hint caption and audio use shared fixed content")
	game._hint()
	game._hint()
	check(game.puzzle_panel.focus_by_id("golden_feather"), "real golden-feather book can be selected")
	game._interact()
	if not await until(func(): return game.checkpoint.current_id == "LIBRARY_SUCCESS", "solving the bookshelf starts the emerald celebration"):
		return
	check(GameState.fragments.has("library"), "emerald is already earned before optional celebration")
	await capture("emerald-celebration")
	if not await until(func(): return game.view == "reward", "real voice completion releases the visible gem reward"):
		return
	check(lines.count("LIBRARY_SUCCESS") == 1, "celebration occurs once")
	check(playback_outcomes.any(func(outcome: Dictionary): return outcome.completion == "audio_completed"), "natural playback acknowledgements reach the contract")
	if not await until(func(): return game.controller.pending_events.is_empty(), "all preview events are acknowledged"):
		return
	check(not game.controller.fatal, "preview protocol remains valid")
	game._continue_reward()
	game.player.position = game.world.targets[1].global_position
	game._interact()
	if not await until(func(): return game.reader.active, "later chapters remain independently playable"):
		return
	game.reader._skip()
	game.reader._close()
	if not await until(func(): return game.checkpoint.current_id == "P1", "Workshop companion question is connected"):
		return
	check(game.checkpoint.preview_line and game.checkpoint.current_text.ends_with("What's something you often put off doing, even though you know you should do it?"), "Workshop keeps the question after Reachy's introduction")
	game.checkpoint._bypass()
	check(game.speech.busy and game.checkpoint.after_speech_action == "bypass", "return-to-game click queues until the question finishes")
	if not await until(func(): return game.puzzle_panel.active, "queued navigation waits for natural speech completion"):
		return
	check(game.speech.play_line("companion_welcome"), "stop test starts actual companion audio")
	if not await until(func(): return game.controller.pending_events.is_empty(), "active voice state reaches the controller before stop"):
		return
	var request := HTTPRequest.new()
	add_child(request)
	request.request(game.controller.url + "/session/stop?session_id=" + ApiClient.session_id.uri_encode(), game.controller._headers(), HTTPClient.METHOD_POST)
	var response: Array = await request.request_completed
	check(response[1] == 200, "external stop endpoint accepts the session capability")
	if not await until(func(): return GameState.stopped, "remote stop interrupts active voice"):
		return
	if not await until(func(): return game.controller.pending_events.is_empty(), "stop acknowledges the terminal state"):
		return
	check(not game.speech.busy and not game.controller.fatal, "stop cancels speech without protocol failure")
	print("ECHO COMPANION PREVIEW: %d assertions, 0 failures" % assertions)
	get_tree().quit(0)
