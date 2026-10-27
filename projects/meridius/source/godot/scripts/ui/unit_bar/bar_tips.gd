## The unit bar's tooltips (scripts/ui/unit_bar), Warcraft III's in the HUD's
## dark tooltip panel (widgets/tip.gd shows them): the name in brass Cinzel with
## its hotkey or kind beside it, what it does, then its numbers line by line
## (bonuses green, penalties red, notes muted) and, in red, why it cannot be
## used now. Built when shown, from the piece's own data (bar_data.gd's).
##
##   Tip.attach(control, func(): return BarTips.command(c), true)
##   BarTips.command(c) / stat(s) / status(e) / man(m, faction) / item(it) -> Control
##   BarTips.text_of(tip) -> String       its plain text (tests)
## A line is {text, tone: "" | "good" | "bad" | "muted"} or a plain String.
extends RefCounted

const UI = preload("res://scripts/ui/ui.gd")
const Style = preload("res://scripts/ui/unit_bar/bar_style.gd")

const WIDTH := 300.0
const TONES := {"good": Color("#9fe08a"), "bad": Color("#ffb0a0"), "muted": UI.DARK_MUTED, "": UI.LIGHT}
const KIND_NAME := {"buff": "Boon", "debuff": "Bane", "state": "State"}


static func command(c: Dictionary) -> Control:
	if c.is_empty():
		return null
	# The hotkey and the cadence beside the name; a cooldown shows on the button itself.
	var tag := "[%s]" % String(c.hotkey) if String(c.get("hotkey", "")) != "" else ""
	var every := int(c.get("every", 0))
	if every > 1:
		tag += " · every %s" % ("other turn" if every == 2 else "%d turns" % every)
	var lines: Array = []
	if String(c.get("desc", "")) != "":
		lines.append(String(c.desc))
	lines.append_array(c.get("lines", []))
	if String(c.get("reason", "")) != "":
		lines.append({"text": String(c.reason), "tone": "bad"})
	if String(c.get("aim", "")) != "":
		lines.append({"text": String(c.aim), "tone": "muted"})
	return _tip(String(c.get("name", "")), tag, lines)


static func stat(s: Dictionary) -> Control:
	if s.is_empty():
		return null
	var lines: Array = []
	if String(s.get("desc", "")) != "":
		lines.append(String(s.desc))
	lines.append_array(s.get("lines", []))
	return _tip("%s  %s" % [String(s.get("name", s.get("label", ""))), String(s.get("value", ""))], "", lines)


static func status(e: Dictionary) -> Control:
	if e.is_empty():
		return null
	var lines: Array = []
	if String(e.get("desc", "")) != "":
		lines.append(String(e.desc))
	var turns := int(e.get("turns", -1))
	if turns > 0:
		lines.append({"text": "%d %s left" % [turns, "turn" if turns == 1 else "turns"], "tone": "muted"})
	if String(e.get("source", "")) != "":
		lines.append({"text": String(e.source), "tone": "muted"})
	var t := _tip(String(e.get("name", "")), KIND_NAME.get(String(e.get("kind", "")), ""), lines)
	(t.get_child(0).get_child(0) as Label).add_theme_color_override("font_color",
		{"buff": Style.BUFF, "debuff": Style.DEBUFF}.get(String(e.get("kind", "")), Style.BRASS_LIGHT))
	return t


static func man(m: Dictionary, faction := "player") -> Control:
	if m.is_empty():
		return null
	if bool(m.get("hidden", false)):
		return _tip("Unseen", "", [{"text": "Out of sight in the fog.", "tone": "muted"}])
	var lines: Array = []
	if not bool(m.get("alive", true)):
		lines.append({"text": "Fallen in this battle.", "tone": "bad"})
	else:
		lines.append("%d / %d HP" % [int(m.get("hp", 0)), int(m.get("hp_max", 0))])
		if bool(m.get("wounded", false)):
			lines.append({"text": "The squad's wounds fall on him first: he goes down before the others lose any HP.", "tone": "muted"})
	if faction == "player" and bool(m.get("alive", true)):
		lines.append({"text": "Click to see him in the portrait.", "tone": "muted"})
	return _tip(String(m.get("name", "")), "", lines)


static func item(it: Dictionary) -> Control:
	if it.is_empty():
		return null
	if bool(it.get("hidden", false)):
		return _tip("Unknown", "", [{"text": String(it.get("desc", "What a foe carries is not known.")), "tone": "muted"}])
	var lines: Array = []
	if String(it.get("desc", "")) != "":
		lines.append(String(it.desc))
	lines.append_array(it.get("lines", []))
	var t := _tip(String(it.get("name", "")), String(it.get("kind", "")), lines)
	(t.get_child(0).get_child(0) as Label).add_theme_color_override("font_color", Style.RARITY.get(String(it.get("rarity", "common")), Style.TEXT))
	return t


## The tip: its head (name, tag) and its lines, each as wide as its text, WIDTH at most.
static func _tip(title: String, tag: String, lines: Array) -> Control:
	var col := UI.vbox(3)
	col.name = "BarTip"
	var head := UI.hbox(12)
	var t := UI.cinzel(title, 15, 700, Style.BRASS_LIGHT)
	head.add_child(t)
	if tag != "":
		var k := UI.label(tag, "", 12, UI.DARK_MUTED)
		k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		k.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		k.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		head.add_child(k)
	col.add_child(head)
	var f: Font = UI.font("alegreya", 400)
	var w := f.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x + (f.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 12.0 if tag != "" else 0.0)
	var rows: Array = []
	for l in lines:
		var text: String = String(l.get("text", "")) if l is Dictionary else String(l)
		var tone: String = String(l.get("tone", "")) if l is Dictionary else ""
		w = maxf(w, f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 4.0)
		var r := UI.rich("[color=%s]%s[/color]" % [TONES.get(tone, UI.LIGHT).to_html(false), UI.esc(text)], "TooltipText")
		col.add_child(r)
		rows.append(r)
	col.custom_minimum_size.x = minf(w, WIDTH)
	# Each line as wide as the tip from the start: wrapped in no width, a line
	# would stand a word a row and the panel be sized to that.
	for r in rows:
		r.custom_minimum_size.x = col.custom_minimum_size.x
	return col


## The plain text of a tip (its labels' and rich texts', in order).
static func text_of(c: Node) -> String:
	if c == null:
		return ""
	var s := ""
	for n in [c] + c.find_children("*", "", true, false):
		if n is Label:
			s += (n as Label).text + "\n"
		elif n is RichTextLabel:
			s += (n as RichTextLabel).get_parsed_text() + "\n"
	return s
