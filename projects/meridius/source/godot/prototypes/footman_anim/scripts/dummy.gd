## Straw training dummy for the prototype: takes any number of blows. Each hit
## is a spring impulse about its foot (it rocks away and back), a squash, a
## warm flash and a puff of straw. Art: a copy of the game's training dummy.
extends Node2D

const TEX := preload("res://prototypes/footman_anim/art/dummy/training_dummy.svg")
const FLASH := preload("res://prototypes/footman_anim/shaders/flash.gdshader")

## Ground radius for the formation checks (grid units) and the height of the sack.
const RADIUS := 0.13
const BODY_HEIGHT := 62.0

var sprite: Sprite2D
var fx: Node2D
var hits := 0
var playback := 1.0
var _th := 0.0
var _w := 0.0
var _squash := 0.0
var _sq_v := 0.0
var _flash := 0.0
var _mat: ShaderMaterial


func _ready() -> void:
	sprite = Sprite2D.new()
	sprite.texture = TEX
	sprite.centered = false
	# The SVG's foot is at (72, 166); imported at 2x.
	sprite.offset = -Vector2(72, 166) * 2.0
	sprite.scale = Vector2.ONE * 0.24
	_mat = ShaderMaterial.new()
	_mat.shader = FLASH
	sprite.material = _mat
	add_child(sprite)


## Where a blade should meet it: the sack's middle, nudged toward the attacker.
func strike_point(from: Vector2) -> Vector2:
	var c := global_position + Vector2(0, -BODY_HEIGHT * 0.62)
	var d := (from - c)
	d.y *= 0.5
	return c + d.normalized() * 9.0 if d.length() > 0.1 else c


func hit(at: Vector2, from_dir: Vector2) -> void:
	hits += 1
	var side := signf(from_dir.x) if absf(from_dir.x) > 0.05 else 1.0
	_w += side * 3.4
	_sq_v -= 2.6
	_flash = 1.0
	if fx:
		fx.straw(at, from_dir)


func _process(dt: float) -> void:
	var d := dt * playback
	var steps := maxi(1, ceili(d / (1.0 / 120.0)))
	var h := d / steps
	for i in steps:
		var a := -110.0 * _th - 7.5 * _w
		_w += a * h
		_th = clampf(_th + _w * h, -0.35, 0.35)
		var sa := -260.0 * _squash - 14.0 * _sq_v
		_sq_v += sa * h
		_squash = clampf(_squash + _sq_v * h, -0.2, 0.2)
	_flash = maxf(0.0, _flash - d * 9.0)
	sprite.rotation = _th
	sprite.scale = Vector2(0.24 * (1.0 - _squash * 0.6), 0.24 * (1.0 + _squash))
	_mat.set_shader_parameter("flash", _flash)
