class_name WorldPuzzles
extends Node3D
signal solved
signal character_line(kind: String)
var ui: IslandUI
var world: EchoWorld
var player: Explorer
var data: Dictionary
var puzzle: EchoPuzzle
var active: bool = false
var items: Dictionary = {}
var roots: Dictionary = {}
var focus: WorldPuzzleItem
var keyboard_focus: bool = false
var slots: Array[String] = ["", "", ""]
var held_gear: String = ""
var held_model: WorldPuzzleItem
var socket_gears: Array[WorldPuzzleItem] = []
var gear_tray: Dictionary = {}
var clock_drawer: Node3D
var altar_lids: Array[Node3D] = []
var altar_open: float = 0.0
var feedback: Label
var hint_label: Label
var inspection: Camera3D
var carrying: bool = false
var crossed_bridge: bool = false
var returning_to_bridge: bool = false
var previous_position := Vector3.ZERO
var parcel: Node3D
var gift: WorldGift
var clock_hand: Node3D
var clock_running: bool = false
var completed_visuals: Dictionary = {}
var route_markers: Array[Node3D] = []
var destination_marker: Node3D
var destination_label: Label3D
var guide_time: float = 0.0
var market_step: int = -1
var feedback_until: float = 0.0

func setup(interface: IslandUI, island: EchoWorld, explorer: Explorer) -> void:
	ui = interface
	world = island
	player = explorer
	feedback = ui.task_feedback
	hint_label = ui.task_hint
	inspection = Camera3D.new()
	inspection.fov = 62
	inspection.cull_mask = 1
	add_child(inspection)
	_make_guidance()
	for index in range(4):
		var stage: Dictionary = Content.stage(index)
		var root := Node3D.new()
		root.position = Vector3(stage.position[0], 0, stage.position[2])
		add_child(root)
		roots[stage.id] = root
		items[stage.id] = []
		match stage.id:
			"library": _library(root, stage)
			"workshop": _workshop(root)
			"market": _market(root)
			"temple": _temple(root)

func _item(root: Node3D, stage_id: String, id: String, title: String, at: Vector3, bounds: Vector3) -> WorldPuzzleItem:
	var item := WorldPuzzleItem.new()
	item.item_id = id
	item.stage_id = stage_id
	item.title = title
	root.add_child(item)
	item.position = at
	item.initialise(bounds)
	items[stage_id].append(item)
	return item

func _library(root: Node3D, stage: Dictionary) -> void:
	var positions := [Vector3(-2.9, 1.0, -2.12), Vector3(-1.9, 1.0, -2.12), Vector3(1.7, 1.0, -2.12), Vector3(2.65, 1.0, -2.12), Vector3(-2.5, 1.92, -2.12), Vector3(2.45, 1.92, -2.12)]
	for i in range(6):
		var option: Dictionary = stage.puzzle.options[i]
		var item := _item(root, "library", option.id, option.label + "\n" + option.detail, positions[i], Vector3(0.68, 0.62, 0.44))
		var color := Color(option.color)
		EchoWorld.box(item, Vector3.ZERO, Vector3(0.59, 0.6, 0.38), color)
		EchoWorld.box(item, Vector3(0.23, 0, 0), Vector3(0.09, 0.55, 0.32), Color("e5d7b1"))
		for y in [-0.23, 0.23]:
			EchoWorld.box(item, Vector3(0, y, 0.2), Vector3(0.5, 0.025, 0.025), Color("dac18b"))
		var mark_color := Color("e8c96c") if option.id == "golden_feather" else Color("e1e4da")
		if "feather" in str(option.id):
			var feather := EchoWorld.box(item, Vector3(-0.04, 0, 0.22), Vector3(0.025, 0.28, 0.025), mark_color)
			feather.rotation.z = -0.45
			for j in range(4):
				var barb := EchoWorld.box(item, Vector3(-0.08 + j * 0.04, -0.08 + j * 0.055, 0.22), Vector3(0.13, 0.024, 0.025), mark_color)
				barb.rotation.z = 0.45
		else:
			var mark := EchoWorld.label(item, Vector3(-0.03, 0, 0.22), option.mark, 32, mark_color)
			mark.billboard = BaseMaterial3D.BILLBOARD_DISABLED

func _workshop(root: Node3D) -> void:
	for i in range(3):
		var item := _item(root, "workshop", "slot_" + str(i), "Gear socket " + str(i + 1), Vector3(0.6 + i * 1.1, 1.18, -1.4), Vector3(0.85, 0.45, 0.85))
		EchoWorld.cylinder(item, Vector3(0, -0.04, 0), 0.38, 0.08, Color("3c4546"), 16)
		var gear := WorldPuzzleItem.new()
		item.add_child(gear)
		_make_gear(gear)
		socket_gears.append(gear)
		EchoWorld.label(root, item.position + Vector3(0, 0.06, 0.58), str(i + 1), 25)
	_update_gears()
	var lever := _item(root, "workshop", "test_clock", "CHECK GEAR ORDER", Vector3(3.8, 1.25, -1.3), Vector3(0.7, 0.8, 0.7))
	EchoWorld.cylinder(lever, Vector3.ZERO, 0.07, 0.5, Color("d3b777"))
	EchoWorld.sphere(lever, Vector3(0, 0.28, 0), 0.17, Color("dcbb72"))
	var check_sign := EchoWorld.label(root, Vector3(3.8, 2.05, -1.3), "CHECK GEARS\nClick the gold key", 20, Color("ffe4a3"))
	check_sign.pixel_size = 0.008
	check_sign.no_depth_test = true
	var dial := EchoWorld.cylinder(root, Vector3(1.7, 2.05, -2.8), 0.65, 0.12, Color("e1d4aa"), 32)
	dial.rotation.x = PI / 2
	var rim := EchoWorld.cylinder(root, Vector3(1.7, 2.05, -2.87), 0.72, 0.12, Color("bda269"), 32)
	rim.rotation.x = PI / 2
	for i in range(12):
		var angle := i * TAU / 12
		var tick := EchoWorld.box(root, Vector3(1.7 + sin(angle) * 0.55, 2.05 + cos(angle) * 0.55, -2.72), Vector3(0.025, 0.09, 0.025), Color("665742"))
		tick.rotation.z = -angle
	clock_hand = Node3D.new()
	root.add_child(clock_hand)
	clock_hand.position = Vector3(1.7, 2.05, -2.7)
	EchoWorld.box(clock_hand, Vector3(0, 0.2, 0), Vector3(0.035, 0.45, 0.035), Color("544635"))
	EchoWorld.box(clock_hand, Vector3(0.12, 0, 0), Vector3(0.25, 0.04, 0.04), Color("544635"))
	EchoWorld.box(root, Vector3(1.8, 0.7, -0.72), Vector3(2.1, 0.5, 0.35), Color("493b32"))
	clock_drawer = Node3D.new()
	root.add_child(clock_drawer)
	clock_drawer.position = Vector3(1.8, 0.65, -0.65)
	EchoWorld.box(clock_drawer, Vector3.ZERO, Vector3(1.9, 0.12, 0.7), Color("9a7851"))
	EchoWorld.box(clock_drawer, Vector3(0, 0.16, 0.35), Vector3(2, 0.4, 0.1), Color("775943"))
	EchoWorld.sphere(clock_drawer, Vector3(0, 0.18, 0.44), 0.08, Color("d3b777"))
	EchoWorld.box(root, Vector3(-1.95, 1.1, -0.7), Vector3(2.5, 0.18, 1.3), Color("775943"))
	for i in range(3):
		var color_name: String = ["YELLOW", "RED", "BLUE"][i]
		var loose := _item(root, "workshop", "gear_" + color_name, "Pick up " + color_name.to_lower() + " gear", Vector3(-2.75 + i * 0.8, 1.25, -0.7), Vector3(0.7, 0.35, 0.7))
		_make_gear(loose)
		_tint_gear(loose, color_name)
		gear_tray[color_name] = loose
		EchoWorld.label(root, loose.position + Vector3(0, 0.15, 0.5), color_name, 18, Color("ffe4a3"))
	held_model = WorldPuzzleItem.new()
	add_child(held_model)
	_make_gear(held_model)
	held_model.hide()

func _make_gear(item: WorldPuzzleItem) -> void:
	item.parts.append(EchoWorld.cylinder(item, Vector3.ZERO, 0.3, 0.12, Color.WHITE, 16))
	for i in range(10):
		var angle := i * TAU / 10
		var tooth := EchoWorld.box(item, Vector3(sin(angle) * 0.31, 0, cos(angle) * 0.31), Vector3(0.14, 0.13, 0.14), Color.WHITE)
		tooth.rotation.y = angle
		item.parts.append(tooth)
	EchoWorld.cylinder(item, Vector3(0, 0.08, 0), 0.08, 0.04, Color("4e4941"), 12)

func _update_gears() -> void:
	for i in range(3):
		var item: WorldPuzzleItem = items.workshop[i]
		item.title = "Socket %d · %s" % [i + 1, "empty" if slots[i].is_empty() else slots[i].to_lower() + " gear"]
		item.nameplate.text = item.title
		socket_gears[i].visible = not slots[i].is_empty()
		if not slots[i].is_empty():
			_tint_gear(socket_gears[i], slots[i])
	for color_name in gear_tray:
		gear_tray[color_name].visible = not color_name in slots and color_name != held_gear
	if is_instance_valid(held_model):
		held_model.visible = not held_gear.is_empty()
		if not held_gear.is_empty():
			_tint_gear(held_model, held_gear)
	if is_instance_valid(focus) and data.get("id", "") == "workshop":
		_set_focus(focus)

func _tint_gear(gear: WorldPuzzleItem, color_name: String) -> void:
	var colors := {"RED": Color("c76451"), "BLUE": Color("628eb4"), "YELLOW": Color("e0bf65")}
	for part in gear.parts:
		part.material_override = EchoWorld.material(colors[color_name])

func action_name() -> String:
	if not is_instance_valid(focus):
		return "Point at an object · Q / T to select"
	if data.id == "workshop" and focus.item_id.begins_with("slot_"):
		var index := int(focus.item_id.trim_prefix("slot_"))
		if not held_gear.is_empty():
			return "Place " + held_gear.to_lower() + " gear in socket " + str(index + 1)
		return "Choose a gear from the tray" if slots[index].is_empty() else "Pick up " + slots[index].to_lower() + " gear"
	return focus.title.split("\n")[0]

func _market(root: Node3D) -> void:
	var package := _item(root, "market", "parcel", "Pick up Nia's parcel", Vector3(0, 0.65, 0.4), Vector3(0.8, 0.7, 0.7))
	_parcel_model(package)
	for choice in [{"id": "forest", "at": Vector3(-5, 0, -6), "name": "Tree cottage", "roof": Color("547a65")}, {"id": "hill", "at": Vector3(11, 0, -10), "name": "Hilltop cottage", "roof": Color("9c795b")}, {"id": "bridge_river", "at": Vector3(10, 0, -4), "name": "Riverside cottage", "roof": Color("6a8d95")}]:
		var at: Vector3 = choice.at
		if choice.id != "bridge_river":
			EchoWorld.box(root, at + Vector3(0, 1, 0), Vector3(2.5, 2, 2.3), Color("d6c7a3"))
			for side in [-1, 1]:
				var roof := EchoWorld.box(root, at + Vector3(side * 0.7, 2.2, 0), Vector3(1.7, 0.16, 2.8), choice.roof)
				roof.rotation.z = side * -0.45
		var mailbox := _item(root, "market", choice.id, "Deliver parcel · " + choice.name, at + Vector3(0, 0.7, 1.65), Vector3(1.1, 1.2, 0.9))
		mailbox.reach = 3.2
		EchoWorld.box(mailbox, Vector3.ZERO, Vector3(0.7, 0.55, 0.6), Color("8d6e4d"))
		EchoWorld.box(mailbox, Vector3(0, 0.03, 0.32), Vector3(0.45, 0.04, 0.04), Color("dfc586"))
		EchoWorld.label(root, at + Vector3(0, 3, 0), choice.name, 23)
	# Real planks and rails make the crossing visible from the delivery path.
	for j in range(9):
		EchoWorld.box(root, Vector3(5.1 + j * 0.48, 0.16, 1), Vector3(0.44, 0.18, 2), Color("9b7953"))
	for z in [0.1, 1.9]:
		EchoWorld.box(root, Vector3(7, 0.8, z), Vector3(4.4, 0.12, 0.12), Color("826748"))
		for x in [5.1, 7, 9]:
			EchoWorld.box(root, Vector3(x, 0.5, z), Vector3(0.1, 1, 0.1), Color("826748"))

func _parcel_model(root: Node3D) -> void:
	EchoWorld.box(root, Vector3.ZERO, Vector3(0.58, 0.5, 0.48), Color("bd9567"))
	EchoWorld.box(root, Vector3.ZERO, Vector3(0.08, 0.52, 0.5), Color("e7d3a0"))
	EchoWorld.box(root, Vector3(0, 0, 0.25), Vector3(0.6, 0.06, 0.03), Color("e7d3a0"))

func _temple(root: Node3D) -> void:
	for i in range(3):
		var symbol: String = ["STAR", "SUN", "WAVE"][i]
		var item := _item(root, "temple", symbol, "Press " + symbol, Vector3(-2.4 + i * 2.4, 1.95, -2.15), Vector3(1.0, 1.0, 1.4))
		EchoWorld.cylinder(item, Vector3(0, -0.8, 0), 0.48, 2.1, Color("81918c"), 8)
		EchoWorld.cylinder(item, Vector3(0, 0.45, 0), 0.56, 0.2, Color("b1b8a1"), 8)
		var button := EchoWorld.cylinder(item, Vector3(0, 0, 0.55), 0.4, 0.12, Color("758c89"), 12)
		button.rotation.x = PI / 2
		item.parts.append(button)
		var carving := Node3D.new()
		item.add_child(carving)
		carving.position.z = 0.55
		carving.rotation.x = PI / 2
		_rune(carving, symbol)
		EchoWorld.label(root, item.position + Vector3(0, 0.9, 0), symbol, 21, Color("ead7a6"))
	for side in [-1, 1]:
		var lid := Node3D.new()
		root.add_child(lid)
		lid.position = Vector3(side * 0.8, 1.4, -0.9)
		EchoWorld.box(lid, Vector3.ZERO, Vector3(1.6, 0.2, 1.7), Color("b5b59c"))
		EchoWorld.box(lid, Vector3(0, 0.12, 0), Vector3(0.9, 0.035, 0.9), Color("d3bb80"))
		altar_lids.append(lid)

func _rune(item: Node3D, symbol: String) -> void:
	var gold := Color("ddc28b")
	if symbol == "SUN":
		EchoWorld.cylinder(item, Vector3(0, 0.09, 0), 0.12, 0.025, gold, 16)
		for i in range(8):
			var angle := i * TAU / 8
			var ray := EchoWorld.box(item, Vector3(sin(angle) * 0.21, 0.09, cos(angle) * 0.21), Vector3(0.035, 0.025, 0.09), gold)
			ray.rotation.y = angle
	elif symbol == "STAR":
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in range(10):
			surface.add_vertex(Vector3(0, 0.09, 0))
			for step in [i, i + 1]:
				var radius := 0.25 if step % 2 == 0 else 0.11
				var angle: float = step * TAU / 10
				surface.add_vertex(Vector3(sin(angle) * radius, 0.09, cos(angle) * radius))
		surface.generate_normals()
		var star := MeshInstance3D.new()
		star.mesh = surface.commit()
		star.material_override = EchoWorld.material(gold)
		star.material_override.cull_mode = BaseMaterial3D.CULL_DISABLED
		item.add_child(star)
	else:
		for row in [-1, 0, 1]:
			for i in range(13):
				var wave := EchoWorld.box(item, Vector3((i - 6) * 0.035, 0.09, row * 0.12 + sin(i * 0.5) * 0.04), Vector3(0.043, 0.025, 0.028), gold)
				wave.rotation.y = -cos(i * 0.5) * 0.4

func open(stage: Dictionary) -> void:
	data = stage
	if puzzle == null or puzzle.definition != data.puzzle:
		puzzle = EchoPuzzle.new(data.puzzle)
	active = true
	keyboard_focus = false
	_set_focus(null)
	previous_position = player.global_position
	ui.close_modal()
	ui.task_panel.show()
	ui.task_title.text = {"library": "SEARCH THE BOOKSHELVES", "workshop": "REPAIR MILO'S CLOCK", "market": "DELIVER NIA'S PARCEL", "temple": "AWAKEN THE ALTAR"}[data.id]
	ui.objective.text = ui.task_title.text.capitalize()
	feedback.text = {"library": "Inspect six real books. Look for the markings and shelf positions from Elara's letter.", "workshop": "Pick up a coloured gear from the left tray, then click a numbered socket to place it. Pick up or swap gears to try another order. The correct order starts the clock.", "market": "Pick up the parcel, cross the wooden bridge, then find the right cottage.", "temple": "Press the large carved symbols on the three pillars in the order from Ori's letter. Each correct symbol lights up."}[data.id]
	hint_label.hide()
	ui.task_action.visible = data.id in ["workshop", "market"]
	ui.task_action.text = "Check gear order"
	ui.task_action.disabled = false
	if data.id == "market":
		market_step = -1
		_update_market_guidance()
	elif data.id == "workshop":
		_update_gears()
	character_line.emit("task")

func focus_by_id(id: String) -> bool:
	if not active:
		return false
	for item in items[data.id]:
		if item.item_id == id and item.visible:
			_set_focus(item)
			keyboard_focus = true
			return true
	return false

func _set_focus(item: WorldPuzzleItem) -> void:
	if is_instance_valid(focus):
		focus.set_focused(false)
	focus = item
	if is_instance_valid(focus):
		focus.set_focused(true)

func cycle(direction: int) -> void:
	if not active:
		return
	var available: Array = items[data.id].filter(func(item): return item.visible)
	if available.is_empty():
		return
	var index := available.find(focus)
	_set_focus(available[posmod(index + direction, available.size())])
	keyboard_focus = true

func _pick(screen: Vector2) -> WorldPuzzleItem:
	var camera := get_viewport().get_camera_3d()
	var from := camera.project_ray_origin(screen)
	var query := PhysicsRayQueryParameters3D.create(from, from + camera.project_ray_normal(screen) * 30, 3, [player.get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return null
	var object: CollisionObject3D = hit.collider
	if not object.has_meta("puzzle_item"):
		return null
	var item = object.get_meta("puzzle_item")
	if item is WorldPuzzleItem and item.stage_id == data.id and item.visible:
		return item
	return null

func _unhandled_input(event: InputEvent) -> void:
	if not active or GameState.ui_locked or GameState.stopped:
		return
	if event is InputEventMouseMotion:
		keyboard_focus = false
	if GameState.inspecting and (event.is_action_pressed("move_forward") or event.is_action_pressed("move_back") or event.is_action_pressed("move_left") or event.is_action_pressed("move_right")):
		end_inspection()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_set_focus(_pick(event.position))
		interact()
	elif event.is_action_pressed("inspect"):
		toggle_inspection()
	elif event.is_action_pressed("previous_item"):
		cycle(-1)
	elif event.is_action_pressed("next_item"):
		cycle(1)

func _process(delta: float) -> void:
	if GameState.paused or GameState.stopped:
		return
	if clock_running:
		clock_hand.rotation.z -= delta * 0.8
		clock_drawer.position.z = move_toward(clock_drawer.position.z, 0.1, delta * 0.8)
		for gear in socket_gears:
			gear.rotation.y += delta * 0.8
	if completed_visuals.has("temple"):
		altar_open = move_toward(altar_open, 1.0, delta)
		altar_lids[0].position.x = -0.8 - smoothstep(0, 1, altar_open) * 1.4
		altar_lids[1].position.x = 0.8 + smoothstep(0, 1, altar_open) * 1.4
	if is_instance_valid(held_model) and held_model.visible:
		var camera := get_viewport().get_camera_3d()
		held_model.global_position = camera.project_position(get_viewport().get_visible_rect().size * Vector2(0.72, 0.6), 2.2)
		held_model.rotation.y += delta
	if not active or GameState.ui_locked:
		return
	ui.task_panel.visible = not ui.veil.visible and (not data.id in ["library", "temple"] or not GameState.inspecting or hint_label.visible or Time.get_ticks_msec() / 1000.0 < feedback_until)
	ui.task_dismiss.visible = hint_label.visible or Time.get_ticks_msec() / 1000.0 < feedback_until
	var show_feedback: bool = not hint_label.visible and (data.id != "workshop" or not GameState.inspecting)
	if feedback.visible != show_feedback:
		feedback.visible = show_feedback
		ui._fit_hud_cards.call_deferred()
	if not keyboard_focus:
		var mouse := get_viewport().get_mouse_position()
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			mouse = get_viewport().get_visible_rect().size * 0.5
		var pointed := _pick(mouse)
		if pointed == null and data.id == "market":
			pointed = _recommended_delivery_item()
		_set_focus(pointed)
	if data.id == "market" and carrying and not crossed_bridge:
		var now := player.global_position
		if previous_position.x < 22.0 and now.x >= 22.0:
			var weight := (22.0 - previous_position.x) / maxf(now.x - previous_position.x, 0.001)
			var crossing_z := lerpf(previous_position.z, now.z, weight)
			if absf(crossing_z + 18.0) < 1.15:
				crossed_bridge = true
				feedback.text = "Bridge crossed. Find the cottage beside the river."
		previous_position = now
		if not crossed_bridge and now.x > 22.2 and absf(now.z + 18) > 1.2:
			returning_to_bridge = true
		if returning_to_bridge and now.x < 21:
			returning_to_bridge = false
	if data.id == "market":
		_update_market_guidance()
		_update_route(delta)
	else:
		destination_marker.hide()
		for marker in route_markers:
			marker.hide()

func interact() -> void:
	if not active or GameState.ui_locked or GameState.stopped:
		return
	if is_instance_valid(focus) and not focus.visible:
		_set_focus(null)
	if data.id == "market" and not is_instance_valid(focus):
		_set_focus(_recommended_delivery_item())
	if not is_instance_valid(focus):
		if data.id == "market":
			if GameState.inspecting:
				end_inspection()
			feedback.text = "Use WASD to carry the parcel across the wooden bridge. Follow the gold ground markers."
			return
		feedback.text = "Point at an object, or use Q / T to select. Press F for a closer 3D view."
		return
	if player.global_position.distance_to(focus.global_position) > focus.reach:
		if data.id == "market" and GameState.inspecting:
			end_inspection()
			feedback.text = "Walk up to the delivery box with WASD, then press E. Follow the gold markers."
		else:
			feedback.text = "Move closer to " + focus.title.to_lower() + "."
		return
	focus.press_feedback()
	var id := focus.item_id
	match data.id:
		"library":
			_attempt(id)
		"workshop":
			if id.begins_with("gear_"):
				held_gear = id.trim_prefix("gear_")
			elif id.begins_with("slot_"):
				var i := int(id.trim_prefix("slot_"))
				var previous := slots[i]
				slots[i] = held_gear
				held_gear = previous
			else:
				_attempt(Array(slots))
				return
			_update_gears()
			feedback.text = ("Holding %s gear. Choose a numbered socket." % held_gear.to_lower()) if not held_gear.is_empty() else "Gear placed. Pick up another gear, or move a placed gear to change the order."
			if Array(slots) == data.puzzle.solution:
				_attempt(Array(slots))
		"market":
			if id == "parcel":
				if not carrying:
					carrying = true
					focus.hide()
					parcel = Node3D.new()
					player.model.add_child(parcel)
					parcel.position = Vector3(0, 1.25, 0.62)
					_parcel_model(parcel)
					feedback.text = "Parcel collected. Follow the wooden bridge to the riverside cottage."
					previous_position = player.global_position
					if GameState.inspecting:
						end_inspection()
					_update_market_guidance()
			elif not carrying:
				feedback.text = "Collect Nia's parcel at the market first."
			elif id == "bridge_river" and not crossed_bridge:
				feedback.text = "The letter says to cross the wooden bridge first. The parcel is still safe."
			else:
				_attempt(id)
		"temple":
			_symbol(id)

func _attempt(answer: Variant) -> void:
	if not active or GameState.stopped:
		return
	var correct := puzzle.attempt(answer)
	ApiClient.emit_event("PUZZLE_ATTEMPTED", {"puzzle_id": data.id, "correct": correct})
	if correct:
		_success()
	else:
		feedback.text = "Not quite; check the letter again. Nothing is lost, so try another idea."
		feedback_until = Time.get_ticks_msec() / 1000.0 + 4.0
		character_line.emit("wrong")

func _symbol(value: String) -> void:
	if not active or GameState.stopped:
		return
	var result := puzzle.press(value)
	ApiClient.emit_event("PUZZLE_ATTEMPTED", {"puzzle_id": data.id, "correct": result >= 0, "complete": result == 1})
	for item in items.temple:
		item.parts[0].material_override = EchoWorld.material(Color("cbb573") if item.item_id in puzzle.sequence else Color("758c89"), item.item_id in puzzle.sequence)
	feedback.text = "Symbols: " + (" → ".join(puzzle.sequence) if result >= 0 else "Not quite. The altar is ready for a fresh try.")
	feedback_until = Time.get_ticks_msec() / 1000.0 + 4.0
	if result == 1:
		_success()
	elif result == -1:
		character_line.emit("wrong")

func _success() -> void:
	complete_visuals()
	solved.emit()

func complete_visuals() -> void:
	cancel()
	if data.is_empty() or completed_visuals.has(data.id):
		return
	completed_visuals[data.id] = true
	match data.id:
		"library":
			var book: WorldPuzzleItem = items.library[5]
			create_tween().tween_property(book, "position", book.position + Vector3(0, 0, 0.65), 0.6)
		"workshop":
			clock_running = true
			slots.assign(["RED", "BLUE", "YELLOW"])
			held_gear = ""
			_update_gears()
		"market":
			if is_instance_valid(parcel):
				parcel.queue_free()
				parcel = null
			var delivered := Node3D.new()
			items.market[3].add_child(delivered)
			delivered.position = Vector3(0, 0.6, 0)
			_parcel_model(delivered)

func hint() -> void:
	if not active:
		return
	hint_label.text = EchoPuzzle.next_hint(data.id)
	hint_label.show()
	ApiClient.emit_event("HINT_REQUESTED", {"level": GameState.hints[data.id]})

func dismiss_guidance() -> void:
	hint_label.hide()
	feedback_until = 0
	ui.task_dismiss.hide()
	if data.id == "market":
		market_step = -1
		_update_market_guidance()
	else:
		feedback.text = "Choose a highlighted object with the mouse or Q / T. Press E to use it, or F for a closer view."
	ui._fit_hud_cards.call_deferred()

func toggle_inspection() -> void:
	if not active or GameState.ui_locked:
		return
	if GameState.inspecting:
		end_inspection()
		return
	if player.global_position.distance_to(waypoint()) > 9 and data.id != "market":
		feedback.text = "Walk back to the marked puzzle, then choose Inspect up close."
		return
	GameState.inspecting = true
	inspection.fov = 74 if data.id == "workshop" else 62
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var base: Vector3 = roots[data.id].global_position
	var eye: Vector3 = {"library": Vector3(0, 1.9, 3.15), "workshop": Vector3(0.2, 3.1, 1.8), "market": Vector3(8, 15, 10), "temple": Vector3(0, 3.6, 4.7)}[data.id]
	var target: Vector3 = {"library": Vector3(0, 1.45, -2.15), "workshop": Vector3(0.2, 1.2, -1.2), "market": Vector3(6, 0, -3), "temple": Vector3(0, 1.65, -1.7)}[data.id]
	inspection.position = base + eye
	inspection.look_at(base + target)
	var final := inspection.transform
	inspection.global_transform = get_viewport().get_camera_3d().global_transform
	inspection.current = true
	create_tween().tween_property(inspection, "transform", final, 0.45).set_trans(Tween.TRANS_SINE)

func end_inspection() -> void:
	GameState.inspecting = false
	player.camera.current = true

func waypoint() -> Vector3:
	if not active:
		return world.targets[GameState.stage_index].global_position
	if data.id == "market":
		if not carrying:
			return items.market[0].global_position
		if not crossed_bridge:
			if returning_to_bridge:
				return Vector3(25, 0, -18) if player.global_position.x > 22 and absf(player.global_position.z + 18) > 1.2 else Vector3(20.2, 0, -18)
			return Vector3(20.2, 0, -18) if player.global_position.x < 21 and player.global_position.distance_to(Vector3(20.2, 0, -18)) > 1.4 else Vector3(25, 0, -18)
		return items.market[3].global_position
	return roots[data.id].global_position + Vector3(0, 0, 1)

func show_gift(fragment: int) -> void:
	if is_instance_valid(gift):
		gift.queue_free()
	end_inspection()
	gift = WorldGift.new()
	gift.fragment = fragment
	world.add_child(gift)
	var forward := -player.camera.global_transform.basis.z
	forward.y = 0
	var right := player.camera.global_transform.basis.x
	right.y = 0
	gift.global_position = player.global_position + forward.normalized() * 1.5 + right.normalized() * 1.65 + Vector3(0, 0.3, 0)

func cancel() -> void:
	active = false
	if is_instance_valid(held_model):
		held_model.hide()
	end_inspection()
	_set_focus(null)
	ui.task_panel.hide()
	ui.task_action.hide()
	destination_marker.hide()
	for marker in route_markers:
		marker.hide()

func primary_action() -> void:
	if not active or GameState.ui_locked or GameState.paused or GameState.stopped:
		return
	if data.id == "workshop":
		focus_by_id("test_clock")
		interact()
	elif data.id == "market":
		if carrying and not crossed_bridge:
			end_inspection()
			feedback.text = "Walk along the gold markers with WASD. Carry the parcel across the wooden bridge."
		else:
			_set_focus(_recommended_delivery_item())
			interact()

func _recommended_delivery_item() -> WorldPuzzleItem:
	if not carrying:
		return items.market[0]
	var best: WorldPuzzleItem
	var distance := INF
	for item in items.market:
		if item.item_id == "parcel":
			continue
		var next_distance := player.global_position.distance_to(item.global_position)
		if next_distance < distance and next_distance <= item.reach:
			distance = next_distance
			best = item
	return best

func market_action_available() -> bool:
	var item := _recommended_delivery_item()
	return is_instance_valid(item) and player.global_position.distance_to(item.global_position) <= item.reach

func market_prompt() -> String:
	if not carrying:
		return "[ E ]  Pick up Nia's parcel" if market_action_available() else "Walk to the marked parcel"
	if not crossed_bridge:
		return "[ F ]  Return to walking" if GameState.inspecting else "[ WASD ]  Carry parcel across bridge"
	return "[ E ]  Deliver parcel to this box" if market_action_available() else "Walk up to a cottage's delivery box"

func _update_market_guidance() -> void:
	var step := 0 if not carrying else (1 if not crossed_bridge else 2)
	ui.task_title.text = "DELIVERY · STEP %d OF 3" % (step + 1)
	ui.objective.text = ["1. Pick up Nia's parcel", "2. Walk across the wooden bridge", "3. Deliver to the riverside cottage"][step]
	if step != market_step:
		feedback.text = ["Pick up the ribboned parcel beside Nia. Click the button below or press E.", "Parcel collected! Follow the gold ground markers and WALK across the wooden bridge with WASD.", "Bridge crossed! Walk up to the DELIVERY BOX outside the cottage from the letter, then press E."][step]
		market_step = step
	if step == 0:
		ui.task_action.show()
		ui.task_action.text = "Pick up parcel  [E]"
		ui.task_action.disabled = not market_action_available()
	elif step == 1:
		ui.task_action.visible = GameState.inspecting
		ui.task_action.text = "Return to walking  [F]"
		ui.task_action.disabled = false
	else:
		ui.task_action.show()
		ui.task_action.text = "Deliver parcel  [E]" if market_action_available() else "Move closer to a delivery box"
		ui.task_action.disabled = not market_action_available()

func waypoint_name() -> String:
	if data.id == "market":
		if carrying and not crossed_bridge and returning_to_bridge:
			return "Return to the bridge's market side"
		return "Pick up parcel" if not carrying else ("Cross wooden bridge" if not crossed_bridge else "Riverside delivery box")
	return data.name

func _make_guidance() -> void:
	for i in range(10):
		var marker := EchoWorld.cylinder(self, Vector3.ZERO, 0.16, 0.03, Color("efd186"), 3)
		marker.material_override = EchoWorld.material(Color("efd186"), true)
		EchoWorld.cylinder(marker, Vector3(0, -0.005, 0), 0.22, 0.01, Color("365b60"), 3)
		marker.hide()
		route_markers.append(marker)
	destination_marker = Node3D.new()
	add_child(destination_marker)
	for side in [-1, 1]:
		var crystal := EchoWorld.cylinder(destination_marker, Vector3(0, side * 0.15, 0), 0.22, 0.3, Color("ffe29a"), 4)
		if side == 1:
			(crystal.mesh as CylinderMesh).top_radius = 0
		else:
			(crystal.mesh as CylinderMesh).bottom_radius = 0
		crystal.material_override = EchoWorld.material(Color("ffe29a"), true)
	destination_label = EchoWorld.label(destination_marker, Vector3(0, 0.7, 0), "", 24, Color("ffe8ae"))
	destination_label.no_depth_test = true
	destination_marker.hide()

func _update_route(delta: float) -> void:
	var target := waypoint()
	_draw_route(target, ["PICK UP PARCEL", "CROSS WOODEN BRIDGE", "DELIVERY BOX"][market_step], delta)

func guide_walk(target: Vector3, delta: float, enabled: bool) -> void:
	if not enabled:
		destination_marker.hide()
		for marker in route_markers:
			marker.hide()
		return
	_draw_route(target, "FOLLOW THE PATH", delta)

func _draw_route(target: Vector3, caption: String, delta: float) -> void:
	guide_time += delta
	destination_marker.visible = player.global_position.distance_to(target) > 2
	destination_marker.position = target + Vector3(0, 2.3 + sin(guide_time * 2) * 0.12, 0)
	destination_marker.rotation.y = guide_time * 0.6
	destination_label.text = caption
	var from := player.global_position
	var direction := target - from
	for i in range(route_markers.size()):
		var marker := route_markers[i]
		marker.show()
		marker.position = from.lerp(target, float(i + 1) / (route_markers.size() + 1))
		marker.position.y = 0.3 if marker.position.x > 20 and marker.position.x < 25 and absf(marker.position.z + 18) < 1.2 else 0.17
		marker.rotation.y = atan2(direction.x, direction.z)
