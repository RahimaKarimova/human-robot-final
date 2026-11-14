class_name MicrophoneIndicator
extends Control
## Level history comes only from live PCM measurements, never an idle animation.
var text: String = ""
var heading := Label.new()
var detail := Label.new()
var history: Array[float] = []
var last_sequence: int = 0
var live: bool = false
var show_caption: bool = false
var caption_label := Label.new()
var accent := Color("91a9ac")

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for label in [heading, detail]:
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		add_child(label)
	heading.add_theme_font_size_override("font_size", 16)
	detail.add_theme_font_size_override("font_size", 13)
	detail.add_theme_color_override("font_color", Color("c5d8d8"))
	caption_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption_label.add_theme_font_size_override("font_size", 16)
	caption_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(caption_label)
	history.resize(32)
	history.fill(0.0)

func _process(_delta: float) -> void:
	caption_label.visible = show_caption
	caption_label.text = ("You said: " if ApiClient.speech_caption_final else "You (live, may change): ") + ApiClient.speech_caption
	caption_label.position = Vector2(16, 58)
	caption_label.size = Vector2(size.x - 32, 42)
	heading.position = Vector2(38, 6)
	detail.position = Vector2(38, 28)
	heading.size = Vector2(maxf(100.0, size.x - 290.0), 21)
	detail.size = Vector2(maxf(100.0, size.x - 290.0), 19)
	live = ApiClient.voice_status == "LISTENING" and ApiClient.microphone_live and Time.get_ticks_msec() - ApiClient.microphone_meter_at < 800
	if GameState.paused and (ApiClient.voice_automatic or ApiClient.voice_status != "LISTENING"):
		live = false
		heading.text = "MIC OFF · GAME PAUSED"
		detail.text = "Resume the game to continue"
		accent = Color("91a9ac")
	elif ApiClient.voice_status == "PROCESSING":
		heading.text = "PROCESSING YOUR REPLY"
		detail.text = "Microphone closed · Please wait"
		accent = Color("f0c773")
	elif ApiClient.voice_status == "LISTENING":
		heading.text = "LISTENING" if live else "CHECKING MICROPHONE"
		accent = Color("69edbb") if live else Color("f0c773")
		if live:
			detail.text = "Sound detected · " if ApiClient.microphone_level > 0.08 else "Mic is open · "
			detail.text += "Speak, then pause to finish" if ApiClient.voice_automatic else "Release V / B when finished"
		else:
			detail.text = "Waiting for audio data · Buttons are available"
	elif ApiClient.voice_status == "STARTING":
		heading.text = "OPENING MICROPHONE"
		detail.text = "Wait for the green listening indicator"
		accent = Color("f0c773")
	elif ApiClient.voice_status == "UNAVAILABLE":
		heading.text = "MIC UNAVAILABLE"
		detail.text = "Use the buttons or try again"
		accent = Color("f28e87")
	else:
		heading.text = "MIC OFF"
		detail.text = "Opens after Reachy asks a question" if ApiClient.conversation_enabled else "Hold V for commands · Hold B to reply"
		accent = Color("91a9ac")
	if live and ApiClient.microphone_sequence != last_sequence:
		last_sequence = ApiClient.microphone_sequence
		history.pop_front()
		history.append(ApiClient.microphone_level)
	elif not live:
		last_sequence = 0
		history.fill(0.0)
	heading.add_theme_color_override("font_color", accent)
	queue_redraw()

func _draw() -> void:
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.035, 0.105, 0.13, 0.97)
	panel.border_color = accent.darkened(0.45)
	panel.set_border_width_all(1)
	panel.set_corner_radius_all(10)
	draw_style_box(panel, Rect2(Vector2.ZERO, size))
	var dot_alpha: float = 0.75 + 0.25 * sin(Time.get_ticks_msec() / 300.0) if live else 0.65
	draw_circle(Vector2(20, 18), 5, Color(accent, dot_alpha))
	var left: float = size.x - 222.0
	draw_line(Vector2(left, 7), Vector2(left, size.y - 7), Color("34545b"), 1)
	for index in range(history.size()):
		var height: float = 2.0 + history[index] * 28.0 if live else 2.0
		var x: float = left + 12.0 + index * 5.6
		draw_line(Vector2(x, 27 - height * 0.5), Vector2(x, 27 + height * 0.5), accent if live else Color("34545b"), 3.0, true)
