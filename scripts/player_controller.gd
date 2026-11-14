class_name Explorer
extends CharacterBody3D
const WALK_SPEED := 7.0
const SPRINT_SPEED := 11.0
const MIN_ZOOM := 3.0
const MAX_ZOOM := 12.0
var yaw: float = 0.0
var pitch: float = -0.32
var sensitivity: float = 0.003
var zoom_target: float = 6.5
var pivot: Node3D
var arm: SpringArm3D
var camera: Camera3D
var model: IslandCharacter

func _ready() -> void:
	var collider := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.31
	shape.height = 2.15
	collider.shape = shape
	collider.position.y = 1.075
	add_child(collider)
	model = IslandCharacter.new()
	model.profile = "explorer"
	add_child(model)
	pivot = Node3D.new()
	pivot.position.y = 1.8
	add_child(pivot)
	arm = SpringArm3D.new()
	arm.spring_length = zoom_target
	arm.margin = 0.2
	arm.add_excluded_object(get_rid())
	pivot.add_child(arm)
	camera = Camera3D.new()
	camera.fov = 62
	camera.current = true
	arm.add_child(camera)

func change_zoom(amount: float) -> void:
	zoom_target = clampf(zoom_target + amount, MIN_ZOOM, MAX_ZOOM)

func _unhandled_input(event: InputEvent) -> void:
	if GameState.inspecting:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not GameState.ui_locked:
		yaw -= event.relative.x * sensitivity
		pitch = clampf(pitch - event.relative.y * sensitivity, -0.85, 0.05)
	if event is InputEventMouseButton and not GameState.ui_locked:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if event.pressed else Input.MOUSE_MODE_VISIBLE
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			change_zoom(-0.7)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			change_zoom(0.7)
	if not GameState.ui_locked and event.is_pressed():
		if event.is_action_pressed("zoom_in"):
			change_zoom(-0.7)
		elif event.is_action_pressed("zoom_out"):
			change_zoom(0.7)

func _physics_process(delta: float) -> void:
	pivot.rotation = Vector3(pitch, yaw, 0)
	arm.spring_length = lerpf(arm.spring_length, zoom_target, minf(delta * 9, 1))
	if GameState.ui_locked or GameState.stopped or GameState.inspecting or not GameState.started:
		velocity = Vector3.ZERO
		model.update_locomotion(0)
		return
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := Vector3(input.x, 0, input.y).rotated(Vector3.UP, yaw)
	var sprinting := Input.is_action_pressed("sprint")
	var speed := SPRINT_SPEED if sprinting else WALK_SPEED
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	if not is_on_floor():
		velocity.y -= 20 * delta
	else:
		velocity.y = 0
	move_and_slide()
	position.x = clampf(position.x, -32, 32)
	position.z = clampf(position.z, -48, 32)
	var moving := direction.length_squared() > 0.01
	model.update_locomotion((1.4 if sprinting else 1.0) if moving else 0.0)
	if moving:
		model.rotation.y = lerp_angle(model.rotation.y, atan2(direction.x, direction.z), minf(delta * 12, 1))
