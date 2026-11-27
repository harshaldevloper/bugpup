extends SceneTree
## The Bugpup's TELEPORT test.
##
## A body that goes through a wall and a body that is PUT on the other
## side of a wall look the same to the detector: in both cases the
## straight line from where it was to where it is now crosses the wall.
##
## The difference is the velocity. A body that really travelled is
## moving at a speed that accounts for the distance it covered. A body
## that was teleported - which is how a game respawns a player that
## fell out of the world - is not moving at all when it jumps.
##
## The official Godot platformer demo does exactly this: it puts the
## player back at spawn when `global_position.y` drops below -12. The
## detector reported that as "passed 0.44 through 'GridMap'", and it
## confirmed 3 times out of 3, because the respawn is deterministic.
## It looked like a solid finding and it was a false alarm.
##
## This test plants both cases:
##
##   1. the RESPAWNING body is teleported across the wall. It must NOT
##      be reported as going through a wall.
##   2. the FAST body is really fired through the wall. It MUST still
##      be reported. This is the control - a "fix" that just stopped
##      reporting through_wall would pass the first case and fail this
##      one.
##
## Run with:
##   godot --headless --path <project> --script res://addons/bugpup/tests/teleport_test.gd
##
## The last line is the signal: TELEPORT_TEST_PASS.

const AGENT_SCRIPT := preload("res://addons/bugpup/agent.gd")

## How long the agent plays. Long enough for the teleport at frame 40,
## the launch at frame 60, and the replay to run.
const RUN_SECONDS := 18.0


func _init() -> void:
	print("=== BUGPUP TELEPORT TEST ===")
	print("godot version: ", Engine.get_version_info()["string"])

	var scene_err := change_scene_to_file("res://addons/bugpup/tests/teleport_lab.tscn")
	print("scene loaded, err=", scene_err)
	await process_frame
	await process_frame

	var agent: Node = AGENT_SCRIPT.new()
	agent.name = "BugpupAgent"
	root.add_child(agent)
	agent.set("duration_seconds", RUN_SECONDS)
	agent.set("seed_value", 20261116)
	agent.set("replay_attempts", 3)
	agent.call("start")
	print("agent started, seed=", agent.get("seed_value"))

	var elapsed := 0.0
	var tick := 1.0 / float(Engine.physics_ticks_per_second)
	while elapsed < RUN_SECONDS + 1.0:
		await physics_frame
		elapsed += tick

	agent.call("finish")
	var waited := 0
	while not bool(agent.get("_finish_complete")) and waited < 60 * 300:
		await physics_frame
		waited += 1

	var bugs: Array = agent.call("confirmed_bugs")
	print("")
	print("=== CONFIRMED BUGS: ", bugs.size(), " ===")
	for bug in bugs:
		print("  - kind=", bug.get("kind", "?"),
			" body=", bug.get("body", "?"),
			" replays=", bug.get("replays", 0),
			" detail=", bug.get("detail", ""))

	var pending: Dictionary = agent.get("_pending")
	print("")
	print("=== SEEN BUT NOT CONFIRMED: ", pending.size(), " ===")
	for key in pending.keys():
		var p: Dictionary = pending[key]
		var f: Dictionary = p.get("finding", {})
		print("  - kind=", f.get("kind", "?"),
			" body=", f.get("body", "?"),
			" seen=", p.get("count", 0),
			" detail=", f.get("detail", ""))

	# --- the body size the detector measures ---
	# A capsule is the shape most player characters use, and the
	# detector used to fall through to a 0.05 default for it. That made
	# the player look 0.4 units wide when it was 0.8, and the "went
	# through" threshold with it, so the detector reported bodies that
	# had merely grazed a surface.
	var capsule_shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 2.1
	capsule_shape.shape = capsule
	var measured: float = agent.call("_body_radius", capsule_shape)
	print("")
	print("=== THE BODY SIZE ===")
	print("  a capsule of radius 0.4 measures as:            ", measured)
	var radius_ok := absf(measured - 0.4) < 0.001

	# --- the assertions ---
	var tunnels: Array = []
	for bug in bugs:
		if String(bug.get("kind", "")) == "through_wall":
			tunnels.append(bug)

	var respawn_reported := _reported(tunnels, "Respawner")
	var fast_reported := _reported(tunnels, "FastBody")

	print("")
	print("=== THE ASSERTIONS ===")
	print("  the teleported body was NOT reported:            ", not respawn_reported)
	print("  the fast body WAS reported as going through:    ", fast_reported)
	print("  a capsule body is measured at its real size:    ", radius_ok)

	var ok := (not respawn_reported) and fast_reported and radius_ok

	print("")
	if ok:
		print("TELEPORT_TEST_PASS: a teleported body is not a wall crossing, and a fast body still is.")
		quit(0)
	else:
		print("TELEPORT_TEST_FAIL: the teleport rule is not working.")
		if respawn_reported:
			print("  the body that was TELEPORTED was reported as going through a wall.")
		if not fast_reported:
			print("  the body that really went through the wall was NOT reported,")
			print("  so the detector no longer works at all.")
		if not radius_ok:
			print("  a capsule body was measured at ", measured, " instead of 0.4.")
		quit(1)


func _reported(bugs: Array, body_name: String) -> bool:
	for bug in bugs:
		if String(bug.get("body", "")) == body_name:
			return true
	return false
