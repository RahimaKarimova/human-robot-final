extends Node
## Deliberately holds no participant answers or experimental assignment.
var stage_index: int = 0
var fragments: Dictionary = {}
var letters: Dictionary = {}
var checkpoints: Dictionary = {}
var hints: Dictionary = {}
var tutorial_done: bool = false
var started: bool = false
var stopped: bool = false
var completed: bool = false
var ui_locked: bool = true
var paused: bool = false
var inspecting: bool = false
var simple_puzzles: bool = false
var demo: bool = true
var socketed_gems: Dictionary = {}
var cave_open: bool = false
var cave_entered: bool = false

func reset() -> void:
	stage_index = 0
	fragments.clear()
	letters.clear()
	checkpoints.clear()
	hints.clear()
	tutorial_done = false
	started = false
	stopped = false
	completed = false
	ui_locked = true
	paused = false
	inspecting = false
	socketed_gems.clear()
	cave_open = false
	cave_entered = false

func stop() -> void:
	if stopped:
		return
	stopped = true
	ui_locked = true
	ApiClient.emit_event("SESSION_TERMINATED")
	EventBus.session_stopped.emit()
