## A vertical `.scroll` area that is as tall as its content up to `max_height`
## (CSS `max-height` + `overflow-y: auto`), with the thin theme scrollbar.
##
##   const ScrollBox = preload("res://scripts/ui/widgets/scroll_box.gd")
##   ScrollBox.make(content: Control, max_height: float, right_pad := 0) -> ScrollContainer
##       max_height <= 0: fill the parent (CSS flex: 1; min-height: 0).
##       right_pad: space kept for the scrollbar (CSS paddingRight).
extends ScrollContainer

var max_height := 0.0
var content: Control


static func make(content_: Control, max_height_: float, right_pad := 0) -> ScrollContainer:
	var s: ScrollContainer = load("res://scripts/ui/widgets/scroll_box.gd").new()
	s.max_height = max_height_
	s.content = content_
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	s.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.mouse_filter = Control.MOUSE_FILTER_PASS
	if max_height_ <= 0.0:
		s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if right_pad > 0:
		var m := MarginContainer.new()
		m.add_theme_constant_override("margin_right", right_pad)
		m.mouse_filter = Control.MOUSE_FILTER_IGNORE
		m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		m.add_child(content_)
		s.add_child(m)
		m.minimum_size_changed.connect(s._fit)
	else:
		s.add_child(content_)
		content_.minimum_size_changed.connect(s._fit)
	s._fit()
	return s


func _fit() -> void:
	if max_height <= 0.0 or get_child_count() == 0:
		return
	var c := get_child(0) as Control
	var h := c.get_combined_minimum_size().y
	custom_minimum_size.y = minf(h, max_height)
