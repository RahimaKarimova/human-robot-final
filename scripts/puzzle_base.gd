class_name EchoPuzzle
extends RefCounted
## All puzzle validation is deterministic and independent of conversations.
var definition: Dictionary
var sequence: Array = []
var solved: bool = false

func _init(data: Dictionary) -> void:
	definition = data

func attempt(answer: Variant) -> bool:
	if solved:
		return true
	if typeof(answer) != typeof(definition.solution):
		return false
	solved = answer == definition.solution
	return solved

func press(symbol: String) -> int:
	if solved:
		return 1
	sequence.append(symbol)
	var target: Array = definition.solution
	if sequence.back() != target[sequence.size() - 1]:
		sequence.clear()
		return -1
	if sequence.size() == target.size():
		solved = true
		return 1
	return 0

static func next_hint(stage_id: String) -> String:
	var data: Dictionary = {}
	for item in Content.stages:
		if item.id == stage_id:
			data = item
	if data.is_empty():
		return ""
	var level: int = mini(int(GameState.hints.get(stage_id, 0)), 2)
	GameState.hints[stage_id] = mini(level + 1, 3)
	return data.hints[level]
