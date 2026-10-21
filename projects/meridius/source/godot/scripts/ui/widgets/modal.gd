## The `.modal-back` overlay: a full-screen radial dimming that centres a dialog
## and fades in (0.25 s) while the dialog rises (0.35 s). A click on the dimmed
## background calls `on_back` (the original closes the panel); clicks inside the
## dialog stay there.
##
##   const Modal = preload("res://scripts/ui/widgets/modal.gd")
##   Modal.make(dialog: Control, on_back := Callable(), animate := true) -> Control
##   Modal.dialog(width := 720, padding := []) -> PanelContainer
##       a `.panel.dialog`: ParchmentPanel, given width, padding 22/26, max height 86 %.
extends Control

const UI = preload("res://scripts/ui/ui.gd")

var on_back := Callable()
var dialog_node: Control


static func make(dialog_: Control, on_back_ := Callable(), animate := true) -> Control:
	var m: Control = load("res://scripts/ui/widgets/modal.gd").new()
	m.name = "Modal"
	m.on_back = on_back_
	m.dialog_node = dialog_
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.mouse_filter = Control.MOUSE_FILTER_STOP
	var back := Panel.new()
	back.theme_type_variation = "ModalBack"
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.add_child(back)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.add_child(center)
	dialog_.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(dialog_)
	if animate:
		m.modulate.a = 0.0
		m.ready.connect(m._animate)
	return m


static func dialog(width := 720, padding: Array = []) -> PanelContainer:
	var p := UI.panel("ParchmentPanel", padding)
	p.custom_minimum_size.x = width
	return p


func _animate() -> void:
	if not is_inside_tree():
		modulate.a = 1.0
		return
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 1.0, 0.25)
	if dialog_node != null:
		dialog_node.pivot_offset = dialog_node.size * 0.5
		dialog_node.scale = Vector2(0.98, 0.98)
		var t2 := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t2.tween_property(dialog_node, "scale", Vector2.ONE, 0.35)


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		if on_back.is_valid():
			on_back.call()
