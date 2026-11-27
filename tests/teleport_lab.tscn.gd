extends Node3D
## The scene for the teleport test.
##
## It has two bodies and one wall:
##
##   1. the RESPAWNING body - a CharacterBody3D that walks into the
##      wall's far side by being teleported, exactly the way the
##      official Godot platformer demo puts the player back at spawn
##      when it falls below the world. Its velocity is zero when it
##      jumps. It must NOT be reported as going through a wall.
##
##   2. the FAST body - a RigidBody3D that is genuinely fired through
##      the wall at speed. It really does go through, so it MUST still
##      be reported. This is the control: a fix that simply stopped
##      reporting through_wall would pass the first case and fail this
##      one.
##
## The wall is a StaticBody3D with a BoxShape3D one unit thick, so the
## fast body has to cross more than its own size to count.

const WALL_Z := 0.0
const WALL_THICKNESS := 1.0
const FAST_SPEED := 40.0

var _respawner: CharacterBody3D
var _fast: RigidBody3D
var _frames := 0
var _fast_launched := false
var _respawned := false


func _ready() -> void:
	_build_wall()

	# --- 1. the respawning body ---
	_respawner = CharacterBody3D.new()
	_respawner.name = "Respawner"
	var res_shape := CollisionShape3D.new()
	var res_box := BoxShape3D.new()
	res_box.size = Vector3.ONE
	res_shape.shape = res_box
	_respawner.add_child(res_shape)
	_respawner.position = Vector3(0.0, 0.0, -4.0)
	add_child(_respawner)

	# --- 2. the fast body ---
	_fast = RigidBody3D.new()
	_fast.name = "FastBody"
	var fast_shape := CollisionShape3D.new()
	var fast_box := BoxShape3D.new()
	fast_box.size = Vector3(0.4, 0.4, 0.4)
	fast_shape.shape = fast_box
	_fast.add_child(fast_shape)
	_fast.position = Vector3(0.0, 0.0, -4.0)
	_fast.collision_mask = 0
	add_child(_fast)

	print("teleport lab: the wall is at z=", WALL_Z,
		", the respawner starts at z=-4, the fast body is fired at ",
		FAST_SPEED, " m/s")


func _build_wall() -> void:
	var wall := StaticBody3D.new()
	wall.name = "Wall"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	# Big enough that a body that has fallen a little cannot miss it.
	box.size = Vector3(40.0, 40.0, WALL_THICKNESS)
	shape.shape = box
	wall.add_child(shape)
	wall.position = Vector3(0.0, 0.0, WALL_Z)
	add_child(wall)


func _physics_process(_delta: float) -> void:
	_frames += 1

	# The respawner is teleported across the wall after a moment. It is
	# NOT moved through it - it is put on the other side, the way a game
	# respawns a player that fell out of the world.
	if _frames == 40 and not _respawned:
		_respawned = true
		_respawner.position = Vector3(0.0, 0.0, 4.0)
		_respawner.velocity = Vector3.ZERO

	# The fast body is fired at the wall from the same side.
	if _frames == 60 and not _fast_launched:
		_fast_launched = true
		# Start it next to the wall, at ground level, so it crosses the
		# wall rather than sailing over it.
		_fast.global_position = Vector3(0.0, 0.0, -2.0)
		_fast.linear_velocity = Vector3(0.0, 0.0, FAST_SPEED)

