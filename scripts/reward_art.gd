class_name RewardArt
extends Control
var time: float = 0.0
var fragment: int = 1

func _ready() -> void:
	custom_minimum_size = Vector2(800, 190)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(delta: float) -> void:
	if not GameState.paused:
		time += delta
		queue_redraw()

func _draw() -> void:
	var c := Vector2(size.x * 0.5, 128)
	var opened := smoothstep(0.35, 1.4, time)
	var gold := Color("e9cc86")
	# Halo, a ribboned gift, hinged lid and an emerging illustrated map piece.
	for i in range(8):
		draw_circle(c + Vector2(0, -28), 85 - i * 8, Color(0.91, 0.75, 0.36, 0.015 + i * 0.005))
	draw_style_box(IslandUI.framed(Color("6f5d86"), 4, 0, gold), Rect2(c + Vector2(-52, -23), Vector2(104, 72)))
	draw_rect(Rect2(c + Vector2(-8, -23), Vector2(16, 72)), gold)
	draw_rect(Rect2(c + Vector2(-52, 7), Vector2(104, 11)), gold.darkened(0.1))
	var lift := c + Vector2(0, -30 - opened * 57)
	draw_set_transform(lift, -opened * 0.3)
	draw_style_box(IslandUI.framed(Color("9580a4"), 4, 0, gold), Rect2(Vector2(-58, -10), Vector2(116, 22)))
	draw_rect(Rect2(Vector2(-9, -10), Vector2(18, 22)), gold)
	draw_arc(Vector2(-12, -15), 14, PI, TAU + 0.7, 24, gold, 4, true)
	draw_arc(Vector2(12, -15), 14, PI - 0.7, TAU, 24, gold, 4, true)
	draw_set_transform(Vector2.ZERO)
	if opened > 0:
		var map_center := c + Vector2(0, -20 - opened * 76)
		var points := PackedVector2Array([Vector2(-25, -22), Vector2(-2, -28), Vector2(24, -20), Vector2(27, 22), Vector2(1, 30), Vector2(-26, 20)])
		for i in range(points.size()):
			points[i] += map_center
		draw_colored_polygon(points, Color("f3dfa5"))
		draw_line(map_center + Vector2(-8, -19), map_center + Vector2(-5, 19), Color("ad9564"), 2, true)
		draw_line(map_center + Vector2(10, -16), map_center + Vector2(12, 18), Color("ad9564"), 2, true)
		draw_string(ThemeDB.fallback_font, map_center + Vector2(-5, 5), str(fragment), HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color("66523d"))
		for i in range(14):
			var angle := i * TAU / 14 + time * 0.12
			var at := c + Vector2(0, -35) + Vector2(cos(angle) * (75 + i % 3 * 13), sin(angle) * 58)
			var radius := 2.2 + sin(time * 3 + i) * 1.3
			draw_line(at - Vector2(radius, 0), at + Vector2(radius, 0), gold, 1.3, true)
			draw_line(at - Vector2(0, radius), at + Vector2(0, radius), gold, 1.3, true)
