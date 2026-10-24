## Battle rules and AI regression traces.
##
## Golden data: tests/fixtures/golden/battle/*.json, first recorded from the
## original TypeScript game by tools/parity/battle_traces.ts, which proved the
## port identical to it. The original is archived; since then the port owns
## the traces: after a deliberate rule change, re-record them with
##   MERIDIUS_RECORD=1 tools/test.sh test_battle_parity
## (same replays; what the port does is written back), review the diff, commit.
## Each trace holds a BattleSetup (rollEncounter + buildBattle with a newGame
## company) and the steps of a whole battle:
## - "auto" traces: the loop of autoBattle (campaign/autoplay.gd) with the AI
##   on both sides; after every step the drained events and a state snapshot
##   must match exactly.
## - "script" traces: explicit API calls (queries with their results, actions
##   with their results, events and state).
## The first divergence is reported with its context.
extends "res://tests/test_case.gd"

const H = preload("res://tests/parity/test_meta_support.gd")
const JS = preload("res://scripts/core/js.gd")
const Battle = preload("res://scripts/rules/battle.gd")
const Ai = preload("res://scripts/rules/ai.gd")
const Grid = preload("res://scripts/rules/grid.gd")

const DIR := "res://tests/fixtures/golden/battle/"

var stats := {"traces": 0, "steps": 0, "events": 0, "queries": 0}
## Re-recording: replays write their results into the traces instead of comparing.
var recording := H.recording()
var _rec: Array = []


func test_goblin_scouts() -> void:
	_run_group("goblin_scouts")


func test_stragglers() -> void:
	_run_group("stragglers")


func test_raiding_party() -> void:
	_run_group("raiding_party")


func test_archer_screen() -> void:
	_run_group("archer_screen")


func test_orc_overseer() -> void:
	_run_group("orc_overseer")


func test_brute_vanguard() -> void:
	_run_group("brute_vanguard")


func test_moss_trolls() -> void:
	_run_group("moss_trolls")


func test_road_ambush() -> void:
	_run_group("road_ambush")


func test_shaman_fire() -> void:
	_run_group("shaman_fire")


func test_siege_train() -> void:
	_run_group("siege_train")


## Battle mages, ballistae and mangonels with the company (auto battles and scripted spells).
func test_magic() -> void:
	_run_group("magic")


func test_refugee_stand() -> void:
	if slow():
		return
	_run_group("refugee_stand")


func test_warband_camp() -> void:
	if slow():
		return
	_run_group("warband_camp")


func test_last_stand() -> void:
	if slow():
		return
	_run_group("last_stand")


func test_extra() -> void:
	if slow():
		return
	_run_group("extra")


func test_scripted() -> void:
	_run_group("scripted")


func after_all() -> void:
	print("      battle parity: %d traces, %d steps, %d events, %d query results matched" % [stats.traces, stats.steps, stats.events, stats.queries])


# ------------------------------------------------------------------ driver

func _run_group(group: String) -> void:
	var path := DIR + group + ".json"
	if not FileAccess.file_exists(path):
		fail("missing golden file %s (run tools/parity/battle_traces.ts)" % path)
		return
	var f := FileAccess.open(path, FileAccess.READ)
	var data: Variant = JSON.parse_string(f.get_as_text())
	if not (data is Dictionary):
		fail("cannot parse %s" % path)
		return
	data = JS.normalize(data)
	for trace in data.traces:
		var t0 := Time.get_ticks_msec()
		var err: String
		if trace.kind == "auto":
			err = _replay_auto(trace)
		else:
			err = _replay_script(trace)
		var ms := Time.get_ticks_msec() - t0
		if err != "":
			fail("%s: %s" % [trace.name, err])
		else:
			stats.traces += 1
			print("      %s %s (%d steps, %d ms)" % [trace.name, "recorded" if recording else "ok", trace.steps.size(), ms])
	if recording:
		H.write_golden(path, data)


## The autoBattle loop of campaign/autoplay.ts, checked step by step.
func _replay_auto(trace: Dictionary) -> String:
	var b = Battle.new(trace.setup.duplicate(true))
	var steps: Array = trace.steps
	_rec = []
	var idx := 0
	var err := ""
	if b.phase == "deploy":
		b.begin(Ai.run_enemy_ai)
		err = _check(b, steps, idx, "begin")
		idx += 1
		if err != "":
			return err
	while not b.is_over() and b.turn <= 30:
		Ai.run_player_auto(b)
		err = _check(b, steps, idx, "player")
		idx += 1
		if err != "":
			return err
		if b.is_over():
			break
		b.end_turn(Ai.run_enemy_ai)
		err = _check(b, steps, idx, "end")
		idx += 1
		if err != "":
			return err
		# A sensible captain pulls out of a fight he has clearly lost, to save the company.
		if not b.is_over() and b.phase == "player":
			var company: Array = b.company()
			var foes: int = b.active("enemy").size()
			if company.size() > 0 and (b.strength("player") < 0.3 or (company.size() <= 2 and foes >= company.size() * 3)):
				b.retreat()
				err = _check(b, steps, idx, "retreat")
				idx += 1
				if err != "":
					return err
	if not b.is_over():
		b.retreat()
		err = _check(b, steps, idx, "retreat")
		idx += 1
		if err != "":
			return err
	if recording:
		trace.steps = _rec
		trace.result = b.result
		trace.turns = b.turn
		return ""
	if idx != steps.size():
		return "the port ended after %d steps, the original after %d" % [idx, steps.size()]
	if not _same(b.result, trace.result):
		return "result %s, expected %s" % [b.result, trace.result]
	return ""


func _check(b, steps: Array, idx: int, op: String) -> String:
	if recording:
		_rec.append({"op": op, "events": H.jsonable(b.drain()), "state": H.jsonable(snapshot(b))})
		return ""
	if idx >= steps.size():
		return "the port takes an extra step '%s' (turn %d)" % [op, b.turn]
	var s: Dictionary = steps[idx]
	var events: Array = b.drain()
	if s.op != op:
		return "step %d: the original did '%s', the port '%s' (turn %d)" % [idx, s.op, op, b.turn]
	stats.steps += 1
	return _check_events_state(b, s, idx, events)


func _check_events_state(b, s: Dictionary, idx: int, events: Array) -> String:
	var want: Array = s.get("events", [])
	var n := mini(want.size(), events.size())
	for i in n:
		var d := _diff(events[i], want[i], "")
		if d != "":
			return "step %d '%s' (turn %d), event %d differs at %s\n          expected %s\n          got      %s\n          before:  %s" % [
				idx, s.op, s.state.turn, i, d, _show(want[i]), _show(events[i]), _context(want, i)]
	if want.size() != events.size():
		var extra: Variant = events[n] if events.size() > n else want[n]
		return "step %d '%s' (turn %d): %d events, expected %d; first unmatched %s %s\n          before:  %s" % [
			idx, s.op, s.state.turn, events.size(), want.size(), "(port)" if events.size() > n else "(original)", _show(extra), _context(want, n)]
	stats.events += events.size()
	var d := _diff(snapshot(b), s.state, "state")
	if d != "":
		return "step %d '%s' (turn %d): state differs at %s" % [idx, s.op, s.state.turn, d]
	return ""


func _context(evs: Array, i: int) -> String:
	var out: Array = []
	for j in range(maxi(0, i - 3), i):
		out.append(_show(evs[j]))
	return " | ".join(out)


# ------------------------------------------------------------------ scripted

func _replay_script(trace: Dictionary) -> String:
	var b = Battle.new(trace.setup.duplicate(true))
	var steps: Array = trace.steps
	for idx in steps.size():
		var s: Dictionary = steps[idx]
		var args: Array = s.get("args", [])
		var ret: Variant = null
		var is_action := s.has("state")
		match s.op:
			# ---- actions
			"deploySwap":
				ret = b.deploy_swap(args[0], args[1], args[2])
			"begin":
				b.begin(Ai.run_enemy_ai)
			"move":
				ret = b.move(args[0], args[1], args[2], args[3])
			"redoMove":
				ret = b.redo_move(args[0])
			"attack":
				ret = b.attack(args[0], args[1], args[2])
			"useStance":
				ret = b.use_stance(args[0], args[1])
			"shout":
				ret = b.shout(args[0], args[1])
			"endUnit":
				b.end_unit(args[0])
			"endTurn":
				b.end_turn(Ai.run_enemy_ai)
			"retreat":
				b.retreat()
			"playerAuto":
				Ai.run_player_auto(b)
			"cast":
				ret = b.cast(args[0], args[1], {"x": args[2], "y": args[3]})
			"actUnit":
				Ai.act_unit(b, b.unit(args[0]), {"useStances": true})
			"setPhase":
				b.phase = args[0]
			"setFlag":
				var u: Dictionary = b.unit(args[0])
				ret = u[args[1]]
				u[args[1]] = args[2]
			# ---- queries
			"company":
				ret = b.company().map(func(u): return u.uid)
			"strength":
				ret = b.strength(args[0])
			"pendingWaves":
				ret = b.pending_waves()
			"nextWave":
				var nw: Variant = b.next_wave()
				ret = null if nw == null else {"index": nw.index, "turn": nw.turn}
			"reachStates":
				ret = _entries(b.reach_states(b.unit(args[0]), args[1] if args.size() > 1 else null))
			"reachable":
				ret = _entries(b.reachable(b.unit(args[0])))
			"zocTiles":
				ret = b.zoc_tiles(b.unit(args[0])).keys()
			"moraleState":
				ret = b.morale_state(b.unit(args[0]))
			"facingTowardFoes":
				ret = b.facing_toward_foes(b.unit(args[0]))
			"isAdjacentEnemy":
				ret = b.is_adjacent_enemy(b.unit(args[0]))
			"facingOptions":
				ret = b.facing_options(b.unit(args[0]), args[1], args[2])
			"defaultFacing":
				var u: Dictionary = b.unit(args[0])
				ret = b.default_facing(u, args[1], args[2], b.facing_options(u, args[1], args[2]))
			"moveOption":
				ret = b.move_option(b.unit(args[0]), args[1], args[2], args[3])
			"pathTo":
				ret = b.path_to(b.unit(args[0]), args[1], args[2])
			"chooseFacing":
				ret = Ai.choose_facing(b, b.unit(args[0]), {"x": args[1], "y": args[2]})
			"exposure":
				ret = Ai.exposure({"x": args[0], "y": args[1]}, args[2], b.active(args[3]))
			"targets":
				ret = b.targets(b.unit(args[0]), args[1], args[2]).map(func(u): return u.uid)
			"preview":
				var opts: Dictionary = args[2]
				ret = b.preview(b.unit(args[0]), b.unit(args[1]), opts)
				if opts.is_empty() and not _same(b.preview_legal(b.unit(args[0]), b.unit(args[1]), opts), ret.legal):
					return "step %d: preview_legal disagrees with preview" % idx
			"arcOf":
				ret = b.arc_of(b.unit(args[0]), {"x": args[1], "y": args[2]})
			"canShoot":
				ret = b.can_shoot(b.unit(args[0]), b.unit(args[1]), args[2])
			"wouldShoot":
				ret = b.would_shoot(b.unit(args[0]), b.unit(args[1]), args[2])
			"canMelee":
				ret = b.can_melee(b.unit(args[0]), b.unit(args[1]), args[2], args[3])
			"canRedo":
				ret = b.can_redo(args[0])
			"los":
				ret = Grid.line_of_sight(b.map, {"x": args[0], "y": args[1]}, {"x": args[2], "y": args[3]})
			"canCast":
				ret = b.can_cast(b.unit(args[0]), args[1])
			"spellTargets":
				ret = b.spell_targets(b.unit(args[0]), args[1], args[2]).map(func(u): return u.uid)
			"spellPreview":
				ret = b.spell_preview(b.unit(args[0]), args[1], {"x": args[2], "y": args[3]}, args[4])
			"impaleTarget":
				var it: Variant = b.impale_target(b.unit(args[0]), b.unit(args[1]))
				ret = null if it == null else it.uid
			_:
				return "step %d: unknown op '%s'" % [idx, s.op]
		if recording:
			s.ret = H.jsonable(ret)
			if is_action:
				s.events = H.jsonable(b.drain())
				s.state = H.jsonable(snapshot(b))
			continue
		var d := _diff(ret, s.get("ret"), "ret")
		if d != "":
			return "step %d '%s' %s: result differs at %s\n          expected %s\n          got      %s" % [idx, s.op, _show(args), d, _show(s.get("ret")), _show(ret)]
		if is_action:
			stats.steps += 1
			var err := _check_events_state(b, s, idx, b.drain())
			if err != "":
				return err
		else:
			stats.queries += 1
	if recording:
		trace.result = b.result
		return ""
	if not _same(b.result, trace.result):
		return "result %s, expected %s" % [b.result, trace.result]
	return ""


static func _entries(m: Dictionary) -> Array:
	var out: Array = []
	for k in m:
		var v: Dictionary = m[k]
		out.append([k, v.cost, v.prev, v.zoc])
	return out


# ------------------------------------------------------------------ state

## The same snapshot as battle_traces.ts.
static func snapshot(b) -> Dictionary:
	var wave_turns: Array = []
	for w in b.waves:
		wave_turns.append(w.turn)
	var records: Array = []
	for k in b.move_records:
		var r: Dictionary = b.move_records[k]
		records.append([k, r.x, r.y, r.facing, r.movedTiles, r.clean, r.path])
	var units: Array = []
	for u in b.units:
		units.append([
			u.uid, u.x, u.y, u.facing, u.hp, u.alive, u.morale, u.status, u.get("stance"), u.hasMoved, u.hasActed, u.done,
			u.movedTiles, u.kills, u.damageDealt, u.xp, u.ammo, u.cooldowns, u.struck, u.get("statuses", []),
		])
	return {
		"turn": b.turn, "phase": b.phase, "result": b.result, "horn": b.horn, "overrun": b.overrun, "rng": b.rng.state,
		"waveState": b.wave_state, "waveTurns": wave_turns, "hitsTaken": b.hits_taken, "moveRecords": records, "units": units,
	}


## Path of the first difference ("" when equal). Absent and null are equal;
## numbers compare as numbers (ints and integral floats are the same).
func _diff(got: Variant, want: Variant, path: String) -> String:
	if (got is int or got is float) and (want is int or want is float):
		return "" if _same(got, want) else "%s (%s != %s)" % [path, JS.num_str(got), JS.num_str(want)]
	if got is Array and want is Array:
		if got.size() != want.size():
			return "%s (length %d != %d)" % [path, got.size(), want.size()]
		for i in got.size():
			var d := _diff(got[i], want[i], "%s[%d]" % [path, i])
			if d != "":
				return d
		return ""
	if got is Dictionary and want is Dictionary:
		for k in want:
			var d := _diff(got.get(k), want[k], "%s.%s" % [path, k])
			if d != "":
				return d
		for k in got:
			if not want.has(k) and got[k] != null:
				return "%s.%s (unexpected %s)" % [path, k, _show(got[k])]
		return ""
	if got == null or want == null:
		return "" if got == want else "%s (%s != %s)" % [path, _show(got), _show(want)]
	if typeof(got) != typeof(want):
		return "%s (%s != %s)" % [path, _show(got), _show(want)]
	return "" if got == want else "%s (%s != %s)" % [path, _show(got), _show(want)]
