extends Node
## Executable tests against the actual game scene and Godot-side adapter.
var failures: int = 0
var assertions: int = 0
var events: Array[Dictionary] = []
var game: Node3D

func capture(name: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var folder := "res://artifacts/screenshots"
	if "--large" in OS.get_cmdline_user_args():
		folder += "-1920"
	DirAccess.make_dir_recursive_absolute(folder)
	get_viewport().get_texture().get_image().save_png(folder + "/" + name + ".png")

func check(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures += 1
		push_error("FAIL: " + message)

func settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

func click(label: String, parent: Node = null) -> bool:
	var search: Node = game.ui.root if parent == null else parent
	for item in search.get_children():
		if item is Button and item.is_visible_in_tree() and item.text.strip_edges() == label and not item.disabled:
			item.pressed.emit()
			return true
		if click(label, item):
			return true
	return false

func use_item(id: String) -> void:
	check(game.puzzle_panel.focus_by_id(id), "3D object can be selected: " + id)
	game._interact()
	await settle()

func delivery_route() -> void:
	check(game.ui.inspection_exit.is_visible_in_tree(), "overhead map has a visible return-to-walking button")
	check(game.ui.task_action.text == "Pick up parcel  [E]", "Market starts with a clearly labelled pickup action")
	game.ui.task_action.pressed.emit()
	await settle()
	check(game.puzzle_panel.carrying and is_instance_valid(game.puzzle_panel.parcel), "parcel becomes a visible carried object")
	check(not GameState.inspecting, "parcel pickup automatically returns to the walking camera")
	check(game.ui.task_title.text == "DELIVERY · STEP 2 OF 3", "delivery HUD explicitly advances to walking across the bridge")
	check(game.puzzle_panel.destination_marker.visible, "next destination is marked visibly in the world")
	game._toggle_pause()
	check(click("Return to quest path"), "delivery has an explicit recovery route from pause")
	await settle()
	check(game.puzzle_panel.carrying and not game.puzzle_panel.crossed_bridge and GameState.fragments.size() == 2, "delivery recovery keeps the parcel and earned gems without faking a bridge crossing")
	await capture("04d-market-parcel-picked-up")
	game.puzzle_panel.toggle_inspection()
	await settle()
	var walk_key := InputEventAction.new()
	walk_key.action = "move_forward"
	walk_key.pressed = true
	game.puzzle_panel._unhandled_input(walk_key)
	check(not GameState.inspecting, "WASD automatically exits the Market overview so the player cannot become stuck")
	await walk_to(Vector3(9, 0, -15))
	await walk_to(Vector3(9, 0, -22))
	await walk_to(Vector3(10, 0, -23.35))
	await use_item("forest")
	check(game.puzzle_panel.carrying and not GameState.fragments.has("market"), "wrong delivery preserves the parcel and quest")
	await walk_to(Vector3(9, 0, -22))
	await walk_to(Vector3(9, 0, -15))
	await walk_to(Vector3(20, 0, -15))
	await walk_to(Vector3(25, 0, -15))
	await walk_to(Vector3(25, 0, -21.35))
	await use_item("bridge_river")
	check(not game.puzzle_panel.crossed_bridge and not GameState.fragments.has("market"), "riverside delivery requires actually crossing the wooden bridge")
	check(game.puzzle_panel.returning_to_bridge, "walking around the river activates bridge recovery guidance")
	await walk_to(game.puzzle_panel.waypoint())
	check(game.puzzle_panel.waypoint().x < 22, "wrong-bank guidance leads back across the bridge to its market side")
	await walk_to(game.puzzle_panel.waypoint())
	check(not game.puzzle_panel.returning_to_bridge, "reaching the market bank restores the outward bridge route")
	await walk_to(game.puzzle_panel.waypoint())
	check(game.puzzle_panel.crossed_bridge, "real movement across the bridge satisfies the route checkpoint")
	check(game.ui.task_title.text == "DELIVERY · STEP 3 OF 3", "bridge crossing advances the explicit delivery step")
	await capture("04e-market-bridge-crossed")
	await walk_to(Vector3(25, 0, -21.35))
	check(game.ui.task_action.text == "Deliver parcel  [E]" and not game.ui.task_action.disabled, "delivery becomes an obvious enabled button beside the correct box")
	await capture("04f-market-deliver-button")
	game.ui.task_action.pressed.emit()
	await settle()

func count_event(kind: String) -> int:
	var count := 0
	for event in events:
		if event.event_type == kind:
			count += 1
	return count

func walk_to(destination: Vector3) -> void:
	# Exercise the real movement/collision path. Accelerate simulation, not player speed.
	Engine.time_scale = 5.0
	var steps := 0
	Input.action_press("move_forward")
	while Vector2(game.player.position.x - destination.x, game.player.position.z - destination.z).length() > 0.65 and steps < 600:
		var direction: Vector3 = destination - game.player.position
		game.player.yaw = atan2(-direction.x, -direction.z)
		await get_tree().physics_frame
		steps += 1
	Input.action_release("move_forward")
	Engine.time_scale = 1.0
	game.player.yaw = 0.0
	await settle()
	check(steps < 600, "signposted route is walkable with actual collisions")
	check(game.player.position.y > -0.1, "route stays on solid island ground")

func follow_guidance() -> void:
	game.navigation.reset()
	var destination: Vector3 = game.world.targets[GameState.stage_index].global_position
	var turns := 0
	while game.player.position.distance_to(destination) > 0.8 and turns < 20:
		await settle()
		var next: Vector3 = game.navigation.next_point(game.player.position, GameState.stage_index)
		check(game.world.guidance_position.distance_to(next) < 0.1, "visible quest marker follows the authored walking route")
		if game.player.position.distance_to(destination) > 6.5:
			check(game.ui.prompt.disabled, "intermediate path markers never advertise an out-of-range NPC interaction")
		await walk_to(next)
		turns += 1
	check(turns < 20, "following visible guidance reaches the next chapter without a navigation loop")

func finish_checkpoint(skip: bool) -> void:
	var guard := 0
	while game.checkpoint.active and guard < 12:
		await settle()
		if not game.checkpoint.active:
			break
		var before: String = game.checkpoint.current_text
		if click("Repeat"):
			check(game.checkpoint.current_text == before, "repeat preserves mock message")
		if skip and click("Skip"):
			pass
		else:
			click("Mock acknowledgement")
		guard += 1
		await settle()
	check(guard < 12, "checkpoint always resumes")

func fresh_library() -> void:
	game.queue_free()
	await settle()
	GameState.reset()
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await settle()
	game.speech.enabled = false
	click("Begin the adventure  →")
	click("Step onto the island")
	game._interact()
	click("Let's explore")
	game.player.position = game.world.targets[0].global_position
	game._interact()
	await settle()

func safety_paths() -> void:
	for outcome in ["ACKNOWLEDGED", "NO_RECALL", "TECHNICAL_FAILURE", "BYPASS"]:
		await fresh_library()
		check(game.reader.active, "fresh library letter opens")
		game.reader._skip()
		game.reader._close()
		await settle()
		var limit := 0
		while game.checkpoint.active and limit < 5:
			if outcome == "BYPASS":
				click("Resume game")
			else:
				game.checkpoint._resolve(outcome)
				game.checkpoint._resolve(outcome)
			await settle()
			limit += 1
		check(limit < 5 and game.puzzle_panel.active, outcome + " unblocks the puzzle, even with double clicks")
		check(GameState.fragments.is_empty(), "mock controls never grant a fragment")
	for context in ["letter", "checkpoint", "puzzle"]:
		await fresh_library()
		if context != "letter":
			game.reader._skip()
			game.reader._close()
			await settle()
		if context == "puzzle":
			await finish_checkpoint(true)
			await settle()
		check(game.ui.stop_button.is_visible_in_tree(), "stop remains visible during " + context)
		game.ui.stop_button.pressed.emit()
		check(GameState.stopped and game.view == "stopped", "immediate stop during " + context)
		check(not game.reader.active and not game.checkpoint.active and not game.puzzle_panel.active, "stop cancels pending modal actions")
		game._interact()
		game._checkpoint_done()
		await settle()
		check(game.view == "stopped", "late inputs cannot continue after stop")

func _ready() -> void:
	await settle()
	ApiClient.event_emitted.connect(func(event: Dictionary): events.append(event))
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await settle()
	game.speech.enabled = false
	await capture("01-title")
	check(game.world.targets.size() == 5, "five reachable destinations")
	check(not QuestManager.finish(), "cannot open treasure without fragments")
	check(not QuestManager.insert_cave_gem("emerald"), "missing gems cannot be inserted before their quests")
	check(not game.world.cave.treasure_contents.visible and not game.world.cave.barrier_shape.disabled, "treasure starts hidden inside the physically sealed cave")
	check(click("Begin the adventure  →"), "begin button exists")
	check(click("Step onto the island"), "tutorial can close")
	game._interact()
	check(GameState.tutorial_done, "dock interaction completes tutorial")
	click("Let's explore")
	await capture("02-island")
	var start: Vector3 = game.player.position
	Input.action_press("move_forward")
	for physics_step in range(12):
		await get_tree().physics_frame
	Input.action_release("move_forward")
	check(game.player.position.z < start.z - 0.2, "WASD moves actual CharacterBody3D")
	check(game.player.position.y > -0.1, "player stands on island collision")
	var walk_distance: float = start.z - game.player.position.z
	game.player.position = start
	Input.action_press("sprint")
	Input.action_press("move_forward")
	for physics_step in range(12):
		await get_tree().physics_frame
	Input.action_release("move_forward")
	Input.action_release("sprint")
	check(start.z - game.player.position.z > walk_distance * 1.3, "Shift sprint moves faster than walking")
	game.player.change_zoom(-100)
	check(is_equal_approx(game.player.zoom_target, Explorer.MIN_ZOOM), "zoom clamps at close camera limit")
	game.player.change_zoom(200)
	check(is_equal_approx(game.player.zoom_target, Explorer.MAX_ZOOM), "zoom clamps at far camera limit")
	game.player.zoom_target = 6.5
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	game.player._unhandled_input(wheel)
	check(game.player.zoom_target < 6.5, "mouse wheel zoom works during exploration")
	var zoom_before: float = game.player.zoom_target
	GameState.ui_locked = true
	game.player._unhandled_input(wheel)
	check(is_equal_approx(zoom_before, game.player.zoom_target), "UI scrolling never changes world camera zoom")
	GameState.ui_locked = false
	game.player.zoom_target = 6.5
	check(game.world.npcs.size() == 4, "all four characters have articulated models")
	check(game.world.scenery.birds.size() == 12, "island has an animated flock")
	var bird: IslandBird = game.world.scenery.birds[0]
	var bird_start: Vector3 = bird.position
	await get_tree().create_timer(0.1).timeout
	check(bird.position.distance_to(bird_start) > 0.01, "birds fly through the scene")
	game.player.position = game.world.targets[3].global_position
	game._interact()
	check(not game.reader.active and not game.checkpoint.active, "future zone cannot start early")
	game.player.position = start
	for index in range(4):
		var data: Dictionary = Content.stage(index)
		check(GameState.stage_index == index, "chapters remain in order")
		check(not QuestManager.award_fragment("cave"), "out-of-order reward rejected")
		check(not QuestManager.advance(), "unsolved chapter cannot advance")
		await follow_guidance()
		check(game.world.npcs[index].greet_count > 0, "approaching a character triggers a greeting wave")
		await capture("02b-greeting-" + data.id)
		game._interact()
		await settle()
		await finish_checkpoint(true)
		await settle()
		check(game.reader.active, "NPC opens letter after entry checkpoint")
		await capture("03-letter-" + data.id)
		check(game.reader.continue_button.disabled, "unread letter requires narration or caption acknowledgement")
		game._interact()
		check(game.reader.active, "repeated interact cannot replace open letter")
		game.reader._skip()
		check(not game.reader.continue_button.disabled, "explicit narration skip unlocks Continue")
		game.reader._close()
		await settle()
		await finish_checkpoint(true)
		await settle()
		check(game.puzzle_panel.active, "skipping mock questions still unlocks puzzle")
		check(not game.ui.veil.visible and not GameState.ui_locked, "puzzle stays in the 3D world, with player movement available")
		check(game.ui.inspect_button.is_visible_in_tree(), "every physical puzzle has a visible Inspect button")
		game.ui.inspect_button.pressed.emit()
		await get_tree().create_timer(0.5).timeout
		check(GameState.inspecting, "close inspection uses an actual 3D camera")
		var walk_key := InputEventAction.new()
		walk_key.action = "move_left"
		walk_key.pressed = true
		game.puzzle_panel._unhandled_input(walk_key)
		check(not GameState.inspecting, "movement exits close-up inspection in every chapter")
		await settle()
		game.ui.inspect_button.pressed.emit()
		await get_tree().create_timer(0.5).timeout
		check(game.ui.inspection_panel.size.y < 120, "return-to-walking toolbar stays compact and does not cover the puzzle")
		if index == 0:
			check(game.puzzle_panel.items.library.size() == 6, "six real selectable books live on the shelves")
			var inspect_position: Vector3 = game.player.position
			Input.action_press("move_forward")
			await get_tree().create_timer(0.1).timeout
			Input.action_release("move_forward")
			check(game.player.position.distance_to(inspect_position) < 0.01, "inspection holds the explorer safely while the camera moves close")
		await capture("04-puzzle-" + data.id)
		var checkpoint_count := count_event("CONVERSATION_CHECKPOINT_REQUESTED")
		game.puzzle_panel._attempt("wrong")
		check(GameState.fragments.size() == index, "incorrect answer gives no fragment")
		for level in range(5):
			game.puzzle_panel.hint()
			check(game.puzzle_panel.hint_label.text == data.hints[mini(level, 2)], "three fixed hints saturate")
		await settle()
		var task_rect: Rect2 = game.ui.task_panel.get_global_rect()
		check(task_rect.end.y <= get_viewport().get_visible_rect().size.y - 24, "3D task and hint remain on screen")
		await capture("04b-hint-" + data.id)
		check(game.ui.task_dismiss.is_visible_in_tree(), "hints have a visible dismiss control")
		game.ui.task_dismiss.pressed.emit()
		await settle()
		check(not game.puzzle_panel.hint_label.visible, "dismiss hides the hint without abandoning the puzzle")
		game._toggle_pause()
		check(GameState.ui_locked and game.ui.pause_veil.visible, "pause locks gameplay")
		game._resume()
		check(not GameState.ui_locked and GameState.inspecting, "resume preserves the 3D inspection camera without a modal")
		if index == 3:
			for pillar in game.puzzle_panel.items.temple:
				var screen: Vector2 = game.puzzle_panel.inspection.unproject_position(pillar.global_position)
				check(game.puzzle_panel._pick(screen) == pillar, "large temple pillars are reachable by real camera rays")
			await use_item("STAR")
			check(game.puzzle_panel.puzzle.sequence.is_empty(), "wrong temple symbol resets only local sequence")
			for symbol in ["SUN", "WAVE", "STAR"]:
				await use_item(symbol)
		elif index == 1:
			for loose in game.puzzle_panel.gear_tray.values():
				var screen: Vector2 = game.puzzle_panel.inspection.unproject_position(loose.global_position)
				check(get_viewport().get_visible_rect().has_point(screen), "inspection frames each loose gear inside the screen")
				check(not game.ui.task_panel.get_global_rect().has_point(screen), "inspection controls leave each gear uncovered")
				check(game.puzzle_panel._pick(screen) == loose, "loose tray gears can be selected with real camera rays")
			check(game.ui.task_action.visible and game.ui.task_action.text == "Check gear order", "clock has an obvious on-screen check button")
			game.ui.task_action.pressed.emit()
			await settle()
			check(not GameState.fragments.has("workshop"), "incorrect physical gear order gives gentle retry")
			await use_item("gear_YELLOW")
			check(game.puzzle_panel.held_gear == "YELLOW", "loose gear can be picked up from the tray")
			game._toggle_pause()
			check(click("Return to quest path"), "pause offers recovery to the current quest path")
			await settle()
			check(not GameState.paused and not GameState.inspecting and game.puzzle_panel.held_gear == "YELLOW", "path recovery preserves a held gear and returns to walking")
			check(not GameState.fragments.has("workshop"), "navigation recovery never grants a puzzle reward")
			game.ui.inspect_button.pressed.emit()
			await get_tree().create_timer(0.5).timeout
			await use_item("slot_0")
			await use_item("gear_RED")
			await use_item("slot_0")
			check(game.puzzle_panel.held_gear == "YELLOW" and game.puzzle_panel.slots[0] == "RED", "placing on an occupied socket swaps the real gears without losing either")
			await use_item("slot_2")
			await use_item("gear_BLUE")
			await use_item("slot_1")
			check(game.puzzle_panel.clock_running and GameState.fragments.has("workshop"), "correct gear order succeeds automatically without finding a hidden control")
		elif index == 0:
			await use_item("leaf")
			check(not GameState.fragments.has("library"), "wrong physical book preserves the search")
			var book: WorldPuzzleItem = game.puzzle_panel.items.library[5]
			var screen: Vector2 = game.puzzle_panel.inspection.unproject_position(book.global_position)
			check(game.puzzle_panel._pick(screen) == book, "camera ray reaches the real golden-feather book collider")
			var click_event := InputEventMouseButton.new()
			click_event.position = screen
			click_event.button_index = MOUSE_BUTTON_LEFT
			click_event.pressed = true
			game.puzzle_panel._unhandled_input(click_event)
		else:
			await delivery_route()
		await settle()
		await finish_checkpoint(true)
		await settle()
		check(GameState.fragments.size() == index + 1, "correct puzzle yields exactly one fragment")
		check(not QuestManager.award_fragment(data.id), "duplicate fragment rejected")
		check(game.view == "reward", "reward panel appears after companion checkpoint")
		check(game.world.npcs[index].celebration_count == 1, "each character celebrates the solved puzzle once")
		if index == 3:
			await get_tree().create_timer(1.1).timeout
			check(game.puzzle_panel.altar_open == 1.0 and game.puzzle_panel.altar_lids[0].position.x < -2, "correct pillar sequence slides the stone altar open")
		elif index == 1:
			await get_tree().create_timer(1.1).timeout
			check(game.puzzle_panel.clock_drawer.position.z > 0, "repaired clock opens its physical reward drawer")
		check(is_instance_valid(game.puzzle_panel.gift) and game.puzzle_panel.gift.fragment == index + 1, "each solved puzzle reveals its fragment in a physical 3D present")
		check(game.puzzle_panel.gift.gem_id == Content.gem_for_stage(index).id, "each present reveals its own named faceted gemstone")
		check(not game.ui.veil.visible, "world reward does not interrupt with a full-screen panel")
		if "--capture" in OS.get_cmdline_user_args():
			await get_tree().create_timer(1.5).timeout
			await capture("04c-present-" + data.id)
		check(count_event("CONVERSATION_CHECKPOINT_REQUESTED") == checkpoint_count + 1, "one post-puzzle checkpoint")
		check(click("Continue to " + Content.stage(index + 1).name + "  →"), "next chapter control")
		await settle()
		# Replay a visited letter through the real journal without re-asking checkpoints.
		var before_replay := count_event("CONVERSATION_CHECKPOINT_REQUESTED")
		game._journal()
		check(click(data.npc + "'s letter · " + data.name), "journal recalls discovered letters")
		game.reader._skip()
		game.reader._close()
		await settle()
		check(count_event("CONVERSATION_CHECKPOINT_REQUESTED") == before_replay, "replay never repeats mock checkpoints")
	check(GameState.fragments.size() == 4, "full map assembled with every mock question skipped")
	check(not game.world.cave.treasure_contents.visible, "treasure remains hidden after collecting all four gems")
	check(not QuestManager.finish(), "four gems alone cannot bypass the sealed cave")
	check(not QuestManager.insert_cave_gem("diamond"), "unknown gemstones cannot unlock the seal")
	await follow_guidance()
	await capture("05-cave-sealed")
	game.player.yaw = 0
	Input.action_press("move_forward")
	await get_tree().create_timer(0.65).timeout
	Input.action_release("move_forward")
	check(game.player.position.z > -31.6 and not GameState.cave_entered, "solid sealed doorway blocks walking into the cave")
	for gem in Content.gems:
		game._interact()
		check(GameState.socketed_gems.has(gem.id), "interaction places the next matching gemstone")
		check(not QuestManager.insert_cave_gem(gem.id), "duplicate socket insertion is rejected")
	check(not game.world.cave.treasure_contents.visible, "treasure is hidden while the sealed door opens")
	await get_tree().create_timer(1.7).timeout
	check(GameState.cave_open and game.world.cave.barrier_shape.disabled, "all four jewels open the physical cave door")
	check(not GameState.cave_entered and not game.world.cave.treasure_contents.visible, "opening the door does not reveal the chest from outside")
	check(not QuestManager.finish(), "player must enter the unlocked cave before finishing")
	await capture("05-cave-open")
	await walk_to(game.world.cave.to_global(Vector3(0, 0, -2)))
	check(GameState.cave_entered and game.world.cave.treasure_contents.visible, "walking through the unlocked doorway reveals the hidden chamber")
	await walk_to(game.world.cave.chest_point.global_position + Vector3(0, 0, 1.8))
	await capture("05-inside-cave")
	game._interact()
	await get_tree().create_timer(1.8).timeout
	check(GameState.completed, "treasure finale completes")
	await capture("05-treasure")
	check(count_event("GAME_COMPLETED") == 1, "completion emitted once")
	check(not QuestManager.finish(), "duplicate finale is ignored")
	var cmd := {"command_id": "test-pause", "session_id": ApiClient.session_id, "type": "SHOW_OBJECTIVE", "text": "Test objective"}
	check(ApiClient.receive_command(cmd), "valid command accepted")
	check(not ApiClient.receive_command(cmd), "duplicate command ignored")
	cmd.command_id = "wrong-session"
	cmd.session_id = "another-session"
	check(not ApiClient.receive_command(cmd), "other session commands rejected")
	cmd.command_id = "bad-command"
	cmd.session_id = ApiClient.session_id
	cmd.type = "ASSIGN_CONDITION"
	check(not ApiClient.receive_command(cmd), "condition assignment is not a game command")
	var before_commands: int = game.mock_robot.command_number
	if not events.is_empty():
		game.mock_robot.accept_event(events[0])
	check(game.mock_robot.command_number == before_commands, "duplicate events do not repeat commands")
	GameState.stop()
	check(game.view == "stopped" and GameState.ui_locked, "stop replaces every panel and locks input")
	check(not QuestManager.advance(), "cannot progress after stop")
	check(not ApiClient.receive_command({"command_id": "after-stop", "session_id": ApiClient.session_id, "type": "RESUME_GAME", "checkpoint_id": "cave_before"}), "resume cannot undo stop")
	GameState.stop()
	check(count_event("SESSION_TERMINATED") == 1, "stop event emitted once")
	for event in events:
		check(not event.has("condition") and not event.payload.has("answer") and not event.payload.has("text"), "events contain no experimental assignment or answer text")
	await safety_paths()
	await audio_checks()
	await accessible_checks()
	await recovery_checks()
	game.queue_free()
	await settle()
	await get_tree().create_timer(0.1).timeout
	print("ECHO ISLAND: %d assertions, %d failures" % [assertions, failures])
	get_tree().quit(1 if failures > 0 else 0)

func audio_checks() -> void:
	await fresh_library()
	game.speech.enabled = true
	var actor_voices: Dictionary = {}
	for stage in Content.stages:
		if stage.has("letter_id"):
			check(game.speech.catalogue.has(stage.letter_id), "letter has bundled neural narration")
			check(game.speech.catalogue[stage.letter_id].text == stage.letter, "narration source text exactly matches the letter")
			var audio: AudioStream = load(game.speech.catalogue[stage.letter_id].path)
			check(audio.get_length() > 8, "narration clip is real nonempty audio")
			for kind in ["greeting", "task", "success", "wrong"]:
				var line: String = kind + "_" + stage.id
				check(game.speech.catalogue.has(line), "each NPC has a personalised prerecorded " + kind + " line")
				check(game.speech.catalogue[line].text == Content.presentation.characters[str(stage.npc).to_lower()][kind], "character audio text matches its fixed subtitles")
			actor_voices[game.speech.catalogue["greeting_" + stage.id].voice] = true
	check(actor_voices.size() == 4, "all four NPCs use distinct voice identities")
	game.reader._play()
	game.reader._completed("task_library")
	check(not game.reader.narration_done, "a different character clip can never complete a letter narration")
	check(game.speech.busy and game.soundscape.ducked, "narration ducks background music and ambience")
	check(game.reader.continue_button.disabled, "letter remains locked during actual audio playback")
	game.speech.pause()
	await get_tree().create_timer(0.12).timeout
	check(game.speech.busy and game.speech.playback.stream_paused, "pause preserves the voice playback position")
	game.speech.playback.pitch_scale = 25.0
	game.speech.resume()
	await get_tree().create_timer(1.5).timeout
	check(not game.speech.busy and game.reader.narration_done, "actual AudioStream completion unlocks the letter")
	check(not game.soundscape.ducked, "background levels restore after narration")
	game.speech.playback.pitch_scale = 1.0
	check(game.soundscape.music.playing and game.soundscape.ambience.playing, "original music and nature loops are playing")
	var actor: IslandCharacter = game.world.npcs[0]
	var actor_time: float = actor.time
	var bird_time: float = game.world.scenery.birds[0].elapsed
	game._toggle_pause()
	await get_tree().create_timer(0.1).timeout
	check(is_equal_approx(actor.time, actor_time), "character animation freezes while paused")
	check(is_equal_approx(game.world.scenery.birds[0].elapsed, bird_time), "the flying flock freezes safely while paused")
	check(game.soundscape.music.stream_paused and game.soundscape.ambience.stream_paused, "pause stops background playback without restarting loops")
	game._resume()
	game.speech.play_line("L2")
	GameState.stop()
	check(not game.speech.busy and not game.speech.playback.playing, "safe stop immediately stops prerecorded voice")
	check(not game.soundscape.music.playing and not game.soundscape.ambience.playing, "safe stop immediately stops background audio")

func accessible_checks() -> void:
	await fresh_library()
	GameState.simple_puzzles = true
	game.reader._skip()
	game.reader._close()
	await settle()
	await finish_checkpoint(true)
	await settle()
	check(game.simple_panel.active and game.ui.veil.visible, "simple puzzle panels remain an explicit accessibility option")
	check(click("❧   Golden feather\nUpper shelf · beside the globe"), "accessible book choice remains keyboard-operable")
	await settle()
	await finish_checkpoint(true)
	await settle()
	check(GameState.fragments.has("library"), "accessible mode awards the same fragment")
	GameState.simple_puzzles = false
	GameState.stop()

func recovery_checks() -> void:
	game.queue_free()
	await settle()
	GameState.reset()
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await settle()
	game.speech.enabled = false
	game._resume_market()
	await settle()
	check(GameState.stage_index == 2 and GameState.fragments.size() == 2, "development recovery preserves the user's two earned fragments")
	check(GameState.fragments.has("library") and GameState.fragments.has("workshop"), "recovery restores only the already-finished chapters")
	check(game.player.position.distance_to(game.world.targets[2].global_position) < 1, "recovery places the explorer at the Market")
	check(game.puzzle_panel.active and game.puzzle_panel.carrying, "recovery restores the parcel visible in the user's screenshot")
	check(not GameState.inspecting and not game.ui.veil.visible, "recovery starts in walking mode without an overhead-view trap")
	check(game.ui.task_title.text == "DELIVERY · STEP 2 OF 3", "recovery clearly points to the next unfinished step")
	await capture("06-market-recovery-step2")
	game._replay()
	check(game.reader.active and game.reader.data.id == "market", "Nia's instructions remain available from the letter button after recovery")
	game.reader._skip()
	game.reader._close()
	GameState.stop()
