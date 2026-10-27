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
var chronicle_open := false
var _chron_list: VBoxContainer
var _chron_latest: VBoxContainer
var _chron_scroll: ScrollContainer
var _chron_toggle: Button
var hover_tip: PanelContainer
var _hover_name: Label
var _hover_role: Label
var roster_button: Button
var plan_button: Button
var _day_button: Button
var _night_button: Button
var _frame_button: Button
var _service_buttons: Dictionary = {}
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
	chronicle.position = Vector2(18, 74)
	chronicle.custom_minimum_size.x = 312
	var cc := UI.vbox(6)
	chronicle.add_child(cc)
	var t := UI.cinzel("Company Chronicle", 14, 700, UI.LIGHT_TITLE)
	cc.add_child(t)
	# Latest-only content sizes directly to the wrapped text. A ScrollContainer
	# can retain its pre-layout height while the RichTextLabel finds its width.
	_chron_latest = UI.vbox(6)
	cc.add_child(_chron_latest)
	_chron_latest.minimum_size_changed.connect(func(): chronicle.call_deferred("reset_size"))
	_chron_list = UI.vbox(6)
	_chron_scroll = ScrollBox.make(_chron_list, 240)
	_chron_scroll.visible = false
	cc.add_child(_chron_scroll)
	_chron_toggle = UI.button("", "GhostSmallButton", func():
		chronicle_open = not chronicle_open
		_build_chronicle())
	_chron_toggle.name = "ChronicleToggle"
	_chron_toggle.focus_mode = Control.FOCUS_ALL
	_chron_toggle.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	cc.add_child(UI.gap(0, 2))
	cc.add_child(_chron_toggle)
	add_child(chronicle)
	_build_camp_controls()
	_build_services()
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
	roster_button.focus_mode = Control.FOCUS_ALL
	plan_button = UI.button("Plan Expedition", "RedBigButton", func(): App.go_prep())
	plan_button.name = "PlanExpedition"
	plan_button.focus_mode = Control.FOCUS_ALL
	br.add_child(roster_button)
	br.add_child(plan_button)
	add_child(br)
	_pulse(plan_button)
	refresh()


## Local view controls: the woodland lighting never changes campaign time.
func _build_camp_controls() -> void:
	var p := UI.panel("DarkPanel", [10, 14])
	p.name = "CampIdentity"
	p.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	p.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	p.offset_left = -18
	p.offset_right = -18
	p.offset_top = 74
	p.offset_bottom = 74
	var col := UI.vbox(3)
	p.add_child(col)
	var title := UI.cinzel("Amberfeld Garrison", 19, 700, UI.LIGHT_TITLE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	col.add_child(title)
	var subtitle := UI.label("Woodland frontier", "SmallMutedLabel", 14)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	col.add_child(subtitle)
	col.add_child(UI.gap(0, 5))
	var controls := UI.hbox(5)
	controls.alignment = BoxContainer.ALIGNMENT_END
	col.add_child(controls)
	_day_button = UI.button("Day", "SmallButtonActive", func(): _set_camp_night(false))
	_day_button.name = "CampDay"
	_day_button.tooltip_text = "View the camp in daylight."
	_night_button = UI.button("Night", "GhostSmallButton", func(): _set_camp_night(true))
	_night_button.name = "CampNight"
	_night_button.tooltip_text = "View the camp by moonlight."
	_frame_button = UI.button("Frame camp", "GhostSmallButton", _frame_camp)
	_frame_button.name = "FrameCamp"
	_frame_button.tooltip_text = "Return to the full camp view."
	for button in [_day_button, _night_button, _frame_button]:
		button.focus_mode = Control.FOCUS_ALL
		button.custom_minimum_size.y = 30
		controls.add_child(button)
	add_child(p)


func _build_services() -> void:
	var p := UI.panel("DarkPanel", [8, 10])
	p.name = "CampServices"
	p.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	p.grow_vertical = Control.GROW_DIRECTION_BEGIN
	p.offset_left = 18
	p.offset_right = 18
	p.offset_top = -18
	p.offset_bottom = -18
	var col := UI.vbox(5)
	p.add_child(col)
	col.add_child(UI.label("CAMP SERVICES", "SmallMutedLabel", 11))
	var row := UI.hbox(4)
	col.add_child(row)
	var index := 0
	for b in DB.BUILDINGS:
		index += 1
		var id: String = b.id
		var button := UI.button("%d  %s" % [index, b.name], "GhostSmallButton", _open_service.bind(id))
		button.name = "Service_" + id
		button.focus_mode = Control.FOCUS_ALL
		button.custom_minimum_size.y = 34
		button.add_theme_font_size_override("font_size", 13)
		row.add_child(button)
		_service_buttons[id] = button
	add_child(p)


func _open_service(id: String) -> void:
	if not _camp_controls_blocked():
		App.open_panel(id)


func _camp_controls_blocked() -> bool:
	return App.panel != null or App.soldier != null or App.manual != null or App.menu_open or welcome_overlay != null


func _set_camp_night(enabled: bool) -> void:
	var v := App.base_view
	if not _camp_controls_blocked() and is_instance_valid(v) and v.has_method("set_night"):
		v.call("set_night", enabled)
		_refresh_camp_controls()


func _frame_camp() -> void:
	var v := App.base_view
	if not _camp_controls_blocked() and is_instance_valid(v) and v.has_method("frame_camp"):
		v.call("frame_camp")


func _refresh_camp_controls() -> void:
	var v := App.base_view
	var blocked := _camp_controls_blocked()
	var can_light := is_instance_valid(v) and v.has_method("set_night")
	var night: bool = can_light and v.get("night_target") == true
	_day_button.disabled = blocked or not can_light
	_night_button.disabled = blocked or not can_light
	_frame_button.disabled = blocked or not is_instance_valid(v) or not v.has_method("frame_camp")
	_day_button.theme_type_variation = "GhostSmallButton" if night else "SmallButtonActive"
	_night_button.theme_type_variation = "SmallButtonActive" if night else "GhostSmallButton"
	for id in _service_buttons:
		var button: Button = _service_buttons[id]
		button.disabled = blocked
		var b := DB.building_by_id(id)
		var level: int = Deps.game().level(App.game, id)
		var current: Dictionary = b.levels[clampi(level - 1, 0, b.levels.size() - 1)]
		button.tooltip_text = "%s · Level %d\n%s" % [current.name, level, b.role]
	# A focused base action must not fire through a modal opened with the mouse.
	for button in [roster_button, plan_button, _chron_toggle]:
		button.disabled = blocked


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
	_refresh_camp_controls()


func _build_chronicle() -> void:
	var g: Dictionary = App.game
	UI.clear(_chron_list)
	UI.clear(_chron_latest)
	_chron_scroll.visible = chronicle_open
	_chron_latest.visible = not chronicle_open
	var list := _chron_list if chronicle_open else _chron_latest
	var n := 9 if chronicle_open else 1
	for c in g.chronicle.slice(0, n):
		var tone: String = str(c.get("tone", "neutral"))
		var col := "#ffb0a0" if tone == "bad" else ("#c8eab0" if tone == "good" else "#efe2c2")
		var r := UI.rich("[font_size=12][color=#b8a27c]Exp. %d · [/color][/font_size][color=%s]%s[/color]" % [c.cycle, col, UI.esc(c.text)], "BodyText")
		r.add_theme_font_size_override("normal_font_size", 14)
		r.add_theme_font_size_override("bold_font_size", 14)
		r.add_theme_constant_override("line_separation", 1)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		list.add_child(r)
	_chron_toggle.visible = g.chronicle.size() > 1
	_chron_toggle.text = "Latest only" if chronicle_open else "Earlier entries (%d)" % (mini(9, g.chronicle.size()) - 1)
	chronicle.call_deferred("reset_size")


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
	hover_tip.position = Vector2(roundf((vp.x - hover_tip.size.x) * 0.5), vp.y - 112 - hover_tip.size.y)


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
