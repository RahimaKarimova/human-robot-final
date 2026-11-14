class_name IslandUI
extends CanvasLayer
const INK := Color("eee9dc")
const PAPER := Color("f4eddc")
const MUTED := Color("a8b8b6")
const GOLD := Color("dcc695")
const DARK := Color("182c38f5")
var root: Control
var objective: Label
var fragments: Label
var status: Label
var prompt: Button
var waypoint: Label
var modal: PanelContainer
var content: VBoxContainer
var veil: ColorRect
var pause_veil: ColorRect
var pause_content: VBoxContainer
var hud: Control
var hint_button: Button
var journal_button: Button
var pause_button: Button
var stop_button: Button
var letter_button: Button
var controls: Label
var tools: HBoxContainer
var safety: HBoxContainer
var scroll: ScrollContainer
var footer: HBoxContainer
var game_art: AdventureHUD
var quest_panel: PanelContainer
var center: CenterContainer
var caption_panel: PanelContainer
var caption_name: Label
var caption_line: Label
var pause_scroll: ScrollContainer
var task_panel: PanelContainer
var task_title: Label
var task_feedback: Label
var task_hint: Label
var reward_panel: PanelContainer
var reward_title: Label
var reward_text: Label
var reward_continue: Button
var task_action: Button
var inspection_panel: PanelContainer
var inspection_status: Label
var inspection_exit: Button
var inspect_button: Button
var task_dismiss: Button

func _ready() -> void:
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var theme := Theme.new()
	theme.default_font_size = 20
	theme.set_color("font_color", "Label", INK)
	theme.set_color("font_color", "Button", PAPER)
	theme.set_color("font_hover_color", "Button", Color.WHITE)
	theme.set_color("font_focus_color", "Button", Color.WHITE)
	theme.set_color("font_disabled_color", "Button", Color("87968e"))
	theme.set_stylebox("normal", "Button", framed(Color("2a3e49"), 5, 12))
	theme.set_stylebox("hover", "Button", framed(Color("49606a"), 5, 12, GOLD))
	theme.set_stylebox("pressed", "Button", framed(Color("1c303b"), 5, 12, GOLD))
	var focus_style := style(Color.TRANSPARENT, 10, 12)
	focus_style.border_color = GOLD
	focus_style.set_border_width_all(3)
	theme.set_stylebox("focus", "Button", focus_style)
	theme.set_stylebox("disabled", "Button", framed(Color("283a4288"), 5, 12))
	theme.set_stylebox("panel", "PanelContainer", framed(DARK, 8, 28, Color("c2ae7c88")))
	root.theme = theme
	hud = Control.new()
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hud)
	game_art = AdventureHUD.new()
	game_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.add_child(game_art)
	quest_panel = PanelContainer.new()
	quest_panel.position = Vector2(200, 60)
	quest_panel.custom_minimum_size = Vector2(355, 90)
	var quest_style := style(Color("172d3899"), 3, 14)
	quest_style.border_color = GOLD
	quest_style.border_width_left = 3
	quest_panel.add_theme_stylebox_override("panel", quest_style)
	hud.add_child(quest_panel)
	var stack := column(quest_panel, 5)
	text(stack, "◆  THE CARTOGRAPHER'S TRAIL", 12, GOLD)
	objective = text(stack, "Find the Forest Library", 18)
	fragments = text(hud, "PRECIOUS GEMS  ·  0 / 4", 12, GOLD)
	fragments.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tools = HBoxContainer.new()
	tools.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	tools.position = Vector2(-580, 26)
	tools.add_theme_constant_override("separation", 8)
	hud.add_child(tools)
	hint_button = _icon_button(tools, "✧", "Hint · H")
	letter_button = _icon_button(tools, "✉", "Replay letter · R")
	journal_button = _icon_button(tools, "▤", "Adventure journal · Tab")
	waypoint = text(hud, "", 18, Color("fff1d2"))
	waypoint.add_theme_stylebox_override("normal", style(Color("142936ed"), 4, 6))
	waypoint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	waypoint.position = Vector2(-180, 142)
	waypoint.size.x = 360
	waypoint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status = text(hud, "OFFLINE  /  MOCK COMPANION", 11, Color("d7e0d5b3"))
	status.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	status.position = Vector2(24, -32)
	controls = text(hud, "WASD  Move   Shift  Sprint   Wheel  Zoom   E  Interact", 12, Color("f4eddbcc"))
	controls.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	controls.position = Vector2(-475, -32)
	prompt = Button.new()
	prompt.text = "E · Read the island sign"
	prompt.custom_minimum_size = Vector2(390, 54)
	prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	prompt.position = Vector2(-195, -104)
	hud.add_child(prompt)
	caption_panel = PanelContainer.new()
	caption_panel.add_theme_stylebox_override("panel", framed(Color("142936df"), 5, 14, Color("dac99d88")))
	hud.add_child(caption_panel)
	var captions := column(caption_panel, 5)
	caption_name = text(captions, "", 14, GOLD)
	caption_line = text(captions, "", 20)
	caption_name.minimum_size_changed.connect(func(): _fit_hud_cards.call_deferred())
	caption_line.minimum_size_changed.connect(func(): _fit_hud_cards.call_deferred())
	caption_panel.hide()
	task_panel = PanelContainer.new()
	task_panel.add_theme_stylebox_override("panel", framed(Color("172e39d9"), 5, 14, Color("d2bb8280")))
	hud.add_child(task_panel)
	var task := column(task_panel, 8)
	task_title = text(task, "", 14, GOLD)
	task_feedback = text(task, "", 17)
	task_hint = text(task, "", 17, GOLD)
	task_feedback.minimum_size_changed.connect(func(): _fit_hud_cards.call_deferred())
	task_hint.minimum_size_changed.connect(func(): _fit_hud_cards.call_deferred())
	text(task, "Click / E  Interact   Q / T  Select\nF  Inspect in 3D   R  Letter   H  Hint", 12, MUTED)
	task_action = button(task, "Check gear order")
	task_action.add_theme_font_size_override("font_size", 17)
	task_action.hide()
	task_dismiss = button(task, "Hide hint / feedback")
	task_dismiss.add_theme_font_size_override("font_size", 16)
	task_dismiss.hide()
	task_dismiss.visibility_changed.connect(func(): _fit_hud_cards.call_deferred())
	task_panel.hide()
	inspect_button = button(hud, "Inspect puzzle up close  [F]")
	inspect_button.add_theme_font_size_override("font_size", 17)
	inspect_button.hide()
	inspection_panel = PanelContainer.new()
	inspection_panel.add_theme_stylebox_override("panel", framed(Color("1c3443ed"), 5, 10, GOLD))
	hud.add_child(inspection_panel)
	var inspection_bar := row(inspection_panel, 12)
	inspection_status = text(inspection_bar, "Close-up view", 15, GOLD)
	inspection_status.minimum_size_changed.connect(func(): _fit_hud_cards.call_deferred())
	inspection_status.custom_minimum_size.x = 240
	inspection_exit = button(inspection_bar, "Return to walking  [F]")
	inspection_exit.add_theme_font_size_override("font_size", 16)
	inspection_panel.hide()
	reward_panel = PanelContainer.new()
	reward_panel.add_theme_stylebox_override("panel", framed(Color("172c39e8"), 5, 18, GOLD))
	hud.add_child(reward_panel)
	var reward := column(reward_panel, 7)
	reward_title = text(reward, "", 23, GOLD)
	reward_text = text(reward, "", 17)
	reward_title.minimum_size_changed.connect(func(): _fit_hud_cards.call_deferred())
	reward_text.minimum_size_changed.connect(func(): _fit_hud_cards.call_deferred())
	reward_continue = button(reward, "Continue")
	reward_panel.hide()
	veil = ColorRect.new()
	veil.color = Color(0.025, 0.06, 0.10, 0.50)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(veil)
	center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.add_child(center)
	modal = PanelContainer.new()
	modal.custom_minimum_size = Vector2(940, 0)
	center.add_child(modal)
	var modal_stack := column(modal, 14)
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	modal_stack.add_child(scroll)
	content = column(scroll, 14)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.minimum_size_changed.connect(func(): _fit_modal.call_deferred())
	footer = row(modal_stack)
	footer.hide()
	footer.minimum_size_changed.connect(func(): _fit_modal.call_deferred())
	pause_veil = ColorRect.new()
	pause_veil.color = Color(0.02, 0.06, 0.07, 0.88)
	pause_veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(pause_veil)
	var pause_center := CenterContainer.new()
	pause_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_veil.add_child(pause_center)
	var pause_panel := PanelContainer.new()
	pause_panel.custom_minimum_size = Vector2(660, 0)
	pause_center.add_child(pause_panel)
	pause_scroll = ScrollContainer.new()
	pause_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pause_scroll.custom_minimum_size.x = 604
	pause_panel.add_child(pause_scroll)
	pause_content = column(pause_scroll, 14)
	pause_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pause_content.minimum_size_changed.connect(func(): _fit_modal.call_deferred())
	pause_veil.hide()
	# Safety controls remain above every letter, puzzle, checkpoint and pause panel.
	safety = HBoxContainer.new()
	safety.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	safety.position = Vector2(-242, 26)
	safety.add_theme_constant_override("separation", 8)
	root.add_child(safety)
	pause_button = _icon_button(safety, "Ⅱ", "Pause · Esc")
	stop_button = _icon_button(safety, "×", "Stop session")
	stop_button.add_theme_color_override("font_color", Color("dfb4a1"))
	get_viewport().size_changed.connect(_resize)
	_resize()

func _resize() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	modal.custom_minimum_size.x = minf(940, viewport_size.x - 48)
	# Free-standing HUD labels need explicit widths to prevent single-letter wrapping.
	waypoint.set_anchors_preset(Control.PRESET_TOP_LEFT)
	waypoint.position = Vector2((viewport_size.x - 450) / 2, 28)
	waypoint.size = Vector2(450, 30)
	status.set_anchors_preset(Control.PRESET_TOP_LEFT)
	status.position = Vector2(24, viewport_size.y - 33)
	status.size = Vector2(500, 25)
	controls.set_anchors_preset(Control.PRESET_TOP_LEFT)
	controls.position = Vector2(viewport_size.x - 480, viewport_size.y - 33)
	controls.size = Vector2(465, 25)
	prompt.set_anchors_preset(Control.PRESET_TOP_LEFT)
	prompt.position = Vector2(viewport_size.x * 0.5 + 100, viewport_size.y * 0.5 + 74)
	prompt.size = Vector2(390, 54)
	inspect_button.position = Vector2(viewport_size.x - 430, viewport_size.y - 240)
	inspect_button.size = Vector2(390, 46)
	tools.set_anchors_preset(Control.PRESET_TOP_LEFT)
	tools.position = Vector2(viewport_size.x - 338, 26)
	safety.set_anchors_preset(Control.PRESET_TOP_LEFT)
	safety.position = Vector2(viewport_size.x - 146, 26)
	fragments.position = Vector2((viewport_size.x - 300) * 0.5, viewport_size.y - 107)
	fragments.size = Vector2(300, 22)
	caption_panel.position = Vector2(28, viewport_size.y - 215)
	caption_panel.custom_minimum_size = Vector2(410, 0)
	caption_panel.size.x = 410
	task_panel.position = Vector2(28, 210)
	task_panel.custom_minimum_size.x = 350
	task_panel.size.x = 350
	inspection_panel.position = Vector2((viewport_size.x - 530) * 0.5, 160)
	inspection_panel.custom_minimum_size.x = 530
	inspection_panel.size.x = 530
	reward_panel.position = Vector2(viewport_size.x - 738, viewport_size.y - 300)
	reward_panel.custom_minimum_size.x = 710
	reward_panel.size.x = 710
	_fit_modal.call_deferred()
	_fit_hud_cards.call_deferred()

func _fit_hud_cards() -> void:
	if is_instance_valid(inspection_panel):
		inspection_panel.size = Vector2(530, 0)
	if is_instance_valid(caption_panel):
		caption_panel.size = Vector2(410, 0)
		caption_panel.position.y = minf(get_viewport().get_visible_rect().size.y - 215, get_viewport().get_visible_rect().size.y - 65 - caption_panel.size.y)
	if is_instance_valid(task_panel):
		task_panel.size = Vector2(350, 0)
	if is_instance_valid(reward_panel):
		reward_panel.size = Vector2(710, 0)

func _fit_modal() -> void:
	if not is_instance_valid(content):
		return
	var available := get_viewport().get_visible_rect().size.y - 208
	if footer.visible:
		available -= footer.get_combined_minimum_size().y + 14
	scroll.custom_minimum_size.y = minf(content.get_combined_minimum_size().y, available)
	if is_instance_valid(pause_scroll):
		pause_scroll.custom_minimum_size.y = minf(pause_content.get_combined_minimum_size().y, get_viewport().get_visible_rect().size.y - 208)

func show_modal(kicker: String, title: String, subtitle: String = "") -> VBoxContainer:
	task_panel.hide()
	reward_panel.hide()
	modal.add_theme_stylebox_override("panel", framed(DARK, 8, 28, Color("c2ae7c88")))
	veil.color = Color(0.025, 0.06, 0.10, 0.50)
	for child in footer.get_children():
		footer.remove_child(child)
		child.queue_free()
	footer.hide()
	for child in content.get_children():
		content.remove_child(child)
		child.queue_free()
	veil.show()
	scroll.scroll_vertical = 0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	GameState.ui_locked = true
	for control in [hint_button, letter_button, journal_button, prompt]:
		control.focus_mode = Control.FOCUS_NONE
	text(content, "—  " + kicker.to_upper() + "  —", 12, GOLD)
	var heading := text(content, title, 34)
	var title_font := SystemFont.new()
	title_font.font_names = PackedStringArray(["Georgia", "Palatino Linotype"])
	heading.add_theme_font_override("font", title_font)
	if not subtitle.is_empty():
		text(content, subtitle, 19, MUTED)
	_focus_first.call_deferred()
	return content

func _focus_first() -> void:
	for control in content.find_children("*", "Button", true, false):
		if not control.disabled:
			control.grab_focus()
			break

func close_modal() -> void:
	veil.hide()
	GameState.ui_locked = pause_veil.visible or GameState.stopped
	for control in [hint_button, letter_button, journal_button, prompt]:
		control.focus_mode = Control.FOCUS_ALL

static func column(parent: Node, gap: int = 12) -> VBoxContainer:
	var result := VBoxContainer.new()
	result.add_theme_constant_override("separation", gap)
	parent.add_child(result)
	return result

static func row(parent: Node, gap: int = 10) -> HBoxContainer:
	var result := HBoxContainer.new()
	result.add_theme_constant_override("separation", gap)
	parent.add_child(result)
	return result

static func text(parent: Node, value: String, size: int = 20, color: Color = INK) -> Label:
	var result := Label.new()
	result.text = value
	result.add_theme_font_size_override("font_size", size)
	result.add_theme_color_override("font_color", color)
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(result)
	return result

static func button(parent: Node, value: String, action: Callable = Callable()) -> Button:
	var result := Button.new()
	result.text = value
	result.custom_minimum_size.y = 46
	result.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	parent.add_child(result)
	if action.is_valid():
		result.pressed.connect(action)
	return result

static func style(color: Color, radius: int, padding: int) -> StyleBoxFlat:
	var result := StyleBoxFlat.new()
	result.bg_color = color
	result.set_corner_radius_all(radius)
	result.content_margin_left = padding
	result.content_margin_right = padding
	result.content_margin_top = padding
	result.content_margin_bottom = padding
	return result

static func framed(color: Color, radius: int, padding: int, border: Color = Color("95a8a44d")) -> StyleBoxFlat:
	var result := style(color, radius, padding)
	result.set_border_width_all(1)
	result.border_color = border
	result.shadow_color = Color("06121d55")
	result.shadow_size = 12
	result.shadow_offset = Vector2(0, 6)
	return result

func _icon_button(parent: Node, symbol: String, help: String) -> Button:
	var result := button(parent, symbol)
	result.custom_minimum_size = Vector2(52, 52)
	result.add_theme_font_size_override("font_size", 25)
	result.tooltip_text = help
	result.add_theme_stylebox_override("normal", framed(Color("1d3443aa"), 26, 8, Color("d8e1d44d")))
	result.add_theme_stylebox_override("hover", framed(Color("51656cdd"), 26, 8, GOLD))
	return result

func cinematic_title() -> void:
	modal.add_theme_stylebox_override("panel", style(Color.TRANSPARENT, 0, 28))
	veil.color = Color(0.015, 0.035, 0.08, 0.15)
	for control in content.get_children():
		if control is Label:
			control.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
