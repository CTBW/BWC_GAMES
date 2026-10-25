extends "res://tests/test_case.gd"

## The squad looks prototype (prototypes/squad_looks): who a squad's men are
## (squad_look.gd) and the parts of unit_look.gd that need no model (the
## footman's export is not in Git): the layers, the helmets' fit, the
## shield's charge mask.

const SquadLook = preload("res://prototypes/squad_looks/scripts/squad_look.gd")
const UnitLook = preload("res://prototypes/squad_looks/scripts/unit_look.gd")


func _men(n := 6, seed_ := 42, kit := "line") -> Array:
	return SquadLook.squad(n, seed_, SquadLook.LIVERIES[0], kit, SquadLook.MARKS[1])


func test_the_same_seed_gives_the_same_men() -> void:
	var a := _men()
	var b := _men()
	for i in a.size():
		assert_eq(SquadLook.describe(a[i]), SquadLook.describe(b[i]), "man %d" % i)
		assert_eq(a[i].hair, b[i].hair, "man %d's hair" % i)
		assert_eq(a[i].dye, b[i].dye, "man %d's dye" % i)
	assert_ne(SquadLook.describe(_men(6, 43)[1]) + SquadLook.describe(_men(6, 43)[2]),
		SquadLook.describe(a[1]) + SquadLook.describe(a[2]), "another seed, other men")


func test_only_the_leader_wears_a_plume_on_a_helmet() -> void:
	for seed_ in range(1, 30):
		for kit in SquadLook.KITS:
			var men := _men(1 + seed_ % 6, seed_, kit)
			assert_true(men[0].leader and men[0].plume.a > 0.0, "a leader's plume")
			assert_true(men[0].helmet in ["kettle", "nasal", "skullcap"], "a leader's helmet (%s)" % men[0].helmet)
			for m in men.slice(1):
				assert_false(m.leader, "one leader")
				assert_eq(m.plume.a, 0.0, "no plume but the leader's")


func test_the_bags_spread_the_men() -> void:
	# A shuffle bag: in a line squad of six, at least three helmet kinds and
	# four hair colours, every seed (dice would give clones now and then).
	for seed_ in range(1, 40):
		var men := _men(6, seed_)
		var helmets := {}
		var hair := {}
		for m in men:
			helmets[m.helmet] = true
			hair[m.hair_name] = true
		assert_true(helmets.size() >= 3, "seed %d: %d helmet kinds" % [seed_, helmets.size()])
		assert_true(hair.size() >= 4, "seed %d: %d hair colours" % [seed_, hair.size()])


func test_a_squad_shares_its_livery_and_shield() -> void:
	var men := _men()
	for m in men:
		assert_eq(m.livery, SquadLook.LIVERIES[0].cloth, "livery")
		assert_eq(m.division, SquadLook.MARKS[1].division, "the mark's division")
		assert_eq(m.field2, SquadLook.MARKS[1].field2, "the mark's tincture")


func test_layers_off_leave_the_texture_as_painted() -> void:
	var was := UnitLook.layers.duplicate()
	for l in UnitLook.LAYERS:
		UnitLook.layers[l] = false
	var p := UnitLook.params(_men()[3])
	assert_eq(p.cloth, UnitLook.REF.cloth, "cloth")
	assert_eq(p.trousers, UnitLook.REF.cloth, "trousers")
	assert_eq(p.linen, UnitLook.REF.linen, "linen")
	assert_eq(p.leather, UnitLook.REF.brown, "leather")
	assert_eq(p.hair, UnitLook.REF.brown, "hair")
	assert_eq(p.skin, UnitLook.REF.skin, "skin")
	assert_eq(p.field, UnitLook.REF.field, "shield field")
	assert_eq([p.beard, p.grime, p.wear, p.division], [0.0, 0.0, 0.0, 0.0], "no beard, dirt or division")
	UnitLook.layers = was
	var c := Color(0.3, 0.4, 0.6)
	var d := UnitLook.dyed(c, Vector3.ZERO)
	assert_almost(d.r, c.r, 1e-5, "undyed r")
	assert_almost(d.b, c.b, 1e-5, "undyed b")


func test_helmets_clear_the_head() -> void:
	# A head 0.22 m tall, its outline widest at the brow and closing over the crown.
	var env := []
	for b in UnitLook.ENV_BANDS + 1:
		env.append(cos(float(b) / UnitLook.ENV_BANDS * PI * 0.45))
	var fit := {"chin": 1.58, "crown": 1.8, "rim": 1.69, "mouth_y": 1.635, "cx": 0.0, "cz": 0.0,
		"rx": 0.1, "rz": 0.11, "face_z": 0.1, "env": env}
	for kind in ["kettle", "nasal", "skullcap", "cap"]:
		var m: ArrayMesh = UnitLook._gear_mesh(kind, fit)
		var worst := INF
		for s in m.get_surface_count():
			for v in m.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
				if v.y > fit.rim + 0.01 and v.y < fit.crown:
					var r := Vector2(v.x / fit.rx, v.z / fit.rz).length()
					worst = minf(worst, r - UnitLook._need(fit, v.y) + UnitLook.MARGIN)
		assert_true(worst > 0.0, "%s clears the outline (by %.3f of the radius)" % [kind, worst])
		assert_true(m.get_aabb().end.y > fit.crown, kind + " covers the crown")


func test_the_charge_mask_is_the_patch_the_field_encloses() -> void:
	# Field blue all over; a light disc on the front (the charge) and a light
	# band along the front's edge (as the rim's metal): only the disc is a charge.
	var img := Image.create(1000, 1000, false, Image.FORMAT_RGB8)
	img.fill(UnitLook.REF.field)
	for y in range(500, 1000):
		for x in range(580, 600):
			img.set_pixel(x, y, Color(0.85, 0.85, 0.86))
	for y in range(690, 811):
		for x in range(730, 851):
			if Vector2(x - 790, y - 750).length() < 60.0:
				img.set_pixel(x, y, Color(0.88, 0.87, 0.85))
	var mask: Image = UnitLook._charge_mask(ImageTexture.create_from_image(img)).tex.get_image()
	var s := mask.get_size()
	# The front (u 0.58..1, v 0.5..1) at half its size.
	assert_true(mask.get_pixel(int(s.x * 0.5), int(s.y * 0.5)).r > 0.5, "the disc is the charge")
	assert_true(mask.get_pixel(3, int(s.y * 0.5)).r < 0.5, "the edge band is not")
	assert_true(mask.get_pixel(int(s.x * 0.85), int(s.y * 0.15)).r < 0.5, "the field is not")
