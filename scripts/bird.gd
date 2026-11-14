class_name IslandBird
extends Node3D
## Animated flock member. Decorative only; no collision or gameplay timing dependency.
var orbit_center := Vector3(0, 10, -6)
var radius: float = 24.0
var phase: float = 0.0
var angular_speed: float = 0.13
var left_wing: Node3D
var right_wing: Node3D
var elapsed: float = 0.0
var previous := Vector3.ZERO

func _ready() -> void:
	var body := EchoWorld.sphere(self, Vector3.ZERO, 0.16, Color("f0eee0"))
	body.scale = Vector3(0.65, 0.7, 1.65)
	EchoWorld.sphere(self, Vector3(0, 0.035, -0.22), 0.1, Color("f4f1e4"))
	var beak := EchoWorld.cylinder(self, Vector3(0, 0.01, -0.34), 0.04, 0.13, Color("dcb76c"), 5)
	beak.rotation.x = PI / 2
	(beak.mesh as CylinderMesh).top_radius = 0
	for side in [-1, 1]:
		var joint := Node3D.new()
		add_child(joint)
		joint.position.x = side * 0.09
		var mesh := SurfaceTool.new()
		mesh.begin(Mesh.PRIMITIVE_TRIANGLES)
		for vertex in [Vector3(0, 0, -0.1), Vector3(side * 0.82, 0.03, 0.12), Vector3(side * 0.5, 0.02, 0.29), Vector3(0, 0, -0.1), Vector3(side * 0.5, 0.02, 0.29), Vector3(0, 0, 0.17)]:
			mesh.add_vertex(vertex)
		mesh.generate_normals()
		var wing := MeshInstance3D.new()
		wing.mesh = mesh.commit()
		var material := EchoWorld.material(Color("d7dfd9"))
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		wing.material_override = material
		joint.add_child(wing)
		if side < 0:
			left_wing = joint
		else:
			right_wing = joint
	previous = _flight_position()
	position = previous

func _flight_position() -> Vector3:
	var angle := phase + elapsed * angular_speed
	return orbit_center + Vector3(cos(angle) * radius + sin(angle * 3) * 2, sin(angle * 2 + phase) * 1.2, sin(angle) * radius * 0.66)

func _process(delta: float) -> void:
	if GameState.paused or GameState.stopped:
		return
	elapsed += delta
	position = _flight_position()
	var direction := position - previous
	if direction.length_squared() > 0.000001:
		look_at(position + direction)
		rotation.z += sin(elapsed * angular_speed + phase) * 0.16
	var glide := sin(elapsed * 0.65 + phase) > 0.2
	var flap := sin(elapsed * 7.5 + phase * 3) * (0.13 if glide else 0.65)
	left_wing.rotation.z = flap
	right_wing.rotation.z = -flap
	previous = position
