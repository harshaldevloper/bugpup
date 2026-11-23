extends SceneTree
## The Bugpup's self test.
##
## It runs the agent on TWO scenes:
##
##   1. the BUG LAB - four bugs planted on purpose. All four must be
##      caught, and each must survive a 3-times replay.
##
##   2. the CLEAN LAB - the same world with the bugs switched off.
##      It must report NOTHING. Anything it reports is a false alarm,
##      and the false-alarm count is printed at the end.
##
## The clean scene is the SAME world with a flag flipped, so the only
## difference between the two runs is the bugs themselves. That makes
## the false-alarm number a measurement rather than a guess.
##
## Run with:
##   godot --headless --path <project> --script res://addons/bugpup/tests/harness.gd
##
## The harness does NOT rely on the editor panel: it drives the agent
## directly so the whole thing can run on a build server.

const AGENT_SCRIPT := preload("res://addons/bugpup/agent.gd")

## How long the agent plays before it stops.
const RUN_SECONDS := 22.0

## The four bugs that are planted on purpose.
const EXPECTED := ["through_wall", "jitter", "out_of_bounds", "nan_numbers"]


func _init() -> void:
	print("=== BUGPUP SELF TEST ===")
	print("godot version: ", Engine.get_version_info()["string"])

	var bug_result := await _run_scene("res://addons/bugpup/tests/bug_lab.tscn",
		"BUG LAB (4 bugs planted)")
	var clean_result := await _run_scene("res://addons/bugpup/tests/clean_lab.tscn",
		"CLEAN LAB (no bugs)")

	print("")
	print("=========================================================")
	print("SUMMARY")
	print("=========================================================")

	var ok := true

	# --- the bug lab ---
	print("")
	print("BUG LAB: ", bug_result["bugs"].size(), " confirmed, ",
		bug_result["expected_found"], "/", EXPECTED.size(), " expected kinds caught")
	for bug in bug_result["bugs"]:
		print("  - kind=", bug.get("kind", "?"),
			" body=", bug.get("body", "?"),
			" replays=", bug.get("replays", 0),
			" detail=", bug.get("detail", ""))
	var missing := []
	for want in EXPECTED:
		if not bug_result["kinds"].has(want):
			missing.append(want)
	if missing.is_empty():
		print("  OK - all 4 planted bugs were caught.")
	else:
		print("  FAIL - missing: ", ", ".join(missing))
		ok = false

	# --- the clean lab ---
	print("")
	print("CLEAN LAB: ", clean_result["bugs"].size(), " reported")
	for bug in clean_result["bugs"]:
		print("  - FALSE ALARM: kind=", bug.get("kind", "?"),
			" body=", bug.get("body", "?"),
			" detail=", bug.get("detail", ""))
	if clean_result["bugs"].is_empty():
		print("  OK - the clean scene reported nothing.")
	else:
		print("  FAIL - the clean scene reported ", clean_result["bugs"].size(),
			" false alarms.")
		ok = false

	print("")
	if ok:
		print("RESULT: PASS - all 4 planted bugs caught, clean scene silent.")
	else:
		print("RESULT: FAIL")
	quit(0 if ok else 1)


## Run the agent on one scene and collect what it found.
func _run_scene(scene_path: String, label: String) -> Dictionary:
	print("")
	print("=========================================================")
	print(label, " - ", scene_path)
	print("=========================================================")

	# The scene is loaded as a real SCENE so that current_scene is set
	# and the agent can reload it during a replay. The agent is a
	# SIBLING of the scene (a child of the tree root), so it survives
	# the reload and keeps its findings.
	var scene_err := change_scene_to_file(scene_path)
	print("scene loaded, err=", scene_err)

	# Attach the agent.
	var agent: Node = AGENT_SCRIPT.new()
	agent.name = "BugpupAgent"
	root.add_child(agent)
	agent.set("duration_seconds", RUN_SECONDS)
	agent.set("seed_value", 20261116)
	# Tighten the detectors so the planted bugs show up fast.
	agent.set("jitter_flips", 4)
	agent.set("jitter_window_frames", 30)
	agent.set("out_of_bounds_y", -20.0)
	agent.set("lag_spike_ms", 100000.0)      # ignore lag in this test
	agent.set("softlock_seconds", 100000.0)  # ignore softlock here
	agent.set("freeze_seconds", 100000.0)    # ignore freeze here
	agent.set("replay_attempts", 3)

	agent.call("start")
	print("agent started, seed=", agent.get("seed_value"))

	# Let the session run.
	var elapsed := 0.0
	var tick := 1.0 / float(Engine.physics_ticks_per_second)
	while elapsed < RUN_SECONDS + 1.0:
		await physics_frame
		elapsed += tick

	# Ask the agent to wrap up. The agent also starts its own
	# finish() when the run time is up, so this may be a no-op -
	# but then it WAITS for the in-flight one, because the results
	# are only meaningful once the replays have run.
	agent.call("finish")
	var waited := 0
	while not bool(agent.get("_finish_complete")) and waited < 60 * 180:
		await physics_frame
		waited += 1
	if waited >= 60 * 180:
		print("TIMED OUT waiting for the agent to finish")

	var bugs: Array = agent.call("confirmed_bugs")
	print("")
	print("=== CONFIRMED BUGS: ", bugs.size(), " ===")
	for bug in bugs:
		print("  - kind=", bug.get("kind", "?"),
			" body=", bug.get("body", "?"),
			" replays=", bug.get("replays", 0),
			" detail=", bug.get("detail", ""))

	# Also print anything seen but not confirmed, so a failure is visible.
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

	var kinds := {}
	var expected_found := 0
	for bug in bugs:
		kinds[bug.get("kind", "?")] = true
	for want in EXPECTED:
		if kinds.has(want):
			expected_found += 1

	# Take the agent out of the tree so the next scene starts clean.
	agent.queue_free()
	await process_frame

	return {
		"bugs": bugs,
		"kinds": kinds,
		"expected_found": expected_found,
	}
