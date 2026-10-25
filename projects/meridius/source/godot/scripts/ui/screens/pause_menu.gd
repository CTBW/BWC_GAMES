## The pause menu (a Godot addition; the original has only the top bar's Menu
## button, which goes to the title). Opened with Esc when nothing else uses it;
## the world is paused while it is open.
## Resume · Field Manual · Sound on/off, with a volume slider each for master,
## music, ambience, effects and voices (Sfx buses, remembered in prefs) ·
## Fullscreen on/off · Save and Quit to Title · New Company (asks first).
extends Control

const UI = preload("res://scripts/ui/ui.gd")
const Modal = preload("res://scripts/ui/widgets/modal.gd")
const Confirm = preload("res://scripts/ui/widgets/confirm.gd")

## Volume sliders: key (App.set_volume) and label.
const VOLUMES := [["master", "Master"], ["music", "Music"], ["ambience", "Ambience"], ["sfx", "Effects"], ["voice", "Voices"]]

var _sound: Button
var _full: Button
var _sliders: Dictionary = {}


func _init() -> void:
	name = "PauseMenu"
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var d := Modal.dialog(380, [22, 30])
	d.theme_type_variation = "DarkPanel"
	d.remove_theme_stylebox_override("panel")
	UI.dark(d)
	UI.pad(d, [26, 30])
	var col := UI.vbox(10)
	d.add_child(col)
	col.add_child(UI.title_block("Meridius"))
	var items := [
		["Resume", "RedButton", func(): App.open_menu(false)],
		["Field Manual", "Button", func():
			App.open_menu(false)
			App.open_manual("battle" if App.screen == "battle" else ("campaign" if App.screen == "campaign" else "base"))],
		["", "Button", func(): App.toggle_mute()],
		["", "Button", func(): App.toggle_fullscreen()],
		["Save and Quit to Title", "Button", func(): App.quit_to_title()],
		["New Company", "GhostButton", _new_company],
	]
	var names := ["Resume", "Manual", "Sound", "Fullscreen", "SaveQuit", "NewCompany"]
	for i in items.size():
		var it: Array = items[i]
		var b := UI.button(it[0], it[1], it[2])
		b.name = names[i]
		b.custom_minimum_size.x = 260
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		col.add_child(b)
		if names[i] == "Sound":
			_sound = b
			col.add_child(_volume_rows())
		elif names[i] == "Fullscreen":
			_full = b
	add_child(Modal.make(d, func(): App.open_menu(false)))
	refresh()


## One row per bus: name, then the slider (0..1); moving it applies at once.
func _volume_rows() -> Control:
	var rows := UI.vbox(2)
	rows.name = "Volumes"
	rows.custom_minimum_size.x = 260
	rows.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	for v in VOLUMES:
		var row := UI.hbox(10)
		var l := UI.label(v[1], "SmallLabel")
		l.custom_minimum_size.x = 70
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(l)
		var sl := HSlider.new()
		sl.name = "Vol_" + v[0]
		sl.min_value = 0.0
		sl.max_value = 1.0
		sl.step = 0.05
		sl.value = App.volume(v[0])
		sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		sl.custom_minimum_size.y = 18
		sl.tooltip_text = "%s volume" % v[1]
		var key: String = v[0]
		sl.value_changed.connect(func(x: float): App.set_volume(key, x))
		row.add_child(sl)
		rows.add_child(row)
		_sliders[key] = sl
	return rows


func refresh() -> void:
	if _sound == null:
		return
	_sound.text = "Sound: Off" if App.is_muted() else "Sound: On"
	_full.text = "Fullscreen: On" if App.is_fullscreen() else "Fullscreen: Off"


func _new_company() -> void:
	if App.has_save():
		Confirm.ask(self, "Start a new company? The current save will be replaced.", func():
			App.open_menu(false)
			App.new_game())
	else:
		App.open_menu(false)
		App.new_game()
