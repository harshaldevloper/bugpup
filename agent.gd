extends Node
## Bugpup - the part that actually plays the game and watches it.
##
## Lives only while a Bugpup session is active. It:
##   1. presses random actions from the game's own input map
##   2. checks eight things every physics frame
##   3. replays any finding 3 times to confirm it before reporting it
##
## Everything is local. No network, no cloud, no AI model.
##
## API notes (verified against the Godot 4.6.3 class reference):
##   - `Input.action_press(action, strength)` / `Input.action_release(action)`
##   - `InputMap.get_actions()` returns Array[StringName]
##   - `is_nan(x: float) -> bool` and `is_inf(x: float) -> bool` are
##     GLOBAL functions in @GlobalScope. There is NO Vector3.is_nan().
##     `Vector3.is_finite() -> bool` does exist and covers NaN + INF.
##   - `CharacterBody3D.get_slide_collision(i)` returns a
##     **KinematicCollision3D** (there is no "Collision3D" class).
##     KinematicCollision3D has get_normal(), get_depth(), get_collider().
##   - `PhysicsDirectSpaceState3D.intersect_ray(params)` returns an Array
##   - `PhysicsRayQueryParameters3D.create(from, to)` exists
##   - `PhysicsShapeQueryParameters3D` has NO create(); assign members.
##     `shape_rid` takes a RID from `Shape3D.get_rid()` (from Resource).
##   - `Node.get_viewport()`, `Node3D.get_world_3d()`
##   - `Viewport.get_texture()` -> ViewportTexture, whose `get_image()`
##     comes from Texture2D.
##   - `Performance.get_monitor(Performance.TIME_FPS)`
##   - `Node.get_name()` is a method on Node; `name` is also a property.

## How many frames the driver probe looks at, before and after a
## press.
const DRIVER_PROBE_FRAMES := 6

const REPORT_DIR := "user://bugpup_reports"
const API_PATH := "res://addons/bugpup/bugpup_api.gd"

# --------------------------------------------------------------- tunables

@export var duration_seconds := 60.0
@export var seed_value := 20261116
@export var action_hold_frames := 6
@export var idle_frames := 3

@export var jitter_flips := 6
@export var jitter_window_frames := 45
@export var jitter_max_avg_step := 0.25
# The distance a body must travel over the jitter window for its
# reversals to count. A still body moves a fraction of a unit in
# float noise; an oscillating one travels a real distance.
@export var jitter_min_path := 0.3

@export var out_of_bounds_y := -50.0
@export var out_of_bounds_radius := 120.0

@export var stuck_depth := 0.25
@export var stuck_normal_cancel := 0.5

@export var lag_spike_ms := 120.0
@export var lag_window := 30

@export var softlock_seconds := 25.0
@export var freeze_seconds := 6.0
# How far a body must have travelled before it can be called
# frozen. A prop that never moved is scenery.
@export var freeze_min_travel := 0.5

@export var replay_attempts := 3

# How many recent positions the tunnel check casts a ray from.
@export var tunnel_history_frames := 4

# --------------------------------------------------------------- state

var active := false
var rng := RandomNumberGenerator.new()

var _pressed: Array[StringName] = []
var _hold_left := 0
var _idle_left := 0
var _elapsed := 0.0
var _ticks := 0
var _last_frame_usec := 0
var _frame_ms: Array[float] = []
var _last_progress_usec := 0
var _seen_progress := false

var _body_state := {}
var _quarantined := {}
var _last_screenshot := ""
var _last_input_frame := -999
var _input_log: Array = []
var _pending := {}
var _confirmed: Array = []
var _confirmed_keys := {}

var _replaying := false
var _finished := false
var _finish_complete := false

# The instance id of the body the agent is driving, worked out by
# measurement - see _score_driver_candidates.
var _driver_id := 0
var _driver_score := {}
# The movement vector of every watched body, and a snapshot of it
# taken at the moment an action was pressed.
var _body_disp := {}
var _press_disp := {}
var _press_frame := -1
# Nodes that have been seen to MOVE, and the position they were
# last seen at.
var _movers := {}
var _mover_extra := {}
# Every watched node, by instance id.
var _watch_map := {}
# Every physics body in the scene, by instance id, whether or not
# it has been quarantined. Used to tell a body from its own
# collision shape.
var _body_ids := {}
# The movement history of every watched body, and the probe that
# works out which body the game is steering with the input.
var _disp_hist := {}
var _driver_probe := {}
# The replay counter is kept here rather than as a local so the
# editor panel can show how far a replay has got. It is only
# written by the replay that owns it - see _replay_inputs_and_watch.
var _replay_ticks := 0


# --------------------------------------------------------------- session

func start() -> void:
	if active:
		return
	active = true
	rng.seed = seed_value
	_elapsed = 0.0
	_ticks = 0
	_frame_ms.clear()
	_body_state.clear()
	_input_log.clear()
	_pending.clear()
	_confirmed.clear()
	_replaying = false
	_seen_progress = false
	_last_progress_usec = Time.get_ticks_usec()
	_last_frame_usec = Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(REPORT_DIR)
	set_physics_process(true)
	_api_call("register", [self])


func stop() -> void:
	active = false
	set_physics_process(false)
	_release_all()
	_api_call("unregister", [self])


func is_active() -> bool:
	return active


func confirmed_bugs() -> Array:
	return _confirmed.duplicate()


## Call a method on the Bugpup API.
##
## The API is an autoload singleton named "Bugpup", so it is found
## with a tree lookup. It is NEVER loaded with load(): loading a
## script while another script is initialising deadlocks Godot's
## ResourceLoader (verified: it hangs the whole engine).
##
## If the API is not in the tree - for example in a headless test
## where the editor plugin never ran - the agent still works. The
## progress() API is optional: a game that never calls it simply
## never reports a softlock.
func _api_call(method: String, args: Array) -> void:
	# The node may not be in the tree yet (start() can be called
	# right after the node is created). get_tree() returns null
	# then, and asking for it logs an error.
	if not is_inside_tree():
		return
	var tree := get_tree()
	if tree == null:
		return
	var autoload := tree.root.get_node_or_null("Bugpup")
	if autoload == null or not autoload.has_method(method):
		return
	autoload.callv(method, args)


## Called by Bugpup.progress("room_3") in game code.
func on_progress(label: String) -> void:
	_seen_progress = true
	_last_progress_usec = Time.get_ticks_usec()


# --------------------------------------------------------------- input

func _candidate_actions() -> Array[StringName]:
	var out: Array[StringName] = []
	for action in InputMap.get_actions():
		var n := String(action)
		if n.begins_with("ui_"):
			continue
		# Never press things that quit, reload, or reset the run - they
		# would hide bugs rather than find them.
		if n in ["reset_run", "pause", "quit", "reload_scene", "ui_cancel"]:
			continue
		out.append(action)
	return out


func _press(action: StringName) -> void:
	Input.action_press(action, 1.0)
	_pressed.append(action)
	_last_input_frame = _ticks
	_input_log.append({"frame": _ticks, "action": String(action), "pressed": true})
	# Remember how everything was moving at the moment of the press,
	# so the driver can be worked out from what changes next.
	_begin_driver_probe()


func _release_all() -> void:
	for action in _pressed:
		Input.action_release(action)
		_input_log.append({"frame": _ticks, "action": String(action), "pressed": false})
	_pressed.clear()


func _drive_random_input() -> void:
	if _hold_left > 0:
		_hold_left -= 1
		return
	if _idle_left > 0:
		_idle_left -= 1
		return
	_release_all()
	var actions := _candidate_actions()
	if actions.is_empty():
		return
	_press(actions[rng.randi_range(0, actions.size() - 1)])
	_hold_left = action_hold_frames
	_idle_left = rng.randi_range(0, idle_frames)


# --------------------------------------------------------------- replay

## Replay the recorded inputs and count how often the same kind of
## finding shows up again. Returns the number of reproductions.
func replay_finding(key: String) -> int:
	# Replay the recorded inputs and count how often the same class
	# of problem comes back. Returns the number of reproductions.
	#
	# THE SCENE IS RELOADED between attempts. That is what makes both
	# kinds of bug reproducible:
	#   - a bug caused by the bot's inputs (through a wall, jittering)
	#     comes back when the same inputs are applied again
	#   - a bug caused by the game's own logic (a NaN velocity, a body
	#     falling out of the world) comes back because the game's
	#     _ready() and _physics_process() run again
	var pending: Dictionary = _pending.get(key, {})
	if pending.is_empty():
		return 0
	var inputs: Array = pending.get("inputs", [])
	var finding: Dictionary = pending.get("finding", {})
	var target := String(finding.get("kind", ""))

	var tree := get_tree()
	if tree == null:
		return 0

	var hits := 0
	# The main loop stands down for the WHOLE replay, including the
	# settle frames after the reload. _physics_process updates
	# _body_state, and the replay reads its previous positions and
	# flip counters from that same dictionary - if the main loop runs
	# during a replay it overwrites the replay's state under its feet.
	_replaying = true
	for attempt in replay_attempts:
		# Start from a fresh copy of the scene.
		if tree.current_scene == null:
			# Nothing to reload; the finding cannot be reproduced.
			break
		var reload_err := tree.reload_current_scene()
		if reload_err != OK:
			break
		# Let the new scene build itself. ONE frame is enough: the
		# probe measured the new scene's bodies already in place on the
		# first physics frame after the reload. A longer wait is not
		# just slow - it is WRONG, because a fast body crosses a thin
		# wall within two frames and the replay would miss it entirely.
		await tree.physics_frame
		# Re-apply the recorded inputs and watch for the same problem.
		if await _replay_inputs_and_watch(inputs, target):
			hits += 1
	_replaying = false

	return hits


## Apply the recorded inputs on their original frame offsets and watch
## for the same class of problem. Returns true if it comes back.
##
## EVERY piece of replay state is LOCAL. The earlier version kept it
## in member variables, and two replays running at the same time
## overwrote each other's counters - which is exactly what happened:
## seventeen replays of one key all reported "1/3".
func _replay_inputs_and_watch(inputs: Array, target: String) -> bool:
	_body_state.clear()
	_quarantined.clear()
	_release_all()
	var replay_index := 0
	var replay_ticks := 0
	_replaying = true
	var found := false

	# How long to run: the span of the recorded inputs, plus a tail so a
	# bug that happens after the last press is still caught - and never
	# less than enough frames for the slowest detector (jitter needs a
	# full window of frames plus several reversals inside it).
	var total_frames := 0
	if not inputs.is_empty():
		total_frames = int(inputs[inputs.size() - 1].get("frame", 0))
	var limit: int = maxi(total_frames + 60, 120)

	while replay_ticks < limit:
		replay_ticks += 1
		_replay_ticks = replay_ticks
		replay_index = _drive_replay_input(inputs, replay_index, replay_ticks)
		if replay_ticks % 10 == 0:
			_discover_movers()
		for body in _watched_bodies():
			if not is_instance_valid(body):
				continue
			var rid: int = body.get_instance_id()
			var rstate: Dictionary = _body_state.get(rid, {})
			var rprev: Vector3 = rstate.get("last_pos", _position_of(body))
			var finding := _check_body(body, 1.0 / 60.0, rprev)
			if finding.is_empty():
				finding = _check_tunnelling(body, rprev)
			_push_history(body, _position_of(body))
			if not finding.is_empty() and String(finding.get("kind", "")) == target:
				found = true
				break
		if found:
			break
		await get_tree().physics_frame

	_release_all()
	return found


## Feed the recorded input events back on the frames they happened.
## Returns the new index into the input list.
func _drive_replay_input(inputs: Array, index: int, ticks: int) -> int:
	var i := index
	while i < inputs.size():
		var ev: Dictionary = inputs[i]
		if int(ev.get("frame", -1)) > ticks:
			break
		i += 1
		var action := StringName(ev.get("action", ""))
		if action == "":
			continue
		if bool(ev.get("pressed", false)):
			Input.action_press(action, 1.0)
		else:
			Input.action_release(action)
		# The bot is driving the game right now, so a direction change
		# in the player is the bot's doing, not a bug. The jitter
		# detector uses this to avoid crying wolf.
		_last_input_frame = ticks
	return i


# --------------------------------------------------------------- bodies

func _watched_bodies() -> Array:
	# Watch everything that could be broken.
	#
	# Three sources, in this order:
	#   1. the "player" and "physics_body" groups, if the game uses them
	#   2. any physics body TYPE, whether the game groups it or not
	#   3. any node that has been seen to MOVE
	#
	# Source 2 matters because a lot of games - including this one -
	# use no groups at all. An agent that only watched groups would
	# watch an empty world and would have nothing to report.
	var out: Array = []
	var seen := {}
	var tree := get_tree()
	if tree == null:
		return out

	# --- 1. the groups a game might use ---
	for group in ["player", "physics_body"]:
		for node in tree.get_nodes_in_group(group):
			_add_watched(out, seen, node)

	# --- 2. the physics body types ---
	_body_ids.clear()
	for node in _physics_bodies():
		_body_ids[node.get_instance_id()] = true
		_add_watched(out, seen, node)

	# --- 3. the nodes that have been seen to move ---
	for id in _mover_extra.keys():
		var node = _mover_extra[id]
		if node == null or not is_instance_valid(node):
			continue
		# Skip anything under a body that is already being watched - a
		# camera pivot under the player would double every finding, and
		# a collision shape would report its parent body's fall.
		if _has_watched_ancestor(node, _body_ids):
			continue
		_add_watched(out, seen, node)

	return out


func _add_watched(out: Array, seen: Dictionary, node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node == self:
		return
	var id: int = node.get_instance_id()
	if seen.has(id):
		return
	# Skip bodies the agent has quarantined.
	if _quarantined.has(id):
		return
	seen[id] = true
	out.append(node)
	_watch_map[id] = node


## Every node in the current scene that is a physics body, whether or
## not the game put it in a group.
func _physics_bodies() -> Array:
	var out: Array = []
	var tree := get_tree()
	if tree == null:
		return out
	var scene := tree.current_scene
	if scene == null:
		return out
	for type_name in ["CharacterBody3D", "CharacterBody2D", "RigidBody3D",
			"RigidBody2D", "AnimatableBody3D", "AnimatableBody2D",
			"Area3D", "Area2D"]:
		for node in scene.find_children("*", type_name, true, false):
			out.append(node)
	return out


## True if any ancestor of this node is already being watched.
func _has_watched_ancestor(node: Node, seen: Dictionary) -> bool:
	var parent := node.get_parent()
	while parent != null:
		if seen.has(parent.get_instance_id()):
			return true
		parent = parent.get_parent()
	return false


## Look for nodes that MOVE. Some actors are plain Node3D - the
## enemies in a lot of games are - and they are exactly the things
## that fall through floors and go through walls.
##
## Only a node that has actually moved is added, so this does not
## flood the report with static scenery.
func _discover_movers() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var scene := tree.current_scene
	if scene == null:
		return
	for type_name in ["Node3D", "Node2D"]:
		for node in scene.find_children("*", type_name, true, false):
			if node == self:
				continue
			# Visual and light nodes are not actors.
			if node is MeshInstance3D or node is MeshInstance2D:
				continue
			if node is Camera3D or node is Camera2D:
				continue
			if node is Light3D or node is Light2D:
				continue
			if node is StaticBody3D or node is StaticBody2D:
				continue
			var id: int = node.get_instance_id()
			var pos := _position_of(node)
			if not _movers.has(id):
				_movers[id] = pos
				continue
			var prev: Vector3 = _movers[id]
			if prev.distance_to(pos) > 0.001:
				_movers[id] = pos
				_mover_extra[id] = node


## Work out WHICH body the game steers with the input the agent is
## pressing.
##
## The measurement: compare the AVERAGE movement over the frames just
## BEFORE a press with the average over the frames just AFTER it.
##
## Why the average and not a single frame: some bodies move on every
## frame regardless of the input - a shaking box reverses direction
## constantly - so a single-frame comparison cannot tell them apart
## from the body the player is steering. Over six frames a shaking box
## averages out to nearly nothing, while the player's average movement
## flips direction the moment a different direction is pressed.
##
## The agent keeps a running score and remembers the winner.
func _score_driver_candidates() -> void:
	# Finish the probes that are due.
	for id in _driver_probe.keys():
		var probe: Dictionary = _driver_probe[id]
		if _ticks - int(probe.get("frame", -999)) < DRIVER_PROBE_FRAMES:
			continue
		_driver_probe.erase(id)
		var node = _watch_map.get(id, null)
		if node == null or not is_instance_valid(node):
			continue
		var hist: Array = _disp_hist.get(id, [])
		if hist.size() < DRIVER_PROBE_FRAMES * 2:
			continue
		var before: Vector3 = probe.get("before", Vector3.ZERO)
		var after: Vector3 = _mean_movement(hist, hist.size() - DRIVER_PROBE_FRAMES)
		var change := (after - before).length()
		if change <= 0.0:
			continue
		_driver_score[id] = _driver_score.get(id, 0.0) + change
		var best := 0
		var best_score := -1.0
		for key in _driver_score.keys():
			if _driver_score[key] > best_score:
				best_score = _driver_score[key]
				best = key
		_driver_id = best


## The average movement over the last `count` entries of a history.
func _mean_movement(hist: Array, count: int) -> Vector3:
	if count <= 0 or hist.is_empty():
		return Vector3.ZERO
	var total := Vector3.ZERO
	var n := 0
	for i in range(hist.size() - count, hist.size()):
		total += hist[i]
		n += 1
	if n == 0:
		return Vector3.ZERO
	return total / float(n)


## Start a probe for every watched body: remember its average movement
## so far, and look at it again in a few frames.
func _begin_driver_probe() -> void:
	for id in _disp_hist.keys():
		var hist: Array = _disp_hist[id]
		if hist.size() < DRIVER_PROBE_FRAMES:
			continue
		_driver_probe[id] = {
			"frame": _ticks,
			"before": _mean_movement(hist, DRIVER_PROBE_FRAMES),
		}


## True if this body is the one the agent is driving.
func _is_bot_driven(body: Node) -> bool:
	if body == null:
		return false
	return body.get_instance_id() == _driver_id


func _velocity_of(body: Node) -> Vector3:
	if body is CharacterBody3D:
		return (body as CharacterBody3D).velocity
	if body is RigidBody3D:
		return (body as RigidBody3D).linear_velocity
	if body is CharacterBody2D:
		var v2 := (body as CharacterBody2D).velocity
		return Vector3(v2.x, v2.y, 0.0)
	if body is RigidBody2D:
		var v2b := (body as RigidBody2D).linear_velocity
		return Vector3(v2b.x, v2b.y, 0.0)
	return Vector3.ZERO


func _position_of(body: Node) -> Vector3:
	if body is Node3D:
		return (body as Node3D).global_position
	if body is Node2D:
		var p2 := (body as Node2D).global_position
		return Vector3(p2.x, p2.y, 0.0)
	return Vector3.ZERO


func _body_label(body: Node) -> String:
	if body == null:
		return "?"
	if body.has_method("get_name"):
		return String(body.get_name())
	return str(body)

## Park a body whose numbers are broken so it cannot poison the
## rest of the simulation, and stop watching it.
func _quarantine(body: Node, pos: Vector3, vel: Vector3) -> void:
	var id: int = body.get_instance_id()
	if _quarantined.has(id):
		return
	_quarantined[id] = true
	if body is RigidBody3D:
		var rb := body as RigidBody3D
		if rb.linear_velocity.is_finite():
			rb.linear_velocity = Vector3.ZERO
		rb.freeze = true
	elif body is CharacterBody3D:
		var cb := body as CharacterBody3D
		if cb.velocity.is_finite():
			cb.velocity = Vector3.ZERO
	elif body is RigidBody2D:
		var rb2 := body as RigidBody2D
		if rb2.linear_velocity.is_finite():
			rb2.linear_velocity = Vector2.ZERO
		rb2.freeze = true
	elif body is CharacterBody2D:
		var cb2 := body as CharacterBody2D
		if cb2.velocity.is_finite():
			cb2.velocity = Vector2.ZERO



## The frame counter the jitter detector compares against. During a
## replay the replay's own counter is the right one, because that is
## the clock the recorded inputs were on.
func ticks_now() -> int:
	if _replaying:
		return _replay_ticks
	return _ticks


## The size of a body, used to tell "passed through" from "touched".
func _body_radius(body: Node) -> float:
	if body is CollisionShape3D:
		var shape = (body as CollisionShape3D).shape
		if shape is SphereShape3D:
			return (shape as SphereShape3D).radius
		if shape is BoxShape3D:
			var s: Vector3 = (shape as BoxShape3D).size
			return maxf(s.x, maxf(s.y, s.z)) * 0.5
	if body is CollisionObject3D:
		var col := body as CollisionObject3D
		for child in col.get_children():
			if child is CollisionShape3D:
				var r := _body_radius(child)
				if r > 0.0:
					return r
	return 0.05
# --------------------------------------------------------------- per frame

func _physics_process(delta: float) -> void:
	if not active:
		return

	var now := Time.get_ticks_usec()
	var frame_ms := float(now - _last_frame_usec) / 1000.0
	_last_frame_usec = now

	if _replaying:
		# A replay is in progress: it drives the recorded inputs
		# itself and watches for the finding. The normal loop must
		# not also press inputs or report anything.
		return

	_frame_ms.append(frame_ms)
	if _frame_ms.size() > lag_window:
		_frame_ms.remove_at(0)
	_elapsed += delta
	_ticks += 1

	_drive_random_input()

	# Look for actors that move, and work out which body the game is
	# steering with the agent's inputs.
	if _ticks % 10 == 0:
		_discover_movers()

	# --- 8. lag spike ---
	if frame_ms > lag_spike_ms and _frame_ms.size() >= 5:
		var sorted := _frame_ms.duplicate()
		sorted.sort()
		var median: float = sorted[sorted.size() / 2]
		if median > 0.0 and frame_ms > median * 4.0:
			_capture_screenshot("lag_spike")
			_report({
				"kind": "lag_spike",
				"body": "-",
				"detail": "frame took %.1fms (median %.1fms)" % [frame_ms, median],
			})
			_frame_ms.clear()

	for body in _watched_bodies():
		if not is_instance_valid(body):
			continue
		# Capture where the body was BEFORE any check updates its
		# stored position, so the tunnel check measures real movement.
		var bid: int = body.get_instance_id()
		var bstate: Dictionary = _body_state.get(bid, {})
		var prev_pos: Vector3 = bstate.get("last_pos", _position_of(body))
		var finding := _check_body(body, delta, prev_pos)
		if finding.is_empty():
			finding = _check_tunnelling(body, prev_pos)
		if not finding.is_empty():
			_capture_screenshot(String(finding.get("kind", "bug")))
			_report(finding)
		# Store the current position for the next frame.
		bstate["last_pos"] = _position_of(body)
		bstate["seen"] = true
		_body_state[bid] = bstate
		# Remember where the body has been, so the tunnel check can cast
		# a ray from each of its recent positions.
		_push_history(body, _position_of(body))
		# Remember how this body moved this frame, so the driver can be
		# worked out from what changes when an action is pressed.
		_body_disp[bid] = _position_of(body) - prev_pos
		var hist: Array = _disp_hist.get(bid, [])
		hist.append(_body_disp[bid])
		while hist.size() > DRIVER_PROBE_FRAMES * 2:
			hist.remove_at(0)
		_disp_hist[bid] = hist

	# Work out which body the game is steering with the agent's input.
	_score_driver_candidates()

	if _elapsed >= duration_seconds:
		finish()


# --------------------------------------------------------------- detectors

func _check_body(body: Node, delta: float, prev_pos: Vector3) -> Dictionary:
	if body == null or not is_instance_valid(body):
		return {}
	var id: int = body.get_instance_id()
	var pos := _position_of(body)
	var vel := _velocity_of(body)
	var state: Dictionary = _body_state.get(id, {})
	var label := _body_label(body)
	# Store the current position BEFORE any early return below. An early
	# return (out of bounds, NaN) used to skip this, which left a stale
	# position behind and made the tunnel check measure the wrong move.
	state["last_pos"] = pos
	state["seen"] = true
	_body_state[id] = state

	# --- 5. NaN / broken numbers ---
	if not pos.is_finite() or not vel.is_finite():
		# Quarantine the body. A NaN velocity poisons the whole solver,
		# so one broken body would blind the entire session and flood
		# the log. Park it, stop watching it, and keep going.
		_quarantine(body, pos, vel)
		return {
			"kind": "nan_numbers",
			"body": label,
			"detail": "position=%s velocity=%s" % [str(pos), str(vel)],
		}

	# --- 3. jittering ---
	# Jitter = the body keeps reversing direction while barely moving.
	# A reversal is a negative dot product between consecutive movement
	# vectors, which is a real direction change (the old sign test used
	# "x > 0 OR z > 0", which flips whenever either axis goes negative).
	var flips: int = state.get("flips", 0)
	var window: Array = state.get("window", [])
	var prev_move: Vector3 = state.get("prev_move", Vector3.ZERO)
	var delta_vec: Vector3 = pos - prev_pos
	var step_len: float = delta_vec.length()
	# A reversal only counts as jitter if the bot was NOT driving THIS
	# body. When the agent presses a direction, the body the game
	# steers with that direction is EXPECTED to turn. A crate that
	# shakes on its own is a real bug, so the excuse only applies to
	# the body the bot is actually steering - and which body that is
	# is worked out by measurement, not by guessing.
	var input_recent := (ticks_now() - _last_input_frame) <= 3
	var bot_drove := _is_bot_driven(body) and input_recent
	if step_len > 0.0005 and prev_move.length() > 0.0005:
		if delta_vec.dot(prev_move) < 0.0 and not bot_drove:
			flips += 1
	if step_len > 0.0005:
		state["prev_move"] = delta_vec
	var entry := Vector2(step_len, 0.0)
	window.append(entry)
	if window.size() > jitter_window_frames:
		window.remove_at(0)
	if flips >= jitter_flips:
		var moved := 0.0
		for w: Vector2 in window:
			moved += w.x
		var avg := moved / maxf(1.0, float(window.size()))
		# Jitter means the body OSCILLATES: it travels a real distance
		# while going nowhere. A body that is not moving has a
		# displacement of float noise, and that noise changes direction
		# at random - which looks exactly like jitter if the only test
		# is "did the direction change". The path length over the
		# window is what tells the two apart.
		if avg < jitter_max_avg_step and moved >= jitter_min_path:
			return {
				"kind": "jitter",
				"body": label,
				"detail": "%d direction reversals in %d frames, avg step %.4f" % [
					flips, window.size(), avg],
			}
	state["flips"] = flips
	state["window"] = window

	# --- 2. fell out of the map ---
	# A body that has left the world is parked: left falling it makes the
	# engine log thousands of errors and drowns the real findings.
	if pos.y < out_of_bounds_y:
		_quarantine(body, pos, vel)
		return {
			"kind": "out_of_bounds",
			"body": label,
			"detail": "y=%.2f is below the floor limit %.2f" % [pos.y, out_of_bounds_y],
		}
	if pos.length() > out_of_bounds_radius:
		return {
			"kind": "out_of_bounds",
			"body": label,
			"detail": "%.1f from origin, limit %.1f" % [
				pos.length(), out_of_bounds_radius],
		}

	# --- 6. stuck inside geometry ---
	# A body wedged inside a collider gets colliding normals from
	# several sides that cancel out.
	if body is CharacterBody3D:
		var cb := body as CharacterBody3D
		var count := cb.get_slide_collision_count()
		if count > 0:
			var deepest := 0.0
			var normal_sum := Vector3.ZERO
			for i in count:
				var col: KinematicCollision3D = cb.get_slide_collision(i)
				deepest = maxf(deepest, col.get_depth())
				normal_sum += col.get_normal()
			if deepest > stuck_depth and normal_sum.length() < stuck_normal_cancel:
				return {
					"kind": "stuck",
					"body": label,
					"detail": "wedged %.3f into a collider, normals cancel" % deepest,
				}

	# --- 4. softlock ---
	if _seen_progress:
		var since := float(Time.get_ticks_usec() - _last_progress_usec) / 1000000.0
		if since > softlock_seconds:
			return {
				"kind": "softlock",
				"body": label,
				"detail": "no Bugpup.progress() call for %.1fs" % since,
			}

	# --- 7. freeze ---
	var stalled: float = state.get("stalled", 0.0)
	if step_len < 0.00001 and state.has("last_pos"):
		stalled += delta
	else:
		stalled = 0.0
	state["stalled"] = stalled
	# A freeze means something that WAS moving stopped. A prop that
	# never moved is scenery, not a freeze, so the body has to have
	# travelled a real distance at some point during the session.
	var travelled: float = state.get("travelled", 0.0)
	travelled += step_len
	state["travelled"] = travelled
	if stalled > freeze_seconds and travelled >= freeze_min_travel:
		return {
			"kind": "freeze",
			"body": label,
			"detail": "no movement for %.1fs" % stalled,
		}

	_body_state[id] = state
	return {}


## --- 1. going through walls ---
## Cast a ray from the body's PREVIOUS positions to its current one.
## If it hits a solid body and the body ended up well past that
## surface, it tunnelled.
##
## The ray is cast from a short HISTORY of positions, not just the
## previous frame. A fast body can cross a thin wall inside a single
## frame, so a check that only compares against the last position
## loses the event whenever the watcher misses the exact crossing
## frame. Checking every remembered position makes the detector
## tolerant of that - and it reports the wall the body actually
## crossed first, which is the one worth reporting.
func _check_tunnelling(body: Node, prev_pos: Vector3) -> Dictionary:
	if not (body is Node3D):
		return {}
	var id: int = body.get_instance_id()
	var state: Dictionary = _body_state.get(id, {})
	if not state.has("seen"):
		return {}
	var now: Vector3 = (body as Node3D).global_position
	var world := (body as Node3D).get_world_3d()
	if world == null:
		return {}
	var space := world.direct_space_state
	if space == null:
		return {}
	var body_radius := _body_radius(body)

	# The positions to check against, oldest first. The current position
	# is added by the caller each frame; this list is the history.
	var history: Array = state.get("history", [])
	var starts: Array = []
	for h in history:
		starts.append(h)
	# The position the caller passed in is the most recent one.
	if prev_pos != now:
		starts.append(prev_pos)

	for start_pos in starts:
		var from: Vector3 = start_pos
		var motion := now - from
		# A body that did not move, or that moved an absurd distance, is
		# not a tunnelling candidate.
		if motion.length() < 0.35 or motion.length() > 25.0:
			continue
		var params := PhysicsRayQueryParameters3D.create(from, now)
		params.collision_mask = 0xFFFFFFFF
		params.collide_with_bodies = true
		params.collide_with_areas = false
		# The ray starts inside the moving body's own collider, so that
		# body must be excluded or the query can hang on a ray that begins
		# inside a shape. Verified against the Godot 4.6.3 class docs.
		if body is CollisionObject3D:
			params.exclude = [(body as CollisionObject3D).get_rid()]
		params.hit_from_inside = true
		# intersect_ray returns a SINGLE Dictionary (the hit), not an Array.
		var hit: Dictionary = space.intersect_ray(params)
		if hit.is_empty():
			continue
		var hit_pos: Vector3 = hit["position"]
		# Travel past the surface, measured ALONG THE RAY. The hit normal
		# points back at the approaching body on the near face of a wall, so
		# a dot product with the normal is NEGATIVE when the body has gone
		# through. The ray direction is the honest measure of how far past.
		var ray_dir := (now - from).normalized()
		var travel := (now - hit_pos).dot(ray_dir)
		# It only counts as tunnelling if the body passed the surface by
		# more than its own size - otherwise it merely touched it.
		if travel > body_radius + 0.02:
			var collider_name := "?"
			if hit.has("collider") and hit["collider"] != null:
				collider_name = _body_label(hit["collider"])
			return {
				"kind": "through_wall",
				"body": _body_label(body),
				"detail": "passed %.2f through '%s' at %s (its size is %.2f)" % [
					travel, collider_name, str(hit_pos.round()), body_radius],
			}
	return {}


## Remember where a body has been, so the tunnel check can cast a ray
## from each of its recent positions.
func _push_history(body: Node, pos: Vector3) -> void:
	var id: int = body.get_instance_id()
	var state: Dictionary = _body_state.get(id, {})
	var history: Array = state.get("history", [])
	history.append(pos)
	# A handful of positions is enough: the fastest useful case is a body
	# crossing a wall in one frame, and a few frames of history covers
	# the watcher missing the exact crossing frame.
	while history.size() > tunnel_history_frames:
		history.remove_at(0)
	state["history"] = history
	_body_state[id] = state


# --------------------------------------------------------------- findings

func _report(finding: Dictionary) -> void:
	if finding.is_empty():
		return
	var key := "%s|%s" % [finding.get("kind", "?"), finding.get("body", "?")]
	if _confirmed_keys.has(key):
		return
	var pending: Dictionary = _pending.get(key, {})
	# Keep the FIRST sighting: it is the earliest occurrence and so
	# the most useful one to report. Later sightings only bump the
	# count.
	if not pending.has("finding"):
		pending["finding"] = finding
	pending["count"] = pending.get("count", 0) + 1
	if not pending.has("inputs"):
		pending["inputs"] = _input_log.duplicate()
	_pending[key] = pending


## Confirm every pending finding by replaying it, then write the report.
func confirm_pending() -> Array:
	var results: Array = []
	# The keys are copied out first: a replay can report a NEW finding,
	# and that would change _pending while it is being iterated.
	for key in _pending.keys():
		var pending: Dictionary = _pending[key]
		var hits := await replay_finding(key)
		if hits >= replay_attempts:
			var finding: Dictionary = pending.get("finding", {})
			var entry := {
				"kind": finding.get("kind", "?"),
				"body": finding.get("body", "?"),
				"detail": finding.get("detail", ""),
				"replays": hits,
				"seen": pending.get("count", 1),
				"screenshot": pending.get("screenshot", ""),
			}
			if _confirmed_keys.has(key):
				continue
			_confirmed.append(entry)
			_confirmed_keys[key] = true
			results.append(entry)
			_write_report(entry, pending)
	return results


func _write_report(entry: Dictionary, pending: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(REPORT_DIR)
	var stamp := str(Time.get_unix_time_from_system()).replace(".", "_")
	var path := "%s/%s_%s.json" % [REPORT_DIR, entry.get("kind", "bug"), stamp]
	var payload := {
		"bug": entry,
		"inputs": pending.get("inputs", []),
		"seed": seed_value,
	}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(payload, "  "))
		file.close()


# --------------------------------------------------------------- screenshot

func _capture_screenshot(tag: String) -> void:
	var viewport := get_viewport()
	if viewport == null:
		return
	var texture := viewport.get_texture()
	if texture == null:
		return
	# In --headless mode there is no real renderer, so the texture has
	# no image. Skip it instead of letting the engine log an error for
	# every frame.
	if DisplayServer.get_name() == "headless":
		return
	var image: Image = texture.get_image()
	if image == null or image.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(REPORT_DIR)
	var stamp := str(Time.get_unix_time_from_system()).replace(".", "_")
	var path := "%s/shot_%s_%s.png" % [REPORT_DIR, tag, stamp]
	var err := image.save_png(path)
	if err == OK:
		_last_screenshot = path


# --------------------------------------------------------------- finish

func finish() -> void:
	# finish() is called from _physics_process, which keeps running
	# while this coroutine is suspended at an await. Without the
	# _finished guard, every frame after the duration elapsed would
	# start ANOTHER confirm_pending(), and the two would run at the
	# same time and overwrite each other's counters.
	#
	# If a finish is already running, WAIT for it rather than
	# returning at once. A caller that returns early reads the
	# results before the replays have finished.
	if _finished:
		while not _finish_complete and is_inside_tree():
			await get_tree().process_frame
		return
	_finished = true
	await confirm_pending()
	stop()
	_finish_complete = true
