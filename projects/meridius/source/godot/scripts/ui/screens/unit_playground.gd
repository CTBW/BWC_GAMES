## Interactive model and animation inspection, entered from the title screen.
## Owns its viewport and practice state; never loads or saves a company.
extends Control

const UI = preload("res://scripts/ui/ui.gd")
const DB = preload("res://scripts/data/db.gd")
const Lab = preload("res://scripts/render/unit_playground.gd")
const SoldierAnim = preload("res://scripts/render/soldier_anim.gd")

var view
var viewport: SubViewport
var field: TextureRect
var unit_picker: OptionButton
var comparison_picker: OptionButton
var pause_button: Button
var status: Label
var description: Label
var model_info: Label
var speed_label: Label
var _clips := {}
var _facings: Array[Button] = []
var _dragging := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var background := ColorRect.new()
	background.color = Color("#10191b")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var layout := UI.vbox(0)
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(layout)
	var header := UI.dark(UI.panel("DarkPanel", [16, 24]))
	var heading := UI.hbox(18)
	heading.add_child(UI.cinzel("UNIT PLAYGROUND", 25, 700, UI.LIGHT_TITLE))
	heading.add_child(UI.label("Practice field", "SmallLabel", 18, UI.DARK_MUTED))
	heading.add_child(UI.spacer())
	var back := UI.button("Back to title  ·  Esc", "DarkButton", func(): App.go_title())
	back.name = "BackToTitle"
	heading.add_child(back)
	header.add_child(heading)
	layout.add_child(header)
	var body := UI.hbox(0)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(body)
	_build_sidebar(body)
	var stage := UI.vbox(0)
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(stage)
	var toolbar := UI.dark(UI.panel("DarkPanel", [10, 16]))
	var row := UI.hbox(10)
	for spec in [["Battle zoom", 1.0], ["Close up", 3.0], ["Frame unit", -1.0]]:
		var zoom_value: float = spec[1]
		var button := UI.button(spec[0], "DarkButton", func(): view.frame_subject(zoom_value))
		button.name = String(spec[0]).replace(" ", "")
		row.add_child(button)
	row.add_child(UI.spacer())
	status = UI.label("", "SmallLabel", 16, UI.LIGHT)
	row.add_child(status)
	toolbar.add_child(row)
	stage.add_child(toolbar)
	viewport = SubViewport.new()
	viewport.name = "PracticeViewport"
	viewport.size = Vector2i(1280, 900)
	viewport.disable_3d = true
	viewport.gui_disable_input = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	add_child(viewport)
	field = TextureRect.new()
	field.name = "PracticeField"
	field.texture = viewport.get_texture()
	field.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	field.stretch_mode = TextureRect.STRETCH_SCALE
	field.size_flags_vertical = Control.SIZE_EXPAND_FILL
	field.mouse_filter = Control.MOUSE_FILTER_STOP
	field.gui_input.connect(_field_input)
	field.resized.connect(func(): viewport.size = Vector2i(field.size.max(Vector2(1, 1))))
	stage.add_child(field)
	var footer := UI.dark(UI.panel("DarkPanel", [12, 18]))
	footer.add_child(UI.label("Click field to walk · Click dummy to attack · Wheel to zoom · Right drag to pan · Space to pause · Q / E to turn", "SmallLabel", 17, UI.LIGHT))
	stage.add_child(footer)
	view = Lab.new()
	viewport.add_child(view)
	_refresh_info()


func _build_sidebar(body: HBoxContainer) -> void:
	var panel := UI.dark(UI.panel("DarkPanel", [18]))
	panel.custom_minimum_size.x = 370
	panel.size_flags_horizontal = Control.SIZE_FILL
	body.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var col := UI.vbox(12)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(col)
	col.add_child(UI.cinzel("INSPECT A UNIT", 18, 700, UI.LIGHT_TITLE))
	unit_picker = _picker("UnitPicker")
	for type_id in DB.UNIT_TYPES:
		unit_picker.add_item(DB.UNIT_TYPES[type_id].name)
		unit_picker.set_item_metadata(unit_picker.item_count - 1, type_id)
	unit_picker.item_selected.connect(func(i):
		view.choose_unit(unit_picker.get_item_metadata(i))
		_refresh_info())
	col.add_child(unit_picker)
	description = UI.label("", "SmallLabel", 17, UI.LIGHT)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(description)
	model_info = UI.label("", "SmallLabel", 15, UI.DARK_MUTED)
	model_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(model_info)
	var appearance := UI.hbox(8)
	var grouping := _picker("Grouping")
	grouping.add_item("Full squad")
	grouping.add_item("Single figure")
	grouping.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grouping.item_selected.connect(func(i):
		view.solo = i == 1
		view.reset_subject()
		_refresh_info())
	appearance.add_child(grouping)
	var look := _picker("Appearance")
	for i in 6:
		look.add_item("Look %d" % (i + 1))
	look.item_selected.connect(func(i):
		view.variant = i
		view.reset_subject())
	appearance.add_child(look)
	col.add_child(appearance)
	col.add_child(UI.label("FACING", "SmallLabel", 15, UI.DARK_MUTED))
	var facings := UI.grid(2, 8, 8)
	for i in 4:
		var direction := i
		var button := _button(["SE  ·  front", "SW  ·  front", "NW  ·  back", "NE  ·  back"][i], "Facing%d" % i, func():
			view.set_facing(direction)
			_refresh_info())
		button.toggle_mode = true
		_facings.append(button)
		facings.add_child(button)
	col.add_child(facings)
	col.add_child(UI.label("ANIMATION", "SmallLabel", 15, UI.DARK_MUTED))
	var clips := UI.grid(2, 8, 8)
	for clip_name in Lab.CLIPS:
		var chosen: String = clip_name
		var button := _button("Attack dummy" if chosen == "Attack" else chosen, "Clip" + chosen, func():
			view.choose_clip(chosen)
			_refresh_info())
		button.toggle_mode = true
		_clips[chosen] = button
		clips.add_child(button)
	var loop := CheckButton.new()
	loop.name = "Loop"
	loop.text = "Loop"
	loop.button_pressed = true
	loop.toggled.connect(func(value): view.looping = value)
	clips.add_child(loop)
	col.add_child(clips)
	var transport := UI.hbox(6)
	pause_button = _button("Pause", "PausePlayback", _toggle_pause)
	transport.add_child(pause_button)
	transport.add_child(_button("+1 frame", "StepFrame", func():
		view.playing = false
		view.tick(0.0, true)
		_refresh_info()))
	transport.add_child(_button("Replay", "Replay", func():
		view.reset_subject()
		_refresh_info()))
	col.add_child(transport)
	speed_label = UI.label("Playback  1.00×", "SmallLabel", 16, UI.LIGHT)
	col.add_child(speed_label)
	var speed := HSlider.new()
	speed.name = "PlaybackSpeed"
	speed.min_value = 0.25
	speed.max_value = 2.0
	speed.step = 0.25
	speed.value = 1.0
	speed.value_changed.connect(func(value):
		view.playback_rate = value
		speed_label.text = "Playback  %.2f×" % value)
	col.add_child(speed)
	col.add_child(UI.label("COMPARE WITH", "SmallLabel", 15, UI.DARK_MUTED))
	comparison_picker = _picker("Comparison")
	comparison_picker.add_item("No comparison")
	comparison_picker.set_item_metadata(0, "")
	for type_id in DB.UNIT_TYPES:
		comparison_picker.add_item(DB.UNIT_TYPES[type_id].name)
		comparison_picker.set_item_metadata(comparison_picker.item_count - 1, type_id)
	comparison_picker.item_selected.connect(func(i):
		view.comparison = comparison_picker.get_item_metadata(i)
		view.reset_subject()
		view.frame_subject())
	col.add_child(comparison_picker)
	var options := UI.hbox(8)
	var grid := CheckButton.new()
	grid.name = "Grid"
	grid.text = "Grid"
	grid.toggled.connect(func(value): view.ui.showGrid = value)
	options.add_child(grid)
	var night := CheckButton.new()
	night.name = "Night"
	night.text = "Night"
	night.toggled.connect(func(value):
		view.atmo.night = value
		view.night_level = 1.0 if value else 0.0)
	options.add_child(night)
	col.add_child(options)
	var note := UI.label("The straw dummy takes unlimited hits. Attack dummy walks into range, then strikes.\nPractice does not change your company or save. War machines keep their crews.", "SmallLabel", 15, UI.DARK_MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(note)


func _picker(id: String) -> OptionButton:
	var option := OptionButton.new()
	option.name = id
	option.custom_minimum_size.y = 40
	option.fit_to_longest_item = false
	return option


func _button(text: String, id: String, action: Callable) -> Button:
	var button := UI.button(text, "DarkButton", action)
	button.name = id
	button.custom_minimum_size.y = 38
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_NONE
	return button


func _refresh_info() -> void:
	description.text = DB.UNIT_TYPES[view.unit_type].role
	model_info.text = "%s · %s" % ["Animated sprite model" if SoldierAnim.animated(view.unit_type) else "Static sprite with procedural motion", "Crew + engine" if DB.is_engine(view.unit_type) else ("1 figure" if view.solo else "%d figures" % DB.squad_size(view.unit_type))]
	pause_button.text = "Pause" if view.playing else "Play"
	for clip_name in _clips:
		_clips[clip_name].set_pressed_no_signal(view.clip == clip_name)
	for i in _facings.size():
		_facings[i].set_pressed_no_signal(view.facing == i)


func _process(dt: float) -> void:
	if view == null:
		return
	view.tick(dt)
	status.text = "%s  ·  %.2fs  ·  %.1f× zoom" % [view.clip, view.elapsed, view.cam.zoom]


func _toggle_pause() -> void:
	view.playing = not view.playing
	_refresh_info()


func _field_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			_dragging = event.pressed
		elif event.pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				view.cam.wheel(-1, 0.4, 5.0)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				view.cam.wheel(1, 0.4, 5.0)
			elif event.button_index == MOUSE_BUTTON_LEFT:
				view.walk_at(event.position)
				_refresh_info()
	elif event is InputEventMouseMotion and _dragging:
		view.cam.drag(event.relative.x, event.relative.y)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and not event.pressed:
		_dragging = false


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	if event.is_action("end_unit"):
		_toggle_pause()
	elif event.is_action("facing_prev"):
		view.set_facing(view.facing - 1)
		_refresh_info()
	elif event.is_action("facing_next"):
		view.set_facing(view.facing + 1)
		_refresh_info()
	else:
		return
	get_viewport().set_input_as_handled()
