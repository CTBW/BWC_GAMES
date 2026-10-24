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


func test_magic_missiles_leave_trails_of_light_and_do_not_stick() -> void:
	var fx = Fx.new()
	for kind in ["orb", "fireball", "shard", "stone"]:
		fx.shoot({"x0": 0, "y0": 0, "x1": 200, "y1": 0, "dur": 0.4, "arc": 20, "kind": kind, "scale": 1.0, "stick": true, "color": "#8fc8ff"})
	fx.update(0.1)
	var glows: Array = fx.particles.filter(func(p): return p.shape == "glow")
	# Fireballs every 12 ms, orbs and shards every 22 ms; stones none.
	assert_eq(glows.size(), 8 + 4 + 4, "trail particles")
	for p in glows:
		assert_between(p.life, 0.0, 0.45)
	fx.update(0.4)
	assert_false(fx.busy)
	assert_eq(fx.marks.size(), 0, "only bolts and arrows stick in the ground")


func test_lightning_flickers_and_tendrils_writhe_then_fade() -> void:
	var fx = Fx.new()
	fx.lightning(0, 0, 300, 100, {"width": 2.8, "branches": 2})
	fx.tendril(0, 0, 100, 50, {"color": "#d8261a", "core": "#ffb08a", "dark": "#4a0606", "width": 2.2, "amp": 10, "life": 0.6})
	assert_eq(fx.arcs.size(), 2)
	var bolt: Dictionary = fx.arcs[0]
	assert_eq(bolt.pts.size(), 33, "five levels of midpoint displacement")
	assert_eq(bolt.pts[0], Vector2(0, 0))
	assert_eq(bolt.pts[32], Vector2(300, 100))
	assert_eq(bolt.branches.size(), 2)
	assert_true(fx.arcs[1].has("tendril"))
	assert_false(fx.busy, "arcs do not hold up the playback")
	fx.update(0.4)
	assert_eq(fx.arcs.size(), 1, "the bolt is gone after its 0.32 s")
	fx.update(0.3)
	assert_eq(fx.arcs.size(), 0)


func test_spell_marks_on_the_ground() -> void:
	var fx = Fx.new()
	fx.mark(10, 20, "scorch", 1.6, 40)
	fx.mark(0, 0, "crater", 1.6, 60)
	fx.mark(0, 0, "frost", 1.1, 20)
	assert_eq(fx.marks.map(func(m): return m.kind), ["scorch", "crater", "frost"])
	fx.update(25)
	assert_eq(fx.marks.map(func(m): return m.kind), ["scorch", "crater"], "frost thaws first")


func test_light_is_flagged_for_the_additive_material() -> void:
	var fx = Fx.new()
	var c := Color(0.5, 0.6, 0.7, 1)
	assert_eq(fx._light(c, 0.5), Color(0.5, 0.6, 0.7, 0.5), "plain blending without the material")
	fx.additive = true
	assert_eq(fx._light(c, 0.5), Color(0.5 + Fx.ADD, 0.6, 0.7, 0.5), "red carries ADD")

