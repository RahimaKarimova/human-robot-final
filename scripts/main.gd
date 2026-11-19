extends Node3D
var world: EchoWorld
var player: Explorer
var ui: IslandUI
var speech: IslandSpeech
var reader: LetterReader
var checkpoint: DialogueCheckpoint
var puzzle_panel: WorldPuzzles
var simple_panel: PuzzlePanel
var mock_robot: MockRobotAdapter
var view: String = "title"
var checkpoint_next: Callable
var title_camera: Camera3D
var title_time: float = 0.0
var soundscape: IslandSoundscape
var presentation: Dictionary
var caption_until: float = 0.0
var navigation := IslandNavigation.new()
var controller: ControllerTransport
var controller_error: String = ""
var controller_context: Dictionary = {}
var active_pause_id: String = ""
var companion_cues: CompanionCues
var pending_letter_handoff: bool = false
var voice_banner: MicrophoneIndicator
var voice_held_key: int = 0

func _ready() -> void:
	_setup_inputs()
	world = EchoWorld.new()
	add_child(world)
	player = Explorer.new()
	player.position = Vector3(0, 0.2, 29)
	add_child(player)
	world.cave.player_target = player
	for actor in world.npcs:
		actor.player_target = player
		actor.greeted.connect(_greeted)
	title_camera = Camera3D.new()
	title_camera.fov = 47
	add_child(title_camera)
	title_camera.position = Vector3(48, 29, 47)
	title_camera.look_at(Vector3(0, 0, -5))
	title_camera.current = true
	ui = IslandUI.new()
	add_child(ui)
	ui.game_art.player = player
	speech = IslandSpeech.new()
	add_child(speech)
	soundscape = IslandSoundscape.new()
	add_child(soundscape)
	speech.activity_changed.connect(soundscape.set_ducked)
	speech.activity_changed.connect(func(active: bool):
		if not active:
			for actor in world.npcs:
				actor.speaking = false
	)
	presentation = Content.presentation
	reader = LetterReader.new()
	add_child(reader)
	reader.setup(ui, speech)
	reader.closed.connect(_letter_closed)
	checkpoint = DialogueCheckpoint.new()
	add_child(checkpoint)
	checkpoint.setup(ui, speech)
	checkpoint.completed.connect(_checkpoint_done)
	puzzle_panel = WorldPuzzles.new()
	add_child(puzzle_panel)
	puzzle_panel.setup(ui, world, player)
	puzzle_panel.solved.connect(_puzzle_solved)
	puzzle_panel.character_line.connect(_character_line)
	simple_panel = PuzzlePanel.new()
	add_child(simple_panel)
	simple_panel.setup(ui)
	simple_panel.solved.connect(_puzzle_solved)
	mock_robot = MockRobotAdapter.new()
	add_child(mock_robot)
	_configure_controller()
	voice_banner = MicrophoneIndicator.new()
	ui.root.add_child(voice_banner)
	voice_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	companion_cues = CompanionCues.new()
	add_child(companion_cues)
	companion_cues.setup(self)
	ui.prompt.pressed.connect(_interact)
	ui.pause_button.pressed.connect(_toggle_pause)
	ui.stop_button.pressed.connect(func(): GameState.stop())
	ui.hint_button.pressed.connect(_hint)
	ui.letter_button.pressed.connect(_replay)
	ui.journal_button.pressed.connect(_journal)
	ui.reward_continue.pressed.connect(_continue_reward)
	ui.inspection_exit.pressed.connect(puzzle_panel.end_inspection)
	ui.task_action.pressed.connect(puzzle_panel.primary_action)
	ui.inspect_button.pressed.connect(puzzle_panel.toggle_inspection)
	ui.task_dismiss.pressed.connect(puzzle_panel.dismiss_guidance)
	EventBus.progress_changed.connect(_update_hud)
	EventBus.session_stopped.connect(_stopped)
	EventBus.command_received.connect(_command)
	_title()
	_update_hud()
	if "--resume-market" in OS.get_cmdline_user_args():
		_resume_market.call_deferred()

func _configure_controller() -> void:
	ApiClient.preview_enabled = false
	ApiClient.companion_output = "laptop"
	ApiClient.external_utterance_id = ""
	ApiClient.microphone_enabled = false
	ApiClient.conversation_enabled = false
	ApiClient.survey_url = ""
	ApiClient.voice_automatic = false
	ApiClient.last_controller_contact = 0
	ApiClient.clear_microphone_meter()
	ApiClient.speech_caption = ""
	ApiClient.session_nickname = ""
	ApiClient.recent_capture_id = ""
	ApiClient.voice_capture_id = ""
	ApiClient.voice_status = "IDLE"
	ApiClient.controller_session_id = ""
	ApiClient.status = "MOCK ROBOT · offline · no microphone or hardware"
	var args := OS.get_cmdline_user_args()
	var flag := args.find("--controller-config")
	if flag < 0:
		return
	mock_robot.enabled = false
	controller = ControllerTransport.new()
	controller_error = controller.configure(args[flag + 1] if flag + 1 < args.size() else "")
	add_child(controller)
	if not controller_error.is_empty():
		ApiClient.status = "CONTROLLER CONFIGURATION ERROR · offline mock not selected"
	speech.activity_changed.connect(func(active: bool):
		if not GameState.stopped:
			ApiClient.emit_event("GAME_AUDIO_STATE_CHANGED", {"active": active})
	)

func _resume_market() -> void:
	# Explicit offline development recovery for the user's already-earned first two pieces.
	GameState.reset()
	speech.stop()
	reader.active = false
	checkpoint.active = false
	simple_panel.active = false
	mock_robot.checkpoints.clear()
	mock_robot.seen_events.clear()
	mock_robot.narrator_ready.clear()
	GameState.stage_index = 2
	GameState.tutorial_done = true
	GameState.started = true
	for index in range(2):
		var stage: Dictionary = Content.stage(index)
		GameState.fragments[stage.id] = true
		GameState.letters[stage.id] = true
		for phase in ["entry", "before", "after"]:
			GameState.checkpoints[stage.id + "_" + phase] = true
		puzzle_panel.data = stage
		puzzle_panel.complete_visuals()
	puzzle_panel.data = Content.stage(2)
	puzzle_panel.puzzle = null
	player.position = world.targets[2].global_position
	player.yaw = -1.05
	player.camera.current = true
	ApiClient.begin()
	ApiClient.emit_event("DEVELOPMENT_RECOVERY", {"fragments": 2, "mock": true})
	GameState.letters["market"] = true
	GameState.checkpoints["market_entry"] = true
	GameState.checkpoints["market_before"] = true
	mock_robot.narrator_ready["market"] = true
	ui.hud.show()
	ui.close_modal()
	_update_hud()
	_open_puzzle()
	puzzle_panel.primary_action()

func _setup_inputs() -> void:
	var bindings := {"move_forward": KEY_W, "move_back": KEY_S, "move_left": KEY_A, "move_right": KEY_D, "interact": KEY_E, "letter": KEY_R, "hint": KEY_H, "journal": KEY_TAB, "pause": KEY_ESCAPE, "sprint": KEY_SHIFT, "zoom_in": KEY_EQUAL, "zoom_out": KEY_MINUS, "inspect": KEY_F, "previous_item": KEY_Q, "next_item": KEY_T}
	for action in bindings:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var key := InputEventKey.new()
			key.physical_keycode = bindings[action]
			InputMap.action_add_event(action, key)

func _title() -> void:
	ui.hud.hide()
	var panel := ui.show_modal("A CARTOGRAPHER'S ADVENTURE", "ECHO ISLAND", "THE LOST TREASURE")
	for child in panel.get_children():
		if child is Label and child.text == "ECHO ISLAND":
			child.add_theme_font_size_override("font_size", 80)
			child.add_theme_color_override("font_shadow_color", Color("102731aa"))
			child.add_theme_constant_override("shadow_offset_y", 5)
	IslandUI.text(panel, "Four precious gems. One sealed treasure cave.", 20, Color("f1ead5"))
	IslandUI.text(panel, "✦     ──────────────     ✦", 22, IslandUI.GOLD)
	var actions := IslandUI.row(panel)
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	var begin_button := IslandUI.button(actions, "Begin the adventure  →", _begin)
	begin_button.add_theme_stylebox_override("normal", IslandUI.framed(Color("e1d0a8"), 4, 16, Color("f8ebc7")))
	begin_button.add_theme_color_override("font_color", Color("283846"))
	begin_button.add_theme_color_override("font_focus_color", Color("283846"))
	begin_button.add_theme_color_override("font_hover_color", Color("283846"))
	begin_button.add_theme_stylebox_override("hover", IslandUI.framed(Color("f1e0bc"), 4, 16, Color("fff3d5")))
	IslandUI.button(actions, "Settings & accessibility", _settings)
	IslandUI.button(actions, "Quit", func(): get_tree().quit())
	var mode_label := "REACHY DRAFT REHEARSAL / LAPTOP VOICE / NO HARDWARE" if ApiClient.preview_enabled else "OFFLINE ADVENTURE  /  MOCK COMPANION"
	if ApiClient.companion_output == "bridge_simulator":
		mode_label = "SILENT BRIDGE SIMULATOR / NO PHYSICAL ROBOT"
	elif ApiClient.companion_output == "reachy_lite":
		mode_label = "REACHY LITE OUTPUT SELECTED / DRAFT LIBRARY FLOW"
	elif ApiClient.companion_output == "reachy_wireless":
		mode_label = "WIRELESS ROBOT OUTPUT SELECTED / REMOTE WORKER REQUIRED"
	elif ApiClient.companion_output == "reachy_mujoco":
		mode_label = "OFFICIAL REACHY MINI MUJOCO SIMULATION / NO HARDWARE"
	elif ApiClient.companion_output == "reachy_control_simulator":
		mode_label = "REACHY MINI CONTROL / BUILT-IN SIMULATOR / NO HARDWARE"
	IslandUI.text(panel, mode_label, 11, Color("d6e0d4"))
	ui.cinematic_title()

func _begin() -> void:
	if not controller_error.is_empty():
		var panel := ui.show_modal("External controller", "Configuration needs attention", controller_error)
		IslandUI.text(panel, "Run Play-Controller.ps1 to create a local mock session. To play offline, restart with Play.cmd. No fallback was activated automatically.", 20)
		IslandUI.button(panel, "Quit", func(): get_tree().quit())
		return
	GameState.started = true
	player.camera.current = true
	ApiClient.begin()
	ui.hud.show()
	if ApiClient.preview_enabled:
		_run_checkpoint("welcome", _tutorial)
	else:
		speech.play_line("intro")
		_tutorial()

func _tutorial() -> void:
	view = "tutorial"
	var panel := ui.show_modal("Welcome to Echo Island", "Your adventure begins at the dock", "Collect four precious gems to unlock the sealed treasure cave.")
	IslandUI.text(panel, presentation.intro, 21)
	IslandUI.text(panel, "W A S D   Move       Shift   Sprint\nHold right mouse   Look around\nMouse wheel or + / −   Zoom in / out\nE   Interact        R   Replay letter\nH   Hint       Tab   Journal       Esc   Pause", 21)
	IslandUI.text(panel, "You can also use the on-screen buttons and Tab / Enter to navigate panels. There are no timers, combat or jumping challenges.", 18, IslandUI.MUTED)
	IslandUI.button(panel, "Step onto the island", func():
		view = "explore"
		ui.close_modal()
	)

func _process(delta: float) -> void:
	voice_banner.visible = ApiClient.microphone_enabled and GameState.started and not GameState.stopped and ApiClient.voice_status in ["STARTING", "LISTENING", "PROCESSING"] and (not GameState.paused or not ApiClient.voice_automatic)
	voice_banner.text = ApiClient.VOICE_TEXT.get(ApiClient.voice_status, "Mic off")
	if ApiClient.conversation_enabled:
		if ApiClient.voice_automatic and ApiClient.voice_status == "LISTENING":
			voice_banner.text = "LISTENING · Speak naturally, then pause · Say skip, repeat or stop"
		elif ApiClient.voice_status == "IDLE":
			voice_banner.text = "Mic off · Reachy listens after each question · V for other voice controls"
	var mic_width: float = minf(780, get_viewport().get_visible_rect().size.x - 36)
	voice_banner.show_caption = not checkpoint.active and not ApiClient.speech_caption.is_empty()
	voice_banner.position = Vector2((get_viewport().get_visible_rect().size.x - mic_width) * 0.5, 80)
	voice_banner.size = Vector2(mic_width, 110 if voice_banner.show_caption else 54)
	if pending_letter_handoff and ApiClient.external_utterance_id.is_empty() and ApiClient.voice_capture_id.is_empty() and not speech.busy and companion_cues.active.is_empty() and companion_cues.pending.is_empty() and not GameState.paused and not GameState.stopped:
		pending_letter_handoff = false
		_open_letter()
	ui.status.text = ApiClient.status
	if is_instance_valid(controller) and GameState.started and not GameState.stopped:
		var context := {"view": view, "puzzle_active": puzzle_panel.active or simple_panel.active, "pause_id": active_pause_id if GameState.paused else ""}
		context["stage"] = GameState.stage_index
		if context != controller_context:
			controller_context = context.duplicate()
			context.erase("stage")
			ApiClient.emit_event("GAME_CONTEXT_CHANGED", context)
	if not GameState.started:
		title_time += delta * 0.015
		title_camera.position = Vector3(cos(title_time + 0.8) * 64, 29, sin(title_time + 0.8) * 64)
		title_camera.look_at(Vector3(0, 0, -5))
		return
	if GameState.stopped:
		return
	ui.caption_panel.visible = not ui.veil.visible and (Time.get_ticks_msec() / 1000.0 < caption_until or (speech.busy and speech.active_line.contains("_")))
	var target: Vector3 = puzzle_panel.waypoint() if puzzle_panel.active else world.targets[GameState.stage_index].global_position
	if not puzzle_panel.active and GameState.tutorial_done and not GameState.completed:
		target = navigation.next_point(player.position, GameState.stage_index)
	if GameState.stage_index == 4 and (GameState.cave_open or player.position.distance_to(world.cave.door_point.global_position) < 5):
		target = _cave_target()
	var interaction_distance := player.position.distance_to(world.targets[GameState.stage_index].global_position)
	var distance := player.position.distance_to(target)
	var direction := target - player.position
	var bearing := wrapf(atan2(-direction.x, -direction.z) - player.yaw, -PI, PI)
	var arrow := "↑"
	if absf(bearing) > 2.3:
		arrow = "↓"
	elif bearing > 0.45:
		arrow = "←"
	elif bearing < -0.45:
		arrow = "→"
	ui.waypoint.text = "%s  %s · %d m" % [arrow, puzzle_panel.waypoint_name() if puzzle_panel.active else Content.stage(GameState.stage_index).name, roundi(distance)]
	world.guidance_enabled = true
	world.guidance_position = target
	if not puzzle_panel.active:
		puzzle_panel.guide_walk(target, delta, GameState.tutorial_done and not GameState.completed and view != "reward")
	ui.inspection_panel.visible = GameState.inspecting and not ui.veil.visible and not ui.pause_veil.visible
	ui.inspection_status.text = "Overhead map · WASD returns to walking" if puzzle_panel.active and puzzle_panel.data.id == "market" else "Close-up view · click the objects"
	if puzzle_panel.active and puzzle_panel.data.id == "workshop":
		ui.inspection_status.text = "Choose a loose gear, then a socket" if puzzle_panel.held_gear.is_empty() else "Holding " + puzzle_panel.held_gear.to_lower() + " · choose a socket"
	ui.inspect_button.visible = puzzle_panel.active and not GameState.inspecting and not ui.veil.visible and not ui.pause_veil.visible
	ui.inspect_button.text = "View delivery map  [F]" if puzzle_panel.active and puzzle_panel.data.id == "market" else "Inspect puzzle up close  [F]"
	ui.prompt.visible = not ui.veil.visible and not ui.pause_veil.visible and not GameState.completed
	ui.prompt.disabled = interaction_distance > 6.5 and GameState.tutorial_done
	ui.prompt.text = "[ E ]   Read the dock sign" if not GameState.tutorial_done else ("[ E ]   Open treasure chest" if GameState.stage_index == 4 else "[ E ]   Speak with " + Content.stage(GameState.stage_index).npc)
	if ui.prompt.disabled:
		ui.prompt.text = "Follow the golden path · %d m" % roundi(distance)
	if GameState.stage_index == 4:
		ui.prompt.visible = not ui.veil.visible and not ui.pause_veil.visible and not GameState.completed
		ui.prompt.disabled = true
		if not GameState.cave_open:
			var gem := world.cave.next_gem()
			ui.prompt.text = "The stone door is opening…" if gem.is_empty() else "[ E ]  Place " + gem.name + " · " + gem.native_name
			ui.prompt.disabled = player.position.distance_to(world.cave.door_point.global_position) >= 4 or gem.is_empty()
		elif not GameState.cave_entered:
			ui.prompt.text = "Walk through the open doorway · WASD"
		else:
			ui.prompt.text = "[ E ]  Open treasure chest" if distance < 2.8 else "Follow the lanterns to the chest"
			ui.prompt.disabled = distance >= 2.8
	if puzzle_panel.active:
		ui.prompt.visible = not ui.veil.visible and not ui.pause_veil.visible
		ui.prompt.disabled = false
		ui.prompt.text = "[ E ]  " + puzzle_panel.action_name()
		if puzzle_panel.data.id == "market":
			ui.prompt.text = puzzle_panel.market_prompt()
			ui.prompt.disabled = not puzzle_panel.market_action_available() and not GameState.inspecting
			if puzzle_panel.carrying and not puzzle_panel.crossed_bridge and not GameState.inspecting:
				ui.prompt.hide()
		ui.prompt.position = Vector2(get_viewport().get_visible_rect().size.x - 430, get_viewport().get_visible_rect().size.y - 170) if GameState.inspecting else Vector2(get_viewport().get_visible_rect().size.x * 0.5 + 100, get_viewport().get_visible_rect().size.y * 0.5 + 74)
	elif view == "reward":
		ui.prompt.hide()
	ui.controls.text = "Q / T  Select    E / Click  Use    F  Return    H  Hint" if GameState.inspecting else "WASD  Move   Shift  Sprint   Wheel  Zoom   E  Interact"

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo() or GameState.stopped:
		return
	if event.is_action_pressed("pause"):
		_toggle_pause()
	elif ui.pause_veil.visible:
		return
	elif event.is_action_pressed("interact"):
		_interact()
	elif event.is_action_pressed("letter"):
		_replay()
	elif event.is_action_pressed("hint"):
		_hint()
	elif event.is_action_pressed("journal"):
		_journal()

func _interact() -> void:
	if GameState.ui_locked or not GameState.started or GameState.stopped or GameState.completed:
		return
	if view == "reward":
		_continue_reward()
		return
	if puzzle_panel.active:
		puzzle_panel.interact()
		return
	if not GameState.tutorial_done:
		GameState.tutorial_done = true
		ApiClient.emit_event("TUTORIAL_COMPLETED")
		var panel := ui.show_modal("The cartographer's trail", "First stop: Forest Library", "Follow the path to Elara. The golden marker shows your next destination.")
		IslandUI.button(panel, "Let's explore", func(): ui.close_modal())
		return
	if GameState.stage_index == 4:
		if not GameState.cave_open and player.position.distance_to(world.cave.door_point.global_position) < 4:
			if world.cave.insert_next():
				soundscape.reward()
		elif GameState.cave_entered and player.position.distance_to(world.cave.chest_point.global_position) < 2.8:
			_finale()
		return
	if player.position.distance_to(world.targets[GameState.stage_index].global_position) > 6.5:
		return
	var stage: Dictionary = Content.stage(GameState.stage_index)
	ApiClient.emit_event("NPC_REACHED", {"npc_id": stage.npc})
	if GameState.fragments.has(stage.id):
		_reward()
	elif not GameState.letters.has(stage.id):
		_run_checkpoint("entry", _open_letter)
	elif not GameState.checkpoints.has(stage.id + "_before"):
		_run_checkpoint("before", _open_puzzle)
	else:
		_open_puzzle()

func _open_letter() -> void:
	if not ApiClient.external_utterance_id.is_empty() or not ApiClient.voice_capture_id.is_empty() or speech.busy or not companion_cues.active.is_empty() or not companion_cues.pending.is_empty():
		ApiClient.voice_release(true)
		pending_letter_handoff = true
		return
	view = "letter"
	reader.open(Content.stage(GameState.stage_index))

func _greeted(actor: IslandCharacter) -> void:
	if GameState.ui_locked or GameState.stopped or speech.busy or not ApiClient.external_utterance_id.is_empty() or not ApiClient.voice_capture_id.is_empty() or actor.profile != str(Content.stage(GameState.stage_index).npc).to_lower():
		return
	var character: Dictionary = presentation.characters[actor.profile]
	ui.caption_name.text = character.name + "  ·  " + character.role
	ui.caption_line.text = character.greeting
	caption_until = Time.get_ticks_msec() / 1000.0 + 6.5
	actor.speaking = speech.play_line("greeting_" + Content.stage(GameState.stage_index).id)

func _character_line(kind: String) -> void:
	if GameState.stopped or reader.active or not ApiClient.external_utterance_id.is_empty() or not ApiClient.voice_capture_id.is_empty():
		return
	var stage: Dictionary = Content.stage(GameState.stage_index)
	var actor: IslandCharacter = world.npcs[GameState.stage_index]
	var character: Dictionary = presentation.characters[actor.profile]
	var id := kind + "_" + str(stage.id)
	if speech.busy and (kind == "wrong" or speech.active_line.begins_with("companion_")):
		return
	ui.caption_name.text = character.name + "  ·  " + character.role
	ui.caption_line.text = character.get(kind, character.greeting)
	caption_until = Time.get_ticks_msec() / 1000.0 + 8.0
	actor.speaking = speech.play_line(id)

func _letter_closed(first_read: bool) -> void:
	if first_read:
		_run_checkpoint("before", _open_puzzle)
	else:
		view = "puzzle" if puzzle_panel.active else "explore"
		ui.close_modal()

func _run_checkpoint(phase: String, next: Callable) -> void:
	view = "checkpoint"
	checkpoint_next = next
	checkpoint.begin(Content.stage(GameState.stage_index), phase)

func _checkpoint_done() -> void:
	if GameState.stopped:
		return
	var next := checkpoint_next
	checkpoint_next = Callable()
	if next.is_valid():
		next.call_deferred()

func _open_puzzle() -> void:
	view = "puzzle"
	puzzle_panel.open(Content.stage(GameState.stage_index))
	if GameState.simple_puzzles:
		puzzle_panel.active = false
		ui.task_panel.hide()
		simple_panel.open(Content.stage(GameState.stage_index))

func _puzzle_solved() -> void:
	puzzle_panel.complete_visuals()
	simple_panel.active = false
	if QuestManager.award_fragment(Content.stage(GameState.stage_index).id):
		world.npcs[GameState.stage_index].celebrate()
		_run_checkpoint("after", _reward)

func _reward() -> void:
	view = "reward"
	var data: Dictionary = Content.stage(GameState.stage_index)
	var giver: Dictionary = presentation.characters[str(data.npc).to_lower()]
	ui.close_modal()
	puzzle_panel.show_gift(GameState.fragments.size())
	var gem := Content.gem_for_stage(GameState.stage_index)
	ui.reward_title.text = "✦  " + gem.name + " · " + gem.native_name + "  ·  GEM %d / 4" % GameState.fragments.size()
	ui.reward_text.text = giver.reward
	ui.reward_continue.text = "Continue to " + Content.stage(GameState.stage_index + 1).name + "  →"
	ui.reward_panel.show()
	ui.objective.text = "Precious gem found · continue when ready"
	soundscape.reward()
	_character_line("success")

func _continue_reward() -> void:
	if view == "reward" and not GameState.stopped and not GameState.paused and QuestManager.advance():
		view = "explore"
		ui.reward_panel.hide()
		ui.close_modal()

func _replay() -> void:
	if ui.pause_veil.visible or GameState.stopped or not GameState.started:
		return
	if reader.active:
		reader._play()
	elif not ui.veil.visible and GameState.stage_index < 4 and GameState.letters.has(Content.stage(GameState.stage_index).id):
		_open_letter()

func _hint() -> void:
	if ui.pause_veil.visible or GameState.stopped or not GameState.started:
		return
	if puzzle_panel.active and not ui.veil.visible:
		puzzle_panel.hint()
	elif simple_panel.active and ui.veil.visible:
		simple_panel.hint()
	elif not ui.veil.visible:
		var data: Dictionary = Content.stage(GameState.stage_index)
		var panel := ui.show_modal("Wayfinding", "Your next step", data.objective)
		if GameState.stage_index < 4 and GameState.letters.has(data.id):
			IslandUI.text(panel, EchoPuzzle.next_hint(data.id), 24)
			ApiClient.emit_event("HINT_REQUESTED", {"level": GameState.hints[data.id]})
		else:
			IslandUI.text(panel, "Follow the golden marker. Move with WASD and press E when you reach it. The arrow above points toward the next destination.", 22)
		IslandUI.button(panel, "Back to exploring", func(): ui.close_modal())

func _journal() -> void:
	if GameState.stopped or not GameState.started or ui.pause_veil.visible:
		return
	if view == "journal" and ui.veil.visible:
		view = "explore"
		ui.close_modal()
		return
	if ui.veil.visible:
		return
	view = "journal"
	var panel := ui.show_modal("The cartographer's journal", "Your island discoveries", Content.stage(GameState.stage_index).objective)
	IslandUI.text(panel, "%d / 4 precious gems\nLetters never contain or store personal answers." % GameState.fragments.size(), 20, IslandUI.MUTED)
	var trail := ""
	for i in range(Content.stages.size()):
		trail += ("✓  " if i < GameState.stage_index else ("→  " if i == GameState.stage_index else "◇  ")) + Content.stage(i).name + ("   ·   " if i < 4 else "")
	IslandUI.text(panel, trail, 17, IslandUI.MUTED)
	for stage in Content.stages:
		if GameState.letters.has(stage.id):
			IslandUI.button(panel, stage.npc + "'s letter · " + stage.name, func():
				view = "letter"
				reader.open(stage)
			)
	IslandUI.button(panel, "Back to the island", func():
		view = "explore"
		ui.close_modal()
	)

func _toggle_pause() -> void:
	if GameState.stopped:
		return
	if ui.pause_veil.visible:
		_resume()
		return
	GameState.ui_locked = true
	GameState.paused = true
	active_pause_id = Crypto.new().generate_random_bytes(8).hex_encode()
	speech.pause()
	soundscape.set_paused(true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	ApiClient.emit_event("PAUSE_REQUESTED")
	for child in ui.pause_content.get_children():
		ui.pause_content.remove_child(child)
		child.queue_free()
	ui.pause_veil.show()
	IslandUI.text(ui.pause_content, "Take a moment", 34)
	IslandUI.text(ui.pause_content, "Your progress is safe while paused. There is no time limit.\nFor technical assistance, ask your nearby researcher.", 21)
	IslandUI.button(ui.pause_content, "Resume", _resume)
	if GameState.started and not GameState.completed and not ui.veil.visible and view in ["explore", "puzzle"]:
		IslandUI.button(ui.pause_content, "Return to quest path", _return_to_path)
	IslandUI.button(ui.pause_content, "Settings & accessibility", func(): _settings(true))
	IslandUI.button(ui.pause_content, "Stop this session", func(): GameState.stop())
	IslandUI.button(ui.pause_content, "Quit game", func():
		GameState.stop()
		get_tree().quit()
	)

func _resume() -> void:
	GameState.paused = false
	active_pause_id = ""
	ui.pause_veil.hide()
	GameState.ui_locked = ui.veil.visible or not GameState.started
	speech.resume()
	soundscape.set_paused(false)
	ApiClient.emit_event("GAME_RESUMED")

func _return_to_path() -> void:
	if GameState.stopped or GameState.completed or ui.veil.visible or not view in ["explore", "puzzle"]:
		return
	_resume()
	puzzle_panel.end_inspection()
	player.global_position = world.targets[GameState.stage_index].global_position + Vector3(0, 0.2, 0)
	player.velocity = Vector3.ZERO
	player.yaw = 0
	navigation.reset()
	if puzzle_panel.active and puzzle_panel.data.id == "market":
		puzzle_panel.previous_position = player.global_position
		puzzle_panel.crossed_bridge = false
		puzzle_panel.returning_to_bridge = false
		puzzle_panel.market_step = -1
		puzzle_panel._update_market_guidance()
	ApiClient.emit_event("WAYFINDING_RETURNED")

func _settings(from_pause: bool = false) -> void:
	var parent: VBoxContainer
	if from_pause:
		for child in ui.pause_content.get_children():
			ui.pause_content.remove_child(child)
			child.queue_free()
		parent = ui.pause_content
		IslandUI.text(parent, "Settings & accessibility", 30)
	else:
		parent = ui.show_modal("Make yourself comfortable", "Settings & accessibility")
	var audio := CheckButton.new()
	audio.text = "Story narration and character greetings"
	audio.button_pressed = speech.enabled
	parent.add_child(audio)
	audio.toggled.connect(func(on: bool):
		speech.enabled = on
		if not on and not speech.active_line.begins_with("companion_"):
			speech.stop()
			if reader.active:
				reader.narration_status.text = "Narration off · select ‘finish reading’ whenever you are ready."
	)
	IslandUI.text(parent, "Neural narration is bundled with the game and plays offline. Captions are always available.", 17, IslandUI.MUTED)
	var previews := IslandUI.row(parent)
	for stage in Content.stages:
		if stage.has("letter_id"):
			var preview := IslandUI.button(previews, "Hear " + stage.npc, func():
				if speech.busy or not ApiClient.external_utterance_id.is_empty(): return
				var character: Dictionary = presentation.characters[str(stage.npc).to_lower()]
				ui.caption_name.text = character.name + "  ·  " + character.role
				ui.caption_line.text = character.greeting
				caption_until = Time.get_ticks_msec() / 1000.0 + 6.5
				speech.playback.stream_paused = false
				speech.play_line("greeting_" + stage.id)
			)
			preview.disabled = reader.active or speech.busy or not ApiClient.external_utterance_id.is_empty()
			preview.tooltip_text = presentation.characters[str(stage.npc).to_lower()].voice_style
	var simple := CheckButton.new()
	simple.text = "Use simple puzzle panels instead of 3D object interaction"
	simple.button_pressed = GameState.simple_puzzles
	parent.add_child(simple)
	simple.toggled.connect(func(on: bool): GameState.simple_puzzles = on)
	_volume_slider(parent, "Voice volume", speech.volume, speech.set_volume)
	_volume_slider(parent, "Background music", soundscape.music_volume, soundscape.set_music_volume)
	_volume_slider(parent, "Nature ambience", soundscape.ambience_volume, soundscape.set_ambience_volume)
	IslandUI.text(parent, "Camera distance · mouse wheel also zooms", 19)
	var zoom := HSlider.new()
	zoom.min_value = Explorer.MIN_ZOOM
	zoom.max_value = Explorer.MAX_ZOOM
	zoom.step = 0.25
	zoom.value = player.zoom_target
	zoom.custom_minimum_size.y = 30
	parent.add_child(zoom)
	zoom.value_changed.connect(func(value: float): player.zoom_target = value)
	IslandUI.text(parent, "Mouse sensitivity", 21)
	var slider := HSlider.new()
	slider.min_value = 0.001
	slider.max_value = 0.006
	slider.step = 0.00025
	slider.value = player.sensitivity
	slider.custom_minimum_size.y = 36
	parent.add_child(slider)
	slider.value_changed.connect(func(value: float): player.sensitivity = value)
	IslandUI.text(parent, "All puzzles use labelled choices. Use Tab / Shift+Tab and Enter / Space to operate buttons. No colour-only clues, fast reactions or audio-only instructions.", 19)
	IslandUI.button(parent, "Back", func():
		if from_pause:
			ui.pause_veil.hide()
			_toggle_pause()
		else:
			_title()
	)

func _volume_slider(parent: Node, label: String, value: float, change: Callable) -> void:
	IslandUI.text(parent, label, 18)
	var slider := HSlider.new()
	slider.min_value = 0
	slider.max_value = 1
	slider.step = 0.05
	slider.value = value
	slider.custom_minimum_size.y = 28
	parent.add_child(slider)
	slider.value_changed.connect(change)

func _finale() -> void:
	if not QuestManager.finish():
		return
	view = "finale"
	world.open_chest()
	ui.prompt.hide()
	# Allow the lid animation to be seen before presenting the end card.
	GameState.ui_locked = true
	await get_tree().create_timer(1.6).timeout
	if GameState.stopped:
		return
	if ApiClient.preview_enabled:
		_run_checkpoint("ending", _ending_card)
	else:
		_ending_card()

func _ending_card() -> void:
	view = "finale"
	var panel := ui.show_modal("Four jewels. One wonderful discovery.", "You found the treasure!", "Your four precious gems opened the ancient seal.")
	IslandUI.text(panel, Content.catalogue.ending, 27)
	if not ApiClient.preview_enabled:
		speech.play_line("ending")
	if ApiClient.survey_url.is_empty():
		IslandUI.text(panel, "Echo Island is complete. Any questionnaire or research debrief happens outside the game.", 19, IslandUI.MUTED)
	else:
		var survey_note := IslandUI.text(panel, "Thank you for playing! Please fill in our short survey about Reachy. It takes about 3 minutes.", 21, IslandUI.GOLD)
		var survey_button := IslandUI.button(panel, "Please do our survey", _open_survey)
		if ApiClient.companion_output != "laptop":
			# Reachy says its ending line, then dances (about 50 s): show the survey after the dance.
			survey_note.text = "Enjoy Reachy's dance! Our short survey link appears when it ends."
			survey_button.disabled = true
			get_tree().create_timer(60.0).timeout.connect(func():
				if is_instance_valid(survey_button):
					survey_note.text = "Thank you for playing! Please fill in our short survey about Reachy. It takes about 3 minutes."
					survey_button.disabled = false
			)
	IslandUI.button(panel, "Explore the island", func():
		view = "explore"
		ui.close_modal()
	)
	if is_instance_valid(controller):
		IslandUI.button(panel, "Finish session", func():
			_open_survey()  # Make sure the survey is open before the game closes.
			get_tree().quit())
	else:
		IslandUI.button(panel, "Start a new adventure", func():
			GameState.reset()
			get_tree().reload_current_scene()
		)

func _open_survey() -> void:
	if ApiClient.survey_url.is_empty() or ApiClient.survey_opened:
		return
	ApiClient.survey_opened = true
	OS.shell_open(ApiClient.survey_url)

func _update_hud() -> void:
	ui.objective.text = "Treasure discovered · thank you for exploring!" if GameState.completed else Content.stage(GameState.stage_index).objective
	ui.fragments.text = "PRECIOUS GEMS  ·  %d / 4" % GameState.fragments.size()
	if GameState.stage_index == 4 and not GameState.completed:
		ui.objective.text = "Cave door · gems placed: %d / 4" % GameState.socketed_gems.size()
		if GameState.cave_open:
			ui.objective.text = "Enter the cave and find the hidden chest" if not GameState.cave_entered else "Open the treasure chest inside the cave"
	ui.status.text = ApiClient.status

func _cave_target() -> Vector3:
	if not GameState.cave_open:
		return world.cave.door_point.global_position
	return world.cave.chest_point.global_position if GameState.cave_entered else world.cave.to_global(Vector3(0, 0, -1))

func _stopped() -> void:
	speech.stop()
	soundscape.stop()
	reader.active = false
	checkpoint.active = false
	puzzle_panel.cancel()
	simple_panel.active = false
	ui.pause_veil.hide()
	view = "stopped"
	var stop_message := "This session does not save audio or reply transcripts." if ApiClient.microphone_enabled else "No microphone or participant answer recording was active."
	var panel := ui.show_modal("Session stopped", "This session has ended", stop_message)
	IslandUI.text(panel, "Speak to your researcher if this was a supervised session. A stopped session cannot resume accidentally.", 22)
	if is_instance_valid(controller):
		IslandUI.text(panel, "Close this window and run the controller launcher again to create a fresh session.", 20)
	else:
		IslandUI.button(panel, "New development session", func():
			GameState.reset()
			get_tree().reload_current_scene()
		)
	IslandUI.button(panel, "Quit", func(): get_tree().quit())
	ui.pause_button.disabled = true
	ui.stop_button.disabled = true

func _command(command: Dictionary) -> void:
	if command.get("type") == "PAUSE_GAME" and not ui.pause_veil.visible:
		_toggle_pause()
	elif command.get("type") == "RESUME_PLAY" and GameState.paused and command.get("pause_id") == active_pause_id:
		_resume()
	elif command.get("type") == "REQUEST_HINT" and command.get("stage_id") == Content.stage(GameState.stage_index).id and not GameState.paused and not reader.active and not checkpoint.active and (puzzle_panel.active or simple_panel.active):
		_hint()
	elif command.get("type") == "COMPANION_NOTICE":
		var notice_id: String = command.get("notice_id", "")
		if checkpoint.active:
			checkpoint.show_notice(notice_id)
		elif puzzle_panel.active and CompanionNotices.TEXTS.has(notice_id):
			ui.task_feedback.text = CompanionNotices.TEXTS[notice_id]
			puzzle_panel.feedback_until = Time.get_ticks_msec() / 1000.0 + 4
	elif command.get("type") == "SHOW_OBJECTIVE":
		ui.objective.text = str(command.get("text", Content.stage(GameState.stage_index).objective))

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_instance_valid(ui) and GameState.started and not GameState.stopped and not ui.pause_veil.visible:
		ApiClient.voice_release(true)
		_toggle_pause()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.physical_keycode in [KEY_V, KEY_B] and not event.echo and ApiClient.microphone_enabled:
		if event.pressed:
			if not ApiClient.voice_capture_id.is_empty():
				return
			if event.physical_keycode == KEY_B and (not checkpoint.active or not checkpoint.question or not checkpoint.playback_done):
				return
			# Bind capture to the view that exists now, including a just-closed panel.
			ApiClient.emit_event("GAME_CONTEXT_CHANGED", {"view":view, "puzzle_active":puzzle_panel.active or simple_panel.active, "pause_id":active_pause_id if GameState.paused else ""})
			ApiClient.voice_start("reply" if event.physical_keycode == KEY_B else "control")
			voice_held_key = event.physical_keycode
		elif voice_held_key == event.physical_keycode:
			ApiClient.voice_release()
			voice_held_key = 0
		get_viewport().set_input_as_handled()
