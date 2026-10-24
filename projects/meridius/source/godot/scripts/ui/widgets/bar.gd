## Port of common.tsx `Bar`: a thin progress bar (`.bar.<kind>`).
##
##   const Bar = preload("res://scripts/ui/widgets/bar.gd")
##   Bar.make(value: float, max: float, kind: String, height := 9, label := "") -> ProgressBar
##       kind: "hp" (turns HpLowBar below 35 %), "morale", "fatigue", "xp", "cp",
##       "over", "cp over". `label` is the hover tooltip. Fill = clamp(value / max).
##   Bar.update(bar, value, max, kind)   change the value / kind of an existing bar
##   Bar.variation(kind, fraction) -> String   the ProgressBar theme variation
extends RefCounted


static func variation(kind: String, f: float) -> String:
	if kind.contains("over"):
		return "OverBar"
	match kind:
		"hp":
			return "HpLowBar" if f < 0.35 else "HpBar"
		"morale":
			return "MoraleBar"
		"fatigue":
			return "FatigueBar"
		"xp":
			return "XpBar"
		"cp":
			return "CpBar"
	return "HpBar"


static func make(value: float, max_value: float, kind: String, height := 9, label := "") -> ProgressBar:
	var b := ProgressBar.new()
	b.show_percentage = false
	b.min_value = 0.0
	b.max_value = 1.0
	b.step = 0.0
	b.custom_minimum_size.y = height
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.mouse_filter = Control.MOUSE_FILTER_PASS if label != "" else Control.MOUSE_FILTER_IGNORE
	b.tooltip_text = label
	update(b, value, max_value, kind)
	return b


static func update(b: ProgressBar, value: float, max_value: float, kind: String) -> void:
	var f := clampf(value / max_value if max_value != 0.0 else 0.0, 0.0, 1.0)
	b.value = f
	b.theme_type_variation = variation(kind, f)
