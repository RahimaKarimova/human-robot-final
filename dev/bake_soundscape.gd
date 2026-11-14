extends SceneTree
## Offline authoring script for the original score, surf/birds and reward chime.
const RATE := 22050
const BEAT := 0.8

func _initialize() -> void:
	_bake("island_theme", 51.2, _music)
	_bake("island_ambience", 25.6, _ambience)
	_bake("reward_chime", 2.8, _reward)
	quit()

func _bake(id: String, seconds: float, sample: Callable) -> void:
	var count := int(seconds * RATE)
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	var random := RandomNumberGenerator.new()
	random.seed = 8134
	var smooth_noise := 0.0
	var peak: int = 1
	for i in range(count):
		var time := float(i) / RATE
		smooth_noise = smooth_noise * 0.96 + random.randf_range(-1, 1) * 0.04
		var value: float = sample.call(time, smooth_noise)
		var fade := minf(1, time / 0.6) * minf(1, (seconds - time) / 0.6)
		var pcm := int(clampf(value * fade, -1, 1) * 28000)
		peak = maxi(peak, absi(pcm))
		bytes.encode_s16(i * 2, pcm)
	# Normalise the baked signals; the runtime mixer then sets predictable relative levels.
	var target := 0.55 if id == "island_ambience" else 0.75
	var gain := target * 32767 / peak
	for i in range(count):
		bytes.encode_s16(i * 2, int(bytes.decode_s16(i * 2) * gain))
	var wave := AudioStreamWAV.new()
	wave.format = AudioStreamWAV.FORMAT_16_BITS
	wave.mix_rate = RATE
	wave.data = bytes
	var error := wave.save_to_wav("res://assets/audio/" + id + ".wav")
	print("Soundscape: ", id, " · ", seconds, " s · result ", error)

func _frequency(midi: int) -> float:
	return 440 * pow(2.0, (midi - 69.0) / 12.0)

func _pluck(time: float, midi: int, gain: float = 1) -> float:
	if time < 0 or time > 3.8:
		return 0
	var phase := TAU * _frequency(midi) * time
	var envelope := (1 - exp(-time * 120)) * exp(-time * 2.3)
	return (sin(phase) + sin(phase * 2) * 0.25 + sin(phase * 3) * 0.08) * envelope * gain

func _music(time: float, _noise: float) -> float:
	var chords := [[50, 57, 62, 66], [43, 55, 59, 62], [47, 54, 59, 62], [45, 57, 61, 64]]
	var chord_index := int(time / (BEAT * 8)) % 4
	var chord: Array = chords[chord_index]
	var local := fmod(time, BEAT * 8)
	var sound := 0.0
	# A soft bowed pad underneath an eight-note harp arpeggio.
	var pad_envelope := minf(local / 0.9, 1) * minf((BEAT * 8 - local) / 1.1, 1)
	for note in chord:
		var f := _frequency(note)
		sound += sin(TAU * f * time + sin(time * 0.7) * 0.04) * pad_envelope * 0.022
	for offset in range(8):
		var note_time := local - offset * BEAT
		var note: int = chord[[0, 2, 1, 3, 1, 2, 3, 2][offset]] + (12 if offset % 3 == 0 else 0)
		sound += _pluck(note_time, note, 0.12)
	var melody := [74, 0, 78, 76, 74, 71, 0, 69, 71, 74, 0, 78, 76, 74, 73, 0]
	var phrase := int(time / (BEAT * 2))
	for back in range(2):
		var at := phrase - back
		if at < 0:
			continue
		var note: int = melody[at % melody.size()]
		if note > 0:
			sound += _pluck(time - at * BEAT * 2, note, 0.075)
	return sound

func _ambience(time: float, noise: float) -> float:
	var surf := noise * (0.13 + 0.08 * sin(time * TAU / 6.4))
	var bird := 0.0
	for start in [3.2, 9.8, 17.1, 22.4]:
		var local: float = time - start
		if local >= 0 and local < 0.8:
			var syllable := fmod(local, 0.23)
			var envelope := sin(minf(syllable / 0.16, 1) * PI) * exp(-local * 1.4)
			bird += sin(TAU * (1800 * local + 450 * local * local) + sin(local * 50) * 0.5) * envelope * 0.017
	return surf + bird

func _reward(time: float, _noise: float) -> float:
	var sound := 0.0
	for i in range(5):
		sound += _pluck(time - i * 0.15, [74, 78, 81, 86, 90][i], 0.22)
	return sound
