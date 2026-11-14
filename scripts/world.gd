class_name EchoWorld
extends Node3D
## Original low-poly scenery generated from Godot meshes; no downloaded assets.
var targets: Array[Node3D] = []
var chest_lid: Node3D
var cave: TreasureCave
var beacon: MeshInstance3D
var sea: MeshInstance3D
var clock: float = 0.0
var npcs: Array[IslandCharacter] = []
var scenery: IslandScenery
var guidance_enabled: bool = false
var guidance_position := Vector3.ZERO
const WOOD := Color("775943")
const CREAM := Color("e8d7af")

func _ready() -> void:
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("488bbc")
	sky_material.sky_horizon_color = Color("b9d7d2")
	sky_material.ground_horizon_color = Color("b9d7d2")
	sky.sky_material = sky_material
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("a7c8dc")
	env.ambient_light_energy = 0.48
	env.fog_enabled = true
	env.fog_light_color = Color("9fc4c8")
	env.fog_density = 0.0018
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.environment = env
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-32, -44, 0)
	sun.light_color = Color("fff0d1")
	sun.light_energy = 0.75
	sun.shadow_enabled = true
	add_child(sun)
	sea = box(self, Vector3(0, -1.5, 0), Vector3(500, 0.3, 500), Color("3e939d"))
	var water_material := ShaderMaterial.new()
	water_material.shader = load("res://assets/water.gdshader")
	sea.material_override = water_material
	var shore := cylinder(self, Vector3(0, -1.0, -5), 44, 1.3, Color("e0ce9d"), 48)
	shore.scale.z = 1.15
	var ground := cylinder(self, Vector3(0, -0.45, -5), 41, 0.9, Color("8ca578"), 48)
	ground.scale.z = 1.15
	var grass_material := ShaderMaterial.new()
	grass_material.shader = load("res://assets/grass.gdshader")
	ground.material_override = grass_material
	_landscape()
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(80, 1, 90)
	floor_shape.shape = shape
	floor_body.position = Vector3(0, -0.5, -5)
	floor_body.add_child(floor_shape)
	add_child(floor_body)
	# A readable continuous path; small garden islands soften the geometry.
	path(Vector3(0, 0, 29), Vector3(-15, 0, 12))
	path(Vector3(-15, 0, 12), Vector3(15, 0, 12))
	path(Vector3(15, 0, 12), Vector3(23, 0, 12))
	path(Vector3(23, 0, 12), Vector3(23, 0, -15))
	path(Vector3(23, 0, -15), Vector3(-15, 0, -15))
	path(Vector3(-15, 0, -15), Vector3(-6, 0, -15))
	path(Vector3(-6, 0, -15), Vector3(0, 0, -30))
	box(self, Vector3(0, 0.04, 28), Vector3(5, 0.15, 8), WOOD)
	for side in [-1, 1]:
		for z in [25, 28, 31]:
			cylinder(self, Vector3(side * 2.5, 0.7, z), 0.14, 1.4, WOOD)
	# A physical dock sign replaces floating welcome text.
	box(self, Vector3(3.8, 1.3, 25), Vector3(1.9, 0.9, 0.16), Color("534b3b"))
	box(self, Vector3(3.8, 0.6, 25), Vector3(0.15, 1.2, 0.15), WOOD)
	label(self, Vector3(3.8, 1.4, 25.12), "LIBRARY  ↖", 20, Color("e9d7a8"))
	for i in range(Content.stages.size()):
		var data: Dictionary = Content.stage(i)
		var location := Node3D.new()
		location.position = Vector3(data.position[0], 0, data.position[2])
		add_child(location)
		if i < 4:
			_build_location(location, i, data)
		else:
			_build_cave(location)
		var target := Node3D.new()
		location.add_child(target)
		target.position = Vector3(0, 0, 4)
		targets.append(target)
		label(location, Vector3(0, 5.8, 0), data.name, 30)
	# Seeded decoration is visual only; puzzles have no random elements.
	var random := RandomNumberGenerator.new()
	random.seed = 2441
	for i in range(110):
		var x := random.randf_range(-35, 35)
		var z := random.randf_range(-42, 32)
		if Vector2(x / 36, (z + 5) / 42).length() > 1.0:
			continue
		var reserved := absf(x) < 5 or (absf(x) < 26 and (absf(z - 10) < 7 or absf(z + 17) < 7)) or (absf(x - 23) < 3 and z > -20 and z < 15)
		if reserved or (Vector2(x + 8, z - 19).length() < 14):
			continue
		_tree(Vector3(x, 0, z), random.randf_range(0.7, 1.4))
	for x in [-7, 7]:
		for z in [-12, 0, 16]:
			_lantern(self, Vector3(x, 0, z))
	# Small rock gardens and flowers give the paths a consistent scale.
	for i in range(40):
		var at := Vector3(random.randf_range(-30, 30), 0.1, random.randf_range(-36, 27))
		if absf(at.x) < 4 or absf(at.z - 8) < 5 or absf(at.z + 19) < 5:
			continue
		var rock := sphere(self, at, random.randf_range(0.25, 0.65), Color("a4ac96"))
		rock.scale = Vector3(1.2, 0.7, 0.9)
		for j in range(3):
			var flower_at := at + Vector3(0.7 + j * 0.25, 0.08, j * 0.2)
			cylinder(self, flower_at, 0.035, 0.3, Color("65805b"), 5)
			sphere(self, flower_at + Vector3(0, 0.2, 0), 0.11, Color("e8c485") if j % 2 else Color("dba5a3"))
	beacon = cylinder(self, Vector3.ZERO, 0.38, 0.08, Color("f5d77e"), 4)
	beacon.material_override = material(Color("f7d97c"), true)
	scenery = IslandScenery.new()
	add_child(scenery)

func _process(delta: float) -> void:
	clock += delta
	if not targets.is_empty():
		var destination := guidance_position if guidance_enabled else targets[mini(GameState.stage_index, 4)].global_position
		beacon.position = destination + Vector3(0, 0.12 + sin(clock * 2) * 0.03, 0)
		beacon.scale = Vector3.ONE * (1.0 + sin(clock * 2) * 0.08)

func _build_location(root: Node3D, index: int, data: Dictionary) -> void:
	var accent := Color(data.accent)
	box(root, Vector3(0, 0.08, 0), Vector3(10, 0.16, 8), Color("c6ba94"))
	if index < 2:
		box(root, Vector3(0, 1.6, -3.2), Vector3(9, 3.2, 0.25), CREAM, true)
		for x in [-4.3, 4.3]:
			box(root, Vector3(x, 1.6, -0.5), Vector3(0.25, 3.2, 5.5), Color("c5baa0"), true)
			box(root, Vector3(x, 1.6, 3), Vector3(0.28, 3.2, 0.28), WOOD)
			for z in [-3.1, -0.5, 2.1]:
				box(root, Vector3(x, 1.6, z), Vector3(0.32, 3.3, 0.22), WOOD)
			box(root, Vector3(x, 0.25, -0.5), Vector3(0.35, 0.5, 5.7), Color("858d81"))
		# Pitched tiled roofs, exposed rafters and brass trim give each landmark a silhouette.
		var roof_color := Color("335a61") if index == 0 else Color("835846")
		for side in [-1, 1]:
			var roof := box(root, Vector3(side * 2.35, 4.25, -0.8), Vector3(5.3, 0.25, 6.8), roof_color)
			roof.rotation_degrees.z = side * -25
			for line in range(7):
				var shingle := box(root, Vector3(side * 2.35, 4.39, -3.9 + line * 1.02), Vector3(5.3, 0.06, 0.06), roof_color.lightened(0.10))
				shingle.rotation_degrees.z = side * -25
		box(root, Vector3(0, 5.39, -0.8), Vector3(0.2, 0.2, 7), Color("d6bc7e"))
		_gable(root, 2.5, CREAM)
		box(root, Vector3(0, 3.22, 2.6), Vector3(9.5, 0.2, 0.2), WOOD)
		box(root, Vector3(0, 3.74, 2.65), Vector3(0.14, 1.0, 0.16), WOOD)
		for x in [-2.6, 2.6]:
			box(root, Vector3(x, 3.65, 2.65), Vector3(0.9, 0.55, 0.12), Color("9cc4c3"))
			box(root, Vector3(x, 3.65, 2.75), Vector3(0.06, 0.55, 0.1), WOOD)
		box(root, Vector3(3, 4.8, -2.6), Vector3(0.8, 2.3, 0.8), Color("8c8b79"))
		for j in range(4):
			box(root, Vector3(-4.9, 0.14, -2.5 + j * 1.1), Vector3(0.6, 0.28, 0.8), Color("8d9584"))
	elif index == 2:
		for x in [-3.2, 3.2]:
			box(root, Vector3(x, 0.6, -0.8), Vector3(2.8, 1.2, 2), WOOD, true)
			box(root, Vector3(x, 2.7, -0.8), Vector3(3.2, 0.2, 2.6), accent)
			for stripe in range(5):
				box(root, Vector3(x - 1.28 + stripe * 0.64, 2.83, -0.8), Vector3(0.32, 0.1, 2.7), Color("eee0b8"))
			box(root, Vector3(x, 2.5, 0.5), Vector3(3.2, 0.55, 0.12), accent)
			for dx in [-1.25, 1.25]:
				box(root, Vector3(x + dx, 1.5, -0.8), Vector3(0.12, 2.8, 0.12), WOOD)
			for dx in [-0.8, 0, 0.8]:
				cylinder(root, Vector3(x + dx, 1.4, -0.8), 0.3, 0.4, Color("d8a14f"), 8)
		# A small visible river and wooden crossing echo the route diagram.
		box(root, Vector3(7, 0.02, -1), Vector3(1.8, 0.04, 14), Color("4e9ba8"))
		box(root, Vector3(7, 0.15, 1), Vector3(4, 0.2, 2), WOOD)
		box(root, Vector3(10, 0.8, -4), Vector3(2, 1.6, 2), CREAM)
		box(root, Vector3(10, 1.8, -4), Vector3(2.5, 0.4, 2.5), accent)
	else:
		for step in range(3):
			box(root, Vector3(0, 0.08 + step * 0.1, 2.9 - step * 0.45), Vector3(8 - step * 0.4, 0.16, 0.45), Color("a4ad9e"))
		for x in [-3.4, 3.4]:
			for z in [-2, 1]:
				box(root, Vector3(x, 1.6, z), Vector3(0.8, 3.2, 0.8), Color("a9aea3"), true)
				box(root, Vector3(x, 0.3, z), Vector3(1.15, 0.6, 1.15), Color("8e9b8c"))
				box(root, Vector3(x, 3.2, z), Vector3(1.15, 0.35, 1.15), Color("c8c8ad"))
		box(root, Vector3(0, 3.4, -2), Vector3(8, 0.7, 1.4), Color("c2c2ae"))
		_gable(root, -1.3, Color("abb8a2"))
		label(root, Vector3(0, 3.6, -1.2), "SUN   ·   WAVE   ·   STAR", 35, Color("ead7a6"))
		# Hollow altar with a visible interior; sliding lids belong to WorldPuzzles.
		box(root, Vector3(0, 0.55, -0.9), Vector3(3.2, 0.2, 1.7), Color("665e50"))
		for x in [-1.5, 1.5]:
			box(root, Vector3(x, 0.95, -0.9), Vector3(0.2, 0.8, 1.7), Color("9d9f94"), true)
		for z in [-1.65, -0.15]:
			box(root, Vector3(0, 0.95, z), Vector3(3.2, 0.8, 0.2), Color("9d9f94"), true)
	if index == 0:
		for x in [-2.5, 2.2]:
			box(root, Vector3(x, 1.3, -2.7), Vector3(2.5, 2.5, 0.65), Color("513f34"))
			for y in [0.6, 1.55, 2.4]:
				box(root, Vector3(x, y, -2.3), Vector3(2.5, 0.1, 0.9), WOOD)
		cylinder(root, Vector3(3.1, 1.5, -1.1), 0.07, 1, WOOD)
		sphere(root, Vector3(3.1, 2.2, -1.1), 0.48, Color("6caca4"))
	if index == 1:
		box(root, Vector3(1.8, 0.9, -1.4), Vector3(3.7, 0.25, 1.7), WOOD, true)
	_npc(root, Vector3(-1.3, 0, 1.8), accent, data.npc)
	_lantern(root, Vector3(4.8, 0, 3.5))

func _build_cave(root: Node3D) -> void:
	cave = TreasureCave.new()
	root.add_child(cave)
	chest_lid = cave.chest_lid

func open_chest() -> void:
	cave.open_chest()
	for i in range(22):
		var angle := i * TAU / 22
		var sparkle := sphere(self, cave.chest_point.global_position + Vector3(0, 1.2, 0), 0.12, Color("fce198"))
		sparkle.material_override = material(Color("ffe9a1"), true)
		var sparkle_tween := create_tween()
		sparkle_tween.set_parallel(true)
		sparkle_tween.tween_property(sparkle, "position", sparkle.position + Vector3(cos(angle) * 3, 2 + (i % 3), sin(angle) * 3), 2.0)
		sparkle_tween.tween_property(sparkle, "scale", Vector3.ZERO, 2.5)

func _npc(root: Node3D, at: Vector3, color: Color, npc_name: String) -> void:
	var actor := IslandCharacter.new()
	actor.profile = npc_name.to_lower()
	actor.position = at
	root.add_child(actor)
	npcs.append(actor)
	var name_label := label(root, at + Vector3(0, 2.6, 0), npc_name, 25, color.lightened(0.3))
	name_label.layers = 4

func _tree(at: Vector3, size: float) -> void:
	# Keep the delivery crossing, cottage and third-person camera clear of canopies.
	if at.x > 18 and at.x < 34 and at.z > -30 and at.z < -9:
		return
	cylinder(self, at + Vector3(0, 1.6 * size, 0), 0.24 * size, 3.2 * size, Color("5a5140"), 6)
	var tint := Color("457658") if sin(at.x) > -0.3 else Color("689365")
	for j in range(4):
		var angle := j * 2.3
		var crown := sphere(self, at + Vector3(cos(angle) * 0.8 * size, (3.0 + j * 0.3) * size, sin(angle) * 0.8 * size), (1.5 - j * 0.12) * size, tint.lightened(j * 0.025))
		crown.scale = Vector3(1, 0.9, 1)

func _lantern(root: Node3D, at: Vector3) -> void:
	cylinder(root, at + Vector3(0, 0.8, 0), 0.08, 1.6, WOOD, 6)
	var glow := box(root, at + Vector3(0, 1.65, 0), Vector3(0.32, 0.45, 0.32), Color("f4d992"))
	glow.material_override = material(Color("f4d992"), true)
	box(root, at + Vector3(0, 1.92, 0), Vector3(0.45, 0.1, 0.45), WOOD)

func path(from: Vector3, to: Vector3) -> void:
	var midpoint := (from + to) * 0.5
	midpoint.y = 0.025
	var mesh := box(self, midpoint, Vector3(2.7, 0.05, from.distance_to(to) + 2), Color("ae9e77"))
	mesh.rotation.y = atan2(to.x - from.x, to.z - from.z)
	var distance := from.distance_to(to)
	for i in range(int(distance / 1.6)):
		var at := from.lerp(to, (i + 0.5) * 1.6 / distance)
		at.y = 0.075
		var paver := box(self, at, Vector3(1.1 + sin(i) * 0.2, 0.08, 0.8), Color("c0b28b") if i % 2 else Color("b8ab85"))
		paver.rotation.y = mesh.rotation.y + sin(i * 2.1) * 0.16

func _gable(root: Node3D, front: float, color: Color) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for vertex in [Vector3(-4.7, 3.2, front), Vector3(4.7, 3.2, front), Vector3(0, 5.4, front)]:
		surface.add_vertex(vertex)
	surface.generate_normals()
	var mesh := MeshInstance3D.new()
	mesh.mesh = surface.commit()
	mesh.material_override = material(color)
	root.add_child(mesh)

func _landscape() -> void:
	var random := RandomNumberGenerator.new()
	random.seed = 9012
	# Layered coastal rock shelves, outside the walkable trail.
	for i in range(44):
		var angle := TAU * i / 44
		var at := Vector3(cos(angle) * 39, -1.2, sin(angle) * 44 - 5)
		var rock := box(self, at, Vector3(4.5, 2.6 + sin(i * 2.2) * 0.7, 4.5), Color("758e80") if i % 2 else Color("899b86"))
		rock.rotation.y = angle
	# Scenic hills add elevation without changing accessible routes or puzzle difficulty.
	for at in [Vector3(-31, 0, -28), Vector3(31, 0, -31), Vector3(-30, 0, 1), Vector3(30, 0, 24)]:
		var hill := sphere(self, at + Vector3(0, 1.2, 0), 7, Color("547659"))
		hill.scale = Vector3(1, 0.65, 1.2)
		for j in range(5):
			_tree(at + Vector3(random.randf_range(-4, 4), 3, random.randf_range(-4, 4)), random.randf_range(1.3, 1.8))
	for i in range(7):
		var angle := -PI * 0.9 + i * 0.45
		var at := Vector3(sin(angle) * 115, -5, cos(angle) * -110)
		var peak := cylinder(self, at, 20 + i % 3 * 5, 35 + i % 4 * 7, Color("688a90"), 6)
		(peak.mesh as CylinderMesh).top_radius = 2.5
		var island := sphere(self, at + Vector3(0, 2, 0), 22, Color("688a90"))
		island.scale = Vector3(1.5, 0.35, 1)
	for i in range(18):
		var at := Vector3(random.randf_range(-130, 130), random.randf_range(24, 38), random.randf_range(-110, 60))
		for j in range(3):
			var cloud := sphere(self, at + Vector3(j * 3, sin(j) * 0.8, 0), 4, Color("e4ece1"))
			cloud.scale = Vector3(1.6, 0.3, 0.75)

static func material(color: Color, glow: bool = false) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = 0.9
	if glow:
		result.emission_enabled = true
		result.emission = color
		result.emission_energy_multiplier = 0.6
	return result

static func box(root: Node3D, at: Vector3, size: Vector3, color: Color, collision: bool = false) -> MeshInstance3D:
	var result := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	result.mesh = mesh
	result.material_override = material(color)
	root.add_child(result)
	result.position = at
	if collision:
		var body := StaticBody3D.new()
		var collider := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		collider.shape = shape
		body.add_child(collider)
		result.add_child(body)
	return result

static func cylinder(root: Node3D, at: Vector3, radius: float, height: float, color: Color, segments: int = 10) -> MeshInstance3D:
	var result := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = segments
	result.mesh = mesh
	result.material_override = material(color)
	root.add_child(result)
	result.position = at
	return result

static func sphere(root: Node3D, at: Vector3, radius: float, color: Color) -> MeshInstance3D:
	var result := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2
	mesh.radial_segments = 10
	mesh.rings = 5
	result.mesh = mesh
	result.material_override = material(color)
	root.add_child(result)
	result.position = at
	return result

static func label(root: Node3D, at: Vector3, text: String, size: int, color: Color = Color("fff2d2")) -> Label3D:
	var result := Label3D.new()
	result.text = text
	result.font_size = size
	result.pixel_size = 0.009
	result.modulate = color
	result.outline_size = 7
	result.visibility_range_end = 25.0
	result.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	root.add_child(result)
	result.position = at
	return result
