## Adds the sandbox's dummy to the production depth sort, lighting and shadows.
extends "res://scripts/render/battle_draw.gd"

static var _dummy: Dictionary = {}


func member_sprite(uv, m) -> Array:
	if m.type != "practice_dummy":
		return super.member_sprite(uv, m)
	if _dummy.is_empty():
		var texture := load("res://assets/sprites/training_dummy.svg") as Texture2D
		_dummy = {"file": "res://assets/sprites/training_dummy.svg", "key": "practice_dummy", "v": 0,
			"tex": texture, "region": Rect2(0, 0, 144, 176), "ax": 72.0, "ay": 166.0,
			"w": 144, "h": 176, "scale": 0.7, "noShadow": false, "art": true}
	return [_dummy, false, _dummy.tex, Rect2(-72, -166, 144, 176), _dummy.region, 0.7]
