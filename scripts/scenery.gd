class_name IslandScenery
extends Node3D
var birds: Array[IslandBird] = []
var clouds: Array[Node3D] = []
var elapsed: float = 0.0

func _ready() -> void:
	var random := RandomNumberGenerator.new()
	random.seed = 76143
	for i in range(12):
		var bird := IslandBird.new()
		bird.orbit_center = Vector3(-3, 10 + i % 3, -5)
		bird.radius = 19.0 + (i % 4) * 3.0
		bird.phase = i * 0.49
		bird.angular_speed = 0.1 + (i % 3) * 0.012
		bird.scale = Vector3.ONE * (0.7 + (i % 3) * 0.2)
		add_child(bird)
		birds.append(bird)
	_meadow(random)
	_gardens()
	# Drifting cloud clusters are kept far above the paths and inspection cameras.
	for i in range(7):
		var cloud := Node3D.new()
		cloud.position = Vector3(random.randf_range(-65, 65), 24 + i % 3 * 3, random.randf_range(-60, 20))
		add_child(cloud)
		for j in range(4):
			var puff := EchoWorld.sphere(cloud, Vector3(j * 2.8, sin(j) * 0.5, 0), 3.2, Color("e3ebe4"))
			puff.scale = Vector3(1.45, 0.4, 0.8)
		clouds.append(cloud)

func _meadow(random: RandomNumberGenerator) -> void:
	var blade_surface := SurfaceTool.new()
	blade_surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for angle in [0.0, 1.05, 2.1]:
		for vertex in [Vector3(-0.12, 0, 0), Vector3(0.04, 0.65, 0), Vector3(0.14, 0, 0)]:
			blade_surface.add_vertex(vertex.rotated(Vector3.UP, angle))
	blade_surface.generate_normals()
	var blade_mesh := blade_surface.commit()
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = blade_mesh
	var positions: Array[Vector3] = []
	for i in range(1500):
		var at := Vector3(random.randf_range(-35, 35), 0.02, random.randf_range(-40, 32))
		if not _safe_meadow(at):
			continue
		positions.append(at)
	multimesh.instance_count = positions.size()
	for i in range(positions.size()):
		var scale := random.randf_range(0.35, 0.9)
		var basis := Basis(Vector3.UP, random.randf_range(0, TAU)).scaled(Vector3.ONE * scale)
		multimesh.set_instance_transform(i, Transform3D(basis, positions[i]))
	var grass := MultiMeshInstance3D.new()
	grass.multimesh = multimesh
	var material := ShaderMaterial.new()
	material.shader = load("res://assets/meadow.gdshader")
	grass.material_override = material
	add_child(grass)
	# Small clusters of individual flower heads provide colour accents, away from clues.
	for i in range(80):
		var at := Vector3(random.randf_range(-32, 32), 0.08, random.randf_range(-36, 29))
		if not _safe_meadow(at):
			continue
		for j in range(4):
			var stem := at + Vector3(j * 0.18, 0.12, sin(j) * 0.22)
			EchoWorld.cylinder(self, stem, 0.018, 0.3, Color("527953"), 5)
			var flower := EchoWorld.sphere(self, stem + Vector3(0, 0.16, 0), 0.09, [Color("e0b8ca"), Color("ead58b"), Color("b7bddb")][i % 3])
			flower.scale.y = 0.45

func _safe_meadow(at: Vector3) -> bool:
	if Vector2(at.x / 36, (at.z + 5) / 42).length() > 1:
		return false
	if absf(at.x) < 5 or absf(at.z - 12) < 3 or absf(at.z + 15) < 4 or absf(at.x - 23) < 4:
		return false
	for stage in Content.stages:
		if Vector2(at.x - stage.position[0], at.z - stage.position[2]).length() < 8:
			return false
	return true

func _gardens() -> void:
	# Library roses and an arbour, a welcoming bench and painted workshop bunting.
	for side in [-1, 1]:
		var at := Vector3(-15 + side * 5.7, 0, 9)
		EchoWorld.box(self, at + Vector3(0, 0.25, 0), Vector3(1.2, 0.5, 2.3), Color("897457"))
		for j in range(4):
			var shrub := EchoWorld.sphere(self, at + Vector3(0, 0.75, -0.7 + j * 0.45), 0.55, Color("507f60"))
			shrub.scale.y = 0.8
			EchoWorld.sphere(self, at + Vector3(0.28, 1.0, -0.7 + j * 0.45), 0.13, Color("d9a4b7"))
	var bench := Vector3(-8, 0, 15)
	EchoWorld.box(self, bench + Vector3(0, 0.55, 0), Vector3(2.5, 0.12, 0.75), Color("94794e"))
	EchoWorld.box(self, bench + Vector3(0, 1.0, -0.3), Vector3(2.5, 0.65, 0.12), Color("94794e"))
	for x in [-1, 1]:
		EchoWorld.box(self, bench + Vector3(x, 0.25, 0), Vector3(0.14, 0.5, 0.5), Color("625740"))
	for i in range(9):
		var at := Vector3(10 + i * 1.2, 3.1 - sin(i * PI / 8) * 0.5, 12.5)
		var flag := EchoWorld.cylinder(self, at, 0.23, 0.025, [Color("d4ab6c"), Color("709c9c"), Color("c18991")][i % 3], 3)
		flag.rotation.x = PI / 2
	# Temple glints and ivy give the final landmark a different palette.
	for side in [-1, 1]:
		for j in range(4):
			var ivy := EchoWorld.sphere(self, Vector3(-15 + side * 3.9, 0.5 + j * 0.6, -21), 0.34, Color("5f856c"))
			ivy.scale = Vector3(0.7, 1.1, 0.5)

func _process(delta: float) -> void:
	if GameState.paused or GameState.stopped:
		return
	elapsed += delta
	for i in range(clouds.size()):
		clouds[i].position.x += delta * (0.12 + (i % 3) * 0.03)
		if clouds[i].position.x > 90:
			clouds[i].position.x = -90
