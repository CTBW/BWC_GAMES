## The `.tag` chip of src/ui/styles.css (Cinzel 700 11.5 px on a tinted
## rounded box), optionally with an icon.
##
##   const Tag = preload("res://scripts/ui/widgets/tag.gd")
##   Tag.make(text: String, kind := "", icon := "", font_size := 0, title := "", pad_h := -1) -> PanelContainer
##       kind: "" | "red" | "blue" | "gold" | "green" (theme variations Tag<Kind> + Tag<Kind>Label;
##       inside a dark panel every kind takes the light dark-panel look).
##       icon: an icon name (12 px) before the text, or a TextureRect/Control.
##       font_size: e.g. 10 for the small tags of the roster cards. pad_h: horizontal padding.
##   Tag.make_with(children: Array, kind := "", font_size := 0) -> PanelContainer   arbitrary content
extends RefCounted

const UI = preload("res://scripts/ui/ui.gd")
const Icon = preload("res://scripts/ui/widgets/icon.gd")


static func _kind(kind: String) -> String:
	return kind.capitalize() if kind != "" else ""


static func make(text: String, kind := "", icon: Variant = "", font_size := 0, title := "", pad_h := -1) -> PanelContainer:
	var children: Array = []
	if icon is String and icon != "":
		children.append(Icon.make(icon, 12))
	elif icon is Control:
		children.append(icon)
	if text != "":
		children.append(UI.label(text, "Tag%sLabel" % _kind(kind), font_size))
	var p := make_with(children, kind, font_size)
	if title != "":
		p.tooltip_text = title
	if pad_h >= 0:
		UI.pad(p, [1, pad_h])
	return p


static func make_with(children: Array, kind := "", font_size := 0) -> PanelContainer:
	var p := PanelContainer.new()
	p.theme_type_variation = "Tag" + _kind(kind)
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var row := UI.hbox(4, children)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	for c in children:
		if c is Label:
			(c as Label).size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.add_child(row)
	return p
