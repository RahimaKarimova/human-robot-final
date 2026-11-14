extends Node

func award_fragment(stage_id: String) -> bool:
	if GameState.stopped or GameState.completed or GameState.stage_index >= 4:
		return false
	if stage_id != Content.stage(GameState.stage_index).id or GameState.fragments.has(stage_id):
		return false
	if not GameState.checkpoints.has(stage_id + "_before"):
		return false
	GameState.fragments[stage_id] = true
	ApiClient.emit_event("PUZZLE_SOLVED", {"puzzle_id": stage_id})
	var gem: Dictionary = Content.gem_for_stage(GameState.stage_index)
	ApiClient.emit_event("GEM_COLLECTED", {"gem_id": gem.id, "count": GameState.fragments.size()})
	EventBus.progress_changed.emit()
	return true

func advance() -> bool:
	if GameState.stopped or GameState.stage_index >= 4:
		return false
	var id: String = Content.stage(GameState.stage_index).id
	if not GameState.fragments.has(id) or not GameState.checkpoints.has(id + "_after"):
		return false
	ApiClient.emit_event("STAGE_COMPLETED")
	GameState.stage_index += 1
	EventBus.progress_changed.emit()
	return true

func finish() -> bool:
	if GameState.stopped or GameState.completed or GameState.fragments.size() != 4 or GameState.stage_index != 4 or not GameState.cave_open or not GameState.cave_entered:
		return false
	GameState.completed = true
	ApiClient.emit_event("GAME_COMPLETED")
	EventBus.progress_changed.emit()
	return true

func insert_cave_gem(id: String) -> bool:
	if GameState.stopped or GameState.completed or GameState.stage_index != 4 or GameState.fragments.size() != 4 or GameState.socketed_gems.has(id):
		return false
	var gem := Content.gem_by_id(id)
	if gem.is_empty() or not GameState.fragments.has(gem.stage_id):
		return false
	GameState.socketed_gems[id] = true
	ApiClient.emit_event("CAVE_GEM_INSERTED", {"gem_id": id, "count": GameState.socketed_gems.size()})
	EventBus.progress_changed.emit()
	return true
