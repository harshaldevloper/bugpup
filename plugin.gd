extends EditorPlugin
## Bugpup - editor plugin entry point.
##
## Registers:
##   1. the "Bugpup" autoload singleton, so game code can call
##      `Bugpup.progress("room_3")` with one line.
##   2. a bottom panel with a Run button and the list of bugs found.
##
## API notes (verified against the local Godot 4.6.3 class docs):
##   - `_enter_tree` is NOT a virtual in Godot 4.x. `_get_plugin_name` is.
##   - `add_control_to_bottom_panel(control, title) -> Button`
##   - `add_autoload_singleton(name, path) -> void`
##   - `EditorInterface.play_current_scene()` / `.is_playing_scene()`

const AGENT_PANEL := preload("res://addons/bugpup/agent_panel.gd")
const AUTOLOAD_NAME := "Bugpup"
const AUTOLOAD_PATH := "res://addons/bugpup/bugpup_api.gd"

var _panel: Control
var _button: Button


func _get_plugin_name() -> String:
	return "Bugpup"


func _enter_tree() -> void:
	# The autoload gives the game a stable `Bugpup.progress(...)` entry
	# point without touching a single game script.
	if not ProjectSettings.has_setting("autoload/" + AUTOLOAD_NAME):
		add_autoload_singleton(AUTOLOAD_NAME, AUTOLOAD_PATH)

	_panel = AGENT_PANEL.new()
	_panel.plugin = self
	_button = add_control_to_bottom_panel(_panel, "Bugpup")


func _exit_tree() -> void:
	if _panel:
		remove_control_from_bottom_panel(_panel)
		_panel.queue_free()
		_panel = null
	_button = null
	# Leave the autoload in place: removing it would break any game code
	# that already calls Bugpup.progress().
