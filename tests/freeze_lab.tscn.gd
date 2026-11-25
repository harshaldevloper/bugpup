extends Node3D
## Test scene for the Bugpup's FREEZE detector.
##
## A freeze is "something that was moving stopped when it should have
## kept going". That is easy to get wrong: an enemy that walks over to
## you and then stands there to fight is doing exactly what it was told,
## but the detector used to report it as frozen.
##
## This scene plants four bodies that all move and then stop:
##
##   1. SENTRY   - a plain Node3D with no physics at all. It moves by
##                 setting its own position. It must NOT be reported.
##   2. OPTED    - a real physics body that the game has opted out of
##                 (it is in the group "bugpup_ignore"). It must NOT
##                 be reported.
##   3. TAGGED   - a real physics body with the meta
##                 "bugpup_ignore" set to true. It must NOT be
##                 reported.
##   4. PLAYER   - the body the bot's input actually drives. It moves
##                 and then stops. This one IS a freeze, and the
##                 agent must report it.
##
## Run with:
##   godot --headless --path <project> --script res://addons/bugpup/tests/freeze_test.gd
##
## The last line is the signal: FREEZE_TEST_PASS.

const BALL_SPEED := 60.0

## How long the decoy bodies move before they stop.
const MOVE_FRAMES := 40

## How long the player moves before it stops.
const PLAYER_MOVE_FRAMES := 60

var _frames := 0
var _sentry: Node3D
var _opted: RigidBody3D
var _tagged: RigidBody3D
var _player: CharacterBody3D


func _ready() -> void:
	_setup_input_actions()
	_build_world()


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

	# A floor, so the player has something to stand on.
	_add_floor(Vector3(0.0, -0.5, 0.0), Vector3(40.0, 1.0, 40.0))
	# Walls, so nothing simply walks off the edge.
	_add_wall(Vector3(0.0, 2.0, -20.0), Vector3(40.0, 4.0, 1.0))
	_add_wall(Vector3(0.0, 2.0, 20.0), Vector3(40.0, 4.0, 1.0))
	_add_wall(Vector3(-20.0, 2.0, 0.0), Vector3(1.0, 4.0, 40.0))
	_add_wall(Vector3(20.0, 2.0, 0.0), Vector3(1.0, 4.0, 40.0))

	# --- 1. the sentry: a plain Node3D, no physics ---
	# It moves by setting its own position, exactly like a scripted
	# enemy that walks over and then waits. There is no collision
	# shape and no physics body, so physics cannot break it.
	_sentry = Node3D.new()
	_sentry.name = "Sentry"
	var sentry_mesh := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.5
	capsule.height = 1.6
	sentry_mesh.mesh = capsule
	_sentry.add_child(sentry_mesh)
	add_child(_sentry)

	# --- 2. the opted-out body: real physics, in the ignore group ---
	_opted = RigidBody3D.new()
	_opted.name = "OptedOut"
	_opted.add_to_group("bugpup_ignore")
	_add_box_shape(_opted, Vector3.ONE)
	add_child(_opted)

	# --- 3. the tagged body: real physics, with the opt-out meta ---
	_tagged = RigidBody3D.new()
	_tagged.name = "Tagged"
	_tagged.set_meta("bugpup_ignore", true)
	_add_box_shape(_tagged, Vector3.ONE)
	add_child(_tagged)

	# --- 4. the player: the body the bot's input drives ---
	_player = CharacterBody3D.new()
	_player.name = "Player"
	_add_box_shape(_player, Vector3(1.0, 1.8, 1.0))
	add_child(_player)


func _add_box_shape(body: CollisionObject3D, size: Vector3) -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)


func _add_floor(pos: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	_add_box_shape(body, size)
	add_child(body)


func _add_wall(pos: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	_add_box_shape(body, size)
	add_child(body)


func _physics_process(_delta: float) -> void:
	_frames += 1

	# The sentry walks, then stops. No physics involved.
	if _sentry != null:
		if _frames <= MOVE_FRAMES:
			_sentry.position = Vector3(0.0, 0.8, -8.0 + float(_frames) * 0.2)
		else:
			_sentry.position = Vector3(0.0, 0.8, 0.0)

	# The opted-out body rolls, then stops.
	if _opted != null:
		if _frames <= MOVE_FRAMES:
			_opted.linear_velocity = Vector3(0.0, 0.0, -BALL_SPEED * 0.2)
		else:
			_opted.linear_velocity = Vector3.ZERO

	# The tagged body rolls, then stops.
	if _tagged != null:
		if _frames <= MOVE_FRAMES:
			_tagged.linear_velocity = Vector3(0.0, 0.0, BALL_SPEED * 0.2)
		else:
			_tagged.linear_velocity = Vector3.ZERO

	# The player moves with the bot's input, then stops dead.
	if _player != null:
		if _frames <= PLAYER_MOVE_FRAMES:
			var dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
			_player.velocity.x = dir.x * 5.0
			_player.velocity.z = dir.y * 5.0
			if not _player.is_on_floor():
				_player.velocity.y -= 18.0 * _delta
			else:
				_player.velocity.y = 0.0
		else:
			# The player stops responding to the controls. That IS a
			# freeze - the bot is pressing buttons and nothing moves.
			_player.velocity = Vector3.ZERO
		_player.move_and_slide()
