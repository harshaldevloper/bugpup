extends VBoxContainer
## Bugpup - the editor panel.
##
## A Run button and a list of the bugs the agent found. It starts the
## game with the agent attached, waits for the session to finish, then
## reads the reports the agent wrote.
##
## API notes (verified against the local Godot 4.6.3 class docs):
##   - `EditorInterface.play_current_scene()` / `.is_playing_scene()`
##   - `EditorInterface.get_edited_scene_root()`
##   - `EditorInterface.get_base_control()`
##   - `DirAccess.get_files_at(dir)` lists files
##   - `FileAccess.open(path, READ)` + `.get_as_text()`
##   - `JSON.parse_string(text)`
##   - `OS.get_user_data_dir()`

const AGENT_SCRIPT := preload("res://addons/bugpup/agent.gd")

var plugin: EditorPlugin

var _run_button: Button
var _stop_button: Button
var _status: Label
var _list: ItemList
var _clear_button: Button
var _agent: Node = null
var _busy := false
var _last_report_count := 0

const REPORT_SUBDIR := "bugpup_reports"


func _ready() -> void:
	name = "Bugpup"
	custom_minimum_size = Vector2(0, 220)

	var title := Label.new()
	title.text = "Bugpup"
	title.add_theme_font_size_override("font_size", 14)
	add_child(title)

	var hint := Label.new()
	hint.text = "Plays the game by itself and reports broken physics, NaNs, softlocks and crashes."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.modulate = Color(1, 1, 1, 0.7)
	add_child(hint)

	var row := HBoxContainer.new()
	add_child(row)

	_run_button = Button.new()
	_run_button.text = "Run"
	_run_button.tooltip_text = "Run the current scene with the Bugpup agent attached."
	_run_button.pressed.connect(_on_run_pressed)
	row.add_child(_run_button)

	_stop_button = Button.new()
	_stop_button.text = "Stop"
	_stop_button.disabled = true
	_stop_button.pressed.connect(_on_stop_pressed)
	row.add_child(_stop_button)

	_clear_button = Button.new()
	_clear_button.text = "Clear reports"
	_clear_button.pressed.connect(_on_clear_pressed)
	row.add_child(_clear_button)

	_status = Label.new()
	_status.text = "Idle."
	add_child(_status)

	var list_label := Label.new()
	list_label.text = "Bugs found:"
	add_child(list_label)

	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.custom_minimum_size = Vector2(0, 120)
	_list.auto_height = false
	add_child(_list)

	_refresh_reports()


# --------------------------------------------------------------- run

func _on_run_pressed() -> void:
	if _busy:
		return
	_busy = true
	_run_button.disabled = true
	_stop_button.disabled = false
	_status.text = "Starting the game with the agent..."
	_list.clear()

	var interface := _editor_interface()
	if interface == null:
		_status.text = "Could not reach the editor interface."
		_busy = false
		_run_button.disabled = false
		_stop_button.disabled = true
		return

	# The agent is added to the tree right before the game starts, so it
	# is present in the running instance.
	_agent = AGENT_SCRIPT.new()
	_agent.name = "BugpupAgent"
	interface.get_base_control().get_tree().root.add_child.call_deferred(_agent)
	_agent.call_deferred("start")

	interface.play_current_scene()
	_status.text = "Running..."
	_poll()


func _on_stop_pressed() -> void:
	_busy = false
	_run_button.disabled = false
	_stop_button.disabled = true
	if _agent and is_instance_valid(_agent):
		_agent.call("stop")
		_agent.queue_free()
	_agent = null
	_status.text = "Stopped."
	_refresh_reports()


func _on_clear_pressed() -> void:
	var dir := DirAccess.open(_reports_dir())
	if dir != null:
		for file in dir.get_files_at("."):
			if file.ends_with(".json") or file.ends_with(".png"):
				dir.remove(file)
	_list.clear()
	_status.text = "Reports cleared."


func _poll() -> void:
	if not _busy:
		return
	var interface := _editor_interface()
	if interface != null and interface.is_playing_scene():
		# Keep the status line live while the game runs.
		if _agent and is_instance_valid(_agent):
			var elapsed: float = _agent.get("_elapsed")
			_status.text = "Running... %.0fs" % elapsed
		await get_tree().create_timer(0.5).timeout
		_poll()
		return

	# The game stopped - the agent has finished and written its reports.
	if _agent and is_instance_valid(_agent):
		await _agent.call("finish")
		_agent.queue_free()
	_agent = null
	_busy = false
	_run_button.disabled = false
	_stop_button.disabled = true
	_refresh_reports()
	_status.text = "Finished. %d confirmed bug(s)." % _list.item_count


# --------------------------------------------------------------- reports

func _reports_dir() -> String:
	return OS.get_user_data_dir().path_join(REPORT_SUBDIR)


func _refresh_reports() -> void:
	_list.clear()
	var dir := DirAccess.open(_reports_dir())
	if dir == null:
		return
	var files := dir.get_files_at(".")
	files.sort()
	var found := 0
	for file in files:
		if not file.ends_with(".json"):
			continue
		var handle := FileAccess.open(_reports_dir().path_join(file), FileAccess.READ)
		if handle == null:
			continue
		var text := handle.get_as_text()
		handle.close()
		var parsed = JSON.parse_string(text)
		if typeof(parsed) != TYPE_DICTIONARY:
			continue
		var bug: Dictionary = parsed.get("bug", {})
		if bug.is_empty():
			continue
		found += 1
		_list.add_item("[%s] %s - %s (replayed %d time(s))" % [
			bug.get("kind", "?"), bug.get("body", "?"),
			bug.get("detail", ""), bug.get("replays", 0)])
	_last_report_count = found
	if found == 0 and _status.text.begins_with("Finished"):
		_status.text = "Finished. No confirmed bugs."


func _editor_interface() -> EditorInterface:
	if plugin != null:
		return plugin.get_editor_interface()
	return null
