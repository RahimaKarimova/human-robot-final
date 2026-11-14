extends Node
var game: Node3D
var assertions: int = 0

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
	if not success:
		print("Speech test state: ", ApiClient.voice_status, " / view ", game.view, " / line ", game.checkpoint.current_id, " / paused ", GameState.paused, " / fatal ", game.controller.fatal)
	check(success, description)
	return success

func key(pressed: bool, keycode: int = KEY_V) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	event.pressed = pressed
	game._input(event)

func _ready() -> void:
	AudioServer.set_bus_mute(0,true)
	get_tree().create_timer(75).timeout.connect(func():
		push_error("FAIL: speech control watchdog timed out")
		get_tree().quit(1)
	)
	GameState.reset()
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	check(ApiClient.microphone_enabled, "voice controls are explicitly enabled")
	check(ApiClient.voice_capture_id.is_empty(), "no capture starts just by launching")
	game._begin()
	game.checkpoint._bypass()
	if not await until(func(): return game.view == "tutorial", "explicit checkpoint bypass reaches tutorial"):
		return
	game.ui.close_modal()
	game.view = "explore"
	GameState.tutorial_done = true
	# Native output cancels asynchronously. Listening is deliberately blocked
	# until the SDK worker acknowledges cancellation and the game reports it.
	if not await until(func(): return ApiClient.external_utterance_id.is_empty() and game.controller.pending_events.is_empty() and not game.speech.busy, "companion releases audio ownership before microphone capture"):
		return
	key(true)
	if not await until(func(): return ApiClient.voice_status == "LISTENING", "V press reaches the separate fixture capture worker"):
		return
	check(not ApiClient.voice_capture_id.is_empty(), "a capture has an explicit capability ID")
	key(false)
	if not await until(func(): return GameState.paused, "actual Vosk recognition and Rasa turn the synthetic pause recording into a game command"):
		return
	if not await until(func(): return ApiClient.voice_capture_id.is_empty(), "result closes the capture state"):
		return
	check(ApiClient.voice_status == "SENT", "UI acknowledges successful routing without showing a transcript")
	game._resume()
	key(true)
	if not await until(func(): return ApiClient.voice_status == "LISTENING", "a second capture can be started explicitly"):
		return
	ApiClient.voice_release(true)
	if not await until(func(): return ApiClient.voice_status == "CANCELLED", "cancelled capture is discarded without recognition"):
		return
	check(not GameState.paused, "cancellation never executes the fixture's pause command")
	# Open a real optional question, then explicitly submit synthetic reply speech.
	game.speech.enabled = false
	game.player.position = game.world.targets[0].global_position
	game._interact()
	if not await until(func(): return game.reader.active, "Library letter opens before reply testing"):
		return
	game.reader._skip()
	game.reader._close()
	if not await until(func(): return game.checkpoint.current_id == "H1" and game.checkpoint.playback_done, "muted H1 has an explicit caption fallback"):
		return
	game.checkpoint._resolve("ACKNOWLEDGED")
	if not await until(func(): return game.checkpoint.current_id == "G1" and game.checkpoint.playback_done, "reply is bound to the real current question"):
		return
	if "--capture-preview" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		var folder := ProjectSettings.globalize_path("res://artifacts/companion-preview")
		DirAccess.make_dir_recursive_absolute(folder)
		check(get_viewport().get_texture().get_image().save_png(folder.path_join("voice-reply-controls.png")) == OK, "voice/reply controls render to a reviewable screenshot")
	key(true,KEY_B)
	if not await until(func(): return ApiClient.voice_status == "LISTENING", "B starts explicit reply capture"):
		return
	key(false,KEY_B)
	if not await until(func(): return game.checkpoint.current_id == "G1_ACK", "recognized reply advances to the shared acknowledgement without storing words"):
		return
	game.checkpoint._resolve("ACKNOWLEDGED")
	if not await until(func(): return game.puzzle_panel.active, "reply completion releases gameplay"):
		return
	key(true)
	if not await until(func(): return ApiClient.voice_status == "LISTENING", "capture can be active before terminal stop"):
		return
	GameState.stop()
	if not await until(func(): return game.controller.pending_events.is_empty(), "stop acknowledgement drains"):
		return
	check(not game.controller.fatal and GameState.stopped, "terminal stop remains valid during capture")
	print("ECHO SPEECH CONTROLS: %d assertions, 0 failures" % assertions)
	get_tree().quit(0)
