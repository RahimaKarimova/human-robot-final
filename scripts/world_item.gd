class_name WorldPuzzleItem
extends Node3D
var item_id: String = ""
var stage_id: String = ""
var title: String = ""
var reach: float = 8.0
var outline: MeshInstance3D
var nameplate: Label3D
var collision: StaticBody3D
var parts: Array[MeshInstance3D] = []

func initialise(bounds: Vector3) -> void:
	collision = StaticBody3D.new()
	collision.collision_layer = 2
	collision.collision_mask = 0
	collision.set_meta("puzzle_item", self)
	add_child(collision)
	var shape := BoxShape3D.new()
	shape.size = bounds
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collision.add_child(collider)
	var lines := ImmediateMesh.new()
	lines.surface_begin(Mesh.PRIMITIVE_LINES)
	var half := bounds * 0.55
	for axis in range(3):
		for a in [-1, 1]:
			for b in [-1, 1]:
				var from := Vector3.ZERO
				var to := Vector3.ZERO
				from[axis] = -half[axis]
				to[axis] = half[axis]
				from[(axis + 1) % 3] = half[(axis + 1) % 3] * a
				to[(axis + 1) % 3] = from[(axis + 1) % 3]
				from[(axis + 2) % 3] = half[(axis + 2) % 3] * b
				to[(axis + 2) % 3] = from[(axis + 2) % 3]
				lines.surface_add_vertex(from)
				lines.surface_add_vertex(to)
	lines.surface_end()
	outline = MeshInstance3D.new()
	outline.mesh = lines
	var material := EchoWorld.material(Color("ffe4a0"), true)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	outline.material_override = material
	add_child(outline)
	nameplate = EchoWorld.label(self, Vector3(0, bounds.y * 0.5 + 0.2, 0), title, 22, Color("ffe9b5"))
	nameplate.no_depth_test = true
	set_focused(false)

func set_focused(value: bool) -> void:
	if is_instance_valid(outline):
		outline.visible = value
		nameplate.visible = value

func press_feedback() -> void:
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3.ONE * 1.06, 0.1)
	tween.tween_property(self, "scale", Vector3.ONE, 0.16)
