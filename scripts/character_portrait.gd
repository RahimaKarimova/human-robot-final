class_name CharacterPortrait
extends SubViewportContainer
var profile: String = "elara"

func _ready() -> void:
	custom_minimum_size = Vector2(185, 235)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	stretch = true
	var viewport := SubViewport.new()
	viewport.size = Vector2i(185, 235)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var root := Node3D.new()
	viewport.add_child(root)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("d6e6e4")
	environment.environment.ambient_light_energy = 0.7
	root.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-25, -30, 0)
	sun.light_energy = 0.7
	root.add_child(sun)
	var actor := IslandCharacter.new()
	actor.profile = profile
	actor.portrait = true
	root.add_child(actor)
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.position = Vector3(0, 1.75, 3.1)
	camera.look_at(Vector3(0, 1.4, 0))
	camera.fov = 35
	camera.current = true
