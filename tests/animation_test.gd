extends SceneTree
## The Bugpup's ANIMATION test.
##
## A body whose movement comes from an AnimationPlayer is not jittering.
## The official Godot character demos have elevators that go up and down
## on an AnimationPlayer, and the physics server fighting the animated
## transform adds sub-centimetre noise on top of that. The jitter
## detector reported them as "6 direction reversals in 45 frames" with
## an average step of 0.0067 - a false alarm, confirmed 3 times out of
## 3 because the animation is deterministic.
##
## This test plants two bodies that oscillate exactly the same way:
##
##   1. the ANIMATED body, moved by an AnimationPlayer. It must NOT be
##      reported as jitter.
##   2. the SCRIPTED body, moved by the scene's own script. It MUST
##      still be reported - that is the control. A "fix" that simply
##      stopped reporting jitter would pass the first case and fail
##      this one.
##
## Run with:
##   godot --headless --path <project> --script res://addons/bugpup/tests/animation_test.gd
##
## The last line is the signal: ANIMATION_TEST_PASS.

const AGENT_SCRIPT := preload("res://addons/bugpup/agent.gd")

## How long the agent plays. Long enough for enough direction
## reversals to land inside one jitter window.
const RUN_SECONDS := 14.0


func _init() -> void:
	print("=== BUGPUP ANIMATION TEST ===")
	print("godot version: ", Engine.get_version_info()["string"])

	var scene_err := change_scene_to_file("res://addons/bugpup/tests/animation_lab.tscn")
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

	# --- the assertions ---
	var jitters: Array = []
	for bug in bugs:
		if String(bug.get("kind", "")) == "jitter":
			jitters.append(bug)

	var animated_reported := _reported(jitters, "AnimatedBody")
	var scripted_reported := _reported(jitters, "ScriptedBody")

	print("")
	print("=== THE ASSERTIONS ===")
	print("  the animated body was NOT reported as jittering: ", not animated_reported)
	print("  the scripted body WAS reported as jittering:    ", scripted_reported)

	var ok := (not animated_reported) and scripted_reported

	print("")
	if ok:
		print("ANIMATION_TEST_PASS: an animated body is not jittering, and a scripted one still is.")
		quit(0)
	else:
		print("ANIMATION_TEST_FAIL: the animation rule is not working.")
		if animated_reported:
			print("  the body moved by an AnimationPlayer was reported as jittering.")
		if not scripted_reported:
			print("  the body moved by a script was NOT reported, so the detector no longer works at all.")
		quit(1)


func _reported(bugs: Array, body_name: String) -> bool:
	for bug in bugs:
		if String(bug.get("body", "")) == body_name:
			return true
	return false
