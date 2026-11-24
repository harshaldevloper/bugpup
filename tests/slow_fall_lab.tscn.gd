extends Node3D
## Test scene for the Bugpup's replay test.
##
## It holds one body that drops SLOWLY past the out-of-bounds
## threshold, and the agent's input actions do NOTHING to it. So the
## finding can only appear from the body's own fall.
##
## The timing is the point:
##
##   - the agent presses a key ONCE, early on
##   - the body then falls on its own, and crosses the threshold
##     several seconds later
##
## The old replay ran for (last input frame + 60 frames). With the
## input happening early, that window closed long before the body had
## fallen far enough, so a REAL bug could never be confirmed.

## How fast the body drops, in units per second.
##
## At 8 units/second the body needs 300 physics frames (5 seconds) to
## fall from its start to the out-of-bounds threshold. That is far
## longer than the old replay's 60-frame tail, and comfortably inside
## the new 10-second budget - which is exactly the gap this test
## exists to cover.
const FALL_SPEED := 8.0

## Where the body starts.
const START_Y := 10.0

## The input actions the agent will press. The lab defines its own, so
## the agent has something to press.
const KEYS := {
	"move_left": KEY_A,
	"move_right": KEY_D,
	"move_forward": KEY_W,
	"move_back": KEY_S,
	"jump": KEY_SPACE,
	"dash": KEY_SHIFT,
}


func _ready() -> void:
	_setup_input_actions()
	_build_world()


func _setup_input_actions() -> void:
	for action in KEYS:
		var key: int = KEYS[action]
		_add_action(StringName(action), key)


func _add_action(action: StringName, key: int) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.45)
	var event := InputEventKey.new()
	event.physical_keycode = key
	for existing in InputMap.action_get_events(action):
		if existing.as_text() == event.as_text():
			return
	InputMap.action_add_event(action, event)


func _build_world() -> void:
	# Two floor slabs with a HOLE between them, exactly like the bug
	# lab's pit. The slow body drops through the hole, so it keeps
	# falling instead of landing on a floor and stopping.
	_add_floor(Vector3(-6.0, -1.0, 0.0), Vector3(8.0, 2.0, 20.0))
	_add_floor(Vector3(6.0, -1.0, 0.0), Vector3(8.0, 2.0, 20.0))

	# The slow body. It is a RigidBody3D with gravity switched off and
	# a constant downward velocity, so it falls at a known, slow speed
	# instead of accelerating.
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.7, 0.7, 0.7)
	var body := RigidBody3D.new()
	body.name = "SlowFaller"
	body.position = Vector3(0.0, START_Y, 0.0)
	body.gravity_scale = 0.0
	body.linear_velocity = Vector3(0.0, -FALL_SPEED, 0.0)
	body.add_to_group("physics_body")
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)
	var mesh := MeshInstance3D.new()
	var cube := BoxMesh.new()
	cube.size = Vector3(0.7, 0.7, 0.7)
	mesh.mesh = cube
	mesh.material_override = _material(Color("b5893b"))
	body.add_child(mesh)
	add_child(body)

	# A light and a camera so the scene is not pitch black.
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -25, 0)
	sun.light_energy = 1.1
	add_child(sun)

	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 12.0, 14.0)
	cam.rotation_degrees = Vector3(-48, 0, 0)
	cam.current = true
	add_child(cam)


func _add_floor(location: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = "Floor"
	body.position = location
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	add_child(body)


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	return material
