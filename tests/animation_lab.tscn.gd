extends Node3D
## The scene for the animation test.
##
## It has two bodies that both oscillate in the same way:
##
##   1. the ANIMATED body - a CharacterBody3D whose position is moved
##      by an AnimationPlayer. It goes up and down ON PURPOSE, and the
##      physics server fighting the animated transform adds a little
##      noise on top. The official Godot character demos do exactly
##      this with their elevators, and the jitter detector reported
##      them as "6 direction reversals in 45 frames" with an average
##      step of 0.0067. It must NOT be reported.
##
##   2. the SCRIPTED body - a plain Node3D moved by this scene's own
##      script, oscillating the same way. Nothing animates it, so its
##      movement is the game's own doing and a real oscillation is a
##      real bug. It MUST still be reported.
##
## The second one is the control. A "fix" that simply stopped reporting
## jitter would pass the first case and fail this one.

## How fast the bodies oscillate, and how far. These numbers are
## chosen so that the OLD detector reported both of them: enough
## direction reversals inside the window, a tiny average step, and
## enough total path to clear the minimum.
const PERIOD_FRAMES := 7.5
const AMPLITUDE := 0.05

var _animated: CharacterBody3D
var _scripted: Node3D
var _frames := 0


func _ready() -> void:
	_build_animated()
	_build_scripted()
	print("animation lab: both bodies oscillate every ", PERIOD_FRAMES,
		" frames by ", AMPLITUDE, " units")


func _build_animated() -> void:
	_animated = CharacterBody3D.new()
	_animated.name = "AnimatedBody"
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 2.1
	shape.shape = capsule
	_animated.add_child(shape)
	_animated.position = Vector3(0.0, 0.0, -4.0)
	add_child(_animated)

	# The AnimationPlayer is a CHILD of the body, and the track path
	# is ".:position" - the same shape the official demos use.
	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	_animated.add_child(player)

	var lib := AnimationLibrary.new()
	var anim := Animation.new()
	anim.length = PERIOD_FRAMES / 60.0
	anim.loop_mode = Animation.LOOP_LINEAR
	var track := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(track, NodePath(".:position"))
	anim.track_insert_key(track, 0.0, Vector3(0.0, 0.0, -4.0))
	anim.track_insert_key(track, anim.length * 0.25, Vector3(0.0, AMPLITUDE, -4.0))
	anim.track_insert_key(track, anim.length * 0.5, Vector3(0.0, 0.0, -4.0))
	anim.track_insert_key(track, anim.length * 0.75, Vector3(0.0, AMPLITUDE, -4.0))
	anim.track_insert_key(track, anim.length, Vector3(0.0, 0.0, -4.0))
	lib.add_animation("wiggle", anim)
	player.add_animation_library("", lib)
	player.play("wiggle")


func _build_scripted() -> void:
	_scripted = Node3D.new()
	_scripted.name = "ScriptedBody"
	_scripted.position = Vector3(0.0, 0.0, 4.0)
	add_child(_scripted)


func _physics_process(_delta: float) -> void:
	_frames += 1
	if _scripted == null:
		return
	# The same oscillation, but driven by the scene's own script.
	var phase := float(_frames) / PERIOD_FRAMES
	_scripted.position = Vector3(0.0, AMPLITUDE * sin(phase * TAU), 4.0)
