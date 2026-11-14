class_name WorldGift
extends Node3D
var fragment: int = 1
var gem_id: String
var elapsed: float = 0.0
var lid: Node3D
var map_piece: Node3D
var sparkles: Array[Node3D] = []

func _ready() -> void:
	var purple := Color("78608d")
	var gold := Color("efd397")
	EchoWorld.box(self, Vector3(0, 0.35, 0), Vector3(0.86, 0.64, 0.7), purple)
	EchoWorld.box(self, Vector3(0, 0.35, 0), Vector3(0.12, 0.66, 0.72), gold)
	EchoWorld.box(self, Vector3(0, 0.35, 0), Vector3(0.88, 0.13, 0.72), gold)
	lid = Node3D.new()
	lid.position = Vector3(0, 0.71, -0.35)
	add_child(lid)
	EchoWorld.box(lid, Vector3(0, 0, 0.35), Vector3(0.94, 0.14, 0.78), purple.lightened(0.15))
	EchoWorld.box(lid, Vector3(0, 0.08, 0.35), Vector3(0.13, 0.04, 0.8), gold)
	for side in [-1, 1]:
		var bow := EchoWorld.sphere(lid, Vector3(side * 0.14, 0.16, 0.35), 0.15, gold)
		bow.scale = Vector3(1, 0.4, 0.6)
	gem_id = Content.gem_for_stage(fragment - 1).id
	map_piece = GemStone.new()
	map_piece.gem_id = gem_id
	add_child(map_piece)
	map_piece.scale = Vector3.ZERO
	for i in range(12):
		var sparkle := EchoWorld.sphere(self, Vector3.ZERO, 0.025, gold)
		sparkle.material_override = EchoWorld.material(gold, true)
		sparkles.append(sparkle)

func _process(delta: float) -> void:
	if GameState.paused or GameState.stopped:
		return
	elapsed += delta
	var open := smoothstep(0.1, 1.2, elapsed)
	lid.rotation.x = -open * 1.9
	map_piece.position = Vector3(0, 0.5 + open * 1.15 + sin(elapsed * 2) * 0.06, 0)
	map_piece.rotation.y = sin(elapsed * 0.8) * 0.3
	map_piece.scale = Vector3.ONE * open
	for i in range(sparkles.size()):
		var angle := i * TAU / sparkles.size() + elapsed * 0.6
		sparkles[i].position = Vector3(cos(angle) * 0.65, 0.8 + sin(angle * 2) * 0.35, sin(angle) * 0.65)
		sparkles[i].scale = Vector3.ONE * (0.6 + sin(elapsed * 3 + i) * 0.4) * open
