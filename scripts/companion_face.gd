class_name CompanionFace
extends Control
## Animated screen rehearsal only. These are not Reachy SDK motions.
var motion_id: String = "LISTEN"
var elapsed: float = 0.0

func _ready() -> void:
	custom_minimum_size = Vector2(220, 115)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(delta: float) -> void:
	if not GameState.paused and not GameState.stopped:
		elapsed += delta
		queue_redraw()

func _draw() -> void:
	var center := Vector2(size.x * 0.5, 63)
	var bob := sin(elapsed * 3.0) * (5.0 if motion_id in ["NOD", "CELEBRATE"] else 1.5)
	center.y += bob
	var antenna := sin(elapsed * 5.0) * (14.0 if motion_id in ["WAVE", "CELEBRATE"] else 3.0)
	var gold := Color("e5c577")
	draw_line(center + Vector2(-36, -23), center + Vector2(-48 - antenna, -48), gold, 4, true)
	draw_line(center + Vector2(36, -23), center + Vector2(48 + antenna, -48), gold, 4, true)
	draw_circle(center + Vector2(-48 - antenna, -48), 5, gold)
	draw_circle(center + Vector2(48 + antenna, -48), 5, gold)
	draw_style_box(IslandUI.framed(Color("e6ede5"), 20, 6, Color("6d9e98")), Rect2(center - Vector2(65, 30), Vector2(130, 65)))
	var blink := 1.8 if fmod(elapsed, 4.2) < 0.15 else 10.0
	var gaze := 5.0 if motion_id == "POINT" else sin(elapsed * 0.8) * 2.0
	for x in [-25, 25]:
		draw_ellipse_eye(center + Vector2(x + gaze, -1), blink)
	if motion_id == "CELEBRATE":
		for i in range(6):
			var angle := i * TAU / 6 + elapsed
			draw_circle(center + Vector2(cos(angle) * 88, sin(angle) * 39), 3, gold)

func draw_ellipse_eye(center: Vector2, height: float) -> void:
	draw_style_box(IslandUI.framed(Color("184751"), 8, 0, Color.TRANSPARENT), Rect2(center - Vector2(8, height), Vector2(16, height * 2)))
