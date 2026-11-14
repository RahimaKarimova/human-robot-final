extends Node
var game: Node3D
var assertions: int = 0
var lines: Array[String] = []
var outcomes: Array[String] = []

func check(value: bool, description: String) -> void:
	assertions += 1
	if not value:
		push_error("FAIL: " + description)
		get_tree().quit(1)

func until(predicate: Callable, description: String) -> bool:
	var deadline := Time.get_ticks_msec() + 15000
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	var success: bool = predicate.call()
	check(success, description)
	return success

func _ready() -> void:
	AudioServer.set_bus_mute(0, true)
	get_tree().create_timer(200).timeout.connect(func():
		push_error("FAIL: bridge watchdog timed out")
		get_tree().quit(1)
	)
	GameState.reset()
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	EventBus.command_received.connect(func(command: Dictionary):
		if command.type == "SHOW_DIALOGUE": lines.append(command.line_id)
		if command.type == "COMPANION_OUTPUT_RESULT": outcomes.append(command.completion)
	)
	check(ApiClient.companion_output in ["bridge_simulator", "reachy_mujoco", "reachy_control_simulator"], "explicit output route is a simulator")
	check(not game.mock_robot.enabled, "offline mock is disabled")
	game._begin()
	if not await until(func(): return game.checkpoint.current_id == "WELCOME", "welcome reaches the external bridge"):
		return
	check(not game.speech.busy, "robot-routed dialogue is not also played through laptop speech")
	check(not game.checkpoint.playback_done, "UI waits for external completion")
	game._toggle_pause()
	await get_tree().create_timer(0.3).timeout
	check(game.checkpoint.current_id == "WELCOME", "pause cannot advance output")
	game._resume()
	if not await until(func(): return game.view == "tutorial", "simulated welcome completion releases tutorial without a name question"):
		return
	check(outcomes.has("simulated_completed") and not outcomes.has("audio_completed"), "simulation cannot masquerade as physical audio")
	check(not lines.has("NAME") and not lines.has("NAME_ACK"), "opening does not request a name")
	game.ui.close_modal()
	game.view = "explore"
	GameState.tutorial_done = true
	game.player.position = game.world.targets[0].global_position
	game._interact()
	if not await until(func(): return game.reader.active, "Library letter remains readable"):
		return
	check(game.speech.active_line == "L1", "narrator still plays through the game")
	game.reader._skip()
	game.reader._close()
	if not await until(func(): return game.checkpoint.current_id == "G1" and not game.checkpoint.playback_done, "H1 completes externally before G1 starts"):
		return
	var expected_jokes := 0 if "--test-jokes-off" in OS.get_cmdline_user_args() else 1
	check(lines.count("H1") == expected_jokes and not game.speech.busy, "selected joke mode has no duplicated laptop audio")
	game.checkpoint._repeat_preview()
	check(game.checkpoint.after_speech_action == "repeat" and not game.checkpoint.playback_done, "repeat clicked during speech waits for the original question to finish")
	if not await until(func(): return lines.count("G1") == 2 and game.checkpoint.playback_done, "question repeat works through the bridge"):
		return
	check(lines.count("H1") == expected_jokes, "repeat does not add another joke")
	game.checkpoint._resolve("SKIPPED")
	if not await until(func(): return game.puzzle_panel.active, "skip and acknowledgement release the real puzzle"):
		return
	game._hint()
	if not await until(func(): return not ApiClient.external_utterance_id.is_empty(), "hint requests an external delivery"):
		return
	check(not game.speech.busy, "hint is not duplicated on laptop")
	game._open_letter()
	check(game.pending_letter_handoff and not game.reader.active, "narrator waits for the complete external hint")
	if not await until(func(): return game.reader.active, "natural hint completion releases narrator ownership"):
		return
	check(not outcomes.has("cancelled"), "opening a letter never cancels Reachy's hint")
	game.reader._skip()
	game.reader._close()
	game._hint()
	if not await until(func(): return not ApiClient.external_utterance_id.is_empty(), "second hint starts before connection failure"):
		return
	var actual_url: String = game.controller.url
	game.controller.url = "http://127.0.0.1:1"
	game._open_letter()
	if not await until(func(): return game.reader.active, "local handoff remains recoverable when controller connection is lost"):
		return
	check(ApiClient.external_utterance_id.is_empty(), "lost-connection cancellation cannot hold narration indefinitely")
	game.controller.url = actual_url
	game.controller.post_delay = 0
	game.controller.poll_delay = 0
	if not await until(func(): return game.controller.pending_events.is_empty(), "reconnection drains cancellation observations without replaying a job"):
		return
	game.reader._skip()
	game.reader._close()
	check(game.puzzle_panel.focus_by_id("golden_feather"), "physical golden-feather book remains selectable")
	game._interact()
	if not await until(func(): return game.view == "reward", "solved bookshelf and external celebration reveal the reward"):
		return
	check(GameState.fragments.has("library"), "dialogue outcomes do not block the earned emerald")
	if not await until(func(): return game.controller.pending_events.is_empty(), "valid bridge events drain without protocol errors"):
		return
	check(not game.controller.fatal, "bridge protocol remains valid")
	GameState.stop()
	if not await until(func(): return game.controller.pending_events.is_empty(), "terminal stop acknowledgement drains"):
		return
	check(not game.speech.busy and not game.controller.fatal, "stop closes output without a protocol failure")
	if ApiClient.companion_output in ["reachy_mujoco", "reachy_control_simulator"]:
		check(not outcomes.has("technical_failure"), "official SDK control tests have no output failure fallback")
	print("ECHO ROBOT BRIDGE: %d assertions, 0 failures" % assertions)
	get_tree().quit(0)
