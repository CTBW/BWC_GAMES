## Port of src/ui/screens/TopBar.tsx: the garrison's top bar — brand, expedition
## count, resources, Field Manual, The Fallen, sound toggle and Menu (to the title).
##
##   const TopBar = preload("res://scripts/ui/screens/top_bar.gd")
##   var bar: PanelContainer = TopBar.new()   # anchors itself to the top edge, height 54
##   bar.refresh()                            # after App.changed
extends PanelContainer

const UI = preload("res://scripts/ui/ui.gd")
const Icon = preload("res://scripts/ui/widgets/icon.gd")
const ResList = preload("res://scripts/ui/widgets/res_list.gd")

var _row: HBoxContainer
var _exp: Label
var _res: HBoxContainer
var _fallen: Button
var _sound: Button


func _init() -> void:
	theme_type_variation = "TopBar"
	UI.dark(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	offset_bottom = 54
	custom_minimum_size.y = 54
	_row = UI.hbox(18)
	add_child(_row)
	var brand := UI.label("MERIDIUS", "BrandLabel")
	brand.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_row.add_child(brand)
	_exp = UI.label("", "SmallMutedLabel", 0, Color("#cdb88a"))
	_exp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_row.add_child(_exp)
	_row.add_child(UI.spacer())
	_res = UI.hbox(18)
	_row.add_child(_res)
	_row.add_child(UI.spacer())
	var manual := UI.button("Field Manual", "SmallButton", func(): App.open_manual("base"))
	manual.name = "FieldManual"
	_row.add_child(manual)
	_fallen = UI.button("The Fallen (0)", "SmallButton", func(): App.open_panel("memorial"))
	_fallen.name = "Fallen"
	_row.add_child(_fallen)
	_sound = UI.button("", "IconButton", _toggle_sound)
	_sound.name = "Sound"
	_sound.icon = Icon.tex("sound")
	_sound.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_row.add_child(_sound)
	var menu := UI.button("Menu", "SmallButton", func(): App.go_title())
	menu.name = "Menu"
	_row.add_child(menu)
	for c in _row.get_children():
		if c is Button:
			c.size_flags_vertical = Control.SIZE_SHRINK_CENTER


func _ready() -> void:
	refresh()


func refresh() -> void:
	var g: Variant = App.game
	if g == null:
		return
	_exp.text = "Amberfeld Garrison · Expeditions: %d" % g.cycle
	UI.clear(_res)
	for k in g.resources:
		var item := UI.hbox(6)
		item.tooltip_text = ResList.RES_NAMES.get(k, k)
		item.mouse_filter = Control.MOUSE_FILTER_PASS
		item.add_child(Icon.make(k, 22))
		var n := UI.label(str(g.resources[k]), "ResLabel")
		n.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		item.add_child(n)
		var lbl := UI.label(ResList.RES_NAMES.get(k, k), "ResNameLabel")
		lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		item.add_child(lbl)
		_res.add_child(item)
	_fallen.text = "The Fallen (%d)" % g.fallen.size()
	var muted := App.is_muted()
	_sound.tooltip_text = "Sound off" if muted else "Sound on"
	_sound.icon = Icon.tex("mute" if muted else "sound")


func _toggle_sound() -> void:
	App.toggle_mute()
	refresh()
