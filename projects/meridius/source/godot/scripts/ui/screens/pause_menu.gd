## The pause menu (a Godot addition; the original has only the top bar's Menu
## button, which goes to the title). Opened with Esc when nothing else uses it;
## the world is paused while it is open.
## Resume · Field Manual · Sound on/off · Fullscreen on/off · Save and Quit to
## Title · New Company (asks first).
extends Control

const UI = preload("res://scripts/ui/ui.gd")
const Modal = preload("res://scripts/ui/widgets/modal.gd")
const Confirm = preload("res://scripts/ui/widgets/confirm.gd")

var _sound: Button
var _full: Button


func _init() -> void:
	name = "PauseMenu"
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var d := Modal.dialog(380, [22, 30])
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
		elif names[i] == "Fullscreen":
			_full = b
	add_child(Modal.make(d, func(): App.open_menu(false)))
	refresh()


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
