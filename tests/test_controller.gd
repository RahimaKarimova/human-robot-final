extends Node
## Actual Godot HTTP transport against the separate loopback controller.
var game: Node3D
var assertions: int = 0
var use_rasa: bool = false

func send_control(control: String) -> void:
	var args := OS.get_cmdline_user_args()
	var config: String = args[args.find("--controller-config") + 1]
	var python := ProjectSettings.globalize_path("res://services/controller/.venv/Scripts/python.exe")
	var entry := ProjectSettings.globalize_path("res://services/controller/send_control.py")
	var output: Array = []
	var result := OS.execute(python, [entry, "--config", config, "--control", control], output)
	if result != 0 or output.is_empty() or str(output[0]).strip_edges() != "applied":
		print("Synthetic control result: ", output)
	check(result == 0 and not output.is_empty() and str(output[0]).strip_edges() == "applied", "synthetic control passes through the real Rasa gateway: " + control)

func check(value: bool, description: String) -> void:
	assertions += 1
	if not value:
		push_error("FAIL: " + description)
		get_tree().quit(1)

func until(predicate: Callable, description: String) -> bool:
	var deadline := Time.get_ticks_msec() + 12000
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	var success: bool = predicate.call()
	check(success, description)
	return success

func _ready() -> void:
	use_rasa = "--test-rasa" in OS.get_cmdline_user_args()
	GameState.reset()
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	game.speech.enabled = false
	check(is_instance_valid(game.controller) and game.controller_error.is_empty(), "external controller configuration loads")
	check(not game.mock_robot.enabled, "external mode disables the in-game mock")
	check(ApiClient.controller_session_id.begins_with("dev-"), "controller owns the configured session ID")
	if "--test-prestart-stop" in OS.get_cmdline_user_args():
		if not await until(func(): return GameState.stopped, "remote stop reaches the title screen before Begin"):
			return
		check(not game.reader.active and not game.puzzle_panel.active, "pre-start stop cannot start narration or puzzles")
		if not await until(func(): return game.controller.pending_events.is_empty(), "pre-start terminal acknowledgement is delivered"):
			return
		check(not game.controller.fatal, "pre-start stop has no protocol error")
		print("ECHO CONTROLLER: %d assertions, 0 failures" % assertions)
		get_tree().quit(0)
		return
	game._begin()
	game.ui.close_modal()
	game.view = "explore"
	GameState.tutorial_done = true
	game.player.position = game.world.targets[0].global_position
	game._interact()
	if not await until(func(): return game.reader.active, "HTTP entry checkpoint resumes into the real Library letter"):
		return
	game.reader._skip()
	game.reader._close()
	if not await until(func(): return game.checkpoint.active and game.checkpoint.current_id == "H1", "narration acknowledgement releases external mock H1"):
		return
	check(game.checkpoint.current_text.begins_with("External mock"), "participant-facing status identifies the external mock")
	var first_text: String = game.checkpoint.current_text
	var cursor: int = game.controller.cursor
	ApiClient.emit_event("MOCK_REPEAT_REQUESTED", {"checkpoint_id": "library_before", "line_id": "H1"})
	if not await until(func(): return game.controller.cursor > cursor, "HTTP repeat delivers another command"):
		return
	check(game.checkpoint.current_text == first_text and game.checkpoint.current_id == "H1", "repeat preserves exact text and line order")
	game._toggle_pause()
	var command := {"command_id": "test-late-replay", "session_id": ApiClient.session_id, "type": "SHOW_DIALOGUE", "checkpoint_id": "library_before", "line_id": "H1", "text": first_text, "question": false}
	ApiClient.receive_command(command)
	check(game.checkpoint.pending_commands.size() == 1 and GameState.paused, "late commands wait behind an explicit player pause")
	game._resume()
	if not await until(func(): return game.checkpoint.pending_commands.is_empty(), "resume safely releases the delayed command"):
		return
	game.checkpoint._resolve("ACKNOWLEDGED")
	if not await until(func(): return game.checkpoint.current_id == "G1", "acknowledgement advances H1 to G1"):
		return
	game._toggle_pause()
	check(GameState.paused and game.checkpoint.active, "pause preserves the external checkpoint")
	game._resume()
	if use_rasa:
		await get_tree().process_frame
		await get_tree().process_frame
		if not await until(func(): return game.controller.pending_events.is_empty(), "context is synchronized before real Rasa requests"):
			return
		var before_repeat: int = game.controller.cursor
		send_control("repeat")
		if not await until(func(): return game.controller.cursor > before_repeat and not game.checkpoint.resolving, "Rasa repeat reaches the active question"):
			return
		check(game.checkpoint.current_id == "G1", "Rasa repeat does not move to another question")
		send_control("pause")
		if not await until(func(): return GameState.paused and game.controller.pending_events.is_empty(), "Rasa pause reaches Godot and synchronizes pause identity"):
			return
		send_control("resume")
		if not await until(func(): return not GameState.paused, "Rasa resume explicitly releases that pause"):
			return
		await get_tree().process_frame
		await get_tree().process_frame
		if not await until(func(): return game.controller.pending_events.is_empty(), "resume context is synchronized before skip"):
			return
		send_control("skip")
	else:
		game.checkpoint._resolve("SKIPPED")
	if not await until(func(): return game.puzzle_panel.active, "skipping external G1 unlocks the physical bookshelf"):
		return
	if use_rasa:
		await get_tree().process_frame
		await get_tree().process_frame
		if not await until(func(): return game.controller.pending_events.is_empty(), "puzzle context is synchronized before hint"):
			return
		var before_hint: int = GameState.hints.get("library", 0)
		send_control("hint")
		if not await until(func(): return GameState.hints.get("library", 0) > before_hint, "Rasa hint reaches the game's unchanged hint ladder"):
			return
		check(not GameState.fragments.has("library"), "Rasa hint never awards the emerald")
	check(game.puzzle_panel.focus_by_id("golden_feather"), "real Library book is selectable")
	game._interact()
	if not await until(func(): return game.view == "reward", "solving the real book puzzle survives HTTP after-checkpoint handoff"):
		return
	check(GameState.fragments.has("library"), "external question skip never blocks the emerald")
	check(game.mock_robot.seen_events.is_empty(), "no silent offline mock handled network-mode events")
	if not await until(func(): return game.controller.pending_events.is_empty(), "outbound events are acknowledged and drained"):
		return
	check(not game.controller.fatal, "valid HTTP protocol does not enter an error state")
	game._continue_reward()
	game.player.position = game.world.targets[1].global_position
	var actual_url: String = game.controller.url
	game.controller.url = "http://127.0.0.1:1"
	game._interact()
	if not await until(func(): return ApiClient.status.begins_with("CONTROLLER DISCONNECTED"), "connection failure is explicitly displayed"):
		return
	check(game.checkpoint.active, "unavailable controller keeps a recoverable checkpoint")
	game.checkpoint._bypass()
	if not await until(func(): return game.reader.active, "explicit Resume remains usable without the controller"):
		return
	check(not game.mock_robot.enabled and not GameState.fragments.has("workshop"), "disconnect recovery neither switches to mock nor grants a reward")
	game.controller.url = actual_url
	game.controller.post_delay = 0
	game.controller.poll_delay = 0
	if not await until(func(): return game.controller.pending_events.is_empty(), "reconnection delivers queued events without lost progress"):
		return
	if use_rasa:
		send_control("stop")
	else:
		var request := HTTPRequest.new()
		add_child(request)
		request.timeout = 2
		request.request(actual_url + "/session/stop?session_id=" + ApiClient.session_id.uri_encode(), game.controller._headers(), HTTPClient.METHOD_POST)
		var response: Array = await request.request_completed
		check(response[1] == 200, "researcher stop endpoint accepts the session capability")
	if not await until(func(): return GameState.stopped, "external SESSION_STOP stops the game during a letter"):
		return
	check(game.view == "stopped" and not game.reader.active, "remote stop locks the game and closes reading")
	if not await until(func(): return game.controller.pending_events.is_empty(), "terminal stop acknowledgement reaches the controller"):
		return
	check(not game.controller.fatal, "stop acknowledgement does not create a protocol error")
	print("ECHO CONTROLLER: %d assertions, 0 failures" % assertions)
	get_tree().quit(0)
