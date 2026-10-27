## Isolated practice field. All figures, formations and event playback are the
## production battle renderer; only the practice commands and camera differ.
extends "res://scripts/render/battle_view.gd"

const PracticeBattle = preload("res://scripts/rules/battle.gd")
const Soldier = preload("res://scripts/meta/soldier.gd")
const PracticeDraw = preload("res://scripts/render/playground_draw.gd")
const FIELD_SIZE := 18
const HOME := Vector2i(8, 8)
const SUBJECT := "practice-subject"
const TARGET := "practice-target"
const COMPARISON := "practice-comparison"
const DUMMY_AT := Vector2i(8, 11)
const CLIPS := ["Idle", "March", "Turn", "Attack", "Fall"]

var unit_type := "footman"
var facing := 1
var variant := 0
var solo := false
var comparison := ""
var clip := "Idle"
var looping := true
var playing := true
var playback_rate := 1.0
var elapsed := 0.0
var _wait := 0.0
var _cycle_done := false


static func field_setup() -> Dictionary:
	var tiles: Array = []
	for y in FIELD_SIZE:
		for x in FIELD_SIZE:
			tiles.append({"x": x, "y": y, "h": 0, "terrain": "grass", "v": floori(Rng.hash2(x, y, 71) * 10000)})
	return {"seed": 71, "units": [], "map": {
		"id": "unit_playground", "name": "Practice field", "w": FIELD_SIZE, "h": FIELD_SIZE,
		"tiles": tiles, "seed": 71, "border": 7, "biome": "summer", "scale": "small",
		"playerDeploy": [], "enemyDeploy": [], "outer": [], "outerGround": [], "entries": {}, "approaches": [],
	}}


func _ready() -> void:
	prepare()


## Explicit construction also supports tests before SceneTree._ready runs.
func prepare() -> void:
	if _is_setup:
		return
	auto_step = false
	threaded_rules = false
	var practice = PracticeBattle.new(field_setup())
	practice.phase = "player"
	setup(practice)
	set_process_input(false)
	set_process_unhandled_input(false)
	# No combat HUD or floating numbers over the models during inspection.
	for layer in ["Overlays", "Minimap", "MinimapBase", "Texts"]:
		_layers[layer].hide()
	ui.showGrid = false
	reset_subject()
	frame_subject(1.6)


func _audio() -> Node:
	return null


func _build_layers() -> void:
	if _world == null:
		_draw = PracticeDraw.new(self)
	super._build_layers()


func _focus_on(x: float, y: float, force: bool) -> void:
	pass # Inspection keeps the user's camera, including during attacks.


func _refresh_hover() -> void:
	pass # The playground handles field clicks; battle command previews are unused.


func _clamp_camera() -> void:
	cam.tzoom = clampf(cam.tzoom, 0.4, 5.0)
	cam.tx = clampf(cam.tx, -900.0, 900.0)
	cam.ty = clampf(cam.ty, 0.0, 1100.0)


func _unit(type_id: String, uid: String, pos: Vector2i, dir: int, single := false) -> Dictionary:
	var u := Soldier.make_enemy(type_id, 1, uid, Rng.new(71))
	u.faction = "player" if uid == SUBJECT else "enemy"
	u.name = DB.UNIT_TYPES[type_id].name
	u.x = pos.x
	u.y = pos.y
	u.facing = dir
	u.variant = variant
	if single and not DB.is_engine(type_id):
		u.size = 1
		u.alive = 1
		u.hp = u.hpPer
		u.maxHp = u.hpPer
	return u


func reset_subject(at := HOME) -> void:
	_queue.clear()
	_anims.clear()
	_anim = null
	_cause.clear()
	corpses.clear()
	flash.a = 0.0
	cam.shake = 0.0
	fx = BattleDeps.make_fx()
	fx.additive = true
	views.clear()
	_ucache.clear()
	b.units.clear()
	b.events.clear()
	b.hits_taken.clear()
	ui.selected = null
	ui.banner = null
	ui.busy = false
	ui.hover = {}
	var u := _unit(unit_type, SUBJECT, at, facing, solo)
	b.units.append(u)
	var dummy := _unit("footman", TARGET, DUMMY_AT, 3, true)
	dummy.name = "Training dummy"
	dummy.stats.armor = 0
	dummy.shieldFront = 0
	b.units.append(dummy)
	if comparison != "":
		b.units.append(_unit(comparison, COMPARISON, at + Vector2i(3, -2), facing))
	for squad in b.units:
		b.hits_taken[squad.uid] = 0
		views[squad.uid] = _make_view(squad)
	var member = views[TARGET].members[0]
	member.type = "practice_dummy"
	member.x = 0.0
	member.y = 0.0
	member.to_x = 0.0
	member.to_y = 0.0
	_warm_sprites()
	_wait = 0.0
	elapsed = 0.0
	_cycle_done = false
	time = 0.0


func choose_unit(type_id: String) -> void:
	if not DB.UNIT_TYPES.has(type_id):
		return
	unit_type = type_id
	reset_subject()
	frame_subject(cam.tzoom)


func choose_clip(value: String) -> void:
	if not CLIPS.has(value):
		return
	clip = value
	reset_subject()


func set_facing(value: int) -> void:
	facing = posmod(value, 4)
	clip = "Idle"
	reset_subject()


func frame_subject(zoom_value := -1.0) -> void:
	var u = views[SUBJECT]
	var p := Iso.iso(u.x, u.y) + Vector2(0, -35)
	if comparison != "":
		var target = views[COMPARISON]
		p = (p + Iso.iso(target.x, target.y) + Vector2(0, -35)) * 0.5
	cam.x = p.x
	cam.tx = p.x
	cam.y = p.y
	cam.ty = p.y
	if zoom_value > 0:
		cam.zoom = zoom_value
		cam.tzoom = zoom_value


func tick(real_dt: float, frame_step := false) -> void:
	var dt := (1.0 / 60.0 if frame_step else minf(real_dt, 0.05) * playback_rate) if playing or frame_step else 0.0
	if dt > 0:
		if not busy():
			_wait = maxf(0.0, _wait - dt)
			if _wait == 0 and (not _cycle_done or looping):
				_start_cycle()
		elapsed += dt
		advance(dt)
	else:
		cam.update(minf(real_dt, 0.05))
	var vs := _view_size()
	_w = vs.x
	_h = vs.y
	_apply_camera()
	_redraw()


func _enqueue(event: Dictionary) -> void:
	b.events.append(event)
	pump()


func _start_cycle() -> void:
	_cycle_done = true
	_wait = 1.0
	var u: Dictionary = b.unit(SUBJECT)
	match clip:
		"March":
			var dest := HOME + Vector2i(Grid.DX[facing], Grid.DY[facing]) * 2
			if Vector2i(u.x, u.y) != HOME:
				dest = HOME
			march_to(dest)
		"Turn":
			u.facing = (int(u.facing) + 1) % 4
			_enqueue({"t": "face", "uid": SUBJECT, "facing": u.facing})
		"Attack":
			_attack_preview()
		"Fall":
			if views[SUBJECT].alive == 0:
				reset_subject()
				_cycle_done = true
			_enqueue({"t": "down", "uid": SUBJECT, "dead": true})
			_wait = 2.2


func march_to(dest: Vector2i) -> void:
	if busy() or not Grid.in_bounds(b.map, dest.x, dest.y) or views[SUBJECT].alive == 0:
		return
	var u: Dictionary = b.unit(SUBJECT)
	var pos := Vector2i(u.x, u.y)
	if dest == pos or dest == DUMMY_AT:
		return
	var path := practice_path(pos, dest)
	if path.size() < 2:
		return
	u.x = dest.x
	u.y = dest.y
	u.facing = dir_of(path[-2], path[-1])
	_enqueue({"t": "move", "uid": SUBJECT, "path": path})


func _attack_preview() -> void:
	var u: Dictionary = b.unit(SUBJECT)
	var ranged := u.has("shot")
	var distance := 3 if ranged else 1
	march_to(DUMMY_AT - Vector2i(Grid.DX[facing], Grid.DY[facing]) * distance)
	_enqueue({"t": "face", "uid": SUBJECT, "facing": facing})
	var target: Dictionary = b.unit(TARGET)
	_enqueue({"t": "attack", "uid": SUBJECT, "target": TARGET, "ranged": ranged,
		"hit": true, "damage": 0, "arc": "front", "aliveBefore": target.alive,
		"aliveAfter": target.alive, "targetHp": target.hp})


func walk_at(screen_pos: Vector2) -> void:
	var world_pos := cam.to_world(screen_pos, Vector2(_w, _h))
	var tile := Iso.from_iso(world_pos.x, world_pos.y)
	var dest := Vector2i(roundi(tile.x), roundi(tile.y))
	if busy() or not Grid.in_bounds(b.map, dest.x, dest.y):
		return
	var dummy_screen := cam.to_screen(Iso.iso(DUMMY_AT.x, DUMMY_AT.y) + Vector2(0, -30), Vector2(_w, _h))
	if dest == DUMMY_AT or screen_pos.distance_to(dummy_screen) < 30 * cam.zoom:
		if views[SUBJECT].alive == 0:
			reset_subject()
		clip = "Attack"
		_cycle_done = false
		_wait = 0.0
		return
	clip = "Idle"
	_cycle_done = true
	march_to(dest)


## Breadth-first walk on the practice field, avoiding the dummy and comparison.
## This has no action-point or turn limits; each step uses production movement.
func practice_path(start: Vector2i, dest: Vector2i) -> Array:
	var blocked := {DUMMY_AT: true}
	if views.has(COMPARISON):
		blocked[Vector2i(views[COMPARISON].x, views[COMPARISON].y)] = true
	if blocked.has(dest):
		return []
	var frontier: Array[Vector2i] = [start]
	var previous := {start: start}
	var index := 0
	while index < frontier.size() and not previous.has(dest):
		var p := frontier[index]
		index += 1
		for i in 4:
			var next := p + Vector2i(Grid.DX[i], Grid.DY[i])
			if Grid.in_bounds(b.map, next.x, next.y) and not blocked.has(next) and not previous.has(next):
				previous[next] = p
				frontier.append(next)
	if not previous.has(dest):
		return []
	var path: Array = []
	var p := dest
	while p != start:
		path.push_front({"x": p.x, "y": p.y})
		p = previous[p]
	path.push_front({"x": start.x, "y": start.y})
	return path
