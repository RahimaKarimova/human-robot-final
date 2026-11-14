extends Node
var assertions := 0

func check(value: bool, description: String) -> void:
	assertions += 1
	if not value:
		push_error("FAIL: " + description)
		get_tree().quit(1)

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color("19363f")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var note := Label.new()
	note.text = "MICROPHONE DISPLAY · SYNTHETIC UI FIXTURE · NO MICROPHONE OPENED"
	note.position = Vector2(36, 25)
	add_child(note)
	var banner := MicrophoneIndicator.new()
	banner.position = Vector2(36, 90)
	banner.size = Vector2(780, 54)
	add_child(banner)
	ApiClient.microphone_enabled = true
	ApiClient.conversation_enabled = true
	ApiClient.voice_automatic = true
	ApiClient.voice_status = "LISTENING"
	ApiClient.voice_capture_id = "synthetic-fixture"
	for index in range(32):
		ApiClient.update_microphone_meter({"capture_id":"synthetic-fixture", "live":true, "sequence":float(index + 1), "level":0.12 + abs(sin(index * 1.3)) * 0.65})
		await get_tree().process_frame
	check(banner.live, "fresh matching audio metadata lights listening indicator")
	check(banner.heading.text == "LISTENING", "live state explicitly labelled")
	check(banner.history.max() > 0.5, "bars retain changing measured level values")
	if not DisplayServer.get_name() == "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://artifacts/official-reachy/microphone-listening-ui.png")
	ApiClient.update_microphone_meter({"capture_id":"wrong-turn", "live":true, "sequence":33.0, "level":0.9})
	await get_tree().process_frame
	await get_tree().process_frame
	check(not banner.live, "wrong capture cannot light microphone indicator")
	check(banner.history.max() == 0.0, "stale/mismatched input clears the display")
	ApiClient.voice_status = "PROCESSING"
	await get_tree().process_frame
	await get_tree().process_frame
	check(not banner.live and banner.heading.text == "PROCESSING YOUR REPLY", "processing explicitly shows microphone closed")
	if not DisplayServer.get_name() == "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://artifacts/official-reachy/microphone-processing-ui.png")
	ApiClient.voice_status = "LISTENING"
	ApiClient.update_microphone_meter({"capture_id":"synthetic-fixture", "live":true, "sequence":34.0, "level":0.7})
	GameState.paused = true
	await get_tree().process_frame
	await get_tree().process_frame
	check(not banner.live and banner.heading.text == "MIC OFF · GAME PAUSED", "pause cannot falsely indicate active automatic listening")
	print("ECHO MICROPHONE INDICATOR: %d assertions, 0 failures; synthetic metadata only" % assertions)
	get_tree().quit(0)
