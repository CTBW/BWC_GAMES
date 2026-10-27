## The frontier at sunrise: the logo over a painted forest overlook, the story
## blurb, Continue (when a save exists) and New Company (asks before replacing
## the save).
extends Control

const UI = preload("res://scripts/ui/ui.gd")
const Confirm = preload("res://scripts/ui/widgets/confirm.gd")
const Regalia = preload("res://scripts/ui/widgets/title_regalia.gd")
const Flourish = preload("res://scripts/ui/widgets/flourish.gd")

var _buttons: VBoxContainer
var continue_button: Button
var new_button: Button


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var landscape := TextureRect.new()
	landscape.name = "FrontierBackdrop"
	landscape.texture = load("res://assets/ui/frontier_title.png")
	landscape.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	landscape.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	landscape.mouse_filter = Control.MOUSE_FILTER_IGNORE
	landscape.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(landscape)
	# Keep the dawn landscape bright. Contrast belongs behind the controls.
	add_child(Regalia.new())

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
	col.add_child(UI.gap(0, 20))
	col.add_child(Flourish.make(10))
	col.add_child(UI.gap(0, 12))

	var p := UI.panel("DarkPanel", [28, 40])
	p.custom_minimum_size.x = 620
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var binding = UI.theme_stylebox(p).duplicate()
	binding.artwork = 1
	binding.metal_width = 10
	binding.ornament = 2
	binding.gradient = null
	binding.bg_color = Color(0.035, 0.055, 0.075, 0.93)
	p.add_theme_stylebox_override("panel", binding)
	var inner := UI.vbox(0)
	inner.add_child(UI.rich("[center]A host of goblins and orcs is pouring out of the Hillsvain Woods into the borderlands of Nordmark. There is no end to them. There is only the Amberfeld Company in the way.[/center]", "DialogText"))
	inner.add_child(UI.gap(0, 14))
	var muted := UI.rich("[center]Lead the Amberfeld Company: recruit, march, fight and return. Every soldier who falls stays fallen.[/center]", "MutedText")
	muted.add_theme_font_size_override("normal_font_size", 15)
	muted.add_theme_font_size_override("bold_font_size", 15)
	inner.add_child(muted)
	inner.add_child(UI.gap(0, 24))
	_buttons = UI.vbox(12)
	_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	_buttons.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	inner.add_child(_buttons)
	p.add_child(inner)
	col.add_child(p)

	var foot := UI.label("Phase one build · Tier I campaign: The Hillsvain Host", "TinyMutedLabel", 0, Color("#f0dfb6"))
	foot.add_theme_color_override("font_shadow_color", Color("#101c21"))
	foot.add_theme_constant_override("shadow_offset_y", 2)
	foot.add_theme_color_override("font_outline_color", Color("#101c21"))
	foot.add_theme_constant_override("outline_size", 3)
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	foot.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	foot.grow_horizontal = Control.GROW_DIRECTION_BOTH
	foot.grow_vertical = Control.GROW_DIRECTION_BEGIN
	foot.offset_bottom = -48
	foot.offset_top = -48 - 16
	add_child(foot)
	refresh()


func refresh() -> void:
	UI.clear(_buttons)
	var save := App.has_save()
	continue_button = null
	if save:
		continue_button = UI.button("Continue", "BlueBigButton", func(): App.continue_game())
		continue_button.name = "Continue"
		continue_button.custom_minimum_size = Vector2(350, 56)
		_buttons.add_child(continue_button)
	new_button = UI.button("New Company", "BigButton" if save else "RedBigButton", _on_new)
	new_button.name = "NewCompany"
	new_button.custom_minimum_size = Vector2(350, 56)
	_buttons.add_child(new_button)
	var playground := UI.button("Unit Playground", "BigButton", func(): App.open_playground())
	playground.name = "UnitPlayground"
	playground.custom_minimum_size = Vector2(350, 48)
	_buttons.add_child(playground)
	var terrain_lab := UI.button("Terrain Test Fields", "BigButton", func(): App.open_terrain_lab())
	terrain_lab.name = "TerrainTestFields"
	terrain_lab.custom_minimum_size = Vector2(350, 48)
	_buttons.add_child(terrain_lab)


func _on_new() -> void:
	if App.has_save():
		Confirm.ask(self, "Start a new company? The current save will be replaced.", func(): App.new_game())
		return
	App.new_game()
