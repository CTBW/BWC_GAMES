## The `.card` container: a light inset card on parchment, optionally clickable
## (hover highlight, pointer), selected (`.sel`, gold border and ring) or
## disabled-looking (`.disabled`, 55 % opacity; still clickable, as in the original).
##
##   const Card = preload("res://scripts/ui/widgets/card.gd")
##   Card.make(on_click := Callable(), selected := false, disabled := false, padding := []) -> PanelContainer
##       Emits `pressed` on a left click when clickable. padding: UI.pad() order.
##   card.set_selected(bool), card.set_disabled_look(bool)
extends PanelContainer

signal pressed

const UI = preload("res://scripts/ui/ui.gd")

var clickable := false
var selected := false
var disabled_look := false
var _hover := false
var _padding: Array = []


static func make(on_click := Callable(), selected_ := false, disabled_ := false, padding: Array = []) -> PanelContainer:
	var c: PanelContainer = load("res://scripts/ui/widgets/card.gd").new()
	c._padding = padding
	c.clickable = on_click.is_valid()
	if c.clickable:
		c.pressed.connect(on_click)
		c.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	c.selected = selected_
	c.disabled_look = disabled_
	c.mouse_filter = Control.MOUSE_FILTER_STOP if c.clickable else Control.MOUSE_FILTER_PASS
	c._restyle()
	c.mouse_entered.connect(c._on_hover.bind(true))
	c.mouse_exited.connect(c._on_hover.bind(false))
	return c


func _on_hover(on: bool) -> void:
	_hover = on
	_restyle()


func set_selected(v: bool) -> void:
	selected = v
	_restyle()


func set_disabled_look(v: bool) -> void:
	disabled_look = v
	_restyle()


func _restyle() -> void:
	var h := _hover and clickable
	var v := "ParchmentCard"
	if selected:
		v = "ParchmentCardSelectedHover" if h else "ParchmentCardSelected"
	elif h:
		v = "ParchmentCardHover"
	theme_type_variation = v
	remove_theme_stylebox_override("panel")
	if not _padding.is_empty():
		UI.pad(self, _padding)
	modulate.a = 0.55 if disabled_look else 1.0


func _gui_input(e: InputEvent) -> void:
	if clickable and e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		pressed.emit()
