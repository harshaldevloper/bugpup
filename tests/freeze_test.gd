extends SceneTree
## The Bugpup's FREEZE test.
##
## A freeze is "something that was moving stopped when it should have
## kept going". The detector used to report any body that stopped,
## which meant an enemy that walks over to you and then stands there
## to fight was reported as frozen. That is a false alarm, and it is
## the commonest one a real game produces.
##
## The freeze detector now has three rules:
##
##   1. the body must have PHYSICS - a plain Node3D moved by its own
##      script is not subject to physics at all;
##   2. the body must be the one the BOT's input actually moves;
##   3. the game can opt a body out, with the group "bugpup_ignore"
##      or the meta "bugpup_ignore".
##
## This test plants one body for each rule and checks that each is
## ignored for the right reason, and that the body the bot really
## drives IS reported.
##
## Run with:
##   godot --headless --path <project> --script res://addons/bugpup/tests/freeze_test.gd
##
## The last line is the signal: FREEZE_TEST_PASS.

const AGENT_SCRIPT := preload("res://addons/bugpup/agent.gd")

## How long the agent plays. It has to outlast the freeze window
## (6 seconds by default) plus the time the player moves for.
const RUN_SECONDS := 22.0


func _init() -> void:
	print("=== BUGPUP FREEZE TEST ===")
	print("godot version: ", Engine.get_version_info()["string"])

	var scene_err := change_scene_to_file("res://addons/bugpup/tests/freeze_lab.tscn")
	print("scene loaded, err=", scene_err)
	await process_frame
	await process_frame

	var agent: Node = AGENT_SCRIPT.new()
	agent.name = "BugpupAgent"
	root.add_child(agent)
	agent.set("duration_seconds", RUN_SECONDS)
	agent.set("seed_value", 20261116)
	agent.set("replay_attempts", 3)
	# The freeze window is 6 seconds by default. The decoys stop at
	# frame 40 and the player at frame 60, so the session has to run
	# long enough for the window to close on all of them.
	agent.set("freeze_seconds", 3.0)
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

	# --- the assertions ---
	print("")
	var freezes: Array = []
	for bug in bugs:
		if String(bug.get("kind", "")) == "freeze":
			freezes.append(bug)

	# Rule 1: the sentry (a plain Node3D, no physics) must not appear.
	var sentry_reported := _reported(freezes, "Sentry")

	# Rule 3: the opted-out body must not appear.
	var opted_reported := _reported(freezes, "OptedOut")

	# Rule 3: the tagged body must not appear.
	var tagged_reported := _reported(freezes, "Tagged")

	# The real freeze: the body the bot drives must be reported.
	var player_reported := _reported(freezes, "Player")

	print("=== THE ASSERTIONS ===")
	print("  the sentry (no physics) was NOT reported:      ", not sentry_reported)
	print("  the opted-out body was NOT reported:            ", not opted_reported)
	print("  the tagged body was NOT reported:               ", not tagged_reported)
	print("  the bot-driven player WAS reported as frozen:   ", player_reported)

	# Nothing at all should have been reported for the decoys, in any
	# detector - the opt-out applies to every detector.
	var any_decoy := false
	for bug in bugs:
		var body_name := String(bug.get("body", ""))
		if body_name == "Sentry" or body_name == "OptedOut" or body_name == "Tagged":
			any_decoy = true
	print("  no decoy was reported by ANY detector:          ", not any_decoy)

	var ok := (not sentry_reported) and (not opted_reported) and (not tagged_reported) \
		and player_reported and (not any_decoy)

	print("")
	if ok:
		print("FREEZE_TEST_PASS: the three decoys were ignored and the real freeze was found.")
		quit(0)
	else:
		print("FREEZE_TEST_FAIL: the freeze rules are not all working.")
		if sentry_reported:
			print("  the sentry (a plain Node3D with no physics) was reported as frozen.")
		if opted_reported:
			print("  the body in the group 'bugpup_ignore' was reported as frozen.")
		if tagged_reported:
			print("  the body with the meta 'bugpup_ignore' was reported as frozen.")
		if not player_reported:
			print("  the body the bot drives was NOT reported, so the detector no longer works at all.")
		if any_decoy:
			print("  a decoy was reported by some other detector.")
		quit(1)


## True if any of the findings is about the named body.
func _reported(findings: Array, body_name: String) -> bool:
	for finding in findings:
		if String(finding.get("body", "")) == body_name:
			return true
	return false
