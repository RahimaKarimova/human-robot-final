class_name GemStone
extends Node3D
## Original faceted gemstone mesh, shared by rewards, the seal and treasure props.
var gem_id: String = "emerald"
var mesh_instance: MeshInstance3D

func _ready() -> void:
	var definition := Content.gem_by_id(gem_id)
	if definition.is_empty():
		definition = Content.gem_for_stage(0)
	var tint := Color(definition.color)
	var sides := 6 if definition.cut == "crystal" else 8
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(sides):
		var angle_a := i * TAU / sides
		var angle_b := (i + 1) * TAU / sides
		var stretch := 0.72 if definition.cut == "emerald" else 1.0
		var a := Vector3(sin(angle_a) * 0.31 * stretch, 0, cos(angle_a) * 0.31)
		var b := Vector3(sin(angle_b) * 0.31 * stretch, 0, cos(angle_b) * 0.31)
		var upper_a := Vector3(a.x * 0.65, 0.18, a.z * 0.65)
		var upper_b := Vector3(b.x * 0.65, 0.18, b.z * 0.65)
		var tip := Vector3(0, -0.4 if definition.cut == "crystal" else -0.32, 0)
		_triangle(surface, [Vector3(0, 0.18, 0), upper_b, upper_a], tint.lightened(0.3))
		_triangle(surface, [upper_a, upper_b, a], tint.lightened(0.09 if i % 2 == 0 else 0.2))
		_triangle(surface, [upper_b, b, a], tint.darkened(0.08 if i % 2 else 0.0))
		_triangle(surface, [a, b, tip], tint.darkened(0.13 if i % 2 else 0.28))
	surface.generate_normals()
	mesh_instance = MeshInstance3D.new()
	mesh_instance.mesh = surface.commit()
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.13
	material.metallic = 0.24
	material.metallic_specular = 0.8
	material.emission_enabled = true
	material.emission = tint
	material.emission_energy_multiplier = 0.09
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh_instance.material_override = material
	add_child(mesh_instance)
	var glint := EchoWorld.sphere(self, Vector3(-0.095, 0.17, 0.12), 0.027, Color("fff4d3"))
	glint.material_override = EchoWorld.material(Color("fff4d3"), true)

func _triangle(surface: SurfaceTool, vertices: Array, tint: Color) -> void:
	for vertex in vertices:
		surface.set_color(tint)
		surface.add_vertex(vertex)
