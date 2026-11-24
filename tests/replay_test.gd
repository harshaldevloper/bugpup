extends SceneTree
## The Bugpup's replay test for SLOW findings.
##
## A finding is only reported if it comes back on a replay. The replay
## used to run for a FIXED number of frames, so a finding that needs
## longer than that to develop could never be confirmed - even when it
## was a real bug.
##
## A body that falls out of the world is the clearest case. Falling from
## the floor to the out-of-bounds threshold takes real time, and the
## replay has to keep running for that long to see it again.
##
## This test plants exactly that: a body that drops SLOWLY, so the
## finding appears late. It then checks that the replay can still
## reproduce it.
##
## Run with:
##   godot --headless --path <project> --script res://addons/bugpup/tests/replay_test.gd
##
## The last line is the signal: REPLAY_TEST_PASS.

const AGENT_SCRIPT := preload("res://addons/bugpup/agent.gd")

## How long the agent plays before it stops. It must outlast the slow
## body's fall (5 seconds), or the finding is never even seen.
const RUN_SECONDS := 9.0

## The body drops this slowly, so it needs a long time to reach the
## out-of-bounds threshold. A fast drop would be caught by the old
## window and the test would prove nothing.
const FALL_SPEED := 3.0


func _init() -> void:
	print("=== BUGPUP REPLAY TEST (slow finding) ===")
	print("godot version: ", Engine.get_version_info()["string"])

	var scene_err := change_scene_to_file("res://addons/bugpup/tests/slow_fall_lab.tscn")
	print("scene loaded, err=", scene_err)
	await process_frame
	await process_frame

	var agent: Node = AGENT_SCRIPT.new()
	agent.name = "BugpupAgent"
	root.add_child(agent)
	agent.set("duration_seconds", RUN_SECONDS)
	agent.set("seed_value", 20261116)
	agent.set("replay_attempts", 3)
	# The threshold is close, so the body has to fall a real distance -
	# but slowly enough that the finding lands late in the session.
	agent.set("out_of_bounds_y", -30.0)
	# Press a key, then leave the controls alone. The old replay window
	# was measured from the LAST INPUT FRAME, so with the inputs over
	# early, the window closed long before the body had fallen far
	# enough to cross the threshold a second time. That is the bug this
	# test exists to catch.
	agent.set("action_hold_frames", 2)
	agent.set("idle_frames", 1000000)
	agent.call("start")
	print("agent started, seed=", agent.get("seed_value"))

	# Let the session run long enough for the slow body to fall past
	# the threshold.
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

	# --- what did the agent see? ---
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

	var bugs: Array = agent.call("confirmed_bugs")
	print("")
	print("=== CONFIRMED BUGS: ", bugs.size(), " ===")
	for bug in bugs:
		print("  - kind=", bug.get("kind", "?"),
			" body=", bug.get("body", "?"),
			" replays=", bug.get("replays", 0),
			" detail=", bug.get("detail", ""))

	# --- the actual assertion ---
	# The slow body must be CONFIRMED, not merely seen. If the replay
	# window is too short, the finding stays unconfirmed and this fails.
	print("")
	var confirmed_slow := false
	for bug in bugs:
		if String(bug.get("kind", "")) == "out_of_bounds" and bug.get("replays", 0) >= 3:
			confirmed_slow = true

	if confirmed_slow:
		print("REPLAY_TEST_PASS: a slow out-of-bounds finding was confirmed 3 times.")
		quit(0)
	else:
		var seen_only := 0
		for key in pending.keys():
			var p2: Dictionary = pending[key]
			var f2: Dictionary = p2.get("finding", {})
			if String(f2.get("kind", "")) == "out_of_bounds":
				seen_only = int(p2.get("count", 0))
		print("REPLAY_TEST_FAIL: the slow out-of-bounds finding was seen "
			+ str(seen_only) + " time(s) but never confirmed.")
		print("  The replay window ended before the body had fallen far")
		print("  enough to cross the threshold a second time.")
		quit(1)
