## Footman animation prototype: sandbox scene.
##   tools/godot.sh --path . res://prototypes/footman_anim/scenes/footman_sandbox.tscn
## Scenarios: a single footman (facing switcher, every state), the squad in
## formation, the squad attacking a straw dummy from any facing, the squad
## marching into a tile and stopping. Toggles: smooth / on twos (12 fps),
## 0.25x / 1x, overlays (collision radii, foot contacts, bones), smear, FX,
## sound. Nothing here touches the game's state, saves or production units.
extends Node2D

const Footman = preload("res://prototypes/footman_anim/scripts/footman.gd")
const Squad = preload("res://prototypes/footman_anim/scripts/squad.gd")
const Dummy = preload("res://prototypes/footman_anim/scripts/dummy.gd")
const FX = preload("res://prototypes/footman_anim/scripts/fx.gd")
const Formation = preload("res://prototypes/footman_anim/scripts/formation.gd")

const FACING_NAMES := ["SE", "SW", "NW", "NE"]
const SEED := 20261023

var scenario := "single"
var facing := 0
var on_twos := false
var speed := 1.0
var show_radii := false
var show_contacts := false
var show_bones := false
var smear := true
var effects := true
var sound := false
var available: Array = []

var world: Node2D
var ground: Node2D
var units: Node2D
var fx_ground: Node2D
var fx_top: Node2D
var overlay: Node2D
var cam: Camera2D
var ui: CanvasLayer
var info: Label
var stats: Label
var single: Node2D
var squad: Node2D
var dummy: Node2D
var overlap_frames := 0
var overlap_log: Array = []
var _buttons := {}
var _state_box: Control
var _squad_box: Control
var _dragging := false
var _zoom := 2.4
var _march_timer := 0.0


func _ready() -> void:
	for k in Footman.FACING_KEYS:
		if FileAccess.file_exists("res://prototypes/footman_anim/motion/%s.tres" % k):
			available.append(k)
	_build_world()
	_build_ui()
	set_scenario(scenario)


func _build_world() -> void:
	world = Node2D.new()
	world.name = "World"
	add_child(world)
	ground = Node2D.new()
	ground.name = "Ground"
	ground.set_script(load("res://prototypes/footman_anim/scripts/ground.gd"))
	world.add_child(ground)
	fx_ground = FX.new()
	fx_ground.name = "FxGround"
	world.add_child(fx_ground)
	units = Node2D.new()
	units.name = "Units"
	units.y_sort_enabled = true
	world.add_child(units)
	fx_top = FX.new()
	fx_top.name = "FxTop"
	world.add_child(fx_top)
	overlay = Node2D.new()
	overlay.name = "Overlay"
	overlay.set_script(load("res://prototypes/footman_anim/scripts/overlay.gd"))
	world.add_child(overlay)
	overlay.sandbox = self
	cam = Camera2D.new()
	cam.name = "Camera"
	world.add_child(cam)
	cam.make_current()


func _build_ui() -> void:
	ui = CanvasLayer.new()
	ui.name = "UI"
	add_child(ui)
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.position = Vector2(12, 12)
	panel.custom_minimum_size = Vector2(330, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.1, 0.12, 0.88)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", sb)
	ui.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	panel.add_child(col)
	col.add_child(_title("FOOTMAN ANIMATION PROTOTYPE"))
	col.add_child(_small("Sandbox only: production units are untouched."))
	col.add_child(_title("SCENARIO"))
	col.add_child(_row([["Single", func(): set_scenario("single")], ["Formation", func(): set_scenario("formation")]], "scn"))
	col.add_child(_row([["Attack dummy", func(): set_scenario("attack")], ["March in", func(): set_scenario("march")]], "scn"))
	col.add_child(_title("FACING  (Q / E)"))
	var frow := []
	for i in 4:
		var fi := i
		frow.append([FACING_NAMES[i], func(): set_facing(fi)])
	col.add_child(_row(frow, "face"))
	_state_box = VBoxContainer.new()
	_state_box.add_child(_title("STATE"))
	_state_box.add_child(_row([["Idle", func(): _single("idle")], ["Walk", func(): _single("walk")], ["Attack", func(): _single("attack")]], "st"))
	_state_box.add_child(_row([["Block", func(): _single("block")], ["Hit", func(): _single("hit")], ["Death", func(): _single("death")]], "st"))
	_state_box.add_child(_row([["Step lane", func(): _single("step_lane")], ["Revive", func(): _single("revive")]], "st"))
	col.add_child(_state_box)
	_squad_box = VBoxContainer.new()
	_squad_box.add_child(_title("SQUAD"))
	_squad_box.add_child(_row([["Kill front man", func(): _kill_front()], ["Revive all", func(): _revive_all()]], "sq"))
	_squad_box.add_child(_row([["Replay", func(): set_scenario(scenario)], ["Hit squad", func(): _hit_squad()]], "sq"))
	col.add_child(_squad_box)
	col.add_child(_title("PLAYBACK"))
	col.add_child(_row([["Smooth", func(): set_twos(false)], ["On twos (12 fps)", func(): set_twos(true)]], "pb"))
	col.add_child(_row([["0.25x", func(): set_speed(0.25)], ["1x", func(): set_speed(1.0)]], "sp"))
	col.add_child(_title("OVERLAYS"))
	col.add_child(_row([["Radii", func(): _toggle("radii")], ["Contacts", func(): _toggle("contacts")], ["Bones", func(): _toggle("bones")]], "ov"))
	col.add_child(_row([["Smear", func(): _toggle("smear")], ["FX", func(): _toggle("fx")], ["Sound", func(): _toggle("sound")]], "ov2"))
	info = _small("")
	col.add_child(info)
	stats = _small("")
	col.add_child(stats)
	var hint := Label.new()
	hint.text = "Wheel zoom · right drag pan · Q/E facing · Space attack · T twos · S speed"
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
	hint.position = Vector2(12, 0)
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	hint.offset_top = -30
	ui.add_child(hint)
	_refresh_buttons()


func _title(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", Color(0.95, 0.84, 0.55))
	return l


func _small(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", Color(0.86, 0.9, 0.92))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 300
	return l


func _row(items: Array, group: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	for it in items:
		var b := Button.new()
		b.text = it[0]
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.y = 32
		b.add_theme_font_size_override("font_size", 14)
		b.pressed.connect(it[1])
		b.name = (group + "_" + String(it[0])).replace(" ", "_").replace(".", "").replace("(", "").replace(")", "")
		_buttons[b.name] = b
		b.toggle_mode = group in ["scn", "face", "pb", "sp", "ov", "ov2"]
		h.add_child(b)
	return h


func _refresh_buttons() -> void:
	var on := {
		"scn_Single": scenario == "single", "scn_Formation": scenario == "formation",
		"scn_Attack_dummy": scenario == "attack", "scn_March_in": scenario == "march",
		"pb_Smooth": not on_twos, "pb_On_twos_12_fps": on_twos, "sp_025x": speed < 0.5, "sp_1x": speed >= 0.5,
		"ov_Radii": show_radii, "ov_Contacts": show_contacts, "ov_Bones": show_bones,
		"ov2_Smear": smear, "ov2_FX": effects, "ov2_Sound": sound,
	}
	for i in 4:
		on["face_" + FACING_NAMES[i]] = facing == i
	for k in on:
		if _buttons.has(k):
			_buttons[k].set_pressed_no_signal(on[k])
	if _state_box:
		_state_box.visible = scenario == "single"
		_squad_box.visible = scenario != "single"


## All soldiers on the field.
func soldiers() -> Array:
	var out := []
	if single != null:
		out.append(single)
	if squad != null:
		out.append_array(squad.members)
	return out


func set_scenario(s: String) -> void:
	scenario = s
	for c in units.get_children():
		c.queue_free()
	single = null
	squad = null
	dummy = null
	fx_ground.clear()
	fx_top.clear()
	overlap_frames = 0
	overlap_log.clear()
	var dirv: Vector2 = Formation.GRID_DIRS[facing]
	match s:
		"single":
			single = Footman.new()
			units.add_child(single)
			single.setup(available, facing)
			single.stepped.connect(func(so, side, at): fx_ground.dust(fx_ground.to_local(at), Footman.screen_dir(so.facing)) if so.state == "walk" else null)
			single.impact_landed.connect(func(so, at): fx_top.spark(fx_top.to_local(at), Footman.screen_dir(so.facing)))
			_zoom = 3.2
			cam.position = Vector2(0, -40)
		"formation":
			_make_squad(Vector2.ZERO)
			_zoom = 2.6
			cam.position = Vector2(0, -36)
		"attack":
			_make_squad(Vector2.ZERO)
			dummy = Dummy.new()
			dummy.position = Formation.iso(dirv)
			dummy.fx = fx_top
			units.add_child(dummy)
			squad.attack(dummy, true)
			_zoom = 2.2
			cam.position = Formation.iso(dirv * 0.5) + Vector2(0, -40)
		"march":
			_make_squad(-dirv * 2.0)
			_zoom = 1.8
			cam.position = Formation.iso(-dirv * 0.8) + Vector2(0, -36)
			_march_timer = 0.6
	ground.focus_tile = Vector2.ZERO
	ground.queue_redraw()
	_apply_settings()
	_refresh_buttons()


func _make_squad(at_tile: Vector2) -> void:
	squad = Squad.new()
	squad.name = "Squad"
	units.add_child(squad)
	# The squad's members are y-sorted with everything else on the field.
	squad.y_sort_enabled = true
	squad.fx = fx_top
	squad.spawn(available, at_tile, facing, SEED)
	for s in squad.members:
		s.stepped.connect(func(so, side, at): if so.state in ["walk", "step_lane"]: fx_ground.dust(fx_ground.to_local(at), Footman.screen_dir(so.facing)))


func set_facing(f: int) -> void:
	facing = posmod(f, 4)
	if scenario == "single":
		single.set_facing(facing)
	else:
		set_scenario(scenario)
	_refresh_buttons()


func set_twos(v: bool) -> void:
	on_twos = v
	_apply_settings()
	_refresh_buttons()


func set_speed(v: float) -> void:
	speed = v
	_apply_settings()
	_refresh_buttons()


func _toggle(what: String) -> void:
	match what:
		"radii": show_radii = not show_radii
		"contacts": show_contacts = not show_contacts
		"bones": show_bones = not show_bones
		"smear": smear = not smear
		"fx": effects = not effects
		"sound": sound = not sound
	_apply_settings()
	_refresh_buttons()


func _apply_settings() -> void:
	for s in soldiers():
		s.on_twos = on_twos
		s.playback = speed
		s.debug_bones = show_bones
		s.debug_contacts = show_contacts
		s.smear_enabled = smear
	if squad:
		squad.sound = sound
	if dummy:
		dummy.playback = speed
	fx_ground.playback = speed
	fx_top.playback = speed
	fx_ground.enabled = effects
	fx_top.enabled = effects
	overlay.visible = show_radii


func _single(what: String) -> void:
	if single == null:
		return
	match what:
		"idle": single.idle()
		"walk": single.walk_in_place()
		"attack": single.attack()
		"block": single.guard()
		"hit": single.hit()
		"death": single.die()
		"step_lane": single.step_lane(Formation.iso(Formation.fwd(facing) * 0.3) * 0)
		"revive":
			single.revive()
			single.position = Vector2.ZERO


func _kill_front() -> void:
	if squad == null:
		return
	for i in squad.members.size():
		if squad._slots[i].rank == 0 and not squad.members[i].dead:
			squad.kill(i)
			return


func _revive_all() -> void:
	if squad:
		squad.revive_all()
		if scenario == "attack":
			squad.attack(dummy, true)


func _hit_squad() -> void:
	if squad == null:
		return
	for s in squad.members:
		if not s.dead:
			s.hit()


func _process(dt: float) -> void:
	cam.zoom = cam.zoom.lerp(Vector2.ONE * _zoom, minf(1.0, dt * 10.0))
	cam.offset = fx_top.shake_offset(dt * speed) if effects else Vector2.ZERO
	if scenario == "march" and _march_timer > 0.0:
		_march_timer -= dt * speed
		if _march_timer <= 0.0:
			squad.march_to(Vector2.ZERO)
	var ov := Formation.overlaps(soldiers())
	if not ov.is_empty():
		overlap_frames += 1
		if overlap_log.size() < 40:
			overlap_log.append({"t": Time.get_ticks_msec(), "n": ov.size(), "kind": ov[0].kind})
	overlay.current = ov
	overlay.queue_redraw()
	var s0 = single if single != null else (squad.members[0] if squad and not squad.members.is_empty() else null)
	var state_txt: String = "%s · %.2fs" % [s0.state, s0.rig.player.current_animation_position] if s0 else ""
	info.text = "%s · facing %s · %s · %s\n%s" % [scenario, FACING_NAMES[facing], "on twos" if on_twos else "smooth", "%.2fx" % speed, state_txt]
	stats.text = "FPS %d · soldiers %d · blows %d · overlaps now %d (frames %d)" % [Engine.get_frames_per_second(), soldiers().size(),
		squad.damage_ticks if squad else (single.impacts if single else 0), ov.size(), overlap_frames]


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom = clampf(_zoom * 1.12, 0.5, 8.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom = clampf(_zoom / 1.12, 0.5, 8.0)
		elif event.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			_dragging = event.pressed
	elif event is InputEventMouseMotion and _dragging:
		cam.position -= event.relative / cam.zoom.x
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_Q: set_facing(facing - 1)
			KEY_E: set_facing(facing + 1)
			KEY_T: set_twos(not on_twos)
			KEY_S: set_speed(0.25 if speed >= 0.5 else 1.0)
			KEY_SPACE:
				if single: single.attack()
				elif squad and dummy: squad.attack(dummy, true)
