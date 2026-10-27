## Real battle movement and drawing on isolated terrain fixtures. No save IO.
extends "res://scripts/render/battle_view.gd"

const Fields = preload("res://scripts/rules/terrain_test_fields.gd")
const LabDraw = preload("res://scripts/render/terrain_lab_draw.gd")

class PatrolBattle extends "res://scripts/rules/battle.gd":
	func check_end() -> void:
		pass # An empty enemy side is intentional in the terrain lab.

var field_index := 0
var smooth_terrain := true
var painted_woodland := true
var mist: ColorRect


func prepare(which := 0, smooth := true) -> void:
	field_index = which
	smooth_terrain = smooth
	threaded_rules = false
	var battle = PatrolBattle.new(Fields.make(which, smooth))
	battle.phase = "player"
	setup(battle)
	if not smooth:
		# Classic ground must remain available when the art toggle redraws its
		# cached exterior; production battles can still release this viewport.
		terrain.set_meta("keep_field", true)
	set_process_input(false)
	set_process_unhandled_input(false)
	for name in ["Minimap", "MinimapBase", "Overlays"]:
		_layers[name].hide()
	ui.showGrid = false
	ui.selected = "terrain-0"
	# The test night matches the readable, misty moonlight of the art references.
	# Production battles retain their own torch/darkness mask.
	_night.hide()
	atmo.own_night_mask = true
	atmo.warmth = 1.25
	_layers.Grade.hide()
	mist = ColorRect.new()
	mist.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mist.z_index = 2
	var mist_material := ShaderMaterial.new()
	mist_material.shader = load("res://assets/shaders/terrain_woodland_mist.gdshader")
	mist.material = mist_material
	add_child(mist)
	var motes := _add_layer(self, "LabMotes", func(ci): atmo.draw_motes(ci, time))
	motes.z_index = 3
	fog.z_index = 4 # Unexplored shroud stays black above the woodland's golden mist.
	frame_field()


func _build_layers() -> void:
	if _world == null:
		_draw = LabDraw.new(self)
	super._build_layers()


func _audio() -> Node:
	return null


func set_painted_woodland(enabled: bool) -> void:
	painted_woodland = enabled
	map_changed()
	# The exterior is cached into the ground. Redraw the ground and existing
	# bake together, clearing the old silhouette instead of layering over it.
	for child in terrain._iso_vp.get_children():
		if child is CanvasItem:
			child.show()
			child.queue_redraw()
	if terrain_surface != null and terrain._paint.material.get_shader_parameter("height_view"):
		terrain._decal_node.hide()
	terrain._iso_vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	terrain._iso_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	if not RenderingServer.frame_post_draw.is_connected(terrain._on_drawn):
		RenderingServer.frame_post_draw.connect(terrain._on_drawn, CONNECT_ONE_SHOT)


func _redraw() -> void:
	super._redraw()
	if mist == null:
		return
	_night.hide()
	mist.size = Vector2(_w, _h)
	var mat: ShaderMaterial = mist.material
	mat.set_shader_parameter("camera", Vector2(cam.x, cam.y))
	mat.set_shader_parameter("view_size", mist.size)
	mat.set_shader_parameter("zoom", cam.zoom)
	mat.set_shader_parameter("clock", time)
	mat.set_shader_parameter("night", atmo.night)
	mat.set_shader_parameter("strength", 1.2 if field_index == 1 else 0.7)
	mat.set_shader_parameter("patrol_a", _view_pos(views["terrain-0"]))
	mat.set_shader_parameter("patrol_b", _view_pos(views["terrain-1"]))


func _focus_on(x: float, y: float, force: bool) -> void:
	pass


func frame_field(close := false) -> void:
	var p := Iso.iso(11.5, 11.5, _tile_h(11.5, 11.5))
	if close:
		var u: Dictionary = b.unit(ui.selected if ui.selected != null else "terrain-0")
		p = Iso.iso(u.x, u.y, _tile_h(u.x, u.y))
	cam.x = p.x
	cam.tx = p.x
	cam.y = p.y - 35
	cam.ty = cam.y
	cam.zoom = 1.45 if close else minf(_view_size().x / 3100.0, _view_size().y / 1550.0)
	cam.tzoom = cam.zoom
	_apply_camera()


func walk_at(p: Vector2) -> void:
	if busy():
		return
	var rp := resolve_pointer(p.x, p.y)
	if rp.unit != null:
		select(rp.unit.uid)
		return
	var u = selected_unit()
	if u != null and rp.tile != null:
		move_patrol(u.uid, rp.tile.x, rp.tile.y)


func move_patrol(uid: String, x: int, y: int) -> bool:
	if busy():
		return false
	if not b.move(uid, x, y):
		return false
	pump()
	_reach_cache = null
	_states_cache = null
	return true


func update(dt: float) -> void:
	super.update(dt)
	if not busy():
		for u in b.units:
			if u.hasMoved:
				u.hasMoved = false
				u.hasActed = false
				u.movedTiles = 0
				_reach_cache = null
				_states_cache = null
				_refresh_hover()
