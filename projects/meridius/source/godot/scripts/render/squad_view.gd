## The visible soldiers of a squad. Port of src/render/squadView.ts.
##
## Gameplay knows only the squad (one tile, one facing, one HP pool); this
## module gives each soldier a body: a slot in the formation, a personal idle
## rhythm, an attack lunge, a hit flash and a fall. Nothing here feeds back
## into the rules.
##
## A soldier is a `Member` object (inner class; fields are the snake_case of the
## original's: `to_x`, `death_t`, `fall_flip`…). Offsets are world pixels.
## Use through `const SquadView = preload("res://scripts/render/squad_view.gd")`.
extends RefCounted

const JS = preload("res://scripts/core/js.gd")
const Rng = preload("res://scripts/core/rng.gd")
const DB = preload("res://scripts/data/db.gd")
const Formation = preload("res://scripts/render/formation.gd")
const SoldierAnim = preload("res://scripts/render/soldier_anim.gd")


class Member extends RefCounted:
	## Stable index within the squad (0 is the champion of a guard squad).
	var id := 0
	var alive := true
	## Falling: 0 → 1; at 1 the body is handed over to the field as a corpse.
	var death_t := 0.0
	var dying := false
	## Seconds to wait before starting to fall (casualties of one volley drop one by one).
	var death_delay := 0.0
	## Current offset from the squad anchor, in world pixels.
	var x := 0.0
	var y := 0.0
	## Formation tween: from → to over `dur`, after `delay`.
	var from_x := 0.0
	var from_y := 0.0
	var to_x := 0.0
	var to_y := 0.0
	var t := 1.0
	var dur := 0.0
	var delay := 0.0
	## Attack offset (lunge toward the enemy, recoil, dodge).
	var lunge := Vector2.ZERO
	var flash := 0.0
	var shake := 0.0
	## "idle" or "atk".
	var pose := "idle"
	## Frame-animated figures (soldier_anim.gd): the key pose of the attack
	## ("wind", "hit"; empty: the blow), and how far he trails the anchor.
	var key := ""
	var drift := Vector2.ZERO
	## The drift's speed (the spring soldier_anim.step_drift follows the anchor on).
	var drift_v := Vector2.ZERO
	## SoldierAnim.pose's result for the frame at `pose_t` (one evaluation a frame).
	var pose_t := -1.0
	var pose_cache = null
	## His gait (SoldierAnim.gait_values) and beat (SoldierAnim.rhythm), cached.
	var gv := PackedFloat64Array()
	var rh := Vector3.ZERO
	## His idle constants (SoldierAnim.P_*), his type's frames by facing, and
	## the roll of his current fidget interval (n, kind, length).
	var pc := PackedFloat64Array()
	var fb: Array = []
	var fid := Vector3(-1, 0, 0)
	## Seconds a fall takes.
	var death_dur := 0.5
	## The way he is turned when it is not the squad's facing (-1: the squad's):
	## men turn toward the enemy they strike or shoot at, then back after `face_t` s.
	var face := -1
	var face_t := 0.0
	## A turn ordered but not yet made: to `face_next` after `face_wait` s.
	var face_next := -1
	var face_wait := 0.0
	## Personal rhythm so the ranks breathe and march out of lockstep.
	var phase := 0.0
	## Figure drawn for this soldier and its look.
	var type := ""
	var variant := 0
	## Which way the body falls.
	var fall_flip := false
	## The view's cache of this soldier's sprite: [sprite, flip] for state `spr_state`.
	var spr_state := -1
	var spr_cache = null


## Scale of a squad soldier relative to the full-size figure sprites.
const MEMBER_SCALE := 0.52
const BIG_MEMBER_SCALE := 0.44


## Standing height of a soldier on screen (world px), for bars and labels.
static func member_height(type_id: String) -> float:
	var def: Dictionary = DB.UNIT_TYPES.get(type_id, {})
	if def.has("crew"):
		return 40.0 if def.crew == "goblin_rabble" else 48.0
	if type_id == "battle_mage":
		return 54.0
	if type_id == "goblin_shaman":
		return 44.0
	if type_id == "troll":
		# Twice the original figure (the pixel-art trolls are drawn at double size).
		return 132.0
	if type_id == "wolf_rider":
		return 58.0
	if type_id == "goblin_rabble":
		return 34.0
	if def.get("size") == "large":
		return 62.0
	if def.get("size") == "small":
		return 40.0
	if type_id.begins_with("orc"):
		return 54.0
	return 49.0


static func member_scale(u: Dictionary) -> float:
	if u.typeId == "wolf_rider":
		return 0.5
	if u.typeId == "goblin_rabble":
		return 0.48
	var def: Dictionary = DB.UNIT_TYPES.get(u.typeId, {})
	# War machines and their crews: goblin crews as small as the rabble they come from.
	if def.has("crew"):
		return 0.48 if def.crew == "goblin_rabble" else MEMBER_SCALE
	# Only the great beasts stand three to a tile at the smaller scale; three mages are men like any other.
	return BIG_MEMBER_SCALE if (u.size <= 3 and def.get("size") == "large") else MEMBER_SCALE


## Index of the soldier who must fall last (the warlord among his guard), or -1.
static func champion_of(u: Dictionary) -> int:
	var def: Dictionary = DB.UNIT_TYPES.get(u.typeId, {})
	return 0 if def.get("escort") else -1


static func make_members(u: Dictionary) -> Array:
	var def: Dictionary = DB.UNIT_TYPES.get(u.typeId, {})
	var size: int = u.size
	var slots := Formation.formation_slots(u.alive, size, u.facing, 1.0, u.typeId)
	var members: Array = []
	var uid: String = u.uid
	var seed := Rng.hash2(uid.length() * 13, uid.unicode_at(uid.length() - 1))
	for i in size:
		var alive: bool = i < u.alive
		var s: Dictionary = slots[i] if alive else {"x": 0.0, "y": 0.0}
		# A guard squad's rank and file, or a war machine's crew.
		var escort: Variant = def.get("escort") if (def.get("escort") and i > 0) else def.get("crew")
		var m := Member.new()
		m.id = i
		m.alive = alive
		m.x = s.x
		m.y = s.y
		m.from_x = s.x
		m.from_y = s.y
		m.to_x = s.x
		m.to_y = s.y
		m.t = 1.0
		m.phase = Rng.hash2(i * 7 + 1, floorf(seed * 1000)) * PI * 2
		m.type = escort if escort != null else u.typeId
		m.death_dur = SoldierAnim.death_duration(m.type)
		# Each soldier gets his own face; the champion keeps the squad's look.
		m.variant = (int(u.variant) * 5 + i * 7 + floori(seed * 6)) % 6 if (escort != null or i > 0) else int(u.variant)
		m.fall_flip = Rng.hash2(i, floorf(seed * 97)) > 0.5
		members.append(m)
	# A champion stands front and centre from the start.
	var champ := champion_of(u)
	if champ >= 0:
		reform(members, size, u.facing, {"instant": true, "champion": champ, "typeId": u.typeId})
	return members


static func standing(members: Array) -> Array:
	var out: Array = []
	for m in members:
		if m.alive:
			out.append(m)
	return out


## Move the standing soldiers to the formation for their number and facing,
## each to the nearest free slot. `stagger` makes the soldiers set off one
## after another instead of all at once.
## opts: dur, delay, stagger, tight, instant, champion, spread, typeId.
static func reform(members: Array, size: int, facing: int, opts: Dictionary = {}) -> void:
	var live := standing(members)
	if live.is_empty():
		return
	var slots := Formation.formation_slots(live.size(), size, facing, float(JS.get_or(opts, "tight", 1.0)), str(JS.get_or(opts, "typeId", "")))
	var champion: int = JS.get_or(opts, "champion", -1)
	var pinned := -1
	if champion >= 0:
		for i in live.size():
			if live[i].id == champion:
				pinned = i
				break
	var positions: Array = []
	for m in live:
		positions.append({"x": m.to_x, "y": m.to_y})
	var pick := Formation.assign_slots(positions, slots, pinned)
	var instant: bool = JS.get_or(opts, "instant", false)
	var spread: float = JS.get_or(opts, "spread", 0.0)
	var dur: float = JS.get_or(opts, "dur", 0.4)
	var delay: float = JS.get_or(opts, "delay", 0.0)
	var stagger: float = JS.get_or(opts, "stagger", 0.0)
	for i in live.size():
		var m: Member = live[i]
		var s: Dictionary = slots[pick[i]]
		var tx: float = s.x
		var ty: float = s.y
		if spread:
			# Loose, ragged order (fleeing): push outward and jitter.
			tx = tx * (1 + spread) + (Rng.hash2(m.id, 31) - 0.5) * 10 * spread
			ty = ty * (1 + spread * 0.6) + (Rng.hash2(m.id, 37) - 0.5) * 6 * spread
		if absf(tx - m.to_x) < 0.01 and absf(ty - m.to_y) < 0.01 and not instant:
			continue
		m.from_x = m.x
		m.from_y = m.y
		m.to_x = tx
		m.to_y = ty
		if instant:
			m.x = tx
			m.from_x = tx
			m.y = ty
			m.from_y = ty
			m.t = 1.0
			m.dur = 0.0
			continue
		m.t = 0.0
		m.dur = dur
		m.delay = delay + stagger * i


## Choose who falls to a blow coming from world direction `from` (relative to
## the squad) and start their falls, one after another.
## `from` is a point `{x, y}` (or a Vector2).
static func kill_members(members: Array, count: int, from: Variant, champion: int, gap: float = 0.07) -> Array:
	var live := standing(members)
	var positions: Array = []
	var idxs: Array = []
	var champ_idx := -1
	for i in live.size():
		positions.append({"x": live[i].to_x, "y": live[i].to_y})
		idxs.append(i)
		if live[i].id == champion and champ_idx < 0:
			champ_idx = i
	var idx := Formation.pick_casualties(positions, idxs, count, from, champ_idx)
	var out: Array = []
	for i in idx:
		out.append(live[i])
	var len := JS.hypot(from.x, from.y)
	if len == 0.0:
		len = 1.0
	for k in out.size():
		var m: Member = out[k]
		m.alive = false
		m.dying = true
		m.death_t = 0.0
		m.death_delay = k * gap
		m.flash = 1.0
		m.pose = "idle"
		m.key = ""
		# Knocked back from the blow before falling.
		m.lunge = Vector2((-from.x / len) * 5, (-from.y / len) * 3)
		m.fall_flip = from.x > 0
	return out


## Advance tweens, flashes and falls. Calls `on_corpse(m)` when a body comes to rest.
static func step_members(members: Array, dt: float, on_corpse: Callable) -> void:
	for m: Member in members:
		m.flash = maxf(0.0, m.flash - dt * 4)
		if m.face_wait > 0:
			m.face_wait -= dt
			if m.face_wait <= 0:
				m.face = m.face_next
		elif m.face_t > 0:
			m.face_t -= dt
			if m.face_t <= 0:
				m.face = -1
		m.shake = maxf(0.0, m.shake - dt * 3)
		if m.t < 1:
			if m.delay > 0:
				m.delay -= dt
			else:
				m.t = minf(1.0, m.t + dt / m.dur) if m.dur > 0 else 1.0
				var k := ease_in_out_quad(m.t)
				m.x = m.from_x + (m.to_x - m.from_x) * k
				m.y = m.from_y + (m.to_y - m.from_y) * k
		if m.dying:
			if m.death_delay > 0:
				m.death_delay -= dt
			else:
				m.death_t = minf(1.0, m.death_t + dt / m.death_dur)
				if m.death_t >= 1:
					m.dying = false
					on_corpse.call(m)


## True while any soldier is still falling or walking to a new slot.
static func members_busy(members: Array) -> bool:
	for m in members:
		if m.dying or m.t < 1:
			return true
	return false


## iso.ts easeInOutQuad (kept local: the formation tween must not depend on the render stack).
static func ease_in_out_quad(t: float) -> float:
	return 2 * t * t if t < 0.5 else 1 - pow(-2 * t + 2, 2) / 2
