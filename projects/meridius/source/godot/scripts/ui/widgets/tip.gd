## Port of common.tsx `Tip`: a dark tooltip panel that follows the mouse while
## it is over a control (shown at once, offset 14/16 px, kept on screen).
##
##   const Tip = preload("res://scripts/ui/widgets/tip.gd")
##   Tip.attach(target: Control, content: Variant, wide := false) -> void
##       content: bbcode String (RichTextLabel "TooltipText": [b]…[/b], [color=#ffb0a0]…)
##                or a Callable returning a Control (built when shown).
##       wide: max width 330 px instead of 290.
##       Works on disabled buttons. The target's mouse_filter must not be IGNORE
##       (attach sets PASS when it is).
##   Tip.set_content(target, content)   replace the text of an attached tip
## The panel lives on a top CanvasLayer (layer 100) with the UI theme.
extends Node

const ThemeBuilder = preload("res://scripts/ui/theme_builder.gd")
const UI = preload("res://scripts/ui/ui.gd")

var content: Variant = ""
var wide := false
var _panel: Control = null
## Last pointer position over the target (viewport coordinates, from its events).
var _pos := Vector2(-1, -1)


static func attach(target: Control, content_: Variant, wide_ := false) -> void:
	var t: Node = load("res://scripts/ui/widgets/tip.gd").new()
	t.name = "Tip"
	t.content = content_
	t.wide = wide_
	if target.mouse_filter == Control.MOUSE_FILTER_IGNORE:
		target.mouse_filter = Control.MOUSE_FILTER_PASS
	target.add_child(t)
	target.mouse_entered.connect(t._show)
	target.mouse_exited.connect(t._hide)
	target.gui_input.connect(t._input_on_target)
	target.tree_exiting.connect(t._hide)
	target.visibility_changed.connect(func(): if not target.is_visible_in_tree(): t._hide())


static func set_content(target: Control, content_: Variant) -> void:
	var t := target.get_node_or_null("Tip")
	if t != null:
		t.content = content_


static func _layer(tree: SceneTree) -> Control:
	var root := tree.root
	var layer: CanvasLayer = root.get_node_or_null("TipLayer")
	if layer == null:
		layer = CanvasLayer.new()
		layer.name = "TipLayer"
		layer.layer = 100
		root.add_child(layer)
		var c := Control.new()
		c.name = "Root"
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		c.theme = ThemeBuilder.theme()
		layer.add_child(c)
	return layer.get_node("Root")


func _show() -> void:
	_hide()
	if not is_inside_tree():
		return
	var max_w := 330.0 if wide else 290.0
	var p := UI.panel("TooltipPanel")
	UI.dark(p)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var body: Control
	if content is Callable:
		body = (content as Callable).call()
	else:
		var text := str(content)
		var r := UI.rich(text, "TooltipText")
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# Shrink to the text like a CSS max-width box.
		var plain := RegEx.create_from_string("\\[[^\\]]*\\]").sub(text, "", true)
		var f: Font = UI.font("alegreya", 400)
		var w := f.get_string_size(plain, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 4.0
		r.custom_minimum_size.x = minf(w, max_w - 20.0)
		body = r
	_ignore_all(body)
	p.add_child(body)
	_panel = p
	_layer(get_tree()).add_child(p)
	p.reset_size()
	_place()


func _ignore_all(c: Node) -> void:
	if c is Control:
		(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for ch in c.get_children():
		_ignore_all(ch)


func _place() -> void:
	if _panel == null or not is_instance_valid(_panel):
		return
	var vp := _panel.get_viewport_rect().size
	var m := _pos if _pos.x >= 0.0 else _panel.get_viewport().get_mouse_position()
	_panel.reset_size()
	var x := minf(vp.x - (340.0 if wide else 300.0), m.x + 14.0)
	var y := minf(vp.y - 120.0, m.y + 16.0)
	_panel.position = Vector2(x, y)


func _input_on_target(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		_pos = (e as InputEventMouseMotion).global_position
		if _panel == null:
			_show()
		else:
			_place()


func _hide() -> void:
	if _panel != null and is_instance_valid(_panel):
		_panel.queue_free()
	_panel = null


func _exit_tree() -> void:
	_hide()
