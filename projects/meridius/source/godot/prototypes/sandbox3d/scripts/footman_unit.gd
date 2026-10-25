## The footman in the 3D sandbox: his own controller (footman3d.gd: the start
## and the stop, turns on the planted foot, the shield charge, the block, the
## lane step) behind the sandbox's unit interface (unit3d.gd).
extends "res://prototypes/footman_anim/scripts/footman3d.gd"

## Never emitted (he has no missile); the sandbox connects every unit alike.
signal release(target: Node3D, kind: String)

var profile: Dictionary
var faction := "player"
var stance := ""


func setup(p: Dictionary) -> void:
	profile = p
	faction = p.get("faction", "player")


func _ready() -> void:
	super._ready()
	player.animation_finished.connect(_clip_done)
	player.seek(rng.randf() * player.current_animation_length, true)


func title() -> String:
	return profile.get("title", "Footman")


func height_m() -> float:
	return float(meta.get("height_m", 1.7))


func is_dead() -> bool:
	return state == "dead"


func clip_names() -> Array:
	var out := []
	for n in player.get_animation_list():
		if String(n) != "RESET":
			out.append(String(n))
	out.sort()
	return out


func has_clip(c: String) -> bool:
	return player.has_animation(c)


func actions() -> Array:
	var out := []
	var atks: Array = profile.get("attacks", [])
	for i in atks.size():
		if player.has_animation(atks[i].clip):
			out.append({"id": "attack:%d" % i, "label": atks[i].label, "target": true})
	if can_charge():
		out.append({"id": "charge", "label": "Shield charge", "target": true})
	out.append({"id": "counter", "label": "Counter", "target": true})
	out.append({"id": "stance:block", "label": "Block", "toggle": true})
	out.append({"id": "lane", "label": "Step lane"})
	return out


func attack_info(i: int) -> Dictionary:
	var atks: Array = profile.get("attacks", [])
	return atks[i] if i >= 0 and i < atks.size() else {}


func reach(i: int) -> float:
	var c: String = attack_info(i).get("clip", "attack")
	return strike_dist(c if player.has_animation(c) else "attack")


func is_ranged(_i: int) -> bool:
	return false


func order_move(points: Array, then := Callable()) -> void:
	if is_dead():
		return
	if block_held:
		set_block(false)
	march(points, then)


func turn_to(at: Vector3, then := Callable()) -> void:
	face(yaw_of(at - position), then)


func strike(target: Node3D, i: int) -> void:
	if is_dead():
		return
	var c: String = attack_info(i).get("clip", "attack")
	if not player.has_animation(c):
		c = "attack"
	if target == null:
		attack(null, c)
		return
	face(yaw_of(target.position - position), func(): attack(target, c))


## A blow at a target in reach, as a squad's man strikes: the slash, or now and
## then the stab when it reaches (pick_attack), turning to it first.
func strike_at(target: Node3D) -> void:
	if is_dead() or target == null:
		return
	var d := Vector2(target.position.x - position.x, target.position.z - position.z).length()
	var c := _fit_attack(target, pick_attack(d))
	face(yaw_of(target.position - position), func(): attack(target, c))


func take_hit(from: Vector3, lethal := false) -> void:
	if is_dead():
		return
	if lethal:
		var d := from - position
		if Vector2(d.x, d.z).length() > 0.05:
			rotation.y = yaw_of(d)
		die()
		return
	hit()


func stop() -> void:
	if is_dead():
		return
	path.clear()
	state = "idle"
	_play("idle")


func toggle_stance(s: String) -> void:
	if s == "block":
		set_block(not block_held)
		stance = "block" if block_held else ""


## Any clip of his once (a looping one until the next order).
func play_clip(c: String) -> void:
	if not player.has_animation(c) or is_dead():
		return
	if c == "death":
		die()
		return
	path.clear()
	state = "clip"
	player.play(c, 0.15)
	player.seek(0.0, true)


func pose_at(c: String, seconds: float) -> void:
	if not player.has_animation(c):
		return
	state = "pose"
	player.play(c, 0.0)
	player.seek(seconds, true)
	player.pause()


func set_fx(_on: bool) -> void:
	pass


func _clip_done(_anim: StringName) -> void:
	if state == "clip":
		state = "idle"
		_play("idle")
