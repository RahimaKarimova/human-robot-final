class_name TreasureCave
extends Node3D
## Opaque sealed chamber. Treasure is not rendered until the unlocked cave is entered.
var player_target: Explorer
var door_point: Node3D
var chest_point: Node3D
var chest_lid: Node3D
var treasure_contents: Node3D
var revealed_reward: Node3D
var roof_shell: Node3D
var barrier_shape: CollisionShape3D
var left_door: Node3D
var right_door: Node3D
var sockets: Dictionary = {}
var socket_models: Dictionary = {}
var door_progress: float = 0.0
var opening: bool = false
var chest_opened: bool = false
var elapsed: float = 0.0
var door_instruction: Label3D

func _ready() -> void:
	door_point = Node3D.new()
	door_point.position = Vector3(0, 0, 4)
	add_child(door_point)
	chest_point = Node3D.new()
	chest_point.position = Vector3(0, 0, -8)
	add_child(chest_point)
	_build_shell()
	_build_door()
	_build_treasure()
	EventBus.progress_changed.connect(_refresh_slots)
	_refresh_slots()

func _build_shell() -> void:
	var rock := Color("647a7c")
	EchoWorld.box(self, Vector3(0, -0.03, -4.5), Vector3(7, 0.15, 14), Color("596e71"))
	for side in [-1, 1]:
		EchoWorld.box(self, Vector3(side * 3.5, 2.25, -4.5), Vector3(1, 4.5, 14), rock, true)
		EchoWorld.box(self, Vector3(side * 3.2, 2.25, 2), Vector3(0.9, 4.5, 1), rock, true)
		var boulder := EchoWorld.sphere(self, Vector3(side * 4.1, 2.0, 0.5), 2.9, rock)
		boulder.scale = Vector3(0.8, 1.0, 0.7)
		for z in [-1, -5, -9]:
			EchoWorld.box(self, Vector3(side * 2.85, 1.2, z), Vector3(0.18, 2.4, 0.3), rock.lightened(0.12))
			var light := OmniLight3D.new()
			light.position = Vector3(side * 2.6, 2.2, z)
			light.light_color = Color("f6ca82")
			light.light_energy = 1.1
			light.omni_range = 5.5
			add_child(light)
			var lantern := EchoWorld.sphere(self, light.position, 0.14, Color("f7d99b"))
			lantern.material_override = EchoWorld.material(Color("f7d99b"), true)
	EchoWorld.box(self, Vector3(0, 2.25, -11.2), Vector3(8, 4.5, 0.8), rock, true)
	EchoWorld.box(self, Vector3(0, 4.7, 1.8), Vector3(8, 1.1, 1.8), rock)
	roof_shell = Node3D.new()
	add_child(roof_shell)
	EchoWorld.box(roof_shell, Vector3(0, 4.75, -4.5), Vector3(8, 1.1, 13), rock)
	for z in [-1, -5, -9]:
		var crown := EchoWorld.sphere(roof_shell, Vector3(0, 4.85, z), 3.5, rock.lightened(0.06))
		crown.scale = Vector3(1.1, 0.6, 0.9)
	EchoWorld.label(self, Vector3(0, 5.45, 2), "THE FOUR JEWEL SEALS", 28, Color("e8d39e"))

func _build_door() -> void:
	var barrier := StaticBody3D.new()
	barrier.position = Vector3(0, 2.15, 2)
	add_child(barrier)
	barrier_shape = CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(5.8, 4.5, 0.7)
	barrier_shape.shape = shape
	barrier.add_child(barrier_shape)
	for side in [-1, 1]:
		var leaf := Node3D.new()
		add_child(leaf)
		leaf.position = Vector3(side * 1.4, 0, 2)
		EchoWorld.box(leaf, Vector3(0, 2.1, 0), Vector3(2.8, 4.2, 0.5), Color("334c57"))
		for x in [-1.2, 1.2]:
			EchoWorld.box(leaf, Vector3(x, 2.1, 0.28), Vector3(0.1, 3.9, 0.05), Color("c6ad76"))
		for y in [0.25, 3.95]:
			EchoWorld.box(leaf, Vector3(0, y, 0.28), Vector3(2.5, 0.1, 0.05), Color("c6ad76"))
		if side < 0:
			left_door = leaf
		else:
			right_door = leaf
	for i in range(4):
		var gem: Dictionary = Content.gems[i]
		var leaf: Node3D = left_door if i < 2 else right_door
		var socket := Node3D.new()
		leaf.add_child(socket)
		socket.position = Vector3((-0.55 if i % 2 == 0 else 0.55), 2.4, 0.35)
		sockets[gem.id] = socket
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.24
		torus.outer_radius = 0.34
		ring.mesh = torus
		ring.material_override = EchoWorld.material(Color(gem.color).darkened(0.28))
		ring.rotation.x = PI / 2
		socket.add_child(ring)
		var backing := EchoWorld.cylinder(socket, Vector3(0, 0, -0.02), 0.25, 0.04, Color("172d39"), 8)
		backing.rotation.x = PI / 2
		var label := EchoWorld.label(socket, Vector3(0, -0.65, 0.08), gem.name, 20, Color(gem.color).lightened(0.2))
		label.pixel_size = 0.007
		var body := StaticBody3D.new()
		body.collision_layer = 2
		body.collision_mask = 0
		body.set_meta("cave_gem", gem.id)
		socket.add_child(body)
		var collider := CollisionShape3D.new()
		var hit_shape := SphereShape3D.new()
		hit_shape.radius = 0.39
		collider.shape = hit_shape
		body.add_child(collider)
	door_instruction = EchoWorld.label(self, Vector3(0, 0.9, 2.45), "Place your four precious gems\nE · Insert the next gem", 22, Color("e8d7ad"))

func _build_treasure() -> void:
	treasure_contents = Node3D.new()
	add_child(treasure_contents)
	treasure_contents.position = Vector3(0, 0, -8)
	treasure_contents.hide()
	EchoWorld.box(treasure_contents, Vector3(0, 0.2, 0), Vector3(3.2, 0.4, 2.4), Color("86938b"))
	EchoWorld.box(treasure_contents, Vector3(0, 0.8, 0), Vector3(2.4, 0.9, 1.5), Color("77523b"))
	for x in [-0.8, 0.8]:
		EchoWorld.box(treasure_contents, Vector3(x, 0.8, 0.78), Vector3(0.14, 0.9, 0.08), Color("d8b66d"))
	EchoWorld.box(treasure_contents, Vector3(0, 0.95, 0.8), Vector3(0.25, 0.3, 0.1), Color("e5c57f"))
	chest_lid = Node3D.new()
	chest_lid.position = Vector3(0, 1.28, -0.75)
	treasure_contents.add_child(chest_lid)
	EchoWorld.box(chest_lid, Vector3(0, 0.08, 0.75), Vector3(2.55, 0.3, 1.6), Color("a67e47"))
	for x in [-0.8, 0.8]:
		EchoWorld.box(chest_lid, Vector3(x, 0.25, 0.75), Vector3(0.14, 0.06, 1.6), Color("d8b66d"))
	revealed_reward = Node3D.new()
	treasure_contents.add_child(revealed_reward)
	revealed_reward.hide()
	for i in range(14):
		var angle := i * 2.4
		var coin := EchoWorld.cylinder(revealed_reward, Vector3(sin(angle) * 0.7, 1.25 + (i % 3) * 0.035, cos(angle) * 0.4), 0.16, 0.045, Color("efd18a"), 12)
		coin.rotation.z = sin(i) * 0.3
	var jewel := GemStone.new()
	jewel.gem_id = "emerald"
	jewel.position = Vector3(0, 1.7, 0)
	jewel.scale = Vector3.ONE * 1.6
	revealed_reward.add_child(jewel)

func _refresh_slots() -> void:
	for gem in Content.gems:
		if GameState.socketed_gems.has(gem.id) and not socket_models.has(gem.id):
			var stone := GemStone.new()
			stone.gem_id = gem.id
			stone.position.z = 0.13
			stone.rotation.x = PI / 2
			stone.scale = Vector3.ONE * 0.8
			sockets[gem.id].add_child(stone)
			socket_models[gem.id] = stone
	if GameState.socketed_gems.size() == 4 and not GameState.cave_open:
		opening = true
		door_instruction.text = "The four jewels awaken the seal"

func next_gem() -> Dictionary:
	for gem in Content.gems:
		if not GameState.socketed_gems.has(gem.id):
			return gem
	return {}

func insert_next() -> bool:
	var gem := next_gem()
	return false if gem.is_empty() else QuestManager.insert_cave_gem(gem.id)

func _unhandled_input(event: InputEvent) -> void:
	if GameState.stage_index != 4 or GameState.ui_locked or GameState.stopped or not is_instance_valid(player_target):
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and player_target.global_position.distance_to(door_point.global_position) < 4:
		var camera := get_viewport().get_camera_3d()
		var origin := camera.project_ray_origin(event.position)
		var query := PhysicsRayQueryParameters3D.create(origin, origin + camera.project_ray_normal(event.position) * 20, 3, [player_target.get_rid()])
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty() and hit.collider.has_meta("cave_gem"):
			QuestManager.insert_cave_gem(str(hit.collider.get_meta("cave_gem")))

func _process(delta: float) -> void:
	if GameState.paused or GameState.stopped:
		return
	elapsed += delta
	if opening and not GameState.cave_open:
		door_progress = minf(door_progress + delta / 1.5, 1)
		var weight := smoothstep(0, 1, door_progress)
		left_door.position.x = -1.4 - weight * 3
		right_door.position.x = 1.4 + weight * 3
		if door_progress >= 1:
			GameState.cave_open = true
			door_instruction.text = "The way is open · walk inside"
			barrier_shape.set_deferred("disabled", true)
			ApiClient.emit_event("CAVE_UNLOCKED")
			EventBus.progress_changed.emit()
	if is_instance_valid(player_target):
		var local := to_local(player_target.global_position)
		var inside := absf(local.x) < 3 and local.z < 1.5 and local.z > -11
		roof_shell.visible = not inside
		if GameState.cave_open and inside and not GameState.cave_entered:
			GameState.cave_entered = true
			treasure_contents.show()
			ApiClient.emit_event("CAVE_ENTERED")
			EventBus.progress_changed.emit()

func open_chest() -> void:
	if chest_opened or not GameState.cave_open or not GameState.cave_entered:
		return
	chest_opened = true
	revealed_reward.show()
	create_tween().tween_property(chest_lid, "rotation_degrees:x", -105.0, 1.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
