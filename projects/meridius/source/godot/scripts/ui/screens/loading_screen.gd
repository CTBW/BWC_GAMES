## The loading screen of src/ui/App.tsx: "Loading… N%" centred in Cinzel.
extends Control

const UI = preload("res://scripts/ui/ui.gd")

var _label: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_label = UI.label("", "LoadingLabel")
	center.add_child(_label)
	refresh()


func refresh() -> void:
	_label.text = "Loading… %d%%" % int(floor(App.load_progress * 100.0 + 0.5))
