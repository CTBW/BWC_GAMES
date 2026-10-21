## Port of src/campaign/autoplay.ts: an automated player for the whole loop.
## Used by tests, the balance simulator and the in-game debug API. It makes
## reasonable, not optimal, decisions.
## Use through `const Autoplay = preload("res://scripts/campaign/autoplay.gd")`.
extends RefCounted

const JS = preload("res://scripts/core/js.gd")
const DB = preload("res://scripts/data/db.gd")
const Battle = preload("res://scripts/rules/battle.gd")
const Ai = preload("res://scripts/rules/ai.gd")
const Setup = preload("res://scripts/rules/setup.gd")
const Game = preload("res://scripts/meta/game.gd")
const Soldier = preload("res://scripts/meta/soldier.gd")
const Expedition = preload("res://scripts/campaign/expedition.gd")

## The autoplayer turns home when its squads hold fewer than this share of the soldiers who marched out.
const RETREAT_STRENGTH := 0.4


## Prepares and launches an expedition from the garrison. False when fewer than
## three squads can march. (`rng` is unused, as in the original.)
static func auto_prepare(g: Dictionary, _rng: RefCounted = null) -> bool:
	# Bring thinned squads back to strength first (veterans first), keeping silver for supplies.
	var by_level: Array = JS.sort(g.roster.duplicate(), func(a: Dictionary, b: Dictionary) -> int: return b.level - a.level)
	for s in by_level:
		while Game.missing_men(s) > 0 and g.resources.silver - Game.reinforce_cost(g, s) >= 70:
			if not Game.reinforce(g, s.id):
				break
	# Keep a roster of seven or eight.
	for r in g.recruits.duplicate():
		if g.roster.size() >= mini(8, Game.roster_cap(g)):
			break
		if g.resources.silver > 150:
			Game.hire(g, r.id)
	# Rest the badly shaken and treat serious injuries when there is spare silver.
	for s in g.roster:
		if s.morale < Soldier.soldier_stats(s).morale * 0.4 and g.resources.silver > 140:
			Game.grant_leave(g, s.id)
		for inj in s.injuries.duplicate():
			if g.resources.silver > 160 and not s.get("recovering", false):
				Game.treat(g, s.id, inj)
	var c: Dictionary = Game.available_campaigns(g)[0]
	var lim := Game.army_limits(g, c)
	var order: Array = g.roster.filter(func(s: Dictionary) -> bool: return Game.eligibility(g, s, c).ok)
	JS.sort(order, func(a: Dictionary, b: Dictionary) -> int:
		var d: int = b.level - a.level
		return d if d != 0 else b.hp - a.hp
	)
	var army: Array = []
	var want := {"footman": 2, "spearman": 2, "crossbowman": 2}
	# The royal guard stands in the line like footmen.
	var role := func(t: String) -> String: return "footman" if t == "collie_guard" else t
	for s in order:
		if army.size() >= lim.slots:
			break
		var rl: String = role.call(s.typeId)
		if want.get(rl, 0) <= 0:
			continue
		if Game.army_command(g, army) + Soldier.command_cost(s) > lim.command:
			continue
		army.append(s.id)
		want[rl] -= 1
	for s in order:
		if army.has(s.id) or army.size() >= lim.slots:
			continue
		if Game.army_command(g, army) + Soldier.command_cost(s) <= lim.command:
			army.append(s.id)
	if army.size() < 3:
		return false
	var xb := 0
	for id in army:
		for s in g.roster:
			if s.id == id:
				if s.typeId == "crossbowman":
					xb += 1
				break
	var sup := Game.recommended_supplies(army.size(), xb, Game.wagon_capacity(g), c.stages + 1)
	while Game.supply_weight(sup) > Game.wagon_capacity(g):
		sup.rations -= 1
	while Game.supply_cost_total(g, sup) > g.resources.silver and sup.rations > 4:
		sup.rations -= 1
	while Game.supply_cost_total(g, sup) > g.resources.silver:
		var k: Variant = null
		for x in ["tools", "torches", "bandages", "bolts"]:
			if sup[x] > 0:
				k = x
				break
		if k == null:
			break
		sup[k] -= 1
	Expedition.start_expedition(g, c.id, army, sup, Game.supply_cost_total(g, sup))
	return true


## Fights a battle with the AI on both sides (a sensible captain retreats from a lost field).
static func auto_battle(b: RefCounted, max_turns: int = 30) -> void:
	var enemy_ai := Callable(Ai, "run_enemy_ai")
	b.begin(enemy_ai)
	while not b.is_over() and b.turn <= max_turns:
		Ai.run_player_auto(b)
		if b.is_over():
			break
		b.end_turn(enemy_ai)
		# A sensible captain pulls out of a fight he has clearly lost, to save the company.
		if not b.is_over() and b.phase == "player":
			var company: Array = b.company()
			var foes: int = b.active("enemy").size()
			if not company.is_empty() and (b.strength("player") < 0.3 or (company.size() <= 2 and foes >= company.size() * 3)):
				b.retreat()
	if not b.is_over():
		b.retreat()


## Plays the current expedition to its end. Returns the outcome
## ("success" | "retreat" | "defeat"). opts: {retreatBelow?, retreatStrength?}.
static func auto_expedition(g: Dictionary, rng: RefCounted, opts: Dictionary = {}) -> String:
	var pref := {"camp": 3, "village": 2.5, "event": 2, "scout": 2.2, "battle": 1, "ambush": 1, "objective": 5}
	var score := func(n: Dictionary) -> float: return float(pref.get(n.type, 1)) + rng.next()
	var guard := 0
	while g.expedition != null and guard < 200:
		guard += 1
		var ex: Dictionary = g.expedition
		var p: Variant = ex.pending
		if p == null:
			# Retreat if the army is in tatters: too few squads, or too few soldiers
			# left in them (unless the objective is the next march).
			var alive: int = ex.army.size()
			if alive <= JS.get_or(opts, "retreatBelow", 1):
				return Expedition.return_home(g, "retreat").outcome
			var nxt := Expedition.next_nodes(ex)
			var men := 0
			for s in Expedition.army_soldiers(g):
				men += s.men
			var objective_next := nxt.any(func(n: Dictionary) -> bool: return n.type == "objective")
			var start_men: int = JS.get_or(ex, "startMen", 0)
			if start_men and men < start_men * float(JS.get_or(opts, "retreatStrength", RETREAT_STRENGTH)) and not objective_next:
				return Expedition.return_home(g, "retreat").outcome
			if nxt.is_empty():
				return Expedition.return_home(g, "success" if ex.objectiveDone else "retreat").outcome
			var prefer: Array = v8_sort(nxt.duplicate(), func(a: Dictionary, b: Dictionary) -> float:
				var sb: float = score.call(b)
				var sa: float = score.call(a)
				return sb - sa
			)
			Expedition.march(g, prefer[0].id)
			continue
		match p.kind:
			"arrive", "scout":
				Expedition.dismiss_pending(g)
			"event":
				if p.get("result") == null:
					var ev: Dictionary = Expedition._event(p.eventId)
					var idx := -1
					for i in ev.choices.size():
						if Expedition.choice_available(g, ev.choices[i]).ok:
							idx = i
							break
					Expedition.choose_event(g, maxi(0, idx))
				Expedition.dismiss_pending(g)
			"camp":
				if ex.supplies.torches > 0:
					Expedition.camp_watch(g)
				Expedition.camp_rest(g)
				if _pending_kind(g) == "camp":
					Expedition.dismiss_pending(g)
			"village":
				for i in p.spots.size():
					if _pending_kind(g) != "village":
						break
					if not p.spots[i].locked or ex.supplies.tools > 0:
						Expedition.search_spot(g, i)
				if _pending_kind(g) == "village":
					Expedition.dismiss_pending(g)
			"battle":
				var night := Expedition.prepare_night(g)
				var setup := Setup.build_battle(p.roll, Expedition.battle_army(g), {"survivalBonus": Expedition.survival_bonus(g), "title": p.title, "darkness": night.darkness})
				var b := Battle.new(setup)
				auto_battle(b)
				Expedition.apply_battle(g, b, p.title, p.objective)
			"battleResult":
				Expedition.dismiss_pending(g)
			"complete":
				return Expedition.return_home(g, "success").outcome
	# A defeat sends the army home from inside dismiss_pending; report how it ended.
	if g.expedition != null:
		return Expedition.return_home(g, "retreat").outcome
	var last: Variant = g.get("lastReport")
	return last.outcome if last != null else "done"


static func _pending_kind(g: Dictionary) -> Variant:
	var ex: Variant = g.expedition
	if ex == null or ex.pending == null:
		return null
	return ex.pending.kind


## Array.prototype.sort exactly as V8 runs it (TimSort) for arrays shorter than
## 64: one natural run (reversed if descending), then binary insertion. The
## comparator calls happen in V8's order, which matters when the comparator
## draws random numbers (auto_expedition's route choice). Longer arrays use the
## stable JS.sort (same result for any consistent comparator).
static func v8_sort(arr: Array, cmp: Callable) -> Array:
	var n := arr.size()
	if n < 2:
		return arr
	if n >= 64:
		return JS.sort(arr, cmp)
	# CountAndMakeRun(0, n)
	var run_len := 2
	var order := _cmp_num(cmp.call(arr[1], arr[0]))
	var desc := order < 0
	var prev: Variant = arr[1]
	for idx in range(2, n):
		var cur: Variant = arr[idx]
		order = _cmp_num(cmp.call(cur, prev))
		if desc:
			if order >= 0:
				break
		elif order < 0:
			break
		prev = cur
		run_len += 1
	if desc:
		var lo := 0
		var hi := run_len - 1
		while lo < hi:
			var t: Variant = arr[lo]
			arr[lo] = arr[hi]
			arr[hi] = t
			lo += 1
			hi -= 1
	# BinaryInsertionSort(0, run_len, n)
	for start in range(run_len, n):
		var left := 0
		var right := start
		var pivot: Variant = arr[start]
		while left < right:
			var mid := left + ((right - left) >> 1)
			if _cmp_num(cmp.call(pivot, arr[mid])) < 0:
				right = mid
			else:
				left = mid + 1
		var p := start
		while p > left:
			arr[p] = arr[p - 1]
			p -= 1
		arr[left] = pivot
	return arr


static func _cmp_num(v: Variant) -> float:
	var f := float(v)
	return 0.0 if is_nan(f) else f
