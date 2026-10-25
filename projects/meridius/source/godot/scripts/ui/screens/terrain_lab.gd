## Desktop terrain inspection, independent of the current company/save.
extends Control

const UI = preload("res://scripts/ui/ui.gd")
const Lab = preload("res://scripts/render/terrain_lab.gd")
const Fields = preload("res://scripts/rules/terrain_test_fields.gd")

var view
var viewport: SubViewport
var field: TextureRect
var status: Label
var description: Label
var field_index := 0
var smooth_terrain := true
var night := false
var grid := false
var contours := false
var field_picker: OptionButton
var surface_picker: OptionButton
var grid_button: CheckButton
var night_button: CheckButton
var contour_button: CheckButton
var fog_button: CheckButton
var woodland_button: CheckButton
var painted_woodland := true
var _dragging := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var layout := UI.vbox(0)
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(layout)
	var header := UI.dark(UI.panel("DarkPanel", [12, 20]))
	var row := UI.hbox(12)
	row.add_child(UI.cinzel("TERRAIN TEST FIELDS", 23, 700, UI.LIGHT_TITLE))
	var picker := OptionButton.new()
	field_picker = picker
	picker.name = "FieldPicker"
	for n in Fields.NAMES:
		picker.add_item(n)
	picker.item_selected.connect(func(i):
		field_index = i
		_load_field())
	row.add_child(picker)
	var mode := OptionButton.new()
	surface_picker = mode
	mode.name = "SurfaceMode"
	mode.add_item("Textured slopes")
	mode.add_item("Classic tile heights")
	mode.item_selected.connect(func(i):
		smooth_terrain = i == 0
		_load_field())
	row.add_child(mode)
	row.add_child(UI.spacer())
	row.add_child(UI.button("Back to title", "DarkButton", func(): App.go_title()))
	header.add_child(row)
	layout.add_child(header)
	var toolbar := UI.dark(UI.panel("DarkPanel", [10, 20]))
	var controls := UI.hbox(10)
	controls.add_child(UI.button("Whole field", "DarkButton", func(): view.frame_field()))
	controls.add_child(UI.button("Inspect patrol", "DarkButton", func(): view.frame_field(true)))
	controls.add_child(UI.button("Reset patrols", "DarkButton", _load_field))
	grid_button = CheckButton.new()
	grid_button.text = "Grid"
	grid_button.toggled.connect(func(on):
		grid = on
		view.ui.showGrid = on)
	controls.add_child(grid_button)
	night_button = CheckButton.new()
	night_button.text = "Night"
	night_button.toggled.connect(func(on):
		night = on
		view.atmo.night = on)
	controls.add_child(night_button)
	contour_button = CheckButton.new()
	contour_button.text = "Heights"
	contour_button.toggled.connect(func(on):
		contours = on
		if view.terrain.has_method("show_height_contours"):
			view.terrain.show_height_contours(on))
	controls.add_child(contour_button)
	fog_button = CheckButton.new()
	fog_button.text = "Fog of war"
	fog_button.toggled.connect(func(on):
		view.b.setup["fogOfWar"] = on
		view.b.refresh_sight(true)
		view.fog.refresh(1.0, true))
	controls.add_child(fog_button)
	woodland_button = CheckButton.new()
	woodland_button.text = "Painted woodland"
	woodland_button.toggled.connect(func(on):
		painted_woodland = on
		view.set_painted_woodland(on))
	controls.add_child(woodland_button)
	controls.add_child(UI.spacer())
	status = UI.label("", "SmallLabel", 16, UI.LIGHT)
	controls.add_child(status)
	toolbar.add_child(controls)
	layout.add_child(toolbar)
	viewport = SubViewport.new()
	viewport.name = "TerrainViewport"
	viewport.size = Vector2i(1920, 880)
	viewport.disable_3d = true
	viewport.gui_disable_input = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	add_child(viewport)
	field = TextureRect.new()
	field.name = "TerrainField"
	field.texture = viewport.get_texture()
	field.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	field.stretch_mode = TextureRect.STRETCH_SCALE
	field.size_flags_vertical = Control.SIZE_EXPAND_FILL
	field.mouse_filter = Control.MOUSE_FILTER_STOP
	field.gui_input.connect(_field_input)
	field.resized.connect(func(): viewport.size = Vector2i(field.size.max(Vector2.ONE)))
	layout.add_child(field)
	var footer := UI.dark(UI.panel("DarkPanel", [10, 20]))
	var info := UI.vbox(6)
	description = UI.label("", "SmallLabel", 17, UI.LIGHT)
	info.add_child(description)
	info.add_child(UI.label("Click a patrol, then highlighted ground to walk. Moves refill on arrival. Wheel: zoom · Right drag: pan · Esc: title", "SmallLabel", 16, UI.DARK_MUTED))
	footer.add_child(info)
	layout.add_child(footer)
	_load_field.call_deferred()


func _load_field() -> void:
	if view != null:
		viewport.remove_child(view)
		view.queue_free()
	view = Lab.new()
	view.painted_woodland = painted_woodland
	viewport.add_child(view)
	view.prepare(field_index, smooth_terrain)
	fog_button.set_pressed_no_signal(view.b.fog_enabled())
	woodland_button.disabled = field_index not in [1, 3]
	woodland_button.set_pressed_no_signal(painted_woodland and not woodland_button.disabled)
	view.atmo.night = night
	view.ui.showGrid = grid
	field_picker.select(field_index)
	surface_picker.select(0 if smooth_terrain else 1)
	grid_button.set_pressed_no_signal(grid)
	night_button.set_pressed_no_signal(night)
	contour_button.disabled = not smooth_terrain
	contour_button.set_pressed_no_signal(contours and smooth_terrain)
	if contours and smooth_terrain:
		view.terrain.show_height_contours(true)
	description.text = Fields.NOTES[field_index]


func _process(dt: float) -> void:
	if view == null:
		return
	var t = view.ui.hover.get("tile")
	status.text = "%.2f× zoom" % view.cam.zoom
	if t != null:
		var tile: Dictionary = view.Grid.tile_at(view.b.map, t.x, t.y)
		status.text += "  |  %s  |  height %.2f / rule %d" % [tile.terrain.capitalize(), view._tile_h(t.x, t.y), tile.h]


func _field_input(event: InputEvent) -> void:
	if view == null:
		return
	if event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			_dragging = event.pressed
		elif event.pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				view.wheel(-1)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				view.wheel(1)
			elif event.button_index == MOUSE_BUTTON_LEFT:
				view.walk_at(event.position)
	elif event is InputEventMouseMotion:
		if _dragging:
			view.cam.drag(event.relative.x, event.relative.y)
		view.pointer_move(event.position)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and not event.pressed:
		_dragging = false
