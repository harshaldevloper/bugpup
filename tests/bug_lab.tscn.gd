extends Node3D
## Test scene for the Bugpup.
##
## Four bugs are planted on purpose, one per kind:
##   1. TUNNEL  - a fast ball that passes through a thin wall
##   2. JITTER  - a box that shakes on a slope
##   3. PIT     - a hole with no floor under it
##   4. NAN     - a body whose velocity becomes NaN
##
## The agent must find all four.

const BALL_SPEED := 220.0
const NAN_AFTER_FRAMES := 90

## When false, the four bugs are NOT built. The clean scene uses
## this to check that the agent reports nothing when there is
## nothing wrong.
@export var plant_bugs := true

var _frames := 0
var _ball: RigidBody3D
var _jitter: RigidBody3D
var _nan_body: CharacterBody3D
var _player: CharacterBody3D


func _ready() -> void:
	# The lab defines its own input actions at runtime, exactly like
	# the real game does in InputSetup.configure_defaults(). Without
	# actions the agent has nothing to press, so it cannot explore.
	_setup_input_actions()
	_build_world()
	_build_bugs()



## Define the input actions the agent will press. The real game does
## this in scripts/InputSetup.gd; the lab does it here so the agent
## has real buttons to explore with.
func _setup_input_actions() -> void:
	_add_action("move_left", KEY_A)
	_add_action("move_right", KEY_D)
	_add_action("move_forward", KEY_W)
	_add_action("move_back", KEY_S)
	_add_action("jump", KEY_SPACE)
	_add_action("dash", KEY_SHIFT)


func _add_action(action: StringName, key: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.45)
	var event := InputEventKey.new()
	event.physical_keycode = key
	for existing in InputMap.action_get_events(action):
		if existing.as_text() == event.as_text():
			return
	InputMap.action_add_event(action, event)

func _build_world() -> void:
	# Environment.
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("101418")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("9fb4c0")
	env.ambient_light_energy = 0.7
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -25, 0)
	sun.light_energy = 1.1
	add_child(sun)

	# Floor with a PIT (a hole with no floor) at x = 0.
	# Two floor slabs, left and right, leaving a gap between them.
	_add_floor(Vector3(-6.0, -0.5, 0.0), Vector3(8.0, 1.0, 24.0), Color("3a4449"))
	_add_floor(Vector3(6.0, -0.5, 0.0), Vector3(8.0, 1.0, 24.0), Color("3a4449"))
	# A marker ring around the pit so it is visible.
	_add_floor(Vector3(0.0, -0.51, -6.5), Vector3(4.0, 1.02, 1.0), Color("7a2f2f"))
	_add_floor(Vector3(0.0, -0.51, 6.5), Vector3(4.0, 1.02, 1.0), Color("7a2f2f"))
	# The clean scene has NO HOLE. The hole IS the pit bug, so a
	# scene with a hole in the floor is not a clean scene - it is a
	# scene with a real bug that the agent would be right to report.
	if not plant_bugs:
		_add_floor(Vector3(0.0, -0.5, 0.0), Vector3(4.0, 1.0, 24.0), Color("3a4449"))

	# Outer walls so the player cannot simply walk off the edge.
	_add_wall(Vector3(0.0, 2.0, -12.0), Vector3(24.0, 4.0, 1.0))
	_add_wall(Vector3(0.0, 2.0, 12.0), Vector3(24.0, 4.0, 1.0))
	_add_wall(Vector3(-12.0, 2.0, 0.0), Vector3(1.0, 4.0, 24.0))
	_add_wall(Vector3(12.0, 2.0, 0.0), Vector3(1.0, 4.0, 24.0))

	# A THIN wall in the middle of the left half: the fast ball goes
	# straight through it because it is only 0.1 units thick and Godot
	# has no continuous collision detection by default.
	_add_wall(Vector3(-7.0, 1.0, -4.0), Vector3(0.05, 2.0, 6.0), Color("5a4a2a"))
	_add_wall_marker(Vector3(-7.0, 1.0, -4.0), Vector3(0.1, 2.0, 6.0))

	# A SLOPE for the jitter bug: a tilted ramp.
	var ramp := StaticBody3D.new()
	ramp.position = Vector3(7.0, 0.9, -4.0)
	ramp.rotation_degrees = Vector3(0, 0, -18)
	var ramp_col := CollisionShape3D.new()
	var ramp_shape := BoxShape3D.new()
	ramp_shape.size = Vector3(6.0, 0.4, 6.0)
	ramp_col.shape = ramp_shape
	ramp.add_child(ramp_col)
	var ramp_mesh := MeshInstance3D.new()
	var ramp_box := BoxMesh.new()
	ramp_box.size = Vector3(6.0, 0.4, 6.0)
	ramp_mesh.mesh = ramp_box
	ramp_mesh.material_override = _material(Color("4a3f5a"))
	ramp.add_child(ramp_mesh)
	add_child(ramp)

	# The player the agent will drive.
	_player = CharacterBody3D.new()
	_player.name = "Player"
	_player.position = Vector3(-2.0, 1.2, 6.0)
	_player.add_to_group("player")
	var p_col := CollisionShape3D.new()
	var p_shape := CapsuleShape3D.new()
	p_shape.radius = 0.4
	p_shape.height = 1.8
	p_col.shape = p_shape
	_player.add_child(p_col)
	var p_mesh := MeshInstance3D.new()
	var p_capsule := CapsuleMesh.new()
	p_capsule.radius = 0.4
	p_capsule.height = 1.8
	p_mesh.mesh = p_capsule
	p_mesh.material_override = _material(Color("5a7a66"))
	_player.add_child(p_mesh)
	add_child(_player)

	# A camera that follows the player.
	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 14.0, 14.0)
	cam.rotation_degrees = Vector3(-48, 0, 0)
	cam.current = true
	add_child(cam)


func _build_bugs() -> void:
	if not plant_bugs:
		# The clean scene: the same world, with no bugs planted.
		_build_clean_bodies()
		return
	# BUG 1 - TUNNEL: a ball fired at the thin wall fast enough to pass
	# through it. Gravity is 0 so it travels in a straight line.
	# A very small ball: it moves 3.7 units per frame at 220 u/s, so a
	# 0.05-thick wall cannot catch it. Godot has no continuous collision
	# detection by default, so it passes straight through.
	var ball_shape := SphereShape3D.new()
	ball_shape.radius = 0.05
	_ball = RigidBody3D.new()
	_ball.name = "FastBall"
	_ball.position = Vector3(-11.0, 1.0, -4.0)
	_ball.gravity_scale = 0.0
	_ball.linear_velocity = Vector3(BALL_SPEED, 0.0, 0.0)
	_ball.add_to_group("physics_body")
	var b_col := CollisionShape3D.new()
	b_col.shape = ball_shape
	_ball.add_child(b_col)
	var b_mesh := MeshInstance3D.new()
	var b_sphere := SphereMesh.new()
	b_sphere.radius = 0.12
	b_sphere.height = 0.24
	b_mesh.mesh = b_sphere
	b_mesh.material_override = _material(Color("a33b3b"))
	_ball.add_child(b_mesh)
	add_child(_ball)

	# BUG 2 - JITTER: a box on the slope that shakes back and forth.
	var j_shape := BoxShape3D.new()
	j_shape.size = Vector3(0.8, 0.8, 0.8)
	_jitter = RigidBody3D.new()
	_jitter.name = "JitterBox"
	_jitter.position = Vector3(7.0, 2.2, -4.0)
	# No gravity, so it hovers in place. A frozen body would ignore
	# velocity entirely and never shake at all.
	_jitter.gravity_scale = 0.0
	_jitter.add_to_group("physics_body")
	var j_col := CollisionShape3D.new()
	j_col.shape = j_shape
	_jitter.add_child(j_col)
	var j_mesh := MeshInstance3D.new()
	var j_box := BoxMesh.new()
	j_box.size = Vector3(0.8, 0.8, 0.8)
	j_mesh.mesh = j_box
	j_mesh.material_override = _material(Color("b5893b"))
	_jitter.add_child(j_mesh)
	add_child(_jitter)

	# BUG 3 - PIT: a box dropped over the hole in the floor. There is
	# nothing under it, so it falls out of the world.
	var pit_shape := BoxShape3D.new()
	pit_shape.size = Vector3(0.7, 0.7, 0.7)
	var pit_box := RigidBody3D.new()
	pit_box.name = "PitFaller"
	pit_box.position = Vector3(0.0, 1.5, 0.0)
	pit_box.add_to_group("physics_body")
	var pit_col := CollisionShape3D.new()
	pit_col.shape = pit_shape
	pit_box.add_child(pit_col)
	var pit_mesh := MeshInstance3D.new()
	var pit_cube := BoxMesh.new()
	pit_cube.size = Vector3(0.7, 0.7, 0.7)
	pit_mesh.mesh = pit_cube
	pit_mesh.material_override = _material(Color("7ab55b"))
	pit_box.add_child(pit_mesh)
	add_child(pit_box)

	# BUG 4 - NAN: a body whose velocity becomes NaN after a while.
	# It is a CharacterBody3D on purpose: a CharacterBody3D does not
	# feed the physics solver, so its NaN stays local to it. A
	# RigidBody3D would spread the NaN through the whole solver and
	# every other body would look broken too, which is not the bug
	# we are trying to plant.
	_nan_body = CharacterBody3D.new()
	_nan_body.name = "NanBox"
	_nan_body.position = Vector3(3.0, 1.0, 6.0)
	_nan_body.add_to_group("physics_body")
	var n_col := CollisionShape3D.new()
	var n_shape := BoxShape3D.new()
	n_shape.size = Vector3(0.7, 0.7, 0.7)
	n_col.shape = n_shape
	_nan_body.add_child(n_col)
	var n_mesh := MeshInstance3D.new()
	var n_box := BoxMesh.new()
	n_box.size = Vector3(0.7, 0.7, 0.7)
	n_mesh.mesh = n_box
	n_mesh.material_override = _material(Color("3b8fb5"))
	_nan_body.add_child(n_mesh)
	add_child(_nan_body)



## The bodies the clean scene gets in place of the buggy ones. They
## are the same shapes in the same places, but they behave: the ball
## is slow enough to be stopped by the wall, the box does not shake,
## the pit box rests on a ledge beside the hole, and the third body
## has a finite velocity.
func _build_clean_bodies() -> void:
	# A slow ball: at 12 u/s it moves 0.2 units per frame, so the thin
	# wall catches it and it stops. Nothing goes through.
	var ball_shape := SphereShape3D.new()
	ball_shape.radius = 0.05
	_ball = RigidBody3D.new()
	_ball.name = "FastBall"
	_ball.position = Vector3(-11.0, 1.0, -4.0)
	_ball.gravity_scale = 0.0
	_ball.linear_velocity = Vector3(12.0, 0.0, 0.0)
	_ball.add_to_group("physics_body")
	var b_col := CollisionShape3D.new()
	b_col.shape = ball_shape
	_ball.add_child(b_col)
	var b_mesh := MeshInstance3D.new()
	var b_sphere := SphereMesh.new()
	b_sphere.radius = 0.12
	b_sphere.height = 0.24
	b_mesh.mesh = b_sphere
	b_mesh.material_override = _material(Color("a33b3b"))
	_ball.add_child(b_mesh)
	add_child(_ball)

	# A box that sits still on the slope. It does not shake.
	var j_shape := BoxShape3D.new()
	j_shape.size = Vector3(0.8, 0.8, 0.8)
	_jitter = RigidBody3D.new()
	_jitter.name = "JitterBox"
	_jitter.position = Vector3(7.0, 2.2, -4.0)
	_jitter.gravity_scale = 0.0
	_jitter.add_to_group("physics_body")
	var j_col := CollisionShape3D.new()
	j_col.shape = j_shape
	_jitter.add_child(j_col)
	var j_mesh := MeshInstance3D.new()
	var j_box := BoxMesh.new()
	j_box.size = Vector3(0.8, 0.8, 0.8)
	j_mesh.mesh = j_box
	j_mesh.material_override = _material(Color("b5893b"))
	_jitter.add_child(j_mesh)
	add_child(_jitter)

	# A box resting ON the floor. The floor is continuous in the
	# clean scene, so it has nothing to fall through.
	var pit_shape := BoxShape3D.new()
	pit_shape.size = Vector3(0.7, 0.7, 0.7)
	var pit_box := RigidBody3D.new()
	pit_box.name = "PitFaller"
	pit_box.position = Vector3(0.0, 0.5, 0.0)
	pit_box.add_to_group("physics_body")
	var pit_col := CollisionShape3D.new()
	pit_col.shape = pit_shape
	pit_box.add_child(pit_col)
	var pit_mesh := MeshInstance3D.new()
	var pit_cube := BoxMesh.new()
	pit_cube.size = Vector3(0.7, 0.7, 0.7)
	pit_mesh.mesh = pit_cube
	pit_mesh.material_override = _material(Color("7ab55b"))
	pit_box.add_child(pit_mesh)
	add_child(pit_box)

	# A body with a perfectly finite velocity.
	_nan_body = CharacterBody3D.new()
	_nan_body.name = "NanBox"
	_nan_body.position = Vector3(3.0, 1.0, 6.0)
	_nan_body.add_to_group("physics_body")
	var n_col := CollisionShape3D.new()
	var n_shape := BoxShape3D.new()
	n_shape.size = Vector3(0.7, 0.7, 0.7)
	n_col.shape = n_shape
	_nan_body.add_child(n_col)
	var n_mesh := MeshInstance3D.new()
	var n_box := BoxMesh.new()
	n_box.size = Vector3(0.7, 0.7, 0.7)
	n_mesh.mesh = n_box
	n_mesh.material_override = _material(Color("3b8fb5"))
	_nan_body.add_child(n_mesh)
	add_child(_nan_body)


func _physics_process(_delta: float) -> void:
	_frames += 1

	if not plant_bugs:
		# The clean scene has nothing to shake and nothing to poison.
		# The player still moves, so the agent still has something to
		# drive - it just cannot find a bug, because there is not one.
		_drive_player()
		return

	# BUG 2 - JITTER: the box shakes back and forth in place. Its
	# POSITION is moved directly, which is what the agent measures and
	# what a body being jostled by a script actually looks like.
	if is_instance_valid(_jitter):
		var shake := sin(float(_frames) * 0.5) * 0.12
		_jitter.global_position = Vector3(7.0 + shake, 2.2, -4.0)

	# BUG 4 - NAN: poison the velocity.
	if is_instance_valid(_nan_body) and _frames > NAN_AFTER_FRAMES:
		if not is_nan(_nan_body.velocity.x):
			_nan_body.velocity = Vector3(NAN, 0.0, 0.0)

	_drive_player()



## Move the player from the input actions. The player READS the
## input map, so the agent genuinely drives it - the same contract
## as the real game.
func _drive_player() -> void:
	if not is_instance_valid(_player):
		return
	var move := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	_player.velocity.x = move.x * 4.0
	_player.velocity.z = move.y * 4.0
	if Input.is_action_pressed("jump"):
		_player.velocity.y = 6.0
	else:
		_player.velocity.y -= 0.3
	_player.move_and_slide()
func _add_floor(pos: Vector3, size: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = _material(color)
	body.add_child(mesh)
	add_child(body)


func _add_wall(pos: Vector3, size: Vector3, color: Color = Color("465057")) -> void:
	_add_floor(pos, size, color)


func _add_wall_marker(pos: Vector3, size: Vector3) -> void:
	# A thin visible strip on the wall so a human can see where it is.
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = _material(Color("d0a03a"))
	mesh.position = pos
	add_child(mesh)


func _material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.85
	return m
