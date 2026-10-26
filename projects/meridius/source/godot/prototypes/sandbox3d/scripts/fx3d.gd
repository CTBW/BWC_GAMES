## Missiles and impact effects for the 3D sandbox: a crossbow bolt, the battle
## mage's four spells and the sparks of a blow. Simple glow cards, ribbons and
## meshes, made and freed here; `land` is called when a missile arrives (the
## sandbox resolves the blow), with the target it was loosed at.
##   bolt       a quarrel on a flat arc
##   arrow      a red-fletched arrow on a higher arc, slower than the bolt; it
##              lobs over the men of its own side in the way (the archers behind
##              their spears)
##   fireball   a ball of fire with embers behind, a burst where it lands
##   lightning  a jagged bolt flickering from the hand to the target
##   frost      a ring of frost swelling from the caster's feet
##   earth      a fist of rock bursting from the ground under the target
##   kiss       the succubus's Sovereign Kiss: a fog heart through the target (kiss_fx3d.gd)
extends Node3D

const KissFX = preload("res://prototypes/sandbox3d/scripts/kiss_fx3d.gd")
const GLOW_TEX_SIZE := 64

## (x, z) -> ground height; set by the sandbox.
var ground: Callable
## who -> the standing men of his side, whom an arrow lobs over; set by the sandbox.
var friends: Callable
var _glow: Texture2D
var _ring: Texture2D
var _live: Array = []
var _rng := RandomNumberGenerator.new()
var _kiss: Node3D


func _ready() -> void:
	_rng.seed = 9091
	_kiss = KissFX.new()
	_kiss.name = "Kiss"
	add_child(_kiss)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.35, Color(1, 1, 1, 0.55))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = GLOW_TEX_SIZE
	gt.height = GLOW_TEX_SIZE
	_glow = gt
	var r := Gradient.new()
	r.offsets = PackedFloat32Array([0.0, 0.62, 0.84, 0.93, 1.0])
	r.colors = PackedColorArray([Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.12), Color(1, 1, 1, 1.0), Color(1, 1, 1, 0.35), Color(1, 1, 1, 0.0)])
	var rt := GradientTexture2D.new()
	rt.gradient = r
	rt.fill = GradientTexture2D.FILL_RADIAL
	rt.fill_from = Vector2(0.5, 0.5)
	rt.fill_to = Vector2(1.0, 0.5)
	rt.width = 128
	rt.height = 128
	_ring = rt


func _ground(p: Vector3) -> float:
	return ground.call(p.x, p.z) if ground.is_valid() else 0.0


## A glowing card turned to the camera: additive light, or a soft puff (dust).
func _card(color: Color, size: float, add := true) -> MeshInstance3D:
	# Each card has its own material: it fades by its alpha (_fade).
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if add else BaseMaterial3D.BLEND_MODE_MIX
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_texture = _glow
	m.albedo_color = color
	m.disable_receive_shadows = true
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_meta("a", color.a)
	add_child(mi)
	return mi


## A card's opacity, as a fraction of its own.
func _fade(n: MeshInstance3D, f: float) -> void:
	n.material_override.albedo_color.a = float(n.get_meta("a", 1.0)) * clampf(f, 0.0, 1.0)


func _flat(tex: Texture2D, color: Color, size: float) -> MeshInstance3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_texture = tex
	m.albedo_color = color
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var q := PlaneMesh.new()
	q.size = Vector2(size, size)
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_meta("a", color.a)
	add_child(mi)
	return mi


## Loose a missile of `kind` from `who` at `target`; `land` is called with the
## target when it strikes (at once for the frost, which strikes all round).
func launch(kind: String, who: Node3D, target: Node3D, land: Callable) -> void:
	if kind == "kiss":
		_kiss.launch(who, target, land)
		return
	var h: float = who.height_m() if who.has_method("height_m") else 1.8
	var from := _at(who) + Vector3(0, h * 0.72, 0) + _facing(who) * 0.45
	# A unit whose sidecar says where its missile leaves (the archer's arrow, at the bow).
	var own: Variant = who.call("missile_from") if who.has_method("missile_from") else Vector3.INF
	if own != Vector3.INF:
		from = own
	var to := (_at(target) + Vector3(0, h * 0.55, 0)) if target else from + _facing(who) * 8.0
	match kind:
		"bolt", "arrow":
			var arrow := kind == "arrow"
			if arrow and target:
				# At the target's chest, as in flight, for the lob over the men in the way.
				to = _at(target) + Vector3(0, (target.height_m() if target.has_method("height_m") else 1.6) * 0.55, 0)
			var d := from.distance_to(to)
			var arc := d * (0.05 if arrow else 0.04)
			if arrow:
				arc = maxf(arc, _over_friends(who, from, to))
			# Flight time by the length of the path (a lob's is longer).
			var path := d * (1.0 + 8.0 / 3.0 * pow(arc / maxf(d, 0.01), 2.0)) if arrow else d
			var shaft := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.025, 0.025, 0.62) if arrow else Vector3(0.035, 0.035, 0.62)
			shaft.mesh = bm
			var sm := StandardMaterial3D.new()
			sm.albedo_color = Color(0.24, 0.17, 0.1)
			sm.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
			shaft.material_override = sm
			add_child(shaft)
			if arrow:
				# Two crossed red vanes at the back (the shaft flies down -Z).
				var fm := StandardMaterial3D.new()
				fm.albedo_color = Color(0.62, 0.12, 0.08)
				fm.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
				fm.cull_mode = BaseMaterial3D.CULL_DISABLED
				for size in [Vector3(0.1, 0.006, 0.13), Vector3(0.006, 0.1, 0.13)]:
					var vane := MeshInstance3D.new()
					var vm := BoxMesh.new()
					vm.size = size
					vane.mesh = vm
					vane.material_override = fm
					vane.position = Vector3(0, 0, 0.24)
					shaft.add_child(vane)
			var streak := _card(Color(1.0, 0.92, 0.7, 0.35), 0.35)
			_live.append({"kind": kind, "t": 0.0, "dur": maxf(path / (30.0 if arrow else 38.0), 0.08), "from": from, "to": to,
				"arc": arc, "nodes": [shaft, streak], "target": target, "land": land})
		"fireball":
			var core := _card(Color(1.0, 0.62, 0.2), 0.9)
			var halo := _card(Color(1.0, 0.3, 0.05, 0.6), 2.0)
			_live.append({"kind": "fireball", "t": 0.0, "dur": maxf(from.distance_to(to) / 13.0, 0.2), "from": from, "to": to,
				"arc": 0.9 + from.distance_to(to) * 0.08, "nodes": [core, halo], "target": target, "land": land, "ember": 0.0})
		"lightning":
			var im := ImmediateMesh.new()
			var mi := MeshInstance3D.new()
			mi.mesh = im
			var lm := StandardMaterial3D.new()
			lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			lm.vertex_color_use_as_albedo = true
			lm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			lm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			lm.cull_mode = BaseMaterial3D.CULL_DISABLED
			mi.material_override = lm
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)
			var flash := _card(Color(0.6, 0.75, 1.0, 0.9), 1.6)
			flash.position = to
			_live.append({"kind": "lightning", "t": 0.0, "dur": 0.42, "from": from, "to": to, "nodes": [mi, flash],
				"mesh": im, "target": target, "land": land, "landed": false, "re": 0.0})
		"frost":
			var at := who.global_position
			at.y = _ground(at) + 0.12
			var ring := _flat(_ring, Color(0.6, 0.85, 1.0, 0.95), 1.0)
			ring.position = at
			var glow := _card(Color(0.55, 0.8, 1.0, 0.7), 2.6)
			glow.position = at + Vector3(0, 0.6, 0)
			_live.append({"kind": "frost", "t": 0.0, "dur": 0.75, "at": at, "nodes": [ring, glow], "target": target, "land": land, "landed": false})
		"earth":
			var spot := to
			spot.y = _ground(spot)
			var rocks := []
			for i in 5:
				var r := MeshInstance3D.new()
				var cm := CylinderMesh.new()
				cm.top_radius = 0.02
				cm.bottom_radius = _rng.randf_range(0.22, 0.4)
				cm.height = _rng.randf_range(1.1, 1.9)
				cm.radial_segments = 5
				cm.rings = 1
				r.mesh = cm
				var rm := StandardMaterial3D.new()
				rm.albedo_color = Color(0.42, 0.35, 0.27).lerp(Color(0.55, 0.5, 0.42), _rng.randf())
				rm.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
				r.material_override = rm
				var a := TAU * i / 5.0 + _rng.randf() * 0.5
				var off := Vector3(cos(a), 0, sin(a)) * (0.0 if i == 0 else _rng.randf_range(0.35, 0.6))
				r.rotation = Vector3(off.z * 0.5, _rng.randf() * TAU, -off.x * 0.5)
				add_child(r)
				rocks.append({"node": r, "off": off, "h": cm.height})
			var dust := _card(Color(0.55, 0.45, 0.32, 0.75), 2.6, false)
			dust.position = spot + Vector3(0, 0.5, 0)
			_live.append({"kind": "earth", "t": 0.0, "dur": 1.5, "at": spot, "rocks": rocks, "nodes": [dust] + rocks.map(func(r): return r.node),
				"target": target, "land": land, "landed": false})


## The arc (the height at mid-flight over the straight line) an arrow from
## `from` to `to` needs to pass 0.25 m over the head of every man of `who`'s
## side within 0.4 m of its path, all the way over him (0.25 m before and
## behind his axis); 0 with none in the way, at most half the shot's length.
func _over_friends(who: Node3D, from: Vector3, to: Vector3) -> float:
	if not friends.is_valid():
		return 0.0
	var line := Vector2(to.x - from.x, to.z - from.z)
	var d := line.length()
	if d < 0.5:
		return 0.0
	var need := 0.0
	for m in friends.call(who):
		var g: Vector3 = _at(m)
		var rel := Vector2(g.x - from.x, g.z - from.z)
		var k := rel.dot(line) / (d * d)
		if k <= 0.0 or k >= 1.0 or absf(rel.cross(line)) / d > 0.4:
			continue
		var head: float = g.y + (m.height_m() if m.has_method("height_m") else 1.6) + 0.25
		for kk in [k - 0.25 / d, k, k + 0.25 / d]:
			if kk > 0.0 and kk < 1.0:
				need = maxf(need, (head - lerpf(from.y, to.y, kk)) / (4.0 * kk * (1.0 - kk)))
	return minf(need, d * 0.5)


## Sparks where a blow lands (warm), or dust where it misses.
func spark(at: Vector3, landed := true) -> void:
	var nodes := []
	var dirs := []
	for i in (7 if landed else 4):
		var c := _card(Color(1.0, 0.85, 0.5) if landed else Color(0.7, 0.62, 0.5, 0.6), 0.16 if landed else 0.5, landed)
		c.position = at
		nodes.append(c)
		dirs.append(Vector3(_rng.randf_range(-1, 1), _rng.randf_range(0.2, 1.2), _rng.randf_range(-1, 1)).normalized() * _rng.randf_range(2.0, 4.5))
	var flash := _card(Color(1.0, 0.9, 0.7, 0.8), 0.7)
	flash.position = at
	nodes.append(flash)
	dirs.append(Vector3.ZERO)
	_live.append({"kind": "spark", "t": 0.0, "dur": 0.35, "nodes": nodes, "dirs": dirs})


func _burst(at: Vector3, color: Color, size: float, dur := 0.45) -> void:
	var c := _card(color, size)
	c.position = at
	_live.append({"kind": "burst", "t": 0.0, "dur": dur, "nodes": [c], "size": size})


## Where a unit stands (its own position outside the tree, as in the tests).
func _at(n: Node3D) -> Vector3:
	return n.global_position if n.is_inside_tree() else n.position


func _facing(n: Node3D) -> Vector3:
	var y := n.global_rotation.y if n.is_inside_tree() else n.rotation.y
	return Vector3(sin(y), 0, cos(y))


func clear() -> void:
	for e in _live:
		for n in e.nodes:
			n.queue_free()
	_live.clear()
	_kiss.clear()


func _process(dt: float) -> void:
	for e in _live.duplicate():
		e.t += dt
		var k: float = clampf(e.t / e.dur, 0.0, 1.0)
		match e.kind:
			"bolt", "arrow", "fireball":
				var target: Node3D = e.target
				if target and is_instance_valid(target):
					var h: float = target.height_m() if target.has_method("height_m") else 1.6
					e.to = _at(target) + Vector3(0, h * 0.55, 0)
				var p: Vector3 = e.from.lerp(e.to, k) + Vector3.UP * e.arc * 4.0 * k * (1.0 - k)
				var ahead: Vector3 = e.from.lerp(e.to, minf(k + 0.02, 1.0)) + Vector3.UP * e.arc * 4.0 * minf(k + 0.02, 1.0) * (1.0 - minf(k + 0.02, 1.0))
				for n in e.nodes:
					n.position = p
				if e.kind != "fireball" and ahead.distance_to(p) > 1e-4 and e.nodes[0].is_inside_tree():
					e.nodes[0].look_at(ahead, Vector3.UP)
				if e.kind == "fireball":
					e.nodes[0].scale = Vector3.ONE * (0.9 + 0.15 * sin(e.t * 40.0))
					e.ember += dt
					while e.ember > 0.025:
						e.ember -= 0.025
						var em := _card(Color(1.0, 0.45, 0.1, 0.8), _rng.randf_range(0.25, 0.5))
						em.position = p + Vector3(_rng.randf_range(-0.1, 0.1), _rng.randf_range(-0.1, 0.1), _rng.randf_range(-0.1, 0.1))
						_live.append({"kind": "ember", "t": 0.0, "dur": 0.4, "nodes": [em], "v": Vector3(0, 0.8, 0)})
				if k >= 1.0:
					_end(e)
					if e.kind == "fireball":
						_burst(p, Color(1.0, 0.55, 0.15), 3.6, 0.5)
						_burst(p, Color(1.0, 0.85, 0.5), 1.6, 0.3)
					else:
						spark(p, true)
					if e.land.is_valid():
						e.land.call(e.target)
			"lightning":
				e.re -= dt
				if e.re <= 0.0:
					e.re = 0.035
					_bolt(e.mesh, e.from, e.to, 1.0 - k * 0.6)
				e.nodes[1].scale = Vector3.ONE * (1.0 + _rng.randf() * 0.4) * (1.0 - k)
				if not e.landed and e.t > 0.06:
					e.landed = true
					if e.land.is_valid():
						e.land.call(e.target)
				if k >= 1.0:
					_end(e)
			"frost":
				var r: float = lerpf(0.6, 6.0, ease(k, 0.4))
				e.nodes[0].scale = Vector3(r, 1, r)
				_fade(e.nodes[0], 1.0 - k)
				e.nodes[1].scale = Vector3.ONE * (1.0 + k)
				_fade(e.nodes[1], 1.0 - k)
				if not e.landed and k > 0.35:
					e.landed = true
					if e.land.is_valid():
						e.land.call(e.target)
				if k >= 1.0:
					_end(e)
			"earth":
				var up := clampf(e.t / 0.14, 0.0, 1.0)
				var down := clampf((e.t - 0.9) / 0.5, 0.0, 1.0)
				for rk in e.rocks:
					var lift: float = rk.h * (ease(up, 0.3) - down) - rk.h * 0.55
					rk.node.position = e.at + rk.off + Vector3(0, lift, 0)
				var dust: MeshInstance3D = e.nodes[0]
				dust.scale = Vector3.ONE * (0.8 + e.t)
				_fade(dust, 1.0 - clampf((e.t - 0.2) * 0.9, 0.0, 1.0))
				if not e.landed and e.t > 0.1:
					e.landed = true
					_burst(e.at + Vector3(0, 0.6, 0), Color(0.9, 0.7, 0.45, 0.6), 2.4, 0.4)
					if e.land.is_valid():
						e.land.call(e.target)
				if k >= 1.0:
					_end(e)
			"spark":
				for i in e.nodes.size():
					var n: MeshInstance3D = e.nodes[i]
					n.position += e.dirs[i] * dt
					e.dirs[i] += Vector3(0, -9.0, 0) * dt
					n.scale = Vector3.ONE * (1.0 - k * 0.7)
					_fade(n, 1.0 - k)
				if k >= 1.0:
					_end(e)
			"burst":
				e.nodes[0].scale = Vector3.ONE * lerpf(0.4, 1.0, ease(k, 0.3))
				_fade(e.nodes[0], 1.0 - k)
				if k >= 1.0:
					_end(e)
			"ember":
				e.nodes[0].position += e.v * dt
				_fade(e.nodes[0], 1.0 - k)
				e.nodes[0].scale = Vector3.ONE * (1.0 - k * 0.6)
				if k >= 1.0:
					_end(e)


func _end(e: Dictionary) -> void:
	for n in e.nodes:
		n.queue_free()
	_live.erase(e)


## A jagged bolt from a to b as a ribbon turned to the camera, with a thinner
## branch or two.
func _bolt(im: ImmediateMesh, a: Vector3, b: Vector3, bright: float) -> void:
	im.clear_surfaces()
	var cam := get_viewport().get_camera_3d()
	var view := -cam.global_basis.z if cam else Vector3(-1, -1, -1).normalized()
	var pts := _jag(a, b, 12, 0.35)
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	_ribbon(im, pts, view, 0.16, Color(0.45, 0.6, 1.0, 0.55 * bright))
	_ribbon(im, pts, view, 0.05, Color(0.9, 0.95, 1.0, bright))
	for i in 2:
		var j := _rng.randi_range(3, pts.size() - 3)
		var tip: Vector3 = pts[j] + Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-0.6, 0.4), _rng.randf_range(-1, 1)) * 1.3
		_ribbon(im, _jag(pts[j], tip, 4, 0.2), view, 0.035, Color(0.75, 0.85, 1.0, 0.8 * bright))
	im.surface_end()


func _jag(a: Vector3, b: Vector3, n: int, amp: float) -> Array:
	var pts := [a]
	for i in range(1, n):
		var f := float(i) / n
		pts.append(a.lerp(b, f) + Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * amp * sin(f * PI))
	pts.append(b)
	return pts


func _ribbon(im: ImmediateMesh, pts: Array, view: Vector3, w: float, c: Color) -> void:
	for i in pts.size() - 1:
		var p0: Vector3 = pts[i]
		var p1: Vector3 = pts[i + 1]
		var side := (p1 - p0).cross(view).normalized() * w * 0.5
		for v in [p0 - side, p0 + side, p1 + side, p0 - side, p1 + side, p1 - side]:
			im.surface_set_color(c)
			im.surface_add_vertex(v)
