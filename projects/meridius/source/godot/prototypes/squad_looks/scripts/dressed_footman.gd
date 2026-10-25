## The sandbox's footman (prototypes/sandbox3d/scripts/footman_unit.gd) in his
## look in his squad: set `look_spec` (a man from squad_look.gd) before he
## enters the tree, and unit_look.gd dresses him whenever his look is set.
extends "res://prototypes/sandbox3d/scripts/footman_unit.gd"

const UnitLook := preload("res://prototypes/squad_looks/scripts/unit_look.gd")

## Empty leaves the export's own materials.
var look_spec := {}


func set_look(mode: String, outline: bool) -> void:
	super.set_look(mode, outline)
	if not look_spec.is_empty():
		UnitLook.paint(self, look_spec, mode, outline)


func set_outline_width(metres: float) -> void:
	super.set_outline_width(metres)
	UnitLook.set_outline_width(metres)
