extends Node
var game: Node3D
var assertions: int = 0
var lines: Array[String] = []
var hints: Array[String] = []
var output_failures: int = 0
var native_completions: int = 0
var natural_answers: Array[String] = []

func check(value: bool, description: String) -> void:
	assertions += 1
	if not value:
		push_error("FAIL: " + description)
		get_tree().quit(1)

func until(predicate: Callable, description: String) -> bool:
	var deadline := Time.get_ticks_msec() + (65000 if ApiClient.companion_output in ["reachy_mujoco", "reachy_control_simulator"] else 35000)
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		if not ApiClient.conversation_enabled and game.checkpoint.active and game.checkpoint.preview_line and game.checkpoint.playback_done and not game.checkpoint.resolving:
			game.checkpoint._resolve("SKIPPED" if game.checkpoint.question else "ACKNOWLEDGED")
		await get_tree().process_frame
	var success: bool = predicate.call()
	if not success:
		print("Campaign diagnostic: view=", game.view, " line=", game.checkpoint.current_id, " voice=", ApiClient.voice_status, " paused=", GameState.paused, " output=", not ApiClient.external_utterance_id.is_empty(), " fatal=", game.controller.fatal)
	check(success, description)
	return success

func use_item(id: String) -> void:
	check(game.puzzle_panel.focus_by_id(id), "physical item is selectable: " + id)
	var point: Vector3 = game.puzzle_panel.focus.global_position
	game.player.position = Vector3(point.x, 0.2, point.z + 1)
	game._interact()
	await get_tree().process_frame

func _ready() -> void:
	AudioServer.set_bus_mute(0, true)
	get_tree().create_timer(450 if "--controller-config" in OS.get_cmdline_user_args() else 220).timeout.connect(func():
		push_error("FAIL: full companion watchdog timed out")
		get_tree().quit(1)
	)
	GameState.reset()
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	game.speech.playback.pitch_scale = 4.0
	EventBus.command_received.connect(func(command: Dictionary):
		if command.type == "SHOW_DIALOGUE":
			lines.append(command.line_id)
			print("Campaign line: ", command.line_id)
		if command.type == "COMPANION_CUE": hints.append(command.stage_id)
		if command.type == "COMPANION_OUTPUT_RESULT":
			if command.completion == "technical_failure": output_failures += 1
			if command.completion == "simulated_completed": native_completions += 1
	)
	ApiClient.event_emitted.connect(func(event: Dictionary):
		if event.event_type == "CHECKPOINT_ITEM_COMPLETED" and event.payload.status == "ACKNOWLEDGED" and event.payload.line_id in ["G1", "G2", "G3", "P1", "P2", "P3"]:
			natural_answers.append(event.payload.line_id)
	)
	game._begin()
	if not await until(func(): return game.view == "tutorial", "welcome finishes without a name question"):
		return
	game.ui.close_modal()
	game.view = "explore"
	GameState.tutorial_done = true
	for stage_index in range(4):
		var stage: Dictionary = Content.stage(stage_index)
		game.player.position = game.world.targets[stage_index].global_position
		game._interact()
		if not await until(func(): return game.reader.active, "entry conversation releases " + stage.name + " letter"):
			return
		game.reader._skip()
		game.reader._close()
		if not await until(func(): return game.puzzle_panel.active, "questions and acknowledgements release " + stage.name + " puzzle"):
			return
		game._hint()
		if not await until(func(): return hints.has(stage.id), "shared voiced hint is connected: " + stage.id):
			return
		if not await until(func(): return game.companion_cues.pending.is_empty() and game.companion_cues.active.is_empty() and not game.speech.busy and ApiClient.external_utterance_id.is_empty(), "hint finishes without overlapping puzzle feedback"):
			return
		match stage.id:
			"library": await use_item("golden_feather")
			"workshop":
				for item in ["gear_RED", "slot_0", "gear_BLUE", "slot_1", "gear_YELLOW", "slot_2"]:
					await use_item(item)
			"market":
				await use_item("parcel")
				game.player.position = Vector3(21, 0.2, -18)
				await get_tree().process_frame
				game.player.position = Vector3(23, 0.2, -18)
				await get_tree().process_frame
				check(game.puzzle_panel.crossed_bridge, "parcel route crosses the actual bridge")
				await use_item("bridge_river")
			"temple":
				for item in ["SUN", "WAVE", "STAR"]:
					await use_item(item)
		if not await until(func(): return game.view == "reward", "post-solve joke / celebration completes: " + stage.id):
			return
		check(GameState.fragments.has(stage.id), "earned gem survives all question skips: " + stage.id)
		game._continue_reward()
		await get_tree().process_frame
	check(GameState.stage_index == 4 and GameState.fragments.size() == 4, "all four chapters completed")
	game.player.position = game.world.cave.door_point.global_position + Vector3(0, 0, 1.5)
	for gem in Content.gems:
		game._interact()
		check(GameState.socketed_gems.has(gem.id), "gem fits the sealed cave door: " + gem.id)
	if not await until(func(): return GameState.cave_open, "all gems open the cave door"):
		return
	game.player.position = game.world.cave.to_global(Vector3(0, 0.2, -2))
	if not await until(func(): return GameState.cave_entered, "entering the cave reveals the hidden chamber"):
		return
	game.player.position = game.world.cave.chest_point.global_position + Vector3(0, 0, 1.8)
	game._interact()
	if not await until(func(): return GameState.checkpoints.has("cave_ending") and game.view == "finale", "shared companion ending releases the final treasure card"):
		return
	for key in ["H1", "H2", "H3", "H4", "G1", "G2", "G3", "P1", "P2", "P3", "LIBRARY_SUCCESS", "WORKSHOP_SUCCESS", "MARKET_SUCCESS", "TEMPLE_SUCCESS", "ENDING"]:
		var expected_count := 0 if key.begins_with("H") and "--test-jokes-off" in OS.get_cmdline_user_args() else 1
		check(lines.count(key) == expected_count, "mode delivers the expected number of lines: " + key)
	if not await until(func(): return game.controller.pending_events.is_empty(), "campaign protocol events drain"):
		return
	check(not game.controller.fatal and GameState.completed, "complete companion campaign has no protocol failure")
	if ApiClient.companion_output in ["reachy_mujoco", "reachy_control_simulator"]:
		check(output_failures == 0, "official SDK run has no caption-only output failure fallbacks")
		check(native_completions == lines.size() + hints.size(), "every official SDK delivery has a real end-of-stream/motion completion")
	if ApiClient.conversation_enabled:
		check(natural_answers.size() == 6, "all six questions answered through VAD/STT/Rasa without V/B or reply buttons")
		check(not ApiClient.voice_automatic and ApiClient.voice_capture_id.is_empty(), "ending leaves the microphone off")
	GameState.stop()
	await until(func(): return game.controller.pending_events.is_empty(), "terminal acknowledgement drains")
	print("ECHO FULL COMPANION: %d assertions, 0 failures" % assertions)
	get_tree().quit(0)
