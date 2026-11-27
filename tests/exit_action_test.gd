extends SceneTree
## Checks that the bot never presses an action that takes the player
## out of the run.
##
## The bug this catches: the official Godot demos bind an action called
## "exit" that calls get_tree().quit(). The bot pressed it, the game
## quit in the middle of the run, and the run reported "no bugs" -
## which looked like a clean result but was actually a cut-short one.
## Two of the three demo projects died this way.
##
## The test also checks the other direction: "reset_position" is a
## gameplay action (the player falls off and is put back). The bot must
## still press it, or the bot would never be able to drive the player
## off an edge.

const AGENT_SCRIPT := preload("res://addons/bugpup/agent.gd")


func _init() -> void:
	print("=== THE EXIT ACTION TEST ===")

	var agent: Node = AGENT_SCRIPT.new()
	# The agent is never added to the tree - the test only asks it
	# which actions it would press.
	root.add_child(agent)

	var failures: Array[String] = []

	# --- the actions that must never be pressed ---
	var must_skip := [
		"exit", "quit", "quit_game", "leave", "close", "back",
		"return_to_menu", "main_menu", "to_menu",
		"reset_run", "restart", "restart_run", "reload_scene",
		"reload_level", "load_scene",
		"pause", "ui_cancel",
	]
	print("")
	print("--- the actions that take the player out of the run ---")
	for name in must_skip:
		var skipped: bool = bool(agent.call("_leaves_the_game", name))
		print("  ", name.lpad(18), " -> skipped: ", skipped)
		if not skipped:
			failures.append("the bot would press '" + name + "'")

	# --- the actions that must still be pressed ---
	print("")
	print("--- the gameplay actions that must still be pressed ---")
	var must_keep := [
		"move_forward", "move_back", "move_left", "move_right",
		"jump", "fire", "reset_position", "interact",
	]
	for name in must_keep:
		var skipped: bool = bool(agent.call("_leaves_the_game", name))
		print("  ", name.lpad(18), " -> skipped: ", skipped)
		if skipped:
			failures.append("the bot would NOT press '" + name + "'")

	# --- the whole input map, end to end ---
	print("")
	print("--- the real input map ---")
	InputMap.add_action("exit")
	InputMap.add_action("reset_position")
	InputMap.add_action("jump")
	var candidates: Array = agent.call("_candidate_actions")
	print("  the actions the bot would press: ", candidates)
	var pressed_exit: bool = candidates.has("exit")
	var pressed_reset: bool = candidates.has("reset_position")
	print("  'exit' is in the list:            ", pressed_exit)
	print("  'reset_position' is in the list:  ", pressed_reset)
	if pressed_exit:
		failures.append("'exit' is in the candidate list")
	if not pressed_reset:
		failures.append("'reset_position' is missing from the candidate list")

	print("")
	if failures.is_empty():
		print("EXIT ACTION TEST PASSED")
		print("  the bot never presses an action that leaves the game,")
		print("  and it still presses the gameplay actions.")
		quit(0)
	else:
		print("EXIT ACTION TEST FAILED")
		for f in failures:
			print("  - ", f)
		quit(1)
