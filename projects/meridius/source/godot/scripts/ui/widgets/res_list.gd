## Port of common.tsx `ResList` and `RES_NAMES`: a row of resource icons with amounts.
##
##   const ResList = preload("res://scripts/ui/widgets/res_list.gd")
##   ResList.make(res: Dictionary, size := 16, nothing_variation := "MutedLabel") -> Control
##       Non-zero entries in the dictionary's order, each an icon (`size` px, title =
##       resource name) and its amount (Cinzel 700, size − 2). Gap 10 between
##       entries. An empty/all-zero dictionary shows "Nothing" (muted).
##   ResList.RES_NAMES  {silver: "Silver", timber: "Timber", iron: "Iron", trophies: "War trophies"}
extends RefCounted

const UI = preload("res://scripts/ui/ui.gd")
const Icon = preload("res://scripts/ui/widgets/icon.gd")

const RES_NAMES := {"silver": "Silver", "timber": "Timber", "iron": "Iron", "trophies": "War trophies"}


static func make(res: Dictionary, size := 16, nothing_variation := "MutedLabel") -> Control:
	var keys: Array = []
	for k in res:
		var v: Variant = res[k]
		if v != null and v != 0:
			keys.append(k)
	if keys.is_empty():
		return UI.label("Nothing", nothing_variation)
	var row := UI.hbox(10)
	row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for k in keys:
		var item := UI.hbox(6)
		item.add_child(Icon.make(k, size, RES_NAMES.get(k, k)))
		var n := UI.label(str(res[k]), "ResLabel", size - 2)
		n.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		item.add_child(n)
		row.add_child(item)
	return row
