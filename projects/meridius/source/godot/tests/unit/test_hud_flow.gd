## A whole expedition played through the HUDs with the real App store and
## views: march (App.click_node, as the map does) → each pending dialog
## answered with the campaign HUD's buttons (event choice, camp, village,
## scouting) → battle briefing → To Battle → the battle HUD's Begin Battle →
## the rest fought by App.debug_auto_battle → the battle result → … → Retreat
## home through the confirmation → the report screen. A new HUD is made for
## each screen as main.gd does. The runner has no frames: HUDs are refreshed
## and the battle view advanced by hand.
extends "res://tests/test_case.gd"

const ThemeBuilder = preload("res://scripts/ui/theme_builder.gd")
const H = preload("res://scripts/ui/hud_common.gd")
const Expedition = preload("res://scripts/campaign/expedition.gd")
const CampaignHud = preload("res://scripts/ui/campaign_hud.gd")
const BattleHud = preload("res://scripts/ui/battle_hud.gd")

var app: Node
var host: Control
var hud: Control
var seen := {}
var saved_path := ""


func before_all() -> void:
	app = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("App")


func before_each() -> void:
	if app == null:
		return
	saved_path = app.save_path
	app.save_path = "user://test_hud_flow_save.json"
	host = Control.new()
	host.theme = ThemeBuilder.theme()
	host.size = Vector2(1920, 1080)
	(Engine.get_main_loop() as SceneTree).root.add_child(host)


func after_each() -> void:
	if app == null:
		return
	app.save_path = saved_path
	if host != null and is_instance_valid(host):
		host.get_parent().remove_child(host)
		host.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_hud_flow_save.json"))


func _live(b: Node) -> bool:
	return is_instance_valid(b) and not b.is_queued_for_deletion() and hud.is_ancestor_of(b)


func _button(text: String) -> BaseButton:
	var live: Array = H.buttons(hud).filter(func(b): return _live(b))
	for b in live:
		if str(b.name) == text:
			return b
	for b in live:
		if H.button_text(b).contains(text):
			return b
	return null


## Presses a HUD button (it must exist and be enabled), then refreshes the HUD.
func _press(text: String) -> bool:
	var b := _button(text)
	if not assert_not_null(b, "button '%s' on %s" % [text, app.screen]):
		return false
	if not assert_false(b.disabled, "'%s' enabled" % text):
		return false
	b.pressed.emit()
	_screen_hud()
	return true


## The HUD main.gd would show for App.screen (made anew when the screen changes).
func _screen_hud() -> void:
	var want: GDScript = CampaignHud if app.screen == "campaign" else (BattleHud if app.screen == "battle" else null)
	if want == null:
		if hud != null and is_instance_valid(hud):
			hud.get_parent().remove_child(hud)
			hud.free()
		hud = null
		return
	if hud == null or not is_instance_valid(hud) or hud.get_script() != want:
		if hud != null and is_instance_valid(hud):
			hud.get_parent().remove_child(hud)
			hud.free()
		hud = want.new()
		host.add_child(hud)
	hud.refresh()


func _pick_next() -> Variant:
	var ex: Dictionary = app.game.expedition
	var nxt: Array = Expedition.next_nodes(ex)
	if nxt.is_empty():
		return null
	# Prefer what this test has not seen yet; the objective last.
	var order := ["event", "camp", "battle", "village", "scout", "ambush", "objective"]
	var best: Variant = nxt[0]
	var best_score := 99
	for n in nxt:
		var k: String = "battle" if n.type == "ambush" else n.type
		var score: int = order.find(n.type) + (10 if seen.has(k) else 0)
		if n.type == "objective":
			score += 20
		if score < best_score:
			best_score = score
			best = n
	return best


func _fight() -> void:
	var bv: Node = app.battle_view
	assert_not_null(bv, "battle view")
	if bv == null:
		return
	bv.threaded_rules = false
	_screen_hud()
	assert_eq(app.screen, "battle")
	assert_true(hud.get_script() == BattleHud, "battle HUD")
	assert_eq(bv.b.phase, "deploy", "deployment first")
	_press("Begin")
	assert_ne(bv.b.phase, "deploy", "Begin Battle starts it")
	app.debug_auto_battle()
	for i in 20000:
		if app.screen != "battle":
			break
		bv.advance(0.05)
		if i % 50 == 0 and app.screen == "battle":
			hud.refresh()
	assert_eq(app.screen, "campaign", "the end of the battle returns to the map")
	_screen_hud()


func test_expedition_through_the_huds() -> void:
	if app == null:
		skip("no App autoload")
		return
	seen = {}
	# Seed 7: events, a battle, scouts and camps within the first marches.
	app.new_game(7)
	assert_true(app.debug_auto_prepare(1), "an expedition launches")
	assert_eq(app.screen, "campaign")
	_screen_hud()
	assert_true(hud.get_script() == CampaignHud, "campaign HUD")
	assert_not_null(hud.get_node_or_null("TopBar"), "top bar")
	var steps := 0
	while steps < 80 and app.screen == "campaign":
		steps += 1
		hud.refresh()
		var kind: String = hud.dialog_kind()
		if kind == "":
			# Once the main kinds have been played, sound the retreat.
			if seen.has("event") and seen.has("camp") and seen.has("battleResult"):
				break
			var n: Variant = _pick_next()
			if n == null:
				break
			app.click_node(n.id)
			_screen_hud()
			continue
		seen[kind] = true
		match kind:
			"arrive", "scout":
				_press("Continue")
			"event":
				var p: Dictionary = app.game.expedition.pending
				if p.get("result") == null:
					var picked := false
					for b in H.buttons(hud):
						if _live(b) and str(b.name).begins_with("Choice") and not b.disabled:
							b.pressed.emit()
							picked = true
							break
					assert_true(picked, "an event choice is available")
					hud.refresh()
					assert_not_null(app.game.expedition.pending.get("result"), "the choice has a result")
				else:
					_press("To arms!" if p.get("followBattle") != null else "Continue")
			"camp":
				for name in ["Watch", "Repair", "Rest"]:
					var b := _button(name)
					if b != null and not b.disabled:
						b.pressed.emit()
						hud.refresh()
				if hud.dialog_kind() == "camp":
					assert_true(app.game.expedition.pending.messages.size() > 0, "camp messages")
					_press("Break camp")
			"village":
				var b := _button("Spot0")
				if b != null and not b.disabled:
					b.pressed.emit()
					hud.refresh()
				if hud.dialog_kind() == "village":
					_press("Move on")
			"battle":
				_press("To Battle")
				_fight()
			"battleResult":
				var r: Dictionary = app.game.expedition.pending.report
				_press("Retreat home" if r.result == "defeat" else "Continue")
			"complete":
				_press("Return to Amberfeld")
	assert_true(seen.has("battle") and seen.has("battleResult"), "fought a battle: %s" % [seen.keys()])
	assert_true(seen.has("event"), "an event: %s" % [seen.keys()])
	if app.screen == "campaign":
		# Retreat home through the confirmation.
		_press("Retreat home")
		assert_not_null(hud.get_node_or_null("Confirm"), "confirmation")
		_press("Retreat")
	assert_eq(app.screen, "report", "home: the report screen")
	assert_eq(app.game.get("expedition"), null, "the expedition is over")
	assert_not_null(app.report, "a report")
