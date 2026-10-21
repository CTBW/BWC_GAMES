## Port of src/ui/screens/Manual.tsx: the Captain's Field Manual — page tabs
## (Battle, The Horde, Squads, Your Troops, Morale and Rout, Expeditions,
## Amberfeld), the page text, "To the field". It opens on its own the first time
## a battle starts (App.start_battle, prefs "manualSeen").
##
##   const Manual = preload("res://scripts/ui/screens/manual.gd")
##   Manual.make(start := "battle", on_close := Callable()) -> Control   (full-rect modal)
##   Manual.PAGES   [{id, title, body: Array of bbcode paragraphs}]
extends Control

const UI = preload("res://scripts/ui/ui.gd")
const Modal = preload("res://scripts/ui/widgets/modal.gd")
const ScrollBox = preload("res://scripts/ui/widgets/scroll_box.gd")

const KBD_FONT := "res://assets/fonts/alegreya-sans-latin-400-normal.woff2"


static func kbd(k: String) -> String:
	return " [bgcolor=#5b46301c][font=%s][font_size=11][color=#2b1d10bf] %s [/color][/font_size][/font][/bgcolor]" % [KBD_FONT, k]


static func ico(name: String) -> String:
	return "[img=18x18]res://assets/icons/%s.svg[/img]" % name


static func pages() -> Array:
	return [
		{"id": "battle", "title": "Battle", "body": [
			"Each turn every squad may [b]move once[/b] and [b]act once[/b], in either order. Click a squad, then a blue tile to move. Click an enemy to attack. If the enemy is out of reach, the squad moves next to it first; [b]move the cursor around the enemy to choose which side you strike from[/b].",
			"A blue tile hidden behind one of your own squads can still be clicked: the move wins, and a faint ghost shows where your squad will stand. Changed your mind? [b]Redo move[/b] (or%s) walks the squad back to where the turn began so you can move again, as long as it has not attacked yet. A move the enemy reacted to (a free attack, a spearwall or an overwatch shot) cannot be taken back." % kbd("Backspace"),
			"[b]Facing comes from marching.[/b] A squad faces the way it took its [b]last step[/b], and nothing else turns it: not attacking, not being attacked. The chevron at a squad's feet shows where it faces. When you choose a destination, the gold arrow on the tile shows the facing it will arrive with. [b]Point at an edge of the tile[/b] to arrive facing that edge, or press%s/%s to try the other sides (faint arrows mark them). To turn without moving, point at an edge of the squad's own tile: it steps out and back, which uses its move." % [kbd("Q"), kbd("E")],
			"Attacks into the [b]flank[/b] gain +10% to hit; attacks from [b]behind[/b] gain +20%, deal +25% damage, ignore shields and shake morale. Shields guard the front; a shield wall also guards the flanks. Spearwall and overwatch watch the front and flanks, never the rear.",
			"[b]Zones of control.[/b] Stepping away from an enemy's front or flank invites a free attack; a squad cannot strike at what moves behind its back. Orange path markers warn you. A solid line protects the crossbows behind it.",
			"[b]Ground.[/b] High ground gives +8% per level to hit (and extends crossbow range); attacking uphill costs the same. Thickets and woods slow movement and hide troops from missiles. Rocks, walls and fences give cover against shots that pass them. Trees and boulders block line of sight.",
		]},
		{"id": "horde", "title": "The Horde", "body": [
			"You are always outnumbered. The host does not win by skill but by numbers: it [b]swarms round the flanks[/b], piles into any gap in your line and goes for the weakest squad it can reach. You win by [b]position[/b]: hold narrow ground, keep your flanks against walls and woods, face the enemy, and let them come to you a few at a time.",
			"[b]Its troops.[/b] [i]Goblin rabble[/i] come nine to a squad, weak alone but deadly around a flank. [i]Goblin spearmen[/i] and [i]archers[/i] are the body of the host. [i]Wolf riders[/i] are fast, slip away from blows and hunt your crossbowmen; set spears stop them. [i]Orc brutes[/i] smash a squad back out of the line and push into the gap. A [i]horn-bearer[/i] calls for help if he lives long enough.",
			"[b]Waves.[/b] More of them are always coming. Squads massing beyond the edge of the field will march in soon: red markers on the edge tiles show where a wave arrives at the end of this turn, and the top of the screen counts the turns. Use the time to close the line where they will strike.",
			"[b]How battles end.[/b] Each battle says what wins it (top of the screen). Small fights are won by destroying or routing every enemy, but a [b]war horn[/b] sounded in time brings more of them: kill the horn-bearer first. A [b]stand[/b] is won by holding until the relief arrives; the enemy must never hold the [b]ground marked in gold[/b] at the end of two of its turns running. In the last stand, slaying the [b]warchief[/b] breaks the whole host. If the company is destroyed or routed, the battle is lost.",
			"[b]Bigger fields.[/b] Last stands are fought on large maps. Scroll to zoom out to the whole field, drag with the right mouse button or use the arrow keys to pan, and click the minimap (bottom left) to jump.",
		]},
		{"id": "squads", "title": "Squads", "body": [
			"Every unit on the field is a [b]squad[/b] of [b]six soldiers[/b] (moss trolls go in threes) that moves, fights and holds its ground as one. A squad is known by its sergeant's name: [i]Aldric's footmen[/i]. The pips beside a squad show its strength: [b]filled[/b] pips are soldiers still serving, [b]hollow[/b] ones have fallen.",
			"[b]Shared health.[/b] The squad has one pool of HP, split into a share per soldier (the segments of its health bar). Each time the pool drops past a share, a soldier [b]falls[/b]; one heavy blow can cut down several. When the last share is gone the squad is destroyed.",
			"[b]Damage is soldiers × blows.[/b] Every soldier still standing strikes: a squad of five footmen dealing 7–10 each hits for 35–50 before armour (armour is taken off each blow). A thinned squad hits softer, so wearing an enemy down pays. The forecast shows how many soldiers strike, how many of the target a hit would slay, and the chance to destroy the squad outright.",
			"[b]The dead stay dead.[/b] Camps, bandages and the trip home heal the survivors, never the fallen. Only the [b]Barracks[/b] at Amberfeld can refill a squad's empty places, for a little silver per soldier. A squad cut down in battle may still keep its sergeant, gravely hurt; he can rebuild it.\n[b]Field triage.[/b] Right after a battle the surgeons search the fallen. Each soldier who fell has the same chance to be found alive as a lone soldier always had (better at higher rank, with bandages and a better Infirmary, and when you hold the field). Those found rejoin their squad badly hurt. Nobody else comes back.",
		]},
		{"id": "units", "title": "Your Troops", "body": [
			"%s [b]Footmen[/b] hold the line. Their kite shields add defense against attacks from the front. [b]Shield Wall[/b] makes them very hard to hit and protects adjacent comrades." % ico("shield"),
			"%s [b]Spearmen[/b] punish anyone who charges in carelessly: they [b]strike first[/b] when attacked from the front by an enemy who moved. [b]Spearwall[/b] strikes the first enemy to step next to them at +50%% damage and stops its advance on a hit. Perfect for bridges, fords and gaps in a wall." % ico("spear"),
			"%s [b]Crossbowmen[/b] hit hard at range and pierce armour, best when they have not moved ([b]steady aim[/b]). They cannot shoot point-blank and are weak in melee. Every shot costs a bolt; refill quivers from spare bolts. [b]Overwatch[/b] shoots the first enemy that moves into sight during the enemy turn." % ico("crossbow"),
			"%s The [b]Border Collie Royal Guard[/b] are rare elite squads that answer a proper Barracks (level 2). Quick, heavily armoured and hard to break, they stand in the front rank like footmen." % ico("shield"),
			"Veteran squads can be [b]promoted[/b] at the Training Yard to learn Shield Bash, Pike Thrust or Heavy Bolt.",
		]},
		{"id": "morale", "title": "Morale and Rout", "body": [
			"Every squad has [b]morale[/b] (the blue bar). Wounds, flank and rear attacks, comrades falling nearby, being surrounded and a losing battle all drain it. Victories, felling foes and standing beside comrades restore it.",
			"[b]Confident[/b] troops fight better. [b]Shaken[/b] and [b]Wavering[/b] troops fight worse; wavering troops cannot use abilities. At zero morale a unit [b]routs[/b] and flees the field. It may rally if it gets clear of the enemy.",
			"Goblins break easily; orcs do not. Kill a warband's [b]leader[/b] and the rest lose heart; slay the host's [b]warchief[/b] and the whole horde breaks and runs.",
			"Soldiers still lying on the field after the surgeons' search are gone for good. When a whole squad is cut down its sergeant may survive, gravely wounded, with a lasting injury; carried bandages and better surgeons improve the odds. The dead stay dead.",
		]},
		{"id": "campaign", "title": "Expeditions", "body": [
			"On campaign, choose your path across the map. Every march eats [b]rations[/b] (one per two squads) and tires the army. Hungry soldiers lose morale and strength, and a weak one may not survive. Wounds, fallen soldiers, morale, fatigue and spent bolts carry from one battle to the next.",
			"[b]Camps[/b] let you rest (rations), keep watch (torches) and mend armour (tools). [b]Villages[/b] hide loot; strongboxes need tools. [b]Lookouts[/b] reveal the road ahead, including enemy numbers. [b]Encounters[/b] ask for decisions that cost or reward.",
			"You may [b]retreat home[/b] at any time and keep the spoils, but the objective's reward is lost. A broken army loses half its spoils.",
		]},
		{"id": "base", "title": "Amberfeld", "body": [
			"Between expeditions the company rests at Amberfeld and the survivors heal. Spend silver, timber, iron and war trophies to upgrade buildings: more command points and slots (Command Tent), better recruits and reinforcements (Barracks), drill and promotions (Training Yard), better gear (Armoury), cheaper treatment and better survival odds (Infirmary), and a bigger wagon (Quartermaster).",
			"Every expedition is capped by [b]unit slots[/b] and [b]command points[/b], one slot per squad. Veteran squads cost more points than recruits, so you can never bring everyone. Refill thinned squads at the Barracks before you march. Squads who stay home recover morale; those treated or sent on leave sit out one expedition.",
		]},
	]


var page := "battle"
var on_close := Callable()
var _tabs: HBoxContainer
var _body: VBoxContainer
var _scroll: ScrollContainer


static func make(start := "battle", on_close_ := Callable()) -> Control:
	var m: Control = load("res://scripts/ui/screens/manual.gd").new()
	m.page = start
	m.on_close = on_close_
	m._build()
	return m


func _build() -> void:
	name = "Manual"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var d := Modal.dialog(760)
	var col := UI.vbox(0)
	d.add_child(col)
	col.add_child(UI.title_block("Captain's Field Manual"))
	_tabs = UI.hbox(6)
	_tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(_tabs)
	col.add_child(UI.gap(0, 6 + 8))
	_body = UI.vbox(16)
	var vh := get_viewport_rect().size.y if is_inside_tree() else 1080.0
	_scroll = ScrollBox.make(_body, vh * 0.58)
	col.add_child(_scroll)
	col.add_child(UI.gap(0, 10))
	var row := UI.hbox(8)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var close := UI.button("To the field", "RedButton", _close)
	close.name = "ToTheField"
	row.add_child(close)
	col.add_child(row)
	add_child(Modal.make(d, _close))
	_show_page()


func _close() -> void:
	if on_close.is_valid():
		on_close.call()


func set_page(id: String) -> void:
	page = id
	_show_page()


func _show_page() -> void:
	var all := pages()
	var p: Dictionary = all[0]
	for x in all:
		if x.id == page:
			p = x
	UI.clear(_tabs)
	for x in all:
		var b := UI.button(x.title, "GoldSmallButton" if x.id == p.id else "GhostSmallButton", set_page.bind(x.id))
		b.name = "Tab_" + x.id
		_tabs.add_child(b)
	UI.clear(_body)
	for para in p.body:
		var r := UI.rich(para, "ManualText")
		_body.add_child(r)
	_scroll.scroll_vertical = 0
