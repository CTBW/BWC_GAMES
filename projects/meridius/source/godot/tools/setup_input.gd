## Registers the game's input actions in project.godot (run once headless):
##   tools/godot.sh --headless --path . -s res://tools/setup_input.gd
extends SceneTree

func _key(code: Key, ctrl := false) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.ctrl_pressed = ctrl
	e.device = -1
	return e

func _add(action: String, events: Array) -> void:
	ProjectSettings.set_setting("input/" + action, {"deadzone": 0.2, "events": events})

func _initialize() -> void:
	_add("cam_up", [_key(KEY_W), _key(KEY_UP)])
	_add("cam_down", [_key(KEY_S), _key(KEY_DOWN)])
	_add("cam_left", [_key(KEY_A), _key(KEY_LEFT)])
	_add("cam_right", [_key(KEY_D), _key(KEY_RIGHT)])
	_add("facing_prev", [_key(KEY_Q)])
	_add("facing_next", [_key(KEY_E)])
	_add("select_next", [_key(KEY_TAB)])
	_add("end_unit", [_key(KEY_SPACE)])
	_add("end_turn", [_key(KEY_ENTER), _key(KEY_KP_ENTER)])
	_add("redo_move", [_key(KEY_BACKSPACE), _key(KEY_Z, true)])
	_add("cancel", [_key(KEY_ESCAPE)])
	_add("toggle_grid", [_key(KEY_G)])
	_add("show_danger", [_key(KEY_ALT)])
	_add("ability_1", [_key(KEY_1)])
	_add("ability_2", [_key(KEY_2)])
	_add("ability_3", [_key(KEY_3)])
	_add("ability_4", [_key(KEY_4)])
	_add("toggle_fullscreen", [_key(KEY_F11)])
	ProjectSettings.set_setting("autoload/Sfx", "*res://scripts/audio/sfx.gd")
	ProjectSettings.set_setting("autoload/App", "*res://scripts/app/app.gd")
	var err := ProjectSettings.save()
	print("input actions saved: ", error_string(err))
	quit(0 if err == OK else 1)
