## Port of src/ui/screens/Prep.tsx: Plan the Expedition — 1. Campaign (choice,
## intelligence and hints), 2. The Army (unit slots, command points, roster cards
## to toggle, eligibility tags), 3. Supplies (− / + within silver and wagon
## capacity, Quartermaster's advice, cost / wagon / marches fed, warnings and
## problems) and March Out.
## Local state like the React component: campaign, army (roster ids), supplies.
extends Control

const UI = preload("res://scripts/ui/ui.gd")
const DB = preload("res://scripts/data/db.gd")
const JS = preload("res://scripts/core/js.gd")
const Deps = preload("res://scripts/ui/deps.gd")
const ScrollBox = preload("res://scripts/ui/widgets/scroll_box.gd")
const Flourish = preload("res://scripts/ui/widgets/flourish.gd")
const ResList = preload("res://scripts/ui/widgets/res_list.gd")
const Icon = preload("res://scripts/ui/widgets/icon.gd")
const Tag = preload("res://scripts/ui/widgets/tag.gd")
const Tip = preload("res://scripts/ui/widgets/tip.gd")
const Bar = preload("res://scripts/ui/widgets/bar.gd")
const Card = preload("res://scripts/ui/widgets/card.gd")
const SoldierCard = preload("res://scripts/ui/widgets/soldier_card.gd")

const RANK_WORDS := ["Recruit", "Soldier", "Veteran", "Sergeant", "Champion"]

var camp_id := ""
var army: Array = []
var supplies: Dictionary = {}
var march_button: Button
var _panel: PanelContainer
var _built := false


func _ready() -> void:
	name = "Prep"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_init_state()
	_build()


func _camps() -> Array:
	return Deps.game().available_campaigns(App.game)


func _campaign() -> Dictionary:
	var camps := _camps()
	for c in camps:
		if c.id == camp_id:
			return c
	return camps[0] if not camps.is_empty() else {}


func _find(id: String) -> Variant:
	for so in App.game.roster:
		if so.id == id:
			return so
	return null


func _init_state() -> void:
	var g: Dictionary = App.game
	var Game = Deps.game()
	var camps := _camps()
	camp_id = camps[0].id if not camps.is_empty() else ""
	var c := _campaign()
	var lim: Dictionary = Game.army_limits(g, c)
	# Suggest a balanced force within the limits.
	var pick: Array = []
	var want := {"footman": 2, "spearman": 2, "crossbowman": 1}
	# The royal guard takes a footman's place in the line.
	var role := func(t: String) -> String: return "footman" if t == "collie_guard" else t
	var pool: Array = g.roster.filter(func(so): return Game.eligibility(g, so, c).ok)
	JS.sort(pool, func(a, b):
		if b.level != a.level:
			return b.level - a.level
		if b.men != a.men:
			return b.men - a.men
		return b.hp - a.hp)
	for so in pool:
		if pick.size() >= lim.slots:
			break
		var r: String = role.call(so.typeId)
		if JS.get_or(want, r, 0) <= 0:
			continue
		if Game.army_command(g, pick + [so.id]) > lim.command:
			continue
		pick.append(so.id)
		want[r] -= 1
	army = pick
	supplies = Game.recommended_supplies(5, 1, Game.wagon_capacity(g), c.stages + 1)


## Re-renders when the game changed (its own state changes rebuild directly).
func refresh() -> void:
	var sig := str(JSON.stringify(App.game).hash())
	if sig != _sig:
		_build()


var _sig := ""


func _build() -> void:
	var g: Dictionary = App.game
	_sig = str(JSON.stringify(g).hash())
	var Game = Deps.game()
	var Soldier = Deps.soldier()
	var c := _campaign()
	var lim: Dictionary = Game.army_limits(g, c)
	var xb := 0
	var counts := {}
	var men := 0
	for id in army:
		var so: Variant = _find(id)
		if so == null:
			continue
		if so.typeId == "crossbowman":
			xb += 1
		counts[so.typeId] = JS.get_or(counts, so.typeId, 0) + 1
		men += so.men
	var cp: int = Game.army_command(g, army)
	var cost: int = Game.supply_cost_total(g, supplies)
	var weight: int = Game.supply_weight(supplies)
	var cap: int = Game.wagon_capacity(g)
	var marches_food: int = ceili(army.size() / 2.0)
	var marches_covered: int = floori(float(supplies.rations) / marches_food) if marches_food else 0
	var problems: Array = []
	if army.is_empty():
		problems.append("Choose at least one squad.")
	if cost > g.resources.silver:
		problems.append("Not enough silver for these supplies.")
	if weight > cap:
		problems.append("The wagon is overloaded.")
	var warnings: Array = []
	if army.size() and marches_covered < c.stages + 1:
		warnings.append("Rations cover only %d marches; the road is about %d." % [marches_covered, c.stages + 1])
	if xb and supplies.bolts == 0:
		warnings.append("No spare bolts: crossbowmen will run dry.")
	if supplies.torches == 0:
		warnings.append("No torches: night camps risk raids.")
	var thin := 0
	for id in army:
		var so: Variant = _find(id)
		if so != null and so.men < DB.squad_size(so.typeId):
			thin += 1
	if thin:
		warnings.append("%s below strength. The Barracks can refill them first." % ("One squad marches" if thin == 1 else "%d squads march" % thin))

	# Keep scroll positions across the re-render.
	var scrolls := _scroll_values()
	if _panel != null:
		_panel.queue_free()
	var vp := get_viewport_rect().size if is_inside_tree() else Vector2(1920, 1080)
	var p := UI.panel("ParchmentPanel", [26, 32])
	_panel = p
	p.name = "PrepPanel"
	var w := minf(1460.0, vp.x * 0.96)
	var h := minf(780.0, vp.y * 0.92)
	p.custom_minimum_size = Vector2(w, h)
	p.size = Vector2(w, h)
	p.position = ((vp - Vector2(w, h)) * 0.5).round()
	add_child(p)
	if not _built:
		_rise(p)
	_built = true
	var col := UI.vbox(0)
	p.add_child(col)
	# Header.
	var head := UI.hbox(8)
	var h2 := UI.label("Plan the Expedition", "H2Label", 28)
	h2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(h2)
	var hr := UI.hbox(14)
	hr.add_child(ResList.make(g.resources, 20))
	var back := UI.button("Back to camp", "Button", func(): App.go_base())
	back.name = "BackToCamp"
	hr.add_child(back)
	head.add_child(hr)
	var heading_band := UI.panel("BannerPanel", [10, 18])
	heading_band.add_child(head)
	col.add_child(heading_band)
	col.add_child(Flourish.make())
	var cols := UI.hbox(16)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(cols)

	# 1. Campaign.
	var c1 := UI.vbox(6)
	c1.add_child(UI.label("1. Campaign", "HeadingLabel", 18))
	for cc in _camps():
		var card := Card.make(_pick_campaign.bind(cc.id), cc.id == c.id)
		card.name = "Campaign_" + str(cc.id)
		var cv := UI.vbox(0)
		card.add_child(cv)
		var top := UI.hbox(8)
		var nm := UI.cinzel(cc.name, 17)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(nm)
		top.add_child(Tag.make("Tier %s · %s" % [JS.num_str(cc.tier), cc.tierName], "gold"))
		cv.add_child(top)
		cv.add_child(UI.label(cc.region, "SmallMutedLabel"))
		cv.add_child(UI.gap(0, 6))
		cv.add_child(UI.rich(UI.esc(cc.blurb), "SmallText"))
		cv.add_child(UI.gap(0, 6))
		c1.add_child(card)
	var intel := UI.panel("ParchmentCard")
	var iv := UI.vbox(0)
	intel.add_child(iv)
	iv.add_child(UI.label("Intelligence", "H4Label"))
	iv.add_child(UI.gap(0, 4))
	var expect := HFlowContainer.new()
	expect.add_theme_constant_override("h_separation", 4)
	expect.add_theme_constant_override("v_separation", 3)
	expect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var el := UI.rich("[b]Expect:[/b]", "SmallText")
	el.autowrap_mode = TextServer.AUTOWRAP_OFF
	el.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	expect.add_child(el)
	for t in c.hints.enemies:
		expect.add_child(Tag.make(DB.UNIT_TYPES[t].plural, "red", Icon.type_icon(t, 12)))
	iv.add_child(expect)
	iv.add_child(UI.gap(0, 6))
	for k in [["Terrain", c.hints.terrain], ["Length", c.hints.length], ["Threat", c.hints.threat], ["Supplies", c.hints.supplies]]:
		iv.add_child(UI.rich("[b]%s:[/b] %s" % [k[0], UI.esc(k[1])], "SmallText"))
	iv.add_child(UI.gap(0, 6))
	iv.add_child(UI.rich("[b]Objective:[/b] %s" % UI.esc(c.objective.description), "SmallText"))
	iv.add_child(UI.gap(0, 6))
	var rw := UI.hbox(6)
	var rl := UI.rich("[b]Reward:[/b]", "SmallText")
	rl.autowrap_mode = TextServer.AUTOWRAP_OFF
	rl.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	rw.add_child(rl)
	rw.add_child(ResList.make(c.reward, 15))
	rw.add_child(UI.label("plus all spoils", "SmallMutedLabel"))
	iv.add_child(rw)
	iv.add_child(UI.gap(0, 6))
	iv.add_child(UI.rich("Soldiers above %s rank are reluctant to chase goblins (-15 morale)." % RANK_WORDS[clampi(c.reluctantAbove - 1, 0, 4)], "SmallMutedText"))
	c1.add_child(intel)
	var s1 := ScrollBox.make(c1, 0)
	s1.name = "CampaignScroll"
	s1.size_flags_stretch_ratio = 1.0
	cols.add_child(s1)

	# 2. The Army.
	var c2 := UI.vbox(6)
	c2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c2.size_flags_stretch_ratio = 1.55
	var ah := UI.hbox(8)
	var at := UI.label("2. The Army", "HeadingLabel", 18)
	at.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ah.add_child(at)
	var atags := UI.hbox(6)
	if army.size() > 0:
		atags.add_child(Tag.make("%d soldiers" % men))
	for t in counts:
		var n: int = counts[t]
		atags.add_child(Tag.make("%d %s" % [n, DB.UNIT_TYPES[t].name if n == 1 else DB.UNIT_TYPES[t].plural], "blue", Icon.type_icon(t, 12)))
	ah.add_child(atags)
	c2.add_child(ah)
	var limits := UI.hbox(8)
	# Unit slots.
	var sl := UI.vbox(3)
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var slh := UI.hbox(4)
	slh.add_child(Icon.make("slot", 16))
	var slt := UI.label("Unit slots", "SmallLabel")
	slt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slh.add_child(slt)
	slh.add_child(UI.rich("[b]%d / %d[/b]" % [army.size(), lim.slots], "SmallText"))
	(slh.get_child(2) as RichTextLabel).autowrap_mode = TextServer.AUTOWRAP_OFF
	(slh.get_child(2) as RichTextLabel).size_flags_horizontal = Control.SIZE_SHRINK_END
	sl.add_child(slh)
	var segs := UI.hbox(3)
	for i in lim.slots:
		var seg := Panel.new()
		var st := StyleBoxFlat.new()
		st.bg_color = UI.BLUE if i < army.size() else Color(30 / 255.0, 18 / 255.0, 8 / 255.0, 0.25)
		st.set_corner_radius_all(2)
		seg.add_theme_stylebox_override("panel", st)
		seg.custom_minimum_size.y = 9
		seg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		seg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		segs.add_child(seg)
	sl.add_child(segs)
	limits.add_child(sl)
	# Command points.
	var cpv := UI.vbox(3)
	cpv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var cph := UI.hbox(4)
	var cpl := UI.hbox(4, [Icon.make("cp", 16), UI.label("Command points", "SmallLabel")])
	Tip.attach(cpl, "Each squad costs command points by type and rank. Veteran squads cost more: they are worth it, but you can never bring everyone.")
	cpl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cph.add_child(cpl)
	var cpn := UI.rich("[b]%d / %d[/b]" % [cp, lim.command], "SmallText")
	cpn.autowrap_mode = TextServer.AUTOWRAP_OFF
	cpn.size_flags_horizontal = Control.SIZE_SHRINK_END
	cph.add_child(cpn)
	cpv.add_child(cph)
	var cpb := Bar.make(cp, lim.command, "cp over" if cp > lim.command else "cp")
	cpb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cpv.add_child(cpb)
	limits.add_child(cpv)
	c2.add_child(limits)
	# The roster.
	var listed: Array = g.roster.duplicate()
	JS.sort(listed, func(a, b):
		var ia := 1 if army.has(a.id) else 0
		var ib := 1 if army.has(b.id) else 0
		if ib != ia:
			return ib - ia
		return SoldierCard.squad_order(a.typeId) - SoldierCard.squad_order(b.typeId))
	var cards: Array = []
	for so in listed:
		var e: Dictionary = Game.eligibility(g, so, c)
		var in_army: bool = army.has(so.id)
		var fits: bool = in_army or (army.size() < lim.slots and cp + Soldier.command_cost(so) <= lim.command)
		var extra: Array = []
		if not e.ok:
			extra.append(Tag.make(str(e.get("reason", "")), "red", "", 10))
		if e.ok and e.get("reluctant"):
			extra.append(Tag.make("Reluctant", "gold", "", 10))
		if e.ok and not in_army and not fits:
			extra.append(Tag.make("Over limit", "", "", 10))
		cards.append(SoldierCard.make(so, _toggle.bind(so.id), in_army, not e.ok or (not in_army and not fits), extra))
	var grid := UI.equal_grid(cards, 2, 7, 7)
	var s2 := ScrollBox.make(grid, 0, 4)
	s2.name = "ArmyScroll"
	c2.add_child(s2)
	cols.add_child(c2)

	# 3. Supplies.
	var c3 := UI.vbox(6)
	c3.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c3.size_flags_stretch_ratio = 1.0
	var sh := UI.hbox(8)
	var stl := UI.label("3. Supplies", "HeadingLabel", 18)
	stl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sh.add_child(stl)
	var advice := UI.button("Quartermaster's advice", "GhostSmallButton", func():
		supplies = Deps.game().recommended_supplies(army.size(), _crossbows(), Deps.game().wagon_capacity(App.game), _campaign().stages + 1)
		_build())
	advice.name = "Advice"
	sh.add_child(advice)
	c3.add_child(sh)
	for k in DB.SUPPLY_ORDER:
		var S: Dictionary = DB.SUPPLIES[k]
		var card := UI.panel("ParchmentCard", [6, 8])
		card.name = "Supply_" + k
		var r := UI.hbox(8)
		card.add_child(r)
		var ic := Icon.make(k, 30)
		Tip.attach(ic, UI.esc(S.description), true)
		r.add_child(ic)
		var info := UI.vbox(0)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_child(UI.cinzel(S.name, 14))
		info.add_child(UI.label("%d silver · weight %s" % [Game.supply_price(g, k), JS.num_str(S.weight)], "TinyMutedLabel"))
		r.add_child(info)
		var minus := UI.button("−", "SmallButton", _add.bind(k, -1))
		minus.name = "Minus"
		minus.disabled = supplies[k] <= 0
		minus.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		r.add_child(minus)
		var n := UI.label(str(supplies[k]), "CinzelLabel", 18)
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		n.custom_minimum_size.x = 28
		n.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		r.add_child(n)
		var plus := UI.button("+", "SmallButton", _add.bind(k, 1))
		plus.name = "Plus"
		plus.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		r.add_child(plus)
		c3.add_child(card)
	var tot := UI.panel("ParchmentCard")
	var tv := UI.vbox(4)
	tot.add_child(tv)
	tv.add_child(_kv("silver", "Cost", "%d / %d" % [cost, g.resources.silver], cost > g.resources.silver))
	tv.add_child(_kv("weight", "Wagon", "%d / %d" % [weight, cap], weight > cap))
	var wb := Bar.make(weight, cap, "over" if weight > cap else "fatigue")
	wb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_child(wb)
	tv.add_child(_kv("rations", "Marches fed", str(marches_covered), false))
	tv.add_child(UI.rich("Silver left after buying: %d. Leftovers sell back cheaply on return." % (g.resources.silver - cost), "TinyMutedText"))
	c3.add_child(tot)
	for wtxt in warnings:
		c3.add_child(UI.rich("[color=#8a4a10]⚠ %s[/color]" % UI.esc(wtxt), "SmallText"))
	for ptxt in problems:
		c3.add_child(UI.rich("[color=#a3261c][b]✖ %s[/b][/color]" % UI.esc(ptxt), "SmallText"))
	c3.add_child(UI.spacer(false))
	march_button = UI.button("March Out", "RedBigButton", func():
		var cc2 := _campaign()
		App.launch(cc2.id, army.duplicate(), supplies.duplicate(), Deps.game().supply_cost_total(App.game, supplies)))
	march_button.name = "MarchOut"
	march_button.disabled = problems.size() > 0
	c3.add_child(march_button)
	cols.add_child(c3)
	_restore_scrolls(scrolls)


func _kv(icon: String, label: String, value: String, bad: bool) -> HBoxContainer:
	var r := UI.hbox(4)
	r.add_child(Icon.make(icon, 15))
	var l := UI.label(label, "SmallLabel")
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_child(l)
	var v := UI.rich(("[color=#a3261c][b]%s[/b][/color]" if bad else "[b]%s[/b]") % value, "SmallText")
	v.autowrap_mode = TextServer.AUTOWRAP_OFF
	v.size_flags_horizontal = Control.SIZE_SHRINK_END
	r.add_child(v)
	return r


func _crossbows() -> int:
	var n := 0
	for id in army:
		var so: Variant = _find(id)
		if so != null and so.typeId == "crossbowman":
			n += 1
	return n


func _pick_campaign(id: String) -> void:
	camp_id = id
	_build()


func _toggle(id: String) -> void:
	var g: Dictionary = App.game
	var Game = Deps.game()
	var so: Variant = _find(id)
	if so == null:
		return
	if army.has(id):
		army.erase(id)
		App.sfx("click")
		_build()
		return
	var c := _campaign()
	var lim: Dictionary = Game.army_limits(g, c)
	var cp: int = Game.army_command(g, army)
	if not Game.eligibility(g, so, c).ok or army.size() >= lim.slots or cp + Deps.soldier().command_cost(so) > lim.command:
		App.sfx("deny")
		return
	army.append(id)
	App.sfx("select")
	_build()


func _add(k: String, n: int) -> void:
	supplies[k] = maxi(0, supplies[k] + n)
	App.sfx("click")
	_build()


func _rise(p: Control) -> void:
	if not p.is_inside_tree():
		return
	p.modulate.a = 0.0
	var y := p.position.y
	p.position.y = y + 18
	var tw := p.create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(p, "modulate:a", 1.0, 0.35)
	tw.tween_property(p, "position:y", y, 0.35)


func _scroll_values() -> Dictionary:
	var out := {}
	if _panel == null:
		return out
	for s in _panel.find_children("*", "ScrollContainer", true, false):
		out[s.name] = (s as ScrollContainer).scroll_vertical
	return out


func _restore_scrolls(vals: Dictionary) -> void:
	var any := false
	for k in vals:
		if vals[k] > 0:
			any = true
	if not any or not is_inside_tree():
		return
	var p := _panel
	for i in 2:
		await get_tree().process_frame
	if not is_instance_valid(p):
		return
	for s in p.find_children("*", "ScrollContainer", true, false):
		if vals.has(s.name):
			(s as ScrollContainer).scroll_vertical = vals[s.name]
