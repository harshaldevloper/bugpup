extends Node
## Bugpup - the public API the game calls, plus the autoload bridge.
##
## Game code uses exactly one line:
##
##     Bugpup.progress("room_3")
##
## That tells the agent "the player reached room 3". If the agent later
## sees the game stop progressing while the world keeps running, it
## reports a softlock.
##
## Everything is local: no network calls, no cloud, no AI model.

## Emitted whenever the agent records a confirmed bug.
signal bug_found(bug: Dictionary)

## Emitted when the agent's state changes (so the editor panel can poll
## or listen without touching the agent directly).
signal agent_state_changed

static var _instance: Node = null
static var _progress_label: String = ""
static var _progress_time_usec: int = 0


## Called by game code. `label` names where the player got to.
static func progress(label: String) -> void:
	_progress_label = label
	_progress_time_usec = Time.get_ticks_usec()
	if _instance and is_instance_valid(_instance):
		_instance.on_progress(label)


## The most recent progress label, or "" if progress() was never called.
static func current_progress() -> String:
	return _progress_label


## How long ago (in seconds) progress() was last called. -1 if never.
static func seconds_since_progress() -> float:
	if _progress_time_usec == 0:
		return -1.0
	return float(Time.get_ticks_usec() - _progress_time_usec) / 1000000.0


## True while the agent is actively playing the game.
static func is_running() -> bool:
	return _instance != null and is_instance_valid(_instance) and _instance.is_active()


func _enter_tree() -> void:
	# The agent itself only exists while a Bugpup session is active,
	# so it never touches the game during normal play.
	pass


func _ready() -> void:
	# The panel starts a session by adding the agent to the tree.
	pass


## Called by the agent when it is created, so the static API can reach it.
static func register(instance: Node) -> void:
	_instance = instance


static func unregister(instance: Node) -> void:
	if _instance == instance:
		_instance = null
