class_name LetterReader
extends Node
signal closed(first_read: bool)
var ui: IslandUI
var speech: IslandSpeech
var data: Dictionary
var narration_done: bool = false
var first_read: bool = false
var active: bool = false
var continue_button: Button
var narration_status: Label

func setup(interface: IslandUI, voice: IslandSpeech) -> void:
	ui = interface
	speech = voice
	speech.finished.connect(_completed)

func open(stage: Dictionary) -> void:
	data = stage
	active = true
	first_read = not GameState.letters.has(data.id)
	var panel := ui.show_modal(data.npc + " · " + data.role, "A letter from " + data.npc, "Story narrator · read along, replay, or finish reading at your own pace")
	var reading := IslandUI.row(panel, 20)
	var portrait := CharacterPortrait.new()
	portrait.profile = str(data.npc).to_lower()
	reading.add_child(portrait)
	var parchment := PanelContainer.new()
	parchment.add_theme_stylebox_override("panel", IslandUI.style(Color("e9dbb4"), 8, 22))
	parchment.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reading.add_child(parchment)
	var story := RichTextLabel.new()
	story.bbcode_enabled = true
	story.fit_content = true
	story.scroll_active = false
	story.custom_minimum_size.x = 570
	story.add_theme_font_size_override("normal_font_size", 22)
	story.add_theme_color_override("default_color", Color("2b3936"))
	story.add_theme_constant_override("line_separation", 5)
	var formatted: String = data.letter.replace(" — ", "\n\n— ")
	var clues := {"library": ["golden feather", "upper shelf beside the globe"], "workshop": ["small blue gear goes between the red gear and the yellow gear", "from left to right"], "market": ["cottage beside the river", "after the wooden bridge", "not the cottage on the hill"], "temple": ["sun, wave, star", "in that order"]}
	for clue in clues.get(data.id, []):
		formatted = formatted.replace(clue, "[b][color=#77551c]" + clue + "[/color][/b]")
	story.text = formatted
	parchment.add_child(story)
	narration_status = IslandUI.text(panel, "", 17, IslandUI.MUTED)
	ui.footer.show()
	var actions := ui.footer
	IslandUI.button(actions, "Replay narration", _play)
	IslandUI.button(actions, "Skip narration / finish reading", _skip)
	continue_button = IslandUI.button(actions, "Continue", _close)
	if first_read:
		ApiClient.emit_event("LETTER_OPENED", {"letter_id": data.letter_id}, data.id)
	_play()

func _play() -> void:
	narration_done = false
	continue_button.disabled = true
	if speech.play_line(data.letter_id):
		narration_status.text = "Narrator reading · key details are highlighted in the letter."
	else:
		narration_status.text = "Caption reading mode · select ‘finish reading’ when ready. No narration audio is playing."

func _completed(line_id: String) -> void:
	if active and line_id == data.letter_id:
		_finish("audio_completed")

func _skip() -> void:
	speech.stop()
	_finish("explicit_skip_or_caption_ack")

func _finish(reason: String) -> void:
	if narration_done:
		return
	narration_done = true
	continue_button.disabled = false
	narration_status.text = "Letter complete · continue whenever you're ready."
	ApiClient.emit_event("LETTER_NARRATION_COMPLETED", {"letter_id": data.letter_id, "completion": reason, "replay": not first_read}, data.id)

func _close() -> void:
	if not narration_done:
		return
	active = false
	GameState.letters[data.id] = true
	closed.emit(first_read)
