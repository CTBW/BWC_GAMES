## Windowed captures of the campaign and battle HUDs (scripts/ui/campaign_hud.gd,
## scripts/ui/battle_hud.gd) in the running game: scenes/main.tscn hosts them as
## it does in play, the App store drives the flow. For comparison with the
## original's captures in projects/meridius/review (loop4/, squads-expedition/,
## squads-final-trolls/, squads-input/).
##
##   tools/godot.sh --path . --resolution 1920x1080 -s res://tests/visual/capture_hud.gd [-- names…]
##
## Writes tests/visual/out/hud_<name>.png. Names (default: all): campaign_start,
## dialog_arrive, dialog_scout, dialog_event, dialog_event_result, dialog_village,
## dialog_village_after, dialog_camp, dialog_camp_after, dialog_battle,
## dialog_battleResult, dialog_complete, campaign_hover, campaign_retreat,
## battle_deploy, battle_selected, battle_preview, battle_unitinfo, battle_tile,
## battle_enemy, battle_retreat, battle_over.
extends SceneTree

const OUT := "res://tests/visual/out/"
const DB = preload("res://scripts/data/db.gd")
const Expedition = preload("res://scripts/campaign/expedition.gd")
const Setup = preload("res://scripts/rules/setup.gd")
const Battle = preload("res://scripts/rules/battle.gd")
const Autoplay = preload("res://scripts/campaign/autoplay.gd")
const H = preload("res://scripts/ui/hud_common.gd")

var app: Node
var main: Node
var only: PackedStringArray


func _initialize() -> void:
	only = OS.get_cmdline_user_args()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_run.call_deferred()


func _want(name: String) -> bool:
	return only.is_empty() or only.has(name)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String) -> void:
	if not _want(name):
		return
	await _frames(3)
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(OUT + "hud_%s.png" % name))
	print("captured ", name, " ", img.get_size())


func _hud() -> Node:
	return main.screen_host.get_child(0) if main.screen_host.get_child_count() > 0 else null


func _press(text: String) -> bool:
	var h := _hud()
	for b in H.buttons(h):
		if not b.is_queued_for_deletion() and (str(b.name) == text or H.button_text(b).contains(text)) and not b.disabled:
			b.pressed.emit()
			return true
	print("no button ", text)
	return false


func _set_pending(p: Variant) -> void:
	app.game.expedition.pending = p
	app.emit_changed()


func _node_of_type(t: String) -> Variant:
	for n in app.game.expedition.nodes:
		if n.type == t:
			return n
	return null


func _run() -> void:
	app = root.get_node("App")
	app.save_path = "user://capture_hud_save.json"
	app.mark_manual_seen()
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _frames(5)
	app.new_game(4242)
	await _frames(5)
	app.debug_auto_prepare(1)
	await _frames(40)
	var g: Dictionary = app.game
	var ex: Dictionary = g.expedition
	await _shot("campaign_start")

	# Hover a reachable node (the view's hover; the HUD shows its card).
	var view = app.campaign_view
	if view != null and _want("campaign_hover"):
		var nxt: Array = Expedition.next_nodes(ex)
		view.ui["hover"] = nxt[0].id
		app.emit_changed()
		await _shot("campaign_hover")
		view.ui.erase("hover")
		app.emit_changed()

	if _want("campaign_retreat"):
		_press("Retreat home")
		await _frames(20)
		await _shot("campaign_retreat")
		_press("Press on")
		await _frames(2)

	# Dialogs over the map, one pending kind after the other.
	var army: Array = Expedition.army_soldiers(g)
	_set_pending({"kind": "arrive", "nodeId": ex.current})
	await _frames(25)
	await _shot("dialog_arrive")
	var scout: Variant = _node_of_type("scout")
	_set_pending({"kind": "scout", "nodeId": scout.id if scout != null else ex.current})
	await _frames(5)
	await _shot("dialog_scout")
	var ev: Dictionary = DB.EVENTS[0]
	for e in DB.EVENTS:
		if e.id == "old_battlefield":
			ev = e
	_set_pending(null)
	await _frames(2)
	_set_pending({"kind": "event", "nodeId": ex.current, "eventId": ev.id, "subject": army[0].id})
	await _frames(25)
	await _shot("dialog_event")
	_press("Choice0")
	await _frames(5)
	await _shot("dialog_event_result")
	_set_pending(null)
	await _frames(2)
	var vil: Variant = _node_of_type("village")
	_set_pending({"kind": "village", "nodeId": vil.id if vil != null else ex.current, "messages": [], "spots": [
		{"label": "The longhouse", "searched": false, "locked": false},
		{"label": "A collapsed barn", "searched": false, "locked": false},
		{"label": "The well house", "searched": false, "locked": false},
		{"label": "A locked strongbox", "searched": false, "locked": true}]})
	await _frames(25)
	await _shot("dialog_village")
	# Search two spots and the strongbox; a search that wakes raiders turns the
	# dialog into a battle briefing, so retry it from the same state with
	# another roll of the expedition's dice.
	var keep: Dictionary = ex.duplicate(true)
	for spot in [0, 1, 3]:
		for attempt in 8:
			_press("Spot%d" % spot)
			await _frames(3)
			if ex.pending != null and ex.pending.kind == "village":
				keep = ex.duplicate(true)
				break
			for k in keep:
				ex[k] = keep[k].duplicate(true) if keep[k] is Dictionary or keep[k] is Array else keep[k]
			ex.rng = int(ex.rng) + 7919 * (attempt + 1)
			app.emit_changed()
			await _frames(3)
	await _frames(5)
	await _shot("dialog_village_after")
	_set_pending(null)
	await _frames(2)
	var camp: Variant = _node_of_type("camp")
	ex.supplies.torches = maxi(1, int(ex.supplies.torches))
	ex.supplies.tools = maxi(1, int(ex.supplies.tools))
	_set_pending({"kind": "camp", "nodeId": camp.id if camp != null else ex.current, "done": [], "messages": []})
	await _frames(25)
	await _shot("dialog_camp")
	_press("Watch")
	await _frames(2)
	_press("Rest")
	await _frames(5)
	await _shot("dialog_camp_after")
	_set_pending(null)
	await _frames(2)
	_set_pending({"kind": "complete"})
	await _frames(25)
	await _shot("dialog_complete")
	_set_pending(null)
	await _frames(2)

	# A battle result from a real (auto-played) battle.
	var bn: Variant = _node_of_type("battle")
	if _want("dialog_battleResult"):
		var setup := Setup.build_battle(bn.encounter, Expedition.battle_army(g), {"title": "%s at %s" % [DB.encounter_by_id(bn.encounter.encounterId).name, bn.name], "darkness": false})
		var b = Battle.new(setup)
		Autoplay.auto_battle(b)
		var keep_roster: Array = g.roster.duplicate(true)
		var keep_ex: Dictionary = ex.duplicate(true)
		Expedition.apply_battle(g, b, setup.title, false)
		app.emit_changed()
		await _frames(25)
		await _shot("dialog_battleResult")
		g.roster = keep_roster
		g.expedition = keep_ex
		ex = keep_ex
		_set_pending(null)
		await _frames(2)

	# The battle briefing, then the battle itself.
	_set_pending({"kind": "battle", "nodeId": bn.id, "roll": bn.encounter, "title": "%s at %s" % [DB.encounter_by_id(bn.encounter.encounterId).name, bn.name], "objective": false, "surprise": false})
	await _frames(25)
	await _shot("dialog_battle")
	_press("To Battle")
	await _frames(60)
	var bv = app.battle_view
	await _shot("battle_deploy")
	_press("Begin")
	await _wait_idle(bv)
	await _frames(10)
	var bb = bv.b
	# Select the second squad from the company column.
	var players: Array = bb.active("player")
	if players.size() > 1:
		bv.select(players[1].uid)
	await _frames(30)
	await _shot("battle_selected")
	# An attack preview: the selected squad against the nearest enemy, from beside it.
	var sel: Dictionary = bb.unit(bv.ui.selected)
	var target: Dictionary = bb.active("enemy")[0]
	var best := 1e9
	for e in bb.active("enemy"):
		var d: float = absf(e.x - sel.x) + absf(e.y - sel.y)
		if d < best:
			best = d
			target = e
	var pv: Dictionary = bb.preview(sel, target, {})
	pv.target = target.uid
	pv.from = null
	pv.ability = null
	pv.moveFirst = false
	bv.ui.hover.preview = pv
	bv.ui.hover.unit = target.uid
	bv.notify()
	await _frames(5)
	await _shot("battle_preview_illegal")
	# A legal move-and-strike from the free tile beside the target.
	for d in [[1, 0], [0, 1], [-1, 0], [0, -1]]:
		var p := {"x": int(target.x) + d[0], "y": int(target.y) + d[1]}
		if bb.preview_legal(sel, target, {"from": p}):
			pv = bb.preview(sel, target, {"from": p, "movedTiles": 1})
			pv.target = target.uid
			pv.from = p
			pv.ability = null
			pv.moveFirst = true
			bv.ui.hover.preview = pv
			bv.ui.hover.dest = p
			bv.ui.hover.facing = (int(target.facing) + 2) % 4
			bv.notify()
			break
	await _frames(5)
	await _shot("battle_preview")
	bv.ui.hover.preview = null
	bv.ui.hover.unit = target.uid
	bv.notify()
	await _frames(5)
	await _shot("battle_unitinfo")
	bv.ui.hover.unit = null
	bv.ui.hover.tile = {"x": int(sel.x), "y": int(sel.y) - 1}
	bv.notify()
	await _frames(5)
	await _shot("battle_tile")
	bv.ui.hover = {"tile": null, "unit": null, "preview": null, "path": null, "zoc": null, "dest": null, "facing": null, "facings": null, "turn": null}
	bv.notify()
	# The enemy turn, mid-playback.
	_press("EndTurn")
	var seen := -1
	for i in 600:
		await process_frame
		if bv.ui.side == "enemy" and seen < 0:
			seen = i
		if seen >= 0 and i - seen >= 25:
			break
	await _shot("battle_enemy")
	await _wait_idle(bv)
	await _frames(10)
	_press("Retreat")
	await _frames(20)
	await _shot("battle_retreat")
	_press("Withdraw")
	for i in 400:
		await process_frame
		if bv.b.phase == "over" and bv.ui.banner != null and str(bv.ui.banner.text) == "Withdrawal":
			break
	await _frames(15)
	await _shot("battle_over")
	print("done")
	quit(0)


func _wait_idle(bv) -> void:
	for i in 2000:
		await process_frame
		if not bv.busy():
			return
