class_name IslandCharacter
extends Node3D
## Original articulated fantasy character. All speech is fixed prerecorded game content.
signal greeted(actor: IslandCharacter)
var profile: String = "explorer"
var actor_name: String = "Explorer"
var portrait: bool = false
var player_target: Node3D
var torso: Node3D
var head: Node3D
var left_arm: Node3D
var right_arm: Node3D
var left_leg: Node3D
var right_leg: Node3D
var forearm: Node3D
var cloak: Node3D
var bubble: Label3D
var home: Vector3
var time: float = 0.0
var wave_time: float = -1.0
var near: bool = false
var greet_count: int = 0
var move_blend: float = 0.0
var locomotion: bool = false
var config: Dictionary
var eyes: Array[Node3D] = []
var mouth: Node3D
var speaking: bool = false
var celebration_time: float = 0.0
var celebration_count: int = 0

func celebrate() -> void:
	celebration_time = 3.0
	celebration_count += 1
	wave_time = -1

func _ready() -> void:
	config = Content.presentation.characters.get(profile, Content.presentation.characters.explorer)
	actor_name = config.name
	home = position
	torso = Node3D.new()
	add_child(torso)
	_build_body()
	if not portrait and profile != "explorer":
		bubble = EchoWorld.label(self, Vector3(0, 2.85, 0), "", 24, Color("fff0cb"))
		bubble.no_depth_test = true
	# Inspection cameras show the work surface without characters blocking its objects.
	for geometry in find_children("*", "GeometryInstance3D", true, false):
		geometry.layers = 4

func _build_body() -> void:
	var cloth := Color(config.color)
	var skin := Color(config.skin)
	var hair := Color(config.hair)
	var dark := Color("253842")
	var brass := Color("dfc992")
	# The silhouette uses articulated limbs, layered fabric, fitted boots and a sculpted face.
	var body := EchoWorld.cylinder(torso, Vector3(0, 1.27, 0), 0.27, 0.63, cloth, 12)
	(body.mesh as CylinderMesh).top_radius = 0.33
	EchoWorld.cylinder(torso, Vector3(0, 0.97, 0), 0.29, 0.12, Color("4d4240"), 12)
	EchoWorld.box(torso, Vector3(0, 0.97, 0.29), Vector3(0.14, 0.12, 0.06), brass)
	for side in [-1, 1]:
		var lapel := EchoWorld.box(torso, Vector3(side * 0.14, 1.4, 0.24), Vector3(0.12, 0.47, 0.05), cloth.lightened(0.3))
		lapel.rotation.z = side * 0.23
		for i in range(3):
			EchoWorld.sphere(torso, Vector3(side * 0.07, 1.15 + i * 0.12, 0.27), 0.023, brass)
	# Coat tails / skirt panels: six shaped fabric panels create a more expressive outline.
	for i in range(6):
		var angle := TAU * i / 6
		var tail := EchoWorld.box(torso, Vector3(sin(angle) * 0.25, 0.75, cos(angle) * 0.22), Vector3(0.25, 0.48, 0.08), cloth.darkened(0.05 + (i % 2) * 0.08))
		tail.rotation = Vector3(cos(angle) * -0.12, angle, sin(angle) * 0.12)
	left_leg = _leg(-1, dark, brass)
	right_leg = _leg(1, dark, brass)
	left_arm = _arm(-1, cloth, skin, brass)
	right_arm = _arm(1, cloth, skin, brass)
	head = Node3D.new()
	head.position = Vector3(0, 1.8, 0)
	torso.add_child(head)
	EchoWorld.cylinder(torso, Vector3(0, 1.61, 0), 0.12, 0.2, skin, 10)
	var face := EchoWorld.sphere(head, Vector3(0, 0.15, 0), 0.28, skin)
	face.scale = Vector3(0.91, 1.15, 0.9)
	for side in [-1, 1]:
		var ear := EchoWorld.sphere(head, Vector3(side * 0.258, 0.13, 0), 0.065, skin)
		ear.scale = Vector3(0.65, 1, 0.7)
		# Large inset eyes, coloured irises, separate pupils and catch lights.
		var eye := EchoWorld.sphere(head, Vector3(side * 0.105, 0.18, 0.223), 0.07, Color("f1ede0"))
		eye.scale = Vector3(1, 0.8, 0.34)
		var iris := EchoWorld.sphere(head, Vector3(side * 0.105, 0.18, 0.246), 0.047, cloth.lightened(0.18))
		iris.scale = Vector3(0.7, 1, 0.25)
		var pupil := EchoWorld.sphere(head, Vector3(side * 0.105, 0.18, 0.256), 0.025, Color("172a36"))
		pupil.scale.z = 0.3
		var highlight := EchoWorld.sphere(head, Vector3(side * 0.105 - 0.012, 0.197, 0.266), 0.009, Color("fff8e8"))
		for part in [eye, iris, pupil, highlight]:
			part.set_meta("open_scale", part.scale.y)
			eyes.append(part)
		var brow := EchoWorld.box(head, Vector3(side * 0.108, 0.272, 0.225), Vector3(0.105, 0.021, 0.02), hair)
		brow.rotation.z = side * -0.08
	EchoWorld.sphere(head, Vector3(0, 0.095, 0.26), 0.037, skin.lightened(0.08))
	mouth = EchoWorld.box(head, Vector3(0, 0.012, 0.238), Vector3(0.09, 0.016, 0.012), Color("ad7069"))
	mouth.rotation.z = 0.03
	# Cap of hair and individually angled locks rather than a featureless cylinder head.
	var hair_cap := EchoWorld.sphere(head, Vector3(0, 0.3, -0.04), 0.29, hair)
	hair_cap.scale = Vector3(1.01, 0.77, 0.95)
	for i in range(7):
		var lock := EchoWorld.box(head, Vector3((i - 3) * 0.065, 0.34 - absf(i - 3) * 0.015, 0.2), Vector3(0.076, 0.22 + (i % 3) * 0.03, 0.09), hair.lightened((i % 2) * 0.05))
		lock.rotation.z = -0.24 + i * 0.065
	if profile in ["elara", "nia"]:
		for side in [-1, 1]:
			var side_hair := EchoWorld.sphere(head, Vector3(side * 0.24, -0.03, -0.06), 0.16, hair)
			side_hair.scale = Vector3(0.65, 2.1, 0.8)
			EchoWorld.sphere(head, Vector3(side * 0.25, -0.13, 0.05), 0.035, brass)
	cloak = Node3D.new()
	torso.add_child(cloak)
	cloak.position = Vector3(0, 1.5, -0.24)
	var cape := EchoWorld.cylinder(cloak, Vector3(0, -0.32, -0.03), 0.4, 0.8, cloth.darkened(0.23), 10)
	(cape.mesh as CylinderMesh).top_radius = 0.24
	cape.scale = Vector3(1, 1, 0.4)
	if profile == "explorer":
		EchoWorld.cylinder(head, Vector3(0, 0.42, -0.02), 0.41, 0.055, Color("d7bc82"), 16)
		EchoWorld.cylinder(head, Vector3(0, 0.53, -0.02), 0.27, 0.23, Color("b49762"), 12)
		EchoWorld.cylinder(head, Vector3(0, 0.45, -0.02), 0.275, 0.07, Color("6d5140"), 12)
		EchoWorld.box(torso, Vector3(0, 1.27, -0.39), Vector3(0.42, 0.5, 0.2), Color("9d744b"))
		EchoWorld.cylinder(torso, Vector3(0, 1.59, 0), 0.2, 0.12, Color("bc694f"), 12)
	elif profile == "milo":
		for side in [-1, 1]:
			var lens := EchoWorld.cylinder(head, Vector3(side * 0.11, 0.38, 0.24), 0.08, 0.05, brass, 12)
			lens.rotation.x = PI / 2
			EchoWorld.sphere(head, Vector3(side * 0.11, 0.38, 0.28), 0.05, Color("80b2b4"))
		EchoWorld.box(torso, Vector3(0.31, 1.05, 0.09), Vector3(0.15, 0.26, 0.12), Color("6e523b"))
	elif profile == "elara":
		var brooch := EchoWorld.sphere(torso, Vector3(0, 1.48, 0.31), 0.07, brass)
		brooch.scale = Vector3(0.65, 1.1, 0.4)
		EchoWorld.box(left_arm, Vector3(-0.05, -0.55, 0.08), Vector3(0.24, 0.32, 0.08), Color("54745e"))
	elif profile == "nia":
		EchoWorld.cylinder(head, Vector3(0, 0.37, 0), 0.295, 0.065, Color("ca9877"), 12)
		EchoWorld.sphere(torso, Vector3(0.31, 0.89, 0), 0.13, Color("9f7954"))
	elif profile == "ori":
		EchoWorld.sphere(head, Vector3(0.21, 0.33, 0.2), 0.055, Color("94cbd4"))
		EchoWorld.box(torso, Vector3(0.24, 1.32, 0.27), Vector3(0.05, 0.5, 0.06), brass)

func _leg(side: int, dark: Color, brass: Color) -> Node3D:
	var joint := Node3D.new()
	joint.position = Vector3(side * 0.15, 0.92, 0)
	torso.add_child(joint)
	EchoWorld.cylinder(joint, Vector3(0, -0.27, 0), 0.105, 0.54, dark, 10)
	EchoWorld.cylinder(joint, Vector3(0, -0.65, 0), 0.13, 0.37, Color("34434a"), 10)
	EchoWorld.cylinder(joint, Vector3(0, -0.49, 0), 0.14, 0.07, brass.darkened(0.25), 10)
	EchoWorld.box(joint, Vector3(0, -0.81, 0.055), Vector3(0.23, 0.16, 0.33), Color("28383d"))
	return joint

func _arm(side: int, cloth: Color, skin: Color, brass: Color) -> Node3D:
	var joint := Node3D.new()
	joint.position = Vector3(side * 0.34, 1.51, 0)
	torso.add_child(joint)
	joint.rotation.z = side * 0.08
	var sleeve := EchoWorld.cylinder(joint, Vector3(side * 0.02, -0.17, 0), 0.115, 0.35, cloth, 10)
	(sleeve.mesh as CylinderMesh).top_radius = 0.14
	var elbow := Node3D.new()
	elbow.position = Vector3(side * 0.02, -0.34, 0)
	joint.add_child(elbow)
	EchoWorld.cylinder(elbow, Vector3(0, -0.14, 0), 0.082, 0.28, skin, 10)
	EchoWorld.cylinder(elbow, Vector3(0, -0.24, 0), 0.09, 0.09, brass.darkened(0.15), 10)
	var palm := EchoWorld.sphere(elbow, Vector3(0, -0.33, 0), 0.09, skin)
	palm.scale = Vector3(0.8, 1.15, 0.6)
	if side == 1:
		forearm = elbow
	return joint

func update_locomotion(amount: float) -> void:
	move_blend = amount
	locomotion = amount > 0.01

func _process(delta: float) -> void:
	if GameState.stopped or GameState.paused:
		return
	time += delta
	var blink_phase := fmod(time + (float(profile.length()) * 0.24), 4.5)
	var openness := 1.0 - sin(clampf((blink_phase - 4.25) / 0.2, 0, 1) * PI) * 0.94
	for eye in eyes:
		eye.scale.y = float(eye.get_meta("open_scale")) * openness
	mouth.scale.y = 1.0 + (absf(sin(time * 17)) * 2.8 if speaking else 0.0)
	torso.position.y = sin(time * 2.1) * 0.012
	cloak.rotation.x = sin(time * 2.2) * 0.05 + move_blend * 0.18
	if profile == "explorer":
		var gait := sin(time * (14 if move_blend > 1 else 10)) * minf(move_blend, 1.4)
		left_arm.rotation.x = gait * 0.5
		right_arm.rotation.x = -gait * 0.5
		left_leg.rotation.x = -gait * 0.5
		right_leg.rotation.x = gait * 0.5
		return
	if portrait:
		head.rotation.y = sin(time * 0.8) * 0.05
		head.rotation.z = sin(time * 1.1) * 0.025
		return
	if is_instance_valid(player_target) and GameState.started:
		var distance := global_position.distance_to(player_target.global_position)
		if distance < 6.5 and not near:
			near = true
			wave_time = 0.0
			greet_count += 1
			greeted.emit(self)
		elif distance > 10:
			near = false
		if near:
			var direction := player_target.global_position - global_position
			rotation.y = lerp_angle(rotation.y, atan2(direction.x, direction.z), delta * 3)
			position = position.lerp(home, minf(delta * 2, 1))
		else:
			# Gentle pacing stays inside each character's clear, non-colliding staging area.
			var destination := home + Vector3(sin(time * 0.32) * 0.55, 0, cos(time * 0.32) * 0.2)
			position = position.lerp(destination, minf(delta * 1.5, 1))
			rotation.y = lerp_angle(rotation.y, sin(time * 0.45) * 0.45, delta)
		left_leg.rotation.x = sin(time * 6) * (0.0 if near else 0.14)
		right_leg.rotation.x = -left_leg.rotation.x
	left_arm.rotation.x = sin(time * 1.6) * 0.045
	left_arm.rotation.z = lerp_angle(left_arm.rotation.z, -0.08, delta * 5)
	if wave_time >= 0:
		wave_time += delta
		right_arm.rotation.z = 2.3 + sin(wave_time * 9) * 0.22
		forearm.rotation.z = sin(wave_time * 11) * 0.25
		if bubble:
			bubble.text = "Hello, traveller!" if wave_time < 2.6 else ""
		if wave_time > 2.8:
			wave_time = -1
	else:
		right_arm.rotation.z = lerp_angle(right_arm.rotation.z, 0.08, delta * 5)
		forearm.rotation.z = lerp_angle(forearm.rotation.z, 0, delta * 5)
		head.rotation.y = sin(time * 0.8) * 0.07
		head.rotation.x = sin(time * 3.5) * (0.035 if speaking else 0.012)
	if celebration_time > 0:
		celebration_time = maxf(0, celebration_time - delta)
		var cheer := sin((3.0 - celebration_time) * 8)
		left_arm.rotation.z = -2.15 - cheer * 0.18
		right_arm.rotation.z = 2.15 + cheer * 0.18
		torso.position.y = absf(cheer) * 0.09
		if bubble:
			bubble.text = "Wonderful work!" if celebration_time > 0 else ""
