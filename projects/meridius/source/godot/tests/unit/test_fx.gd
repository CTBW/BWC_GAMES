## FX (src/render/fx.ts): particles, texts, projectiles, marks and rings.
extends "res://tests/test_case.gd"

const Fx = preload("res://scripts/render/fx.gd")
const WD = preload("res://scripts/render/world_draw.gd")


func test_css_colours() -> void:
	assert_eq(WD.css("#fff"), Color(1, 1, 1, 1))
	assert_eq(WD.css("#ffb347"), Color8(0xff, 0xb3, 0x47))
	var c := WD.css("rgba(210,210,205,0.5)")
	assert_almost(c.r, 210 / 255.0, 1e-6)
	assert_almost(c.a, 0.5, 1e-6)
	assert_eq(WD.css(Color.RED), Color.RED)


func test_burst_and_update() -> void:
	var fx = Fx.new()
	fx.burst(10, 20, 5, 7, {"shape": "puff", "color": "rgba(210,210,205,1)", "speed": 6, "vz": 40, "gravity": -8, "size": 10, "max": 3, "drag": 0.2})
	assert_eq(fx.particles.size(), 7)
	for p in fx.particles:
		assert_between(p.life, 3 * 0.6, 3 * 1.2)
		assert_eq(p.shape, "puff")
	fx.burst(0, 0, 0, 4, {"colors": ["#ff0000", "#00ff00"]})
	assert_eq(fx.particles[7].color, Color(1, 0, 0))
	assert_eq(fx.particles[8].color, Color(0, 1, 0))
	for i in 300:
		fx.update(1.0 / 60.0)
	assert_eq(fx.particles.size(), 0, "particles expire")


func test_particles_bounce_on_ground() -> void:
	var fx = Fx.new()
	fx.burst(0, 0, 1, 1, {"vz": -100, "gravity": 300, "max": 10})
	fx.update(0.1)
	assert_almost(fx.particles[0].z, 0.0, 1e-9, "z clamps at the ground")


func test_text_stacking() -> void:
	var fx = Fx.new()
	fx.text(100, 200, "12", "#ffd76a")
	fx.text(105, 210, "Hit", "#fff", {"size": 14, "delay": 0.2})
	assert_eq(fx.texts.size(), 2)
	assert_almost(fx.texts[1].y, 210 - 18.0, 1e-9, "second text stacks above")
	fx.update(0.1)
	assert_almost(fx.texts[1].delay, 0.1, 1e-9, "delayed text waits")
	assert_almost(fx.texts[1].y, 192.0, 1e-9)
	for i in 120:
		fx.update(1.0 / 30.0)
	assert_eq(fx.texts.size(), 0)


func test_projectile_hits_and_sticks() -> void:
	var fx = Fx.new()
	var hits := [0]
	fx.shoot({"x0": 0, "y0": 0, "x1": 100, "y1": 50, "dur": 0.5, "arc": 30, "kind": "bolt", "stick": true, "onHit": func() -> void: hits[0] += 1})
	assert_true(fx.busy)
	fx.update(0.3)
	assert_eq(hits[0], 0)
	fx.update(0.3)
	assert_eq(hits[0], 1, "onHit once")
	assert_false(fx.busy)
	assert_eq(fx.marks.size(), 1)
	assert_almost(fx.marks[0].angle, atan2(50, 100), 1e-9)
	for i in 100:
		fx.marks.append({"x": 0, "y": 0, "angle": 0, "kind": "arrow", "life": 40, "scale": 1})
	fx.update(0.01)
	assert_eq(fx.marks.size(), 90, "at most 90 marks")


func test_ring_grows_and_fades() -> void:
	var fx = Fx.new()
	fx.ring(0, 0, 60, "#ffd76a")
	fx.update(0.1)
	assert_between(fx.rings[0].r, 4.0, 60.0)
	fx.update(0.7)
	assert_eq(fx.rings.size(), 0)


func test_draws_without_errors() -> void:
	var fx = Fx.new()
	fx.burst(0, 0, 0, 3, {"shape": "spark"})
	fx.burst(0, 0, 0, 3, {"shape": "leaf"})
	fx.burst(0, 0, 0, 3, {})
	fx.text(0, 0, "7", "#fff")
	fx.ring(0, 0, 40, "rgba(255,0,0,0.5)")
	fx.shoot({"x0": 0, "y0": 0, "x1": 10, "y1": 10, "dur": 1.0, "arc": 5, "kind": "arrow", "scale": 0.6})
	fx.update(0.05)
	var n := Node2D.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(n)
	# _draw-only calls: run them through a draw callback.
	n.draw.connect(func() -> void:
		fx.draw_ground(n)
		fx.draw_air(n)
		fx.draw_texts(n, 0.7))
	n.queue_redraw()
	n.free()
