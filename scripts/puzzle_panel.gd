class_name PuzzlePanel
extends Node
signal solved
var ui: IslandUI
var data: Dictionary
var puzzle: EchoPuzzle
var feedback: Label
var hint_label: Label
var slots: Array[String] = ["YELLOW", "RED", "BLUE"]
var symbol_progress: Label
var active: bool = false

func setup(interface: IslandUI) -> void:
	ui = interface

func open(stage: Dictionary) -> void:
	data = stage
	active = true
	if puzzle == null or puzzle.definition != data.puzzle:
		puzzle = EchoPuzzle.new(data.puzzle)
		slots = ["YELLOW", "RED", "BLUE"]
	var panel := ui.show_modal("Chapter %d · find the precious gem · no time limit" % (GameState.stage_index + 1), data.name)
	match data.puzzle.kind:
		"books": _books(panel)
		"gears": _gears(panel)
		"routes": _routes(panel)
		"symbols": _symbols(panel)
	feedback = IslandUI.text(panel, "Check the letter, then try your idea.", 19)
	hint_label = IslandUI.text(panel, "", 19, IslandUI.GOLD)
	hint_label.hide()
	ui.footer.show()
	var actions := ui.footer
	IslandUI.button(actions, "Ask for a hint", hint)
	IslandUI.button(actions, "Read the clue", func():
		hint_label.show()
		hint_label.text = data.letter
		hint_label.add_theme_font_size_override("font_size", 18)
		_reveal_hint.call_deferred()
	)
	IslandUI.button(actions, "Back to the island", func():
		active = false
		ui.close_modal()
	)

func _books(panel: VBoxContainer) -> void:
	IslandUI.text(panel, "Elara's bookshelf", 23)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 10)
	panel.add_child(grid)
	# Upper shelf first. Six choices include one feather-like distractor.
	var options: Array = data.puzzle.options
	for index in [4, 5, 0, 1, 2, 3]:
		var item: Dictionary = options[index]
		var choice := IslandUI.button(grid, "\n\n%s   %s\n%s" % [item.mark, item.label, item.detail], func(): _attempt(item.id))
		choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		choice.custom_minimum_size = Vector2(275, 146)
		choice.add_theme_font_size_override("font_size", 16)
		choice.add_theme_stylebox_override("normal", IslandUI.framed(Color(item.color).darkened(0.52), 4, 18, Color(item.color).lightened(0.25)))
		_art(choice, "book", Color(item.color), item.mark)

func _gears(panel: VBoxContainer) -> void:
	IslandUI.text(panel, "Repair the little clock", 24)
	IslandUI.text(panel, "Click a gear to change its colour. Arrange the three gears from left to right.", 19, IslandUI.MUTED)
	var gear_row := IslandUI.row(panel, 16)
	for i in range(3):
		var slot := IslandUI.button(gear_row, "", Callable())
		slot.custom_minimum_size = Vector2(280, 160)
		slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_style_slot(slot, i)
		_art(slot, "gear", {"RED": Color("cf7765"), "BLUE": Color("729dc0"), "YELLOW": Color("ddbd68")}[slots[i]], "")
		slot.pressed.connect(func():
			var colors: Array[String] = ["RED", "BLUE", "YELLOW"]
			slots[i] = colors[(colors.find(slots[i]) + 1) % 3]
			_style_slot(slot, i)
		)
	IslandUI.button(panel, "Test the clock", func(): _attempt(Array(slots)))

func _style_slot(slot: Button, i: int) -> void:
	var colors := {"RED": Color("a95245"), "BLUE": Color("436e91"), "YELLOW": Color("8c7135")}
	slot.text = "\n\n⚙   " + slots[i] + "\nSlot " + str(i + 1)
	slot.add_theme_stylebox_override("normal", IslandUI.framed(colors[slots[i]].darkened(0.35), 4, 18, colors[slots[i]].lightened(0.35)))
	var art := slot.get_node_or_null("Art") as IslandItemArt
	if art:
		art.tint = colors[slots[i]].lightened(0.2)
		art.queue_redraw()

func _routes(panel: VBoxContainer) -> void:
	IslandUI.text(panel, "The delivery map", 24)
	var map_panel := PanelContainer.new()
	map_panel.add_theme_stylebox_override("panel", IslandUI.framed(Color("243d46"), 4, 16))
	panel.add_child(map_panel)
	IslandUI.text(map_panel, "HILL PATH → HILLTOP COTTAGE\nMARKET → WOODEN BRIDGE → RIVERSIDE COTTAGE\nFOREST PATH → TREE COTTAGE", 20)
	for option in data.puzzle.options:
		IslandUI.button(panel, option.mark + "   " + option.label, func(): _attempt(option.id))

func _symbols(panel: VBoxContainer) -> void:
	IslandUI.text(panel, "The temple altar", 24)
	IslandUI.text(panel, "Press the symbols in order. The entrance reads: SUN → WAVE → STAR.", 20, IslandUI.MUTED)
	var symbols := IslandUI.row(panel, 16)
	for item in [{"id": "STAR", "mark": "★"}, {"id": "SUN", "mark": "☀"}, {"id": "WAVE", "mark": "≈"}]:
		var choice := IslandUI.button(symbols, "\n\n" + item.mark + "\n" + item.id, func(): _symbol(item.id))
		choice.custom_minimum_size = Vector2(280, 160)
		choice.add_theme_font_size_override("font_size", 20)
		_art(choice, "symbol", Color("e8d4a2"), item.id)
	symbol_progress = IslandUI.text(panel, _sequence_text(), 22)
	IslandUI.button(panel, "Clear sequence", func():
		puzzle.sequence.clear()
		symbol_progress.text = _sequence_text()
	)

func _sequence_text() -> String:
	return "Sequence:  " + (" → ".join(puzzle.sequence) if not puzzle.sequence.is_empty() else "—   —   —")

func _symbol(value: String) -> void:
	if not active:
		return
	var result := puzzle.press(value)
	ApiClient.emit_event("PUZZLE_ATTEMPTED", {"puzzle_id": data.id, "correct": result >= 0, "complete": result == 1})
	symbol_progress.text = _sequence_text()
	if result == 1:
		_success()
	elif result == -1:
		feedback.text = "Not quite; check the letter again. The sequence is ready for a fresh try."
	else:
		feedback.text = "That symbol fits. What comes next?"

func _attempt(answer: Variant) -> void:
	if not active:
		return
	var correct := puzzle.attempt(answer)
	ApiClient.emit_event("PUZZLE_ATTEMPTED", {"puzzle_id": data.id, "correct": correct})
	if correct:
		_success()
	else:
		feedback.text = "Not quite; check the letter again. You can try another idea or ask for a hint."

func _success() -> void:
	if not active:
		return
	active = false
	solved.emit()

func hint() -> void:
	if not active:
		return
	hint_label.text = EchoPuzzle.next_hint(data.id)
	hint_label.show()
	ApiClient.emit_event("HINT_REQUESTED", {"level": GameState.hints[data.id]})
	_reveal_hint.call_deferred()

func _reveal_hint() -> void:
	await get_tree().process_frame
	if is_instance_valid(hint_label):
		ui.scroll.ensure_control_visible(hint_label)

func _art(button: Button, kind: String, tint: Color, mark: String) -> void:
	var art := IslandItemArt.new()
	art.name = "Art"
	art.kind = kind
	art.tint = tint
	art.mark = mark
	art.set_anchors_preset(Control.PRESET_CENTER_TOP)
	art.position = Vector2(-40, -6)
	art.size = Vector2(80, 76)
	button.add_child(art)
