class_name AdventureHUD
extends Control
## Code-drawn game HUD: live circular map, compass, crosshair and four inventory slots.
var player: Node3D

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if not GameState.started:
		return
	var ink := Color("142731dd")
	var gold := Color("d7c294")
	var center := Vector2(104, 106)
	draw_circle(center + Vector2(0, 4), 77, Color("07161a55"))
	draw_circle(center, 76, ink)
	draw_arc(center, 74, 0, TAU, 80, gold, 2, true)
	draw_circle(center, 67, Color("46898e"))
	var coast := PackedVector2Array()
	for i in range(48):
		var angle := TAU * i / 48
		coast.append(center + Vector2(cos(angle) * 56, sin(angle) * 61))
	draw_colored_polygon(coast, Color("7b9c7b"))
	var points := [Vector2(0, 29), Vector2(-15, 12), Vector2(15, 12), Vector2(23, 12), Vector2(23, -15), Vector2(-15, -15), Vector2(-6, -15), Vector2(0, -30)]
	for i in range(points.size() - 1):
		draw_line(center + (points[i] + Vector2(0, 5)) * 1.25, center + (points[i + 1] + Vector2(0, 5)) * 1.25, Color("d5c89d"), 2, true)
	for i in range(5):
		var stage: Dictionary = Content.stage(i)
		var at := center + Vector2(stage.position[0], stage.position[2] + 5) * 1.25
		draw_circle(at, 4.0, gold if i <= GameState.stage_index else Color("40565a"))
		if i == GameState.stage_index:
			draw_arc(at, 7, 0, TAU, 20, Color("fff0bd"), 1.5, true)
	if is_instance_valid(player):
		var at := center + Vector2(player.position.x, player.position.z + 5) * 1.25
		var arrow := PackedVector2Array([Vector2(0, -7), Vector2(5, 5), Vector2(0, 2), Vector2(-5, 5)])
		var transformed := PackedVector2Array()
		for point in arrow:
			transformed.append(point.rotated(player.yaw) + at)
		draw_colored_polygon(transformed, Color("fff5db"))
	draw_string(ThemeDB.fallback_font, center + Vector2(-5, -59), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("f6e4bc"))
	# Minimal crosshair, no combat reticle or unnecessary health/stamina meters.
	var cross := size * 0.5
	draw_circle(cross, 2, Color("fff4dd99"))
	draw_arc(cross, 5, 0, TAU, 20, Color("fff4dd55"), 1, true)
	var start := Vector2(size.x * 0.5 - 123, size.y - 84)
	for i in range(4):
		var at := start + Vector2(i * 65, 0)
		var rect := Rect2(at, Vector2(57, 57))
		var gem: Dictionary = Content.gems[i]
		var collected := GameState.fragments.has(gem.stage_id)
		draw_style_box(_slot_style(collected), rect)
		var c := at + Vector2(28.5, 26)
		var color := Color(gem.color) if collected else Color("52666d")
		var tile := PackedVector2Array([c + Vector2(-14, -6), c + Vector2(-7, -14), c + Vector2(7, -14), c + Vector2(14, -6), c + Vector2(0, 14)])
		draw_colored_polygon(tile, color)
		draw_colored_polygon(PackedVector2Array([c + Vector2(-14, -6), c + Vector2(-7, -14), c + Vector2(0, -6)]), color.lightened(0.3))
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -6), c + Vector2(14, -6), c + Vector2(0, 14)]), color.darkened(0.22))
		draw_line(c + Vector2(-14, -6), c + Vector2(14, -6), color.lightened(0.4), 1, true)
		draw_string(ThemeDB.fallback_font, at + Vector2(3, 50), "Set" if GameState.socketed_gems.has(gem.id) else gem.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, color.lightened(0.35))

func _slot_style(collected: bool) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color("293b43dd") if collected else Color("172b35bb")
	box.set_corner_radius_all(5)
	box.set_border_width_all(2 if collected else 1)
	box.border_color = Color("dfc78e") if collected else Color("c8d3c34d")
	return box
