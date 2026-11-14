class_name IslandSpeech
extends Node
## Bundled neural narration; audio playback only, no runtime TTS/model/backend.
signal finished(line_id: String)
signal activity_changed(active: bool)
var enabled: bool = true
var busy: bool = false
var volume: float = 0.9
var catalogue: Dictionary = {}
var playback: AudioStreamPlayer
var active_line: String = ""

func _ready() -> void:
	playback = AudioStreamPlayer.new()
	add_child(playback)
	playback.finished.connect(_ended)
	var text := FileAccess.get_file_as_string("res://assets/audio/manifest.json").trim_prefix("\ufeff")
	var parsed = JSON.parse_string(text)
	if parsed is Dictionary:
		catalogue = parsed

func _exit_tree() -> void:
	stop()

func play_line(id: String) -> bool:
	# Incidental character greetings and settings previews cannot replace Reachy.
	if busy and active_line.begins_with("companion_"):
		return false
	stop()
	if not enabled or not catalogue.has(id):
		return false
	var entry: Dictionary = catalogue[id]
	if not ResourceLoader.exists(entry.path):
		return false
	playback.stream = load(entry.path)
	playback.volume_db = -80 if volume <= 0 else linear_to_db(volume)
	playback.play()
	active_line = id
	busy = true
	activity_changed.emit(true)
	return true

func speak(value: String, _narrator: bool = false) -> bool:
	# Compatibility for Repeat: only a known fixed line may play. No generated dialogue.
	for id in catalogue:
		if catalogue[id].text == value:
			return play_line(id)
	return false

func _ended() -> void:
	if not busy:
		return
	busy = false
	var completed_line := active_line
	active_line = ""
	activity_changed.emit(false)
	finished.emit(completed_line)

func stop() -> void:
	if is_instance_valid(playback):
		playback.stop()
	active_line = ""
	if busy:
		busy = false
		activity_changed.emit(false)

func pause() -> void:
	playback.stream_paused = true

func resume() -> void:
	playback.stream_paused = false

func set_volume(value: float) -> void:
	volume = clampf(value, 0, 1)
	playback.volume_db = -80 if volume <= 0 else linear_to_db(volume)
