## Port of src/ui/screens/Title.tsx: the logo over the dimmed camp, the story
## blurb, Continue (when a save exists) and New Company (asks before replacing
## the save).
extends Control

const UI = preload("res://scripts/ui/ui.gd")
const Confirm = preload("res://scripts/ui/widgets/confirm.gd")

var _buttons: HBoxContainer
var continue_button: Button
var new_button: Button


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# .title-screen background: radial-gradient(ellipse at center, rgba(10,8,4,.05) 0%, rgba(10,8,4,.6) 75%)
	var bg := TextureRect.new()
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.75, 1.0])
	g.colors = PackedColorArray([Color(10 / 255.0, 8 / 255.0, 4 / 255.0, 0.05), Color(10 / 255.0, 8 / 255.0, 4 / 255.0, 0.6), Color(10 / 255.0, 8 / 255.0, 4 / 255.0, 0.6)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 1.0)
	gt.width = 256
	gt.height = 256
	bg.texture = gt
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var col := UI.vbox(0)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(col)

	# Stacked: a soft dark halo behind the letters (text-shadow 0 0 40px / 0 0 4px), then the logo.
	var logo_box := MarginContainer.new()
	logo_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# CSS line-height: 1 — the 104 px line box is shorter than Cinzel's natural line.
	logo_box.add_theme_constant_override("margin_top", -20)
	logo_box.add_theme_constant_override("margin_bottom", -21)
	var halo := UI.label("MERIDIUS", "LogoLabel")
	halo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	halo.add_theme_color_override("font_color", Color(0, 0, 0, 0))
	halo.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	halo.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.28))
	halo.add_theme_constant_override("outline_size", 22)
	var logo := UI.label("MERIDIUS", "LogoLabel")
	logo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	logo_box.add_child(halo)
	logo_box.add_child(logo)
	col.add_child(logo_box)

	var sub := UI.label("THE FRONTIER COMPANY", "LogoSubLabel")
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(UI.gap(0, 10))
	col.add_child(sub)
	col.add_child(UI.gap(0, 34))

	var p := UI.panel("ParchmentPanel", [18, 26])
	p.custom_minimum_size.x = 520
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var inner := UI.vbox(0)
	inner.add_child(UI.rich("[center]A host of goblins and orcs is pouring out of the Hillsvain Woods into the borderlands of Nordmark. There is no end to them. There is only the Amberfeld Company in the way.[/center]", "DialogText"))
	inner.add_child(UI.gap(0, 6))
	var muted := UI.rich("[center]Lead the Amberfeld Company: recruit, march, fight and return. Every soldier who falls stays fallen.[/center]", "MutedText")
	muted.add_theme_font_size_override("normal_font_size", 15)
	muted.add_theme_font_size_override("bold_font_size", 15)
	inner.add_child(muted)
	inner.add_child(UI.gap(0, 14))
	_buttons = UI.hbox(14)
	_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	inner.add_child(_buttons)
	p.add_child(inner)
	col.add_child(p)

	var foot := UI.label("Phase one build · Tier I campaign: The Hillsvain Host", "TinyMutedLabel", 0, Color("#cdb88a"))
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	foot.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	foot.grow_horizontal = Control.GROW_DIRECTION_BOTH
	foot.grow_vertical = Control.GROW_DIRECTION_BEGIN
	foot.offset_bottom = -12
	foot.offset_top = -12 - 16
	add_child(foot)
	refresh()


func refresh() -> void:
	UI.clear(_buttons)
	var save := App.has_save()
	continue_button = null
	if save:
		continue_button = UI.button("Continue", "BlueBigButton", func(): App.continue_game())
		continue_button.name = "Continue"
		_buttons.add_child(continue_button)
	new_button = UI.button("New Company", "BigButton" if save else "RedBigButton", _on_new)
	new_button.name = "NewCompany"
	_buttons.add_child(new_button)


func _on_new() -> void:
	if App.has_save():
		Confirm.ask(self, "Start a new company? The current save will be replaced.", func(): App.new_game())
		return
	App.new_game()
