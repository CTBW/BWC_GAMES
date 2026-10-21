## Port of src/ui/screens/Base.tsx `Base`: the garrison screen over the camp
## view — top bar, Company Chronicle (latest entry / earlier entries), the
## hovered building's name, Roster and Plan Expedition, and the overlays: a
## building panel / the roster / the fallen (App.panel), the soldier detail
## (App.soldier) and the welcome letter on the first visit.
## Re-renders on App.changed: cheap parts always, panels only when the game or
## the open panel changed (keeping their scroll position, as React keeps the DOM).
extends Control

const UI = preload("res://scripts/ui/ui.gd")
const DB = preload("res://scripts/data/db.gd")
const Deps = preload("res://scripts/ui/deps.gd")
const Modal = preload("res://scripts/ui/widgets/modal.gd")
const ScrollBox = preload("res://scripts/ui/widgets/scroll_box.gd")
const TopBar = preload("res://scripts/ui/screens/top_bar.gd")
const BuildingPanel = preload("res://scripts/ui/screens/building_panel.gd")
const RosterPanel = preload("res://scripts/ui/screens/roster_panel.gd")
const Memorial = preload("res://scripts/ui/screens/memorial.gd")
const SoldierDetail = preload("res://scripts/ui/screens/soldier_detail.gd")

var top_bar: PanelContainer
var chronicle: PanelContainer
var chronicle_open := true
var _chron_list: VBoxContainer
var _chron_toggle: Button
var hover_tip: PanelContainer
var _hover_name: Label
var _hover_role: Label
var roster_button: Button
var plan_button: Button
var panel_overlay: Control = null
var soldier_overlay: Control = null
var welcome_overlay: Control = null
var _panel_key := ""
var _soldier_key := ""
var _sig := ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	top_bar = TopBar.new()
	top_bar.name = "TopBar"
	add_child(top_bar)
	# Company Chronicle.
	chronicle = UI.panel("DarkPanel", [10, 14])
	chronicle.name = "Chronicle"
	chronicle.position = Vector2(14, 68)
	chronicle.custom_minimum_size.x = 300
	var cc := UI.vbox(0)
	chronicle.add_child(cc)
	var t := UI.title_block("Company Chronicle", 17)
	cc.add_child(t)
	_chron_list = UI.vbox(6)
	cc.add_child(ScrollBox.make(_chron_list, 240))
	_chron_toggle = UI.button("", "GhostSmallButton", func():
		chronicle_open = not chronicle_open
		_build_chronicle())
	_chron_toggle.name = "ChronicleToggle"
	_chron_toggle.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cc.add_child(UI.gap(0, 2))
	cc.add_child(_chron_toggle)
	add_child(chronicle)
	# Hovered building.
	hover_tip = UI.panel("DarkPanel", [8, 16])
	hover_tip.name = "HoverTip"
	hover_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hc := UI.vbox(0)
	hover_tip.add_child(hc)
	_hover_name = UI.cinzel("")
	_hover_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hc.add_child(_hover_name)
	_hover_role = UI.label("", "SmallMutedLabel")
	_hover_role.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hc.add_child(_hover_role)
	hover_tip.visible = false
	add_child(hover_tip)
	# Roster and Plan Expedition.
	var br := UI.hbox(12)
	br.name = "Actions"
	br.alignment = BoxContainer.ALIGNMENT_END
	br.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	br.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	br.grow_vertical = Control.GROW_DIRECTION_BEGIN
	br.offset_right = -18
	br.offset_bottom = -18
	br.offset_left = -18
	br.offset_top = -18
	roster_button = UI.button("Roster", "BigButton", func(): App.open_panel("roster"))
	roster_button.name = "Roster"
	plan_button = UI.button("Plan Expedition", "RedBigButton", func(): App.go_prep())
	plan_button.name = "PlanExpedition"
	br.add_child(roster_button)
	br.add_child(plan_button)
	add_child(br)
	_pulse(plan_button)
	refresh()


## `.pulse`: brightness 1 → 1.3 → 1 over 1.6 s, forever.
func _pulse(c: Control) -> void:
	if not c.is_inside_tree():
		return
	var tw := c.create_tween().set_loops()
	tw.tween_property(c, "modulate", Color(1.3, 1.3, 1.3), 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(c, "modulate", Color(1, 1, 1), 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _game_sig() -> String:
	return str(JSON.stringify(App.game).hash())


func refresh() -> void:
	var g: Variant = App.game
	if g == null:
		return
	var sig := _game_sig()
	var changed := sig != _sig
	_sig = sig
	top_bar.refresh()
	if changed:
		_build_chronicle()
		roster_button.text = "Roster (%d)" % g.roster.size()
	_update_hover()
	_sync_panel(changed)
	_sync_soldier(changed)
	_sync_welcome()


func _build_chronicle() -> void:
	var g: Dictionary = App.game
	UI.clear(_chron_list)
	var n := 9 if chronicle_open else 1
	for c in g.chronicle.slice(0, n):
		var tone: String = str(c.get("tone", "neutral"))
		var col := "#ffb0a0" if tone == "bad" else ("#c8eab0" if tone == "good" else "#efe2c2")
		var r := UI.rich("[font_size=12][color=#b8a27c]Exp. %d · [/color][/font_size][color=%s]%s[/color]" % [c.cycle, col, UI.esc(c.text)], "BodyText")
		r.add_theme_font_size_override("normal_font_size", 14)
		r.add_theme_font_size_override("bold_font_size", 14)
		r.add_theme_constant_override("line_separation", 1)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_chron_list.add_child(r)
	_chron_toggle.visible = g.chronicle.size() > 1
	_chron_toggle.text = "Latest only" if chronicle_open else "Earlier entries (%d)" % (mini(9, g.chronicle.size()) - 1)


func _update_hover() -> void:
	var v := App.base_view
	var hover: Variant = null
	if v != null and is_instance_valid(v) and v.get("ui") is Dictionary:
		hover = v.ui.get("hover")
	if hover == null or hover == "" or App.panel != null:
		hover_tip.visible = false
		return
	var g: Dictionary = App.game
	var b := DB.building_by_id(hover)
	if b.is_empty():
		hover_tip.visible = false
		return
	var lvl: int = Deps.game().level(g, hover)
	_hover_name.text = b.levels[lvl - 1].name
	_hover_role.text = "%s Click to enter." % b.role
	hover_tip.visible = true
	hover_tip.reset_size()
	var vp := get_viewport_rect().size
	hover_tip.position = Vector2(roundf((vp.x - hover_tip.size.x) * 0.5), vp.y - 26 - hover_tip.size.y)


func _vh() -> float:
	return get_viewport_rect().size.y if is_inside_tree() else 1080.0


func _sync_panel(game_changed: bool) -> void:
	var key: String = str(App.panel) if App.panel != null else ""
	if key == "":
		if panel_overlay != null:
			panel_overlay.queue_free()
			panel_overlay = null
		_panel_key = ""
		return
	if key == _panel_key and not game_changed and panel_overlay != null:
		return
	var reopen := key != _panel_key or panel_overlay == null
	var scroll := 0
	if panel_overlay != null:
		scroll = _scroll_of(panel_overlay)
		panel_overlay.queue_free()
	var d: Control
	if key == "roster":
		d = RosterPanel.make(_vh())
	elif key == "memorial":
		d = Memorial.make(_vh())
	else:
		d = BuildingPanel.make(key, _vh())
	panel_overlay = Modal.make(d, func(): App.open_panel(null), reopen)
	panel_overlay.name = "PanelOverlay"
	add_child(panel_overlay)
	_panel_key = key
	if not reopen and scroll > 0:
		_restore_scroll(panel_overlay, scroll)
	# Keep the soldier detail and the welcome above the panel.
	if soldier_overlay != null:
		move_child(soldier_overlay, -1)


func _scroll_of(n: Node) -> int:
	for s in n.find_children("*", "ScrollContainer", true, false):
		return (s as ScrollContainer).scroll_vertical
	return 0


func _restore_scroll(n: Node, v: int) -> void:
	for i in 3:
		await get_tree().process_frame
		if not is_instance_valid(n):
			return
		for s in n.find_children("*", "ScrollContainer", true, false):
			(s as ScrollContainer).scroll_vertical = v
			break


func _sync_soldier(game_changed: bool) -> void:
	var key: String = str(App.soldier) if App.soldier != null else ""
	if key == "":
		if soldier_overlay != null:
			soldier_overlay.queue_free()
			soldier_overlay = null
		_soldier_key = ""
		return
	if key != _soldier_key or soldier_overlay == null:
		if soldier_overlay != null:
			soldier_overlay.queue_free()
		soldier_overlay = SoldierDetail.make(key)
		add_child(soldier_overlay)
		_soldier_key = key
	elif game_changed:
		soldier_overlay.refresh()


## Esc on the soldier detail saves a changed name like Close.
func close_soldier() -> void:
	if soldier_overlay != null and is_instance_valid(soldier_overlay):
		soldier_overlay.close()
	else:
		App.open_soldier(null)


func _sync_welcome() -> void:
	var g: Dictionary = App.game
	var flags: Variant = g.get("flags")
	var show: bool = not (flags is Dictionary and flags.get("welcome", false) == true) and App.panel == null
	if show and welcome_overlay == null:
		welcome_overlay = Memorial.welcome()
		add_child(welcome_overlay)
	elif not show and welcome_overlay != null:
		welcome_overlay.queue_free()
		welcome_overlay = null
