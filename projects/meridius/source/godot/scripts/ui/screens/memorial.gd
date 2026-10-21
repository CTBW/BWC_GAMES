## Port of Base.tsx `Memorial` and `Welcome`.
##
##   const Memorial = preload("res://scripts/ui/screens/memorial.gd")
##   Memorial.make(viewport_h := 1080.0) -> PanelContainer   The Fallen (greyed portraits, cause, expedition)
##   Memorial.welcome() -> Control                             the first-visit letter (full-rect modal)
extends RefCounted

const UI = preload("res://scripts/ui/ui.gd")
const Modal = preload("res://scripts/ui/widgets/modal.gd")
const ScrollBox = preload("res://scripts/ui/widgets/scroll_box.gd")
const Portrait = preload("res://scripts/ui/widgets/portrait.gd")
const Flourish = preload("res://scripts/ui/widgets/flourish.gd")


static func make(viewport_h := 1080.0) -> PanelContainer:
	var g: Dictionary = App.game
	var d := Modal.dialog(640)
	d.name = "Memorial"
	var col := UI.vbox(0)
	d.add_child(col)
	col.add_child(UI.title_block("The Fallen"))
	# p.muted with margin-top -4 under the title (whose margin is 10).
	var tb: Control = col.get_child(0)
	(tb.get_child(tb.get_child_count() - 1) as Control).custom_minimum_size.y = 6
	col.add_child(UI.rich("[center]Their names are cut into the gatepost of Amberfeld.[/center]", "MutedText"))
	col.add_child(UI.gap(0, 16))
	var list := UI.vbox(6)
	if g.fallen.is_empty():
		list.add_child(UI.rich("[center]No squad of the company has been lost. Yet.[/center]", "BodyText"))
	for f in g.fallen:
		var card := UI.panel("ParchmentCard")
		var row := UI.hbox(8)
		card.add_child(row)
		var p := Portrait.make(f.typeId, 0, 44, true)
		p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(p)
		var info := UI.vbox(0)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		info.add_child(UI.cinzel(f.name))
		info.add_child(UI.label("%s · %d battles · %d enemy squads slain" % [UI.squad_type_label(f.typeId, f.level), f.battles, f.kills], "SmallMutedLabel"))
		row.add_child(info)
		var cause := UI.vbox(0)
		cause.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var c1 := UI.label(f.cause, "SmallLabel")
		c1.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		cause.add_child(c1)
		var c2 := UI.label("Expedition %d" % f.cycle, "TinyMutedLabel")
		c2.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		cause.add_child(c2)
		row.add_child(cause)
		list.add_child(card)
	col.add_child(ScrollBox.make(list, viewport_h * 0.6))
	col.add_child(UI.gap(0, 12))
	var row2 := UI.hbox(8)
	row2.alignment = BoxContainer.ALIGNMENT_CENTER
	var close := UI.button("Close", "Button", func(): App.open_panel(null))
	close.name = "Close"
	row2.add_child(close)
	col.add_child(row2)
	return d


static func welcome() -> Control:
	var d := Modal.dialog(640)
	d.name = "Welcome"
	var col := UI.vbox(0)
	d.add_child(col)
	col.add_child(UI.title_block("To the Captain of the Amberfeld Company"))
	col.add_child(UI.rich("[i]A host of goblins and orcs is coming out of the Hillsvain Woods, more than anyone has ever counted, and it is burning every steading west of the Vattern. The Margrave's riders are days away. The council has given you six squads of six, a camp of tents and a little silver. You are what stands between the host and the river. Slow it, and hold Brannsted until the riders come.[/i]", "DialogText"))
	col.add_child(Flourish.make())
	var steps := UI.vbox(4)
	for t in [
		"[b]1. Prepare.[/b] Hire new squads and refill thinned ones at the Barracks. Then plan an expedition: choose which squads march within the army limit, and pack supplies.",
		"[b]2. March.[/b] Pick a path across the map. Fight, scout, loot, rest. Wounds, fallen soldiers, morale and supplies carry from one fight to the next.",
		"[b]3. Return.[/b] Come home with the spoils, win or lose. Spend them on buildings, gear and training, then go again.",
	]:
		var r := UI.rich(t, "BodyText")
		r.add_theme_font_size_override("normal_font_size", 15)
		r.add_theme_font_size_override("bold_font_size", 15)
		steps.add_child(r)
	col.add_child(steps)
	col.add_child(UI.gap(0, 8))
	col.add_child(UI.rich("The Field Manual (top bar) explains facing, flanks, morale and supplies whenever you need it.", "SmallMutedText"))
	col.add_child(UI.gap(0, 8))
	var row := UI.hbox(10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var read := UI.button("Read the Field Manual", "Button", func():
		_close_welcome()
		App.open_manual("battle"))
	read.name = "ReadManual"
	var work := UI.button("To work", "RedButton", _close_welcome)
	work.name = "ToWork"
	row.add_child(read)
	row.add_child(work)
	col.add_child(row)
	var m := Modal.make(d)
	m.name = "WelcomeModal"
	return m


static func _close_welcome() -> void:
	var g: Dictionary = App.game
	var flags: Dictionary = g.get("flags") if g.get("flags") is Dictionary else {}
	flags.welcome = true
	g.flags = flags
	App.commit()
