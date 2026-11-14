class_name IslandItemArt
extends Control
## Small original vector illustrations for inspectable books, gears and glyphs.
var kind: String = "book"
var tint := Color("c6a15c")
var mark: String = ""

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	var c := size * 0.5
	if kind == "book":
		draw_ellipse(c + Vector2(2, 26), Vector2(34, 5), Color("09142066"))
		var cover := PackedVector2Array([c + Vector2(-25, -26), c + Vector2(18, -32), c + Vector2(28, -22), c + Vector2(28, 28), c + Vector2(-15, 34), c + Vector2(-25, 25)])
		draw_colored_polygon(cover, tint.darkened(0.35))
		var pages := PackedVector2Array([c + Vector2(-17, -18), c + Vector2(23, -24), c + Vector2(23, 23), c + Vector2(-17, 29)])
		draw_colored_polygon(pages, Color("d5d0b4"))
		var face := PackedVector2Array([c + Vector2(-25, -26), c + Vector2(18, -32), c + Vector2(18, 18), c + Vector2(-25, 25)])
		draw_colored_polygon(face, tint)
		draw_line(c + Vector2(-18, -25), c + Vector2(-18, 23), tint.darkened(0.45), 3, true)
		draw_line(c + Vector2(-11, -20), c + Vector2(11, -23), Color("f3d38d"), 1, true)
		draw_line(c + Vector2(-11, 13), c + Vector2(11, 10), Color("f3d38d"), 1, true)
		if mark == "❧":
			draw_line(c + Vector2(-8, 5), c + Vector2(7, -14), Color("fbe1a0"), 2, true)
			for i in range(5):
				var at := c + Vector2(-7 + i * 3, 3 - i * 3.5)
				draw_line(at, at + Vector2(-2, -7), Color("fbe1a0"), 2, true)
				draw_line(at, at + Vector2(6, 0), Color("fbe1a0"), 2, true)
		else:
			draw_string(ThemeDB.fallback_font, c + Vector2(-9, 2), mark, HORIZONTAL_ALIGNMENT_LEFT, -1, 25, Color("f7e6c6"))
	elif kind == "gear":
		for i in range(12):
			var angle := TAU * i / 12
			var corners := PackedVector2Array()
			for point in [Vector2(22, -5), Vector2(32, -5), Vector2(32, 5), Vector2(22, 5)]:
				corners.append(c + point.rotated(angle))
			draw_colored_polygon(corners, tint)
		draw_circle(c, 26, tint)
		draw_arc(c, 21, 0, TAU, 40, tint.lightened(0.3), 2, true)
		draw_circle(c, 10, Color("182b36"))
		draw_circle(c, 4, Color("d9ca9c"))
	elif kind == "symbol":
		if mark == "SUN":
			draw_circle(c, 17, tint)
			for i in range(8):
				var angle := TAU * i / 8
				draw_line(c + Vector2(23, 0).rotated(angle), c + Vector2(31, 0).rotated(angle), tint, 3, true)
		elif mark == "STAR":
			var points := PackedVector2Array()
			for i in range(10):
				points.append(c + Vector2(0, -31 if i % 2 == 0 else -13).rotated(i * TAU / 10))
			draw_colored_polygon(points, tint)
		else:
			for j in range(3):
				var wave := PackedVector2Array()
				for i in range(31):
					wave.append(c + Vector2(i * 2 - 30, sin(i * 0.22) * 6 + j * 12 - 12))
				draw_polyline(wave, tint, 3, true)

func draw_ellipse(center: Vector2, radius: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for i in range(32):
		points.append(center + Vector2(cos(i * TAU / 32) * radius.x, sin(i * TAU / 32) * radius.y))
	draw_colored_polygon(points, color)
