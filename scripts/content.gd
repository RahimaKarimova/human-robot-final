extends Node
## One versioned content catalogue, shared by the client and external controller.
var stages: Array = []
var catalogue: Dictionary = {}
var presentation: Dictionary = {}
var gems: Array = []

func _ready() -> void:
	catalogue = JSON.parse_string(FileAccess.get_file_as_string("res://data/game.json"))
	stages = catalogue.stages
	presentation = JSON.parse_string(FileAccess.get_file_as_string("res://data/presentation.json"))
	gems = JSON.parse_string(FileAccess.get_file_as_string("res://data/gems.json")).gems

func gem_for_stage(index: int) -> Dictionary:
	return gems[clampi(index, 0, gems.size() - 1)]

func gem_by_id(id: String) -> Dictionary:
	for gem in gems:
		if gem.id == id:
			return gem
	return {}

func stage(index: int) -> Dictionary:
	return stages[clampi(index, 0, stages.size() - 1)]
