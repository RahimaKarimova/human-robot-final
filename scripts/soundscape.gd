class_name IslandSoundscape
extends Node
var music: AudioStreamPlayer
var ambience: AudioStreamPlayer
var effect: AudioStreamPlayer
var music_volume: float = 0.6
var ambience_volume: float = 0.5
var ducked: bool = false

func _ready() -> void:
	music = _player("res://assets/audio/island_theme.wav", true)
	ambience = _player("res://assets/audio/island_ambience.wav", true)
	effect = _player("res://assets/audio/reward_chime.wav", false)
	music.play()
	ambience.play()
	_apply_levels()

func _player(path: String, looped: bool) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	add_child(player)
	if ResourceLoader.exists(path):
		var stream := load(path).duplicate() as AudioStreamWAV
		if looped:
			stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
			stream.loop_begin = 0
			stream.loop_end = stream.data.size() / 2
		player.stream = stream
	return player

func set_ducked(value: bool) -> void:
	ducked = value
	_apply_levels()

func _apply_levels() -> void:
	if not is_instance_valid(music):
		return
	music.volume_db = -80 if music_volume <= 0 else -12 + linear_to_db(music_volume) - (13 if ducked else 0)
	ambience.volume_db = -80 if ambience_volume <= 0 else -17 + linear_to_db(ambience_volume) - (10 if ducked else 0)

func set_music_volume(value: float) -> void:
	music_volume = clampf(value, 0, 1)
	_apply_levels()

func set_ambience_volume(value: float) -> void:
	ambience_volume = clampf(value, 0, 1)
	_apply_levels()

func reward() -> void:
	effect.volume_db = -9
	effect.play()

func set_paused(value: bool) -> void:
	music.stream_paused = value
	ambience.stream_paused = value
	effect.stream_paused = value

func stop() -> void:
	music.stop()
	ambience.stop()
	effect.stop()

func _exit_tree() -> void:
	stop()
