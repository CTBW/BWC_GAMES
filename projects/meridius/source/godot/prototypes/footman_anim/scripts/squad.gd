## The prototype footman squad: the master footman instanced squad-size times
## (DB.squad_size("footman")), each with his own clock, a seeded tempo, idle
## phase and attack stagger, standing in formation slots inside one tile.
## Every soldier's blow is handled from his own `impact` event (spark, sound,
## the dummy's reaction, the damage tick count); there is no shared timer.
extends Node2D

const Footman = preload("res://prototypes/footman_anim/scripts/footman.gd")
const Formation = preload("res://prototypes/footman_anim/scripts/formation.gd")
const DB = preload("res://scripts/data/db.gd")

signal blow(soldier: Node2D, at: Vector2)

var members: Array = []
var tile := Vector2.ZERO
var facing := 0
var fx: Node2D
var target: Node2D
var seed := 1
var rng := RandomNumberGenerator.new()
var file_gap := Formation.FILE
var damage_ticks := 0
var looping_attack := false
var sound := true
var _params: Array = []
var _slots: Array = []
var _role: Array = []
var _loop_t := 0.0


func spawn(available: Array, p_tile: Vector2, p_facing: int, p_seed: int, count: int = -1) -> void:
	seed = p_seed
	rng.seed = p_seed
	tile = p_tile
	facing = p_facing
	var n := count if count > 0 else DB.squad_size("footman")
	for i in n:
		var s := Footman.new()
		s.name = "Footman%d" % i
		add_child(s)
		s.setup(available, facing)
		s.label = str(i)
		var p := {
			"idle": rng.randf_range(0.0, 7.5),
			"tempo": rng.randf_range(0.965, 1.035),
			"attack": rng.randf_range(0.0, 0.16),
			"march": rng.randf_range(0.0, 0.12),
		}
		_params.append(p)
		s.tempo = p.tempo
		s.impact_landed.connect(_on_impact)
		s.stepped.connect(_on_step)
		s.finished.connect(_on_finished)
		members.append(s)
	_role.resize(n)
	form(true)
	for i in n:
		members[i].idle(_params[i].idle)


func set_facing(f: int) -> void:
	facing = posmod(f, 4)
	for s in members:
		s.set_facing(facing)
	form(true)


func form(instant: bool) -> void:
	_slots = Formation.slots(members.size(), facing, file_gap)
	for i in members.size():
		var s: Node2D = members[i]
		_role[i] = _slots[i].rank
		if instant and not s.dead:
			s.position = Formation.iso(tile + _slots[i].g)


func slot_world(i: int) -> Vector2:
	return Formation.iso(tile + _slots[i].g)


func march_to(p_tile: Vector2) -> void:
	var d := p_tile - tile
	if d.length() > 0.0:
		var f := 0
		for k in 4:
			if (Formation.GRID_DIRS[k] as Vector2).dot(d.normalized()) > 0.7:
				f = k
		facing = f
	tile = p_tile
	_slots = Formation.slots(members.size(), facing, file_gap)
	for i in members.size():
		var s: Node2D = members[i]
		if s.dead:
			continue
		s.set_facing(facing)
		var goal := slot_world(i)
		var delay: float = _params[i].march
		get_tree().create_timer(delay, true, false, false).timeout.connect(func():
			if is_instance_valid(s) and not s.dead:
				s.walk_toward(goal))


func attack(p_target: Node2D, loop: bool = false) -> void:
	target = p_target
	looping_attack = loop
	_strike_round()


func stop_attacking() -> void:
	looping_attack = false
	for s in members:
		if not s.dead and s.base_state == "block":
			s.idle()


func _strike_round() -> void:
	var front_alive := []
	for i in members.size():
		if _slots[i].rank == 0:
			front_alive.append(not members[i].dead)
	for i in members.size():
		var s: Node2D = members[i]
		if s.dead:
			continue
		if _slots[i].rank == 0:
			# Stagger: each man's own seeded offset plus a fresh jitter per round.
			s.attack(_params[i].attack + rng.randf_range(0.0, 0.06))
		else:
			s.guard()
	_loop_t = 2.05 + rng.randf_range(-0.1, 0.1)


func _process(dt: float) -> void:
	if looping_attack:
		var pb: float = members[0].playback if not members.is_empty() else 1.0
		_loop_t -= dt * pb
		if _loop_t <= 0.0:
			_strike_round()


## A front-rank man falls: the rear man of the same file steps into his lane.
func kill(i: int) -> void:
	if i < 0 or i >= members.size() or members[i].dead:
		return
	members[i].die()
	if _slots[i].rank != 0:
		return
	var file: int = _slots[i].file
	for j in members.size():
		if j != i and _slots[j].rank == 1 and _slots[j].file == file and not members[j].dead:
			var to: Vector2 = slot_world(i) - members[j].position
			members[j].step_lane(to)
			# He takes the fallen man's slot and role.
			var tmp = _slots[i]
			_slots[i] = _slots[j]
			_slots[j] = tmp
			break


func revive_all() -> void:
	for s in members:
		if s.dead:
			s.revive()
	_slots = Formation.slots(members.size(), facing, file_gap)
	form(true)
	for i in members.size():
		members[i].idle(_params[i].idle)


func _on_impact(s: Node2D, at: Vector2) -> void:
	damage_ticks += 1
	var hit_at := at
	var dir := Vector2.RIGHT
	if target != null and is_instance_valid(target):
		hit_at = target.strike_point(s.global_position)
		dir = (target.global_position - s.global_position).normalized()
		# The blade has to reach: a blow whose tip ends far from the sack whiffs.
		if at.distance_to(hit_at) < 60.0:
			target.hit(hit_at, dir)
		else:
			hit_at = at
	if fx:
		fx.spark(fx.to_local(hit_at), dir)
	blow.emit(s, hit_at)
	if sound:
		var sfx := get_node_or_null("/root/Sfx")
		if sfx != null and sfx.has_method("play"):
			sfx.play("hit_flesh" if rng.randf() < 0.6 else "block")


func _on_step(s: Node2D, side: String, at: Vector2) -> void:
	if fx and s.state in ["walk", "step_lane"]:
		fx.dust(fx.to_local(at + Vector2(0, 1)), Footman.screen_dir(s.facing))


func _on_finished(s: Node2D, clip: String) -> void:
	pass
