## One facing of the prototype footman: a cut-out rig of rigid painted parts
## driven by a bone hierarchy (plain Node2D bones, keyed by an AnimationPlayer).
##
## Why rigid parts on bones and not Skeleton2D + skinned Polygon2D: the art is
## painted cel shading with ink outlines; skinning bends those strokes and
## smears the joints. Every joint of this costume has a natural cover (cowl
## over shoulders and neck, bracer cuff over the elbow, glove cuff over the
## wrist, skirt over the hips, boot cuff over the knee), so rigid parts with
## padded underlaps keep the outline continuous. Cloth (cowl, skirts, tabard)
## gets secondary motion from damped pendulum springs instead of skinning.
##
## Bones live under `Bones`; the sprites are flat children of `Parts` in draw
## order, so a part can change layer (the sword passing behind the body)
## without z_index, which would fight the squad's Y-sort. Each frame the parts
## copy their bone's transform (update_parts).
extends Node2D

signal impact
signal step(side: String)

const ART := "res://prototypes/footman_anim/art/"
const MOTION := "res://prototypes/footman_anim/motion/"

## name, parent ("" = root)
const BONES := [
	["hips", ""], ["spine", "hips"], ["head", "spine"],
	["upper_r", "spine"], ["fore_r", "upper_r"], ["hand_r", "fore_r"], ["sword", "hand_r"],
	["upper_l", "spine"], ["fore_l", "upper_l"], ["hand_l", "fore_l"], ["shield", "hand_l"],
	["thigh_r", "hips"], ["shin_r", "thigh_r"], ["foot_r", "shin_r"],
	["thigh_l", "hips"], ["shin_l", "thigh_l"], ["foot_l", "shin_l"],
]
const STRETCH_BONES := ["upper_r", "fore_r", "upper_l", "fore_l", "sword", "thigh_r", "shin_r", "thigh_l", "shin_l"]
## Which bone carries each part (the same for every view; NW remaps, see _bone_of).
const PART_BONE := {
	"head": "head", "cowl_back": "spine", "cowl_front": "spine", "chest": "spine",
	"upper_l": "upper_l", "fore_l": "fore_l", "hand_l": "hand_l",
	"pelvis": "hips", "skirt_rear": "hips", "tabard": "hips", "skirt_front": "hips",
	"thigh_r": "thigh_r", "shin_r": "shin_r", "foot_r": "foot_r",
	"thigh_l": "thigh_l", "shin_l": "shin_l", "foot_l": "foot_l",
	"upper_r": "upper_r", "fore_r": "fore_r", "hand_r": "hand_r", "sword": "sword", "shield": "shield",
}
## Parts that stretch with their bone (foreshortening, blade stretch).
const STRETCH_PARTS := ["upper_r", "fore_r", "upper_l", "fore_l", "sword", "thigh_r", "shin_r", "thigh_l", "shin_l"]
## Secondary motion: pendulum frequency (Hz), damping ratio, how much of the
## parent's turn the cloth resists, gravity follow, limit (rad). Pivot: a joint
## or "top" (the part's top centre).
const SPRINGS := {
	"cowl_front": {"pivot": "neck", "hz": 5.0, "zeta": 0.8, "lag": 0.08, "hang": 0.02, "max": 0.035, "push": 0.25},
	"cowl_back": {"pivot": "neck", "hz": 4.5, "zeta": 0.75, "lag": 0.1, "hang": 0.03, "max": 0.05, "push": 0.3},
	"skirt_rear": {"pivot": "top", "hz": 3.0, "zeta": 0.3, "lag": 0.45, "hang": 0.3, "max": 0.32, "push": 1.0},
	"tabard": {"pivot": "top", "hz": 2.7, "zeta": 0.26, "lag": 0.55, "hang": 0.4, "max": 0.36, "push": 1.3},
	"skirt_front": {"pivot": "top", "hz": 3.0, "zeta": 0.3, "lag": 0.45, "hang": 0.3, "max": 0.32, "push": 1.0},
}
## Layer of the sword when it passes behind the body.
const SWORD_BEHIND_LAYER := 22
const GRAVITY := 2600.0

var facing := ""
var view := ""
var meta: Dictionary = {}
var rest: Dictionary = {}
var origin := Vector2.ZERO
var figure_scale := 1.0
var mirrored := false
var player: AnimationPlayer
var bones := {}
var stretch_nodes := {}
## [{name, sprite, bone, layer, offset, spring}]
var parts: Array = []
var sword_behind := false:
	set(value):
		if value != sword_behind:
			sword_behind = value
			_relayer()
## Draw layer of the sword, keyed by the clip (45 in hand, 22 behind the body,
## 55 over the shield during a cut).
var sword_layer := 45:
	set(value):
		if value != sword_layer:
			sword_layer = value
			_relayer()
## Extra layer overrides for authored moments ({part: layer}).
var layer_override := {}
var springs_enabled := true
var _bones_root: Node2D
var _parts_root: Node2D
var _xf := {}
var _spring_state := {}


static func bone_path(name: String) -> String:
	var chain: Array[String] = []
	var cur := name
	while cur != "":
		chain.push_front(cur)
		cur = _parent_of(cur)
	return "Bones/" + "/".join(chain)


static func _parent_of(name: String) -> String:
	for b in BONES:
		if b[0] == name:
			return b[1]
	return ""


func setup(p_facing: String, p_scale: float) -> void:
	facing = p_facing
	figure_scale = p_scale
	meta = JSON.parse_string(FileAccess.get_file_as_string(MOTION + facing + "_rig.json"))
	rest = meta.rest
	view = meta.view
	mirrored = meta.mirror
	var art: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ART + view + "/parts.json"))
	var J: Dictionary = art.joints
	if mirrored:
		J = _mirror_joints(J, art.size[0])
	# Ground point: under the hips, at the soles' mean depth.
	var sole := (_v(rest.foot_r.pos).y + _v(rest.foot_l.pos).y) * 0.5 + 14.0
	origin = Vector2(_v(rest.hips.pos).x, sole)
	scale = Vector2(-p_scale if mirrored else p_scale, p_scale)
	_bones_root = Node2D.new()
	_bones_root.name = "Bones"
	_bones_root.position = -origin
	add_child(_bones_root)
	for b in BONES:
		var n := Node2D.new()
		n.name = b[0]
		var parent_node: Node2D = _bones_root if b[1] == "" else bones[b[1]]
		parent_node.add_child(n)
		var s := Node2D.new()
		s.name = "S"
		n.add_child(s)
		bones[b[0]] = n
		stretch_nodes[b[0]] = s
	_apply_rest()
	_parts_root = Node2D.new()
	_parts_root.name = "Parts"
	_parts_root.position = -origin
	add_child(_parts_root)
	for p in art.parts:
		var bone := _bone_of(p.name)
		if bone == "" or not rest.has(bone):
			continue
		var tex: Texture2D = load(ART + view + "/" + p.name + ".png")
		var spr := Sprite2D.new()
		spr.name = p.name
		spr.texture = tex
		spr.centered = false
		var rb: Dictionary = rest[bone]
		var a: float = rb.ang
		var jb := _v(rb.pos)
		# The texture is drawn as is (a mirrored facing flips the whole rig by
		# scale.x); a prop that changed hands moves with its new hand.
		var px := Vector2(p.x, p.y)
		var shift: Array = meta.get("part_shift", {}).get(p.name, [0, 0])
		px += Vector2(shift[0], shift[1])
		var off := Transform2D(-a, (px - jb).rotated(-a))
		var layer := int(meta.get("layers", {}).get(p.name, p.layer))
		var entry := {"name": p.name, "sprite": spr, "bone": bone, "layer": layer, "offset": off,
			"stretch": p.name in STRETCH_PARTS and bone in STRETCH_BONES, "spring": null}
		if SPRINGS.has(p.name):
			var cfg: Dictionary = SPRINGS[p.name]
			var pivot: Vector2 = Vector2(p.x + p.w * 0.5, p.y + 6.0) if cfg.pivot == "top" else _v(J.get(cfg.pivot, rb.pos))
			var centre := Vector2(p.x + p.w * 0.5, p.y + p.h * 0.5)
			entry.spring = {"cfg": cfg, "pivot_local": (pivot - jb).rotated(-a), "lever": (centre - pivot).rotated(-a)}
			_spring_state[p.name] = {"th": 0.0, "w": 0.0, "pp": null, "pv": Vector2.ZERO, "pa": null, "pw": 0.0}
		parts.append(entry)
		_parts_root.add_child(spr)
	_relayer()
	player = AnimationPlayer.new()
	player.name = "AnimationPlayer"
	add_child(player)
	player.root_node = NodePath("..")
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	player.callback_mode_method = AnimationMixer.ANIMATION_CALLBACK_MODE_METHOD_IMMEDIATE
	var lib: AnimationLibrary = load(MOTION + facing + ".tres")
	player.add_animation_library("", lib)
	update_parts(0.0)


func _bone_of(part: String) -> String:
	var b: String = PART_BONE.get(part, "")
	if meta.get("swap", false):
		# NW: the mirrored back view has the left side nearest the camera; the
		# drawing's near limbs become the left ones and the props change hands.
		if part in ["sword"]:
			return "sword"
		if part in ["shield"]:
			return "shield"
		if b.ends_with("_r"):
			return b.substr(0, b.length() - 2) + "_l"
		if b.ends_with("_l"):
			return b.substr(0, b.length() - 2) + "_r"
	return b


static func _mirror_joints(J: Dictionary, w: float) -> Dictionary:
	var out := {}
	for k in J:
		out[k] = [J[k][0], J[k][1]]
	return out


static func _v(a) -> Vector2:
	return Vector2(a[0], a[1])


func _apply_rest() -> void:
	for b in BONES:
		var n: Node2D = bones[b[0]]
		var rb: Dictionary = rest[b[0]]
		if b[1] == "":
			n.position = _v(rb.pos)
			n.rotation = rb.ang
		else:
			var rp: Dictionary = rest[b[1]]
			n.position = (_v(rb.pos) - _v(rp.pos)).rotated(-float(rp.ang))
			n.rotation = float(rb.ang) - float(rp.ang)


func _relayer() -> void:
	if _parts_root == null:
		return
	var order := parts.duplicate()
	order.sort_custom(func(a, b): return _layer_of(a) < _layer_of(b) or (_layer_of(a) == _layer_of(b) and a.layer < b.layer))
	for i in order.size():
		_parts_root.move_child(order[i].sprite, i)


func _layer_of(p: Dictionary) -> int:
	if layer_override.has(p.name):
		return layer_override[p.name]
	if p.name == "sword":
		return SWORD_BEHIND_LAYER if sword_behind else sword_layer
	return p.layer


func set_layer_override(part: String, layer: int) -> void:
	if layer < 0:
		layer_override.erase(part)
	else:
		layer_override[part] = layer
	_relayer()


## Pose the parts from the bones (after the AnimationPlayer advanced), with
## the cloth springs integrated over dt (0 = no spring step).
func update_parts(dt: float) -> void:
	for b in BONES:
		var n: Node2D = bones[b[0]]
		_xf[b[0]] = n.transform if b[1] == "" else _xf[b[1]] * n.transform
	for p in parts:
		var bx: Transform2D = _xf[p.bone]
		if p.stretch:
			bx = bx * stretch_nodes[p.bone].transform
		if p.spring != null:
			var th := _spring(p, _xf[p.bone], dt)
			var pl: Vector2 = p.spring.pivot_local
			bx = bx * Transform2D(0.0, pl) * Transform2D(th, Vector2.ZERO) * Transform2D(0.0, -pl)
		p.sprite.transform = bx * p.offset


func _spring(p: Dictionary, bone_xf: Transform2D, dt: float) -> float:
	var st: Dictionary = _spring_state[p.name]
	if not springs_enabled:
		st.th = 0.0
		st.w = 0.0
		return 0.0
	var cfg: Dictionary = p.spring.cfg
	var pivot := bone_xf * (p.spring.pivot_local as Vector2)
	var ang := bone_xf.get_rotation()
	if dt <= 0.0 or st.pp == null:
		st.pp = pivot
		st.pa = ang
		st.pv = Vector2.ZERO
		st.pw = 0.0
		return st.th
	var vel := (pivot - (st.pp as Vector2)) / dt
	var acc := (vel - (st.pv as Vector2)) / dt
	var wb := wrapf(ang - float(st.pa), -PI, PI) / dt
	var alpha := (wb - float(st.pw)) / dt
	st.pp = pivot
	st.pv = vel
	st.pa = ang
	st.pw = wb
	# Pseudo-force on the cloth's centre (it lags the pivot), as a lean from
	# vertical against gravity, in the bone's frame.
	var lever: Vector2 = (p.spring.lever as Vector2).rotated(ang)
	var down := lever.normalized()
	var side := Vector2(-down.y, down.x)
	var push := -acc.dot(side) / GRAVITY * float(cfg.push)
	var target := clampf(push, -1.0, 1.0) - float(cfg.hang) * wrapf(ang - _rest_ang(p.bone), -PI, PI)
	var w0 := TAU * float(cfg.hz)
	# Substeps keep the spring stable at 12 fps (on twos) and at 0.25x.
	var steps := maxi(1, ceili(dt / (1.0 / 120.0)))
	var h := dt / steps
	for i in steps:
		var a: float = w0 * w0 * (target - float(st.th)) - 2.0 * float(cfg.zeta) * w0 * float(st.w) - float(cfg.lag) * alpha / steps
		st.w = float(st.w) + a * h
		st.th = clampf(float(st.th) + float(st.w) * h, -float(cfg.max), float(cfg.max))
	return st.th


func _rest_ang(bone: String) -> float:
	return float(rest[bone].ang)


func reset_springs() -> void:
	for k in _spring_state:
		_spring_state[k] = {"th": 0.0, "w": 0.0, "pp": null, "pv": Vector2.ZERO, "pa": null, "pw": 0.0}


## A bone joint in this rig's parent's space (the footman's local space).
func joint(name: String) -> Vector2:
	var t: Transform2D = _xf.get(name, Transform2D())
	return transform * (_bones_root.transform * t.origin)


## End of a bone (its drawn length along its axis, stretched) in parent space.
func bone_tip(name: String) -> Vector2:
	var t: Transform2D = _xf.get(name, Transform2D())
	var s: Node2D = stretch_nodes[name]
	var tip := t * (Vector2(float(rest[name].len) * s.scale.x, 0.0))
	return transform * (_bones_root.transform * tip)


func part_sprite(name: String) -> Sprite2D:
	for p in parts:
		if p.name == name:
			return p.sprite
	return null


## Draw order index of a part (QA: layering checks).
func part_index(name: String) -> int:
	var s := part_sprite(name)
	return s.get_index() if s != null else -1


func _ev_impact() -> void:
	impact.emit()


func _ev_step(side: String) -> void:
	step.emit(side)
