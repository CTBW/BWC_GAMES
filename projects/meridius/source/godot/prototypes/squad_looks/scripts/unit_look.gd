## Dresses a squad's footman (dressed_footman.gd) in his look (squad_look.gd):
##  - Regions: his body mesh is copied once per model with vertex colours made
##    from its skin weights (R head and neck, G legs, B the lower face, A the
##    height at rest / 2 m), which unit_variant.gdshader needs to tell hair
##    from leather and trousers from the scarf in a texture without masks.
##  - Materials: one ShaderMaterial per look mode (toon, flat, PBR) for the
##    body, one for the shield and one for the gear, shared by every man; his
##    own colours are per-instance uniforms on his meshes.
##  - Gear: a kettle hat, nasal helm, skullcap or padded cap, and the leader's
##    plume, built once per kind as surfaces of revolution fitted to the
##    head's outline (with a margin all round, so the hair never shows
##    through), riding a BoneAttachment3D on the Head bone.
##  - Build and glances: body_shape.gd under his Skeleton3D.
## `layers` switches parts of the variety off (the squad look lab compares
## them); `refresh` applies a change to a dressed man.
extends RefCounted

const BODY_SHADER := preload("res://prototypes/squad_looks/shaders/unit_variant.gdshader")
const SHIELD_SHADER := preload("res://prototypes/squad_looks/shaders/shield_variant.gdshader")
const GEAR_SHADER := preload("res://prototypes/squad_looks/shaders/gear.gdshader")
const OUTLINE := preload("res://prototypes/footman_anim/shaders/outline3d.gdshader")
const BodyShape := preload("res://prototypes/squad_looks/scripts/body_shape.gd")

const LAYERS := ["livery", "clothes", "faces", "helmets", "build", "glances", "grime"]
const LAYER_TITLES := {"livery": "Livery and shield", "clothes": "Own clothes and dye", "faces": "Hair, skin, beard",
	"helmets": "Helmets and plume", "build": "Build", "glances": "Glances", "grime": "Dirt and wear"}
## The footman texture's band means (footman_fantasy_character_3d_model_basecolor.jpg
## and the shield's, measured): a target equal to one leaves its band as painted.
const REF := {
	"cloth": Color(0.234, 0.276, 0.418), "linen": Color(0.800, 0.713, 0.618),
	"brown": Color(0.344, 0.238, 0.180), "skin": Color(0.848, 0.638, 0.482),
	"field": Color(0.231, 0.326, 0.495), "charge": Color(0.86, 0.86, 0.86),
}
## The shield texture's front island (UV), where its charge is looked for.
const FRONT_LO := Vector2(0.58, 0.5)
const FRONT_HI := Vector2(1.0, 1.0)
## Gap between the head's outline and a helmet (fraction of the skull's radii).
const MARGIN := 0.09
## The hair under a helmet: across and up from the brow (see _crop).
const CROP := Vector2(0.86, 0.6)

## Layer name -> on (a missing name is on).
static var layers := {}
static var outline_mat: ShaderMaterial
static var _regions := {}
static var _cropped := {}
static var _fits := {}
static var _gear := {}
static var _mats := {}
static var _shaders := {}
static var _charges := {}
static var _faces := {}


static func on(layer: String) -> bool:
	return layers.get(layer, true)


# --- Dressing --------------------------------------------------------------------

## Paint `u` in `mode` (toon, flat, pbr), dressing him first if he is not yet.
## Called from his set_look, after the export's own materials are set.
static func paint(u: Node3D, spec: Dictionary, mode: String, outline: bool) -> void:
	var body := _body(u)
	if body == null:
		return
	if not u.has_meta("dressed"):
		_dress(u, body, spec)
	var tex: Texture2D = _albedo(body.mesh.surface_get_material(0))
	body.set_surface_override_material(0, _material("body", mode, outline, tex, body))
	var shield := _part(u, "Shield")
	if shield != null:
		var stex: Texture2D = _albedo(shield.mesh.surface_get_material(0))
		shield.set_surface_override_material(0, _material("shield", mode, outline, stex, shield))
	for g in u.get_meta("gear", []):
		g.material_override = _material("gear", mode, outline, null, g)
	refresh(u)


## Apply the look and the layers to a dressed man: his instance uniforms, his
## gear's visibility, his build and glances.
static func refresh(u: Node3D) -> void:
	if not u.has_meta("dressed"):
		return
	var spec: Dictionary = u.get_meta("look")
	var p := params(spec)
	var body := _body(u)
	var full: Mesh = u.get_meta("full_mesh")
	var want: Mesh = _cropped.get(full, full) if on("helmets") and spec.get("helmet", "none") != "none" else full
	if body.mesh != want:
		var m := body.get_surface_override_material(0)
		body.mesh = want
		body.set_surface_override_material(0, m)
	for k in ["cloth", "trousers", "linen", "leather", "hair", "skin", "beard", "grime"]:
		body.set_instance_shader_parameter(k, p[k])
	var shield := _part(u, "Shield")
	if shield != null:
		for k in ["field", "field2", "charge", "division", "wear"]:
			shield.set_instance_shader_parameter(k, p[k])
	for g in u.get_meta("gear", []):
		g.visible = on("helmets") and (g.name != "Plume" or spec.get("leader", false))
		g.set_instance_shader_parameter("tint", spec.plume if g.name == "Plume" else spec.helmet_tint)
		g.set_instance_shader_parameter("metal", 0.0 if g.name == "Plume" else float(spec.helmet_metal))
	var sh = u.get_meta("shape")
	if sh != null:
		sh.head_scale = float(spec.head_scale) if on("build") else 1.0
		sh.chest_scale = float(spec.chest_scale) if on("build") else 1.0
		sh.glance = float(spec.glance) if on("glances") else 0.0


## A new look on a dressed man (the gear rebuilt for it).
static func restyle(u: Node3D, spec: Dictionary, mode: String, outline: bool) -> void:
	u.set_meta("look", spec)
	for g in u.get_meta("gear", []):
		g.queue_free()
	u.set_meta("gear", _build_gear(u, _body(u), spec))
	paint(u, spec, mode, outline)


## The shader values for a look under the current layers: a layer that is
## off gives its parts the texture's own colours.
static func params(spec: Dictionary) -> Dictionary:
	var liv: Color = spec.livery if on("livery") else REF.cloth
	var cl := on("clothes")
	var p := {}
	p.cloth = dyed(liv, spec.dye) if cl else liv
	if cl:
		p.trousers = dyed(liv.darkened(0.12), spec.dye) if spec.trousers_livery else spec.trousers
	else:
		p.trousers = liv
	p.linen = spec.linen if cl else REF.linen
	p.leather = spec.leather if cl else REF.brown
	var f := on("faces")
	p.hair = spec.hair if f else REF.brown
	p.skin = spec.skin if f else REF.skin
	p.beard = float(spec.beard) if f else 0.0
	var g := on("grime")
	p.grime = float(spec.grime) if g else 0.0
	p.wear = float(spec.wear) if g else 0.0
	var lv := on("livery")
	p.field = spec.field if lv else REF.field
	p.field2 = spec.field2 if lv else REF.field
	p.charge = spec.charge if lv else REF.charge
	p.division = float(spec.division) if lv else 0.0
	return p


## A livery colour as one man's cloth: `d` = hue offset, saturation and value factors - 1.
static func dyed(c: Color, d: Vector3) -> Color:
	return Color.from_hsv(fposmod(c.h + d.x, 1.0), clampf(c.s * (1.0 + d.y), 0.0, 1.0), clampf(c.v * (1.0 + d.z), 0.0, 1.0))


## His squadmates and foes, for his glances.
static func link(men: Array, others: Array = []) -> void:
	for m in men:
		var sh = m.get_meta("shape") if m.has_meta("shape") else null
		if sh != null:
			sh.look_at = men + others


static func set_outline_width(metres: float) -> void:
	if outline_mat != null:
		outline_mat.set_shader_parameter("width", metres)


static func _dress(u: Node3D, body: MeshInstance3D, spec: Dictionary) -> void:
	u.set_meta("dressed", true)
	u.set_meta("look", spec)
	body.mesh = _region_mesh(body.mesh, body.skin)
	u.set_meta("full_mesh", body.mesh)
	var sk: Skeleton3D = u.skeleton
	var shape := BodyShape.new()
	shape.name = "BodyShape"
	shape.unit = u
	sk.add_child(shape)
	u.set_meta("shape", shape)
	u.set_meta("gear", _build_gear(u, body, spec))


static func _body(u: Node3D) -> MeshInstance3D:
	if u.get("model") == null:
		return null
	for mi in u.model.find_children("*", "MeshInstance3D", true, false):
		if mi.skin != null:
			return mi
	return null


static func _part(u: Node3D, n: String) -> MeshInstance3D:
	for mi in u.model.find_children(n, "MeshInstance3D", true, false):
		return mi
	return null


static func _albedo(m: Material) -> Texture2D:
	return m.albedo_texture if m is BaseMaterial3D else null


# --- Materials -----------------------------------------------------------------

static func _material(kind: String, mode: String, outline: bool, tex: Texture2D, mi: MeshInstance3D) -> ShaderMaterial:
	var key := "%s:%s:%s:%d" % [kind, mode, outline, tex.get_instance_id() if tex else 0]
	if _mats.has(key):
		return _mats[key]
	if outline_mat == null:
		outline_mat = ShaderMaterial.new()
		outline_mat.shader = OUTLINE
	var src: Shader = {"body": BODY_SHADER, "shield": SHIELD_SHADER, "gear": GEAR_SHADER}[kind]
	var m := ShaderMaterial.new()
	m.shader = _variant(src, mode)
	match kind:
		"body":
			m.set_shader_parameter("albedo_tex", tex)
			m.set_shader_parameter("ref_cloth", Vector3(REF.cloth.r, REF.cloth.g, REF.cloth.b))
			m.set_shader_parameter("roughness", 0.8 if mode == "pbr" else 1.0)
		"shield":
			var ch := _charge_mask(tex)
			m.set_shader_parameter("albedo_tex", tex)
			m.set_shader_parameter("charge_tex", ch.tex)
			m.set_shader_parameter("charge_lo", FRONT_LO)
			m.set_shader_parameter("charge_hi", FRONT_HI)
			var f := _face(mi.mesh)
			m.set_shader_parameter("face_lo", f[0])
			m.set_shader_parameter("face_hi", f[1])
			m.set_shader_parameter("roughness", 0.8 if mode == "pbr" else 1.0)
	m.next_pass = outline_mat if outline else null
	_mats[key] = m
	return m


## The shader with its render mode for a look: toon as written, flat
## unshaded, PBR with the default diffuse and a soft specular.
static func _variant(src: Shader, mode: String) -> Shader:
	var key := "%s:%s" % [src.resource_path, mode]
	if _shaders.has(key):
		return _shaders[key]
	if mode == "toon":
		_shaders[key] = src
		return src
	var code := src.code
	var at := code.find("render_mode ")
	var end := code.find(";", at)
	# Its diffuse and specular modes swapped, the rest (culling) kept.
	var modes := ["unshaded" if mode == "flat" else "specular_schlick_ggx"]
	for k in code.substr(at + 12, end - at - 12).split(","):
		var m := k.strip_edges()
		if not m.begins_with("diffuse_") and not m.begins_with("specular_"):
			modes.append(m)
	code = code.substr(0, at) + "render_mode " + ", ".join(modes) + code.substr(end)
	var sh := Shader.new()
	sh.code = code
	_shaders[key] = sh
	return sh


# --- Body regions ----------------------------------------------------------------

## A copy of a skinned mesh with its regions in the vertex colour (see the top).
static func _region_mesh(mesh: Mesh, skin: Skin) -> ArrayMesh:
	if _regions.has(mesh):
		return _regions[mesh]
	var head := []
	var skull := []
	var legs := []
	for i in skin.get_bind_count():
		var n := String(skin.get_bind_name(i))
		if n.ends_with("Head") or n.ends_with("HeadTop_End"):
			skull.append(i)
			head.append(i)
		elif n.ends_with("Neck"):
			head.append(i)
		elif n.ends_with("Leg") or n.ends_with("Foot") or n.ends_with("ToeBase") or n.ends_with("Toe_End"):
			legs.append(i)
	var out := ArrayMesh.new()
	var cropped := ArrayMesh.new()
	for s in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(s)
		var V: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var B: PackedInt32Array = arr[Mesh.ARRAY_BONES]
		var W: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
		var per := B.size() / maxi(V.size(), 1)
		var fit := _head_fit(V, B, W, per, skull)
		var V2 := V
		if not fit.is_empty():
			V2 = _crop(V, B, W, per, skull, fit)
			# Gear fits the cropped head, its rim where the full head's is.
			_fits[out] = _head_fit(V2, B, W, per, skull, fit.rim)
			_fits[out].mouth_y = fit.mouth_y
			_fits[cropped] = _fits[out]
		var col := PackedColorArray()
		col.resize(V.size())
		for i in V.size():
			var h := 0.0
			var sk := 0.0
			var g := 0.0
			for k in per:
				var b := B[i * per + k]
				var w := W[i * per + k]
				if b in head:
					h += w
				if b in skull:
					sk += w
				if b in legs:
					g += w
			var p := V[i]
			var beard := 0.0
			if not fit.is_empty():
				beard = sk * (1.0 - smoothstep(fit.mouth_y - 0.004, fit.mouth_y + 0.02, p.y)) * smoothstep(fit.cz - 0.05, fit.cz + 0.01, p.z)
			col[i] = Color(clampf(h, 0.0, 1.0), clampf(g, 0.0, 1.0), beard, clampf(p.y * 0.5, 0.0, 1.0))
		arr[Mesh.ARRAY_COLOR] = col
		var flags := Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS if per == 8 else 0
		out.add_surface_from_arrays(mesh.surface_get_primitive_type(s), arr, [], {}, flags)
		out.surface_set_material(s, mesh.surface_get_material(s))
		arr[Mesh.ARRAY_VERTEX] = V2
		cropped.add_surface_from_arrays(mesh.surface_get_primitive_type(s), arr, [], {}, flags)
		cropped.surface_set_material(s, mesh.surface_get_material(s))
	_regions[mesh] = out
	_cropped[out] = cropped
	return out


## The head's vertices above the brow pulled in toward the skull (CROP:
## across, and up from the rim), for a helmet to sit close: the model's hair
## is thick, and a helmet over it looks like a top hat. Below the brow
## (eyes, ears, face) nothing moves.
static func _crop(V: PackedVector3Array, B: PackedInt32Array, W: PackedFloat32Array, per: int, skull: Array, fit: Dictionary) -> PackedVector3Array:
	var out := V.duplicate()
	var rim: float = fit.rim
	for i in V.size():
		var p := V[i]
		if p.y <= rim - 0.02:
			continue
		var w := 0.0
		for k in per:
			if B[i * per + k] in skull:
				w += W[i * per + k]
		if w <= 0.0:
			continue
		var k := smoothstep(rim - 0.02, rim + 0.025, p.y) * clampf(w, 0.0, 1.0)
		var f := lerpf(1.0, CROP.x, k)
		var y := rim + (p.y - rim) * lerpf(1.0, CROP.y, k) if p.y > rim else p.y
		out[i] = Vector3(fit.cx + (p.x - fit.cx) * f, y, fit.cz + (p.z - fit.cz) * f)
	return out


## The head's outline at rest from its vertices (weighted to the Head bone):
## chin and crown, the rim height (halfway), the mouth (a quarter up), the
## skull's centre and radii above the rim, the face's front, and `env`: the
## outline's largest radius (a fraction of the radii) in ENV_BANDS bands from
## the rim to the crown.
const ENV_BANDS := 8


static func _head_fit(V: PackedVector3Array, B: PackedInt32Array, W: PackedFloat32Array, per: int, skull: Array, rim_at := NAN) -> Dictionary:
	var pts := []
	for i in V.size():
		var w := 0.0
		for k in per:
			if B[i * per + k] in skull:
				w += W[i * per + k]
		if w > 0.6:
			pts.append(V[i])
	if pts.size() < 20:
		return {}
	var lo := INF
	var hi := -INF
	for p in pts:
		lo = minf(lo, p.y)
		hi = maxf(hi, p.y)
	var rim := lerpf(lo, hi, 0.5) if is_nan(rim_at) else rim_at
	var x0 := INF
	var x1 := -INF
	var z0 := INF
	var z1 := -INF
	var face_z := -INF
	for p in pts:
		if p.y >= rim - 0.01:
			x0 = minf(x0, p.x)
			x1 = maxf(x1, p.x)
			z0 = minf(z0, p.z)
			z1 = maxf(z1, p.z)
		if p.y > lerpf(lo, hi, 0.3) and p.y < lerpf(lo, hi, 0.45):
			face_z = maxf(face_z, p.z)
	var cx := (x0 + x1) * 0.5
	var cz := (z0 + z1) * 0.5
	var rx := (x1 - x0) * 0.5
	var rz := (z1 - z0) * 0.5
	var env := []
	env.resize(ENV_BANDS + 1)
	env.fill(0.0)
	for p in pts:
		if p.y < rim - 0.01:
			continue
		var t := clampf((p.y - rim) / (hi - rim), 0.0, 1.0)
		var r := Vector2((p.x - cx) / rx, (p.z - cz) / rz).length()
		var b := roundi(t * ENV_BANDS)
		env[b] = maxf(env[b], r)
	# Each band covers its neighbours too: no vertex between bands pokes out.
	var cover := []
	for b in ENV_BANDS + 1:
		cover.append(maxf(env[b], maxf(env[maxi(b - 1, 0)], env[mini(b + 1, ENV_BANDS)])))
	return {"chin": lo, "crown": hi, "rim": rim, "mouth_y": lerpf(lo, hi, 0.25), "cx": cx, "cz": cz,
		"rx": rx, "rz": rz, "face_z": face_z, "env": cover}


## The outline's radius at height y (a fraction of the radii), with the margin.
static func _need(fit: Dictionary, y: float) -> float:
	var t := clampf((y - fit.rim) / (fit.crown - fit.rim), 0.0, 1.0) * ENV_BANDS
	var a := floori(t)
	var b := mini(a + 1, ENV_BANDS)
	return lerpf(fit.env[a], fit.env[b], t - a) + MARGIN if y <= fit.crown else 0.0


# --- Gear --------------------------------------------------------------------

## The gear for a look under a BoneAttachment3D on his Head bone.
static func _build_gear(u: Node3D, body: MeshInstance3D, spec: Dictionary) -> Array:
	var kind: String = spec.get("helmet", "none")
	var out := []
	var fit: Dictionary = _fits.get(body.mesh, {})
	if fit.is_empty() or kind == "none":
		return out
	var sk: Skeleton3D = u.skeleton
	var head := -1
	for i in sk.get_bone_count():
		if sk.get_bone_name(i).ends_with("Head"):
			head = i
	if head < 0:
		return out
	var att: BoneAttachment3D = u.get_meta("head_att") if u.has_meta("head_att") else null
	if att == null:
		att = BoneAttachment3D.new()
		att.name = "LookHead"
		sk.add_child(att)
		att.bone_name = sk.get_bone_name(head)
		var rest := Node3D.new()
		rest.name = "Rest"
		# Gear is built in the body's rest space; this undoes the head's rest.
		rest.transform = sk.get_bone_global_rest(head).affine_inverse()
		att.add_child(rest)
		u.set_meta("head_att", att)
	var holder: Node3D = att.get_node("Rest")
	var mi := MeshInstance3D.new()
	mi.name = "Helmet"
	mi.mesh = _gear_mesh(kind, fit)
	holder.add_child(mi)
	out.append(mi)
	if spec.get("leader", false) and kind != "cap":
		var pl := MeshInstance3D.new()
		pl.name = "Plume"
		pl.mesh = _gear_mesh("plume_" + kind, fit)
		holder.add_child(pl)
		out.append(pl)
	return out


static func _gear_mesh(kind: String, fit: Dictionary) -> ArrayMesh:
	var key := "%s:%d" % [kind, fit.hash()]
	if _gear.has(key):
		return _gear[key]
	var m := ArrayMesh.new()
	var rim: float = fit.rim
	var top: float = fit.crown
	var H := top - rim
	match kind:
		"kettle":
			# A rounded dome over a band, and a broad brim sloping down all round.
			_lathe(m, fit, _dome(fit, rim - 0.006, top + 0.045, 1.7, 1.08, 0.6), true)
			_lathe(m, fit, [[1.12, rim - 0.014, 0.6], [1.14, rim + 0.004, 0.95], [1.12, rim + 0.02, 0.95], [1.07, rim + 0.024, 0.75]], false)
			# The brim, a closed ring: its top out and down, its edge, its underside back in.
			_lathe(m, fit, [[1.10, rim - 0.002, 0.95], [1.42, rim - 0.032, 1.0], [1.74, rim - 0.078, 0.9],
				[1.75, rim - 0.09, 0.55], [1.42, rim - 0.046, 0.4], [1.08, rim - 0.014, 0.4]], false, true)
		"nasal":
			# A Norman cone to a point, a band, and the bar down over the nose.
			_lathe(m, fit, _dome(fit, rim - 0.012, top + 0.085, 1.15, 1.07, 0.8), true)
			_lathe(m, fit, [[1.12, rim - 0.018, 0.6], [1.13, rim + 0.016, 0.95], [1.1, rim + 0.022, 0.8], [1.07, rim + 0.02, 0.75]], false)
			_nasal(m, fit)
		"skullcap":
			_lathe(m, fit, _dome(fit, rim + 0.012, top + 0.022, 2.4, 1.04), true)
			_lathe(m, fit, [[1.08, rim + 0.006, 0.6], [1.10, rim + 0.016, 0.95], [1.06, rim + 0.03, 0.8]], false)
		"cap":
			var prof := []
			for i in 11:
				var t := i / 10.0
				var y := lerpf(rim - 0.004, top + 0.035, t)
				var r := maxf(1.1 * sqrt(maxf(1.0 - t * t, 0.0)) + 0.05 * sin(t * PI), _need(fit, y) + 0.02)
				prof.append([r if i < 10 else 0.0, y, lerpf(0.8, 1.0, t)])
			_lathe(m, fit, prof, true)
			# The rolled edge.
			_lathe(m, fit, [[1.12, rim - 0.016, 0.6], [1.2, rim - 0.004, 0.9], [1.19, rim + 0.016, 1.0], [1.1, rim + 0.022, 0.8]], false, true)
		_:
			if kind.begins_with("plume_"):
				var base: float = top + {"plume_nasal": 0.065, "plume_kettle": 0.035}.get(kind, 0.02)
				_plume(m, Vector3(fit.cx, base, fit.cz - 0.01))
	_gear[key] = m
	return m


## A dome from the rim (y0) to its crown (y1): radius `r0` (a fraction of the
## skull's radii) falling as (1 - t^k)^e (e 0.5 round, toward 1 a cone), never
## inside the head's outline; shaded darker toward the rim.
static func _dome(fit: Dictionary, y0: float, y1: float, k: float, r0: float, e := 0.5) -> Array:
	var prof := []
	var n := 14
	for i in n + 1:
		var t := float(i) / n
		var y := lerpf(y0, y1, t)
		var r := maxf(r0 * pow(maxf(1.0 - pow(t, k), 0.0), e), _need(fit, y))
		prof.append([r if i < n else 0.0, y, lerpf(0.7, 1.0, sqrt(t))])
	return prof


## A surface of revolution about the head's axis, as one surface of `m`:
## `prof` = [r (fraction of the skull's radii), y, shade] from the bottom up.
## A last r of 0 closes it in a point; `closed` joins the last ring to the first.
static func _lathe(m: ArrayMesh, fit: Dictionary, prof: Array, pole: bool, closed := false, seg := 32) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := prof.size() - (1 if pole else 0)
	for j in rings:
		var pr: Array = prof[j]
		for i in seg:
			var a := TAU * i / seg
			st.set_color(Color(pr[2], 0, 0))
			st.add_vertex(Vector3(fit.cx + sin(a) * pr[0] * fit.rx, pr[1], fit.cz + cos(a) * pr[0] * fit.rz))
	if pole:
		var pp: Array = prof[prof.size() - 1]
		st.set_color(Color(pp[2], 0, 0))
		st.add_vertex(Vector3(fit.cx, pp[1], fit.cz))
	var last := rings if closed else rings - 1
	for j in last:
		var j2 := (j + 1) % rings
		for i in seg:
			var i2 := (i + 1) % seg
			# Outward faces: Godot's front faces wind clockwise seen from outside.
			st.add_index(j * seg + i)
			st.add_index(j2 * seg + i)
			st.add_index(j * seg + i2)
			st.add_index(j * seg + i2)
			st.add_index(j2 * seg + i)
			st.add_index(j2 * seg + i2)
	if pole:
		var p := rings * seg
		var j := rings - 1
		for i in seg:
			st.add_index(j * seg + i)
			st.add_index(p)
			st.add_index(j * seg + (i + 1) % seg)
	st.generate_normals()
	st.commit(m)


## The nasal helm's nose guard: a flat bar from the band down over the nose.
static func _nasal(m: ArrayMesh, fit: Dictionary) -> void:
	var front: float = fit.cz + fit.rz * 1.12
	var a := Vector3(fit.cx, fit.rim + 0.012, front + 0.002)
	var b := Vector3(fit.cx, fit.rim - 0.062, maxf(fit.face_z + 0.014, front - 0.03))
	var down := (b - a).normalized()
	var side := Vector3.RIGHT * 0.012
	var out := down.cross(Vector3.RIGHT).normalized() * -0.005
	if out.z < 0.0:
		out = -out
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c := [a - side - out, a + side - out, b + side * 0.8 - out, b - side * 0.8 - out,
		a - side + out, a + side + out, b + side * 0.8 + out, b - side * 0.8 + out]
	var faces := [[4, 5, 6, 7], [1, 0, 3, 2], [0, 4, 7, 3], [5, 1, 2, 6], [0, 1, 5, 4], [7, 6, 2, 3]]
	for f in faces:
		var n: Vector3 = (c[f[1]] - c[f[0]]).cross(c[f[2]] - c[f[0]]).normalized()
		for k in [0, 1, 2, 0, 2, 3]:
			st.set_normal(n)
			st.set_color(Color(0.9, 0, 0))
			st.add_vertex(c[f[k]])
	st.commit(m)


## The leader's plume: a horsehair tuft from a socket on the crown, up and
## over backward, swelling and then thinning to a point; deep (in its own
## plane) and narrow across, so it reads from the side and from above.
static func _plume(m: ArrayMesh, at: Vector3) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts := [at, at + Vector3(0, 0.2, 0.01), at + Vector3(0, 0.2, -0.24), at + Vector3(0, -0.02, -0.33)]
	var n := 18
	var seg := 12
	for j in n + 1:
		var t := float(j) / n
		var p := _bezier(pts, t)
		var d := (_bezier(pts, minf(t + 0.02, 1.0)) - _bezier(pts, maxf(t - 0.02, 0.0))).normalized()
		var side := Vector3.RIGHT
		var up := side.cross(d).normalized()
		# Thin at the socket, fullest a third along, a point at the tip.
		var r := 0.075 * sin(PI * pow(t, 0.6)) + 0.012 * (1.0 - t)
		for i in seg:
			var a := TAU * i / seg
			st.set_color(Color(lerpf(0.72, 1.0, sin(a) * 0.5 + 0.5), 0, 0))
			st.add_vertex(p + side * cos(a) * r * 0.42 + up * sin(a) * r)
	for j in n:
		for i in seg:
			var i2 := (i + 1) % seg
			st.add_index(j * seg + i)
			st.add_index(j * seg + i2)
			st.add_index((j + 1) * seg + i)
			st.add_index(j * seg + i2)
			st.add_index((j + 1) * seg + i2)
			st.add_index((j + 1) * seg + i)
	st.generate_normals()
	st.commit(m)


static func _bezier(p: Array, t: float) -> Vector3:
	var u := 1.0 - t
	return p[0] * u * u * u + p[1] * 3.0 * u * u * t + p[2] * 3.0 * u * t * t + p[3] * t * t * t


# --- Shield ------------------------------------------------------------------

## The shield front's extent in its own space (x, y), from the vertices on the
## texture's front island.
static func _face(mesh: Mesh) -> Array:
	if _faces.has(mesh):
		return _faces[mesh]
	var arr := mesh.surface_get_arrays(0)
	var V: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var UV: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for i in V.size():
		if UV[i].x > FRONT_LO.x and UV[i].y > FRONT_LO.y:
			lo = Vector2(minf(lo.x, V[i].x), minf(lo.y, V[i].y))
			hi = Vector2(maxf(hi.x, V[i].x), maxf(hi.y, V[i].y))
	if lo.x == INF:
		lo = Vector2(mesh.get_aabb().position.x, mesh.get_aabb().position.y)
		hi = lo + Vector2(mesh.get_aabb().size.x, mesh.get_aabb().size.y)
	_faces[mesh] = [lo, hi]
	return _faces[mesh]


## The shield's charge (the eagle) as a mask over the texture's front island:
## a light patch the painted field encloses (the rim's light metal reaches the
## island's edge; scratches and rivets are small).
static func _charge_mask(tex: Texture2D) -> Dictionary:
	if _charges.has(tex):
		return _charges[tex]
	var img := tex.get_image()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGB8)
	var full := img.get_size()
	var r := Rect2i(Vector2i(Vector2(full) * FRONT_LO), Vector2i(Vector2(full) * (FRONT_HI - FRONT_LO)))
	var sub := img.get_region(r)
	sub.resize(maxi(r.size.x / 2, 8), maxi(r.size.y / 2, 8), Image.INTERPOLATE_BILINEAR)
	var w := sub.get_width()
	var h := sub.get_height()
	var data := sub.get_data()
	var hue := rgb_hue(REF.field)
	# 1 field, 2 light, 0 other.
	var cls := PackedByteArray()
	cls.resize(w * h)
	for i in w * h:
		var c := Color8(data[i * 3], data[i * 3 + 1], data[i * 3 + 2])
		if c.s >= 0.3 and absf(fposmod(c.h - hue + 0.5, 1.0) - 0.5) < 0.11:
			cls[i] = 1
		elif c.v > 0.55 and c.s < 0.3:
			cls[i] = 2
	var seen := PackedByteArray()
	seen.resize(w * h)
	var mask := PackedByteArray()
	mask.resize(w * h)
	for start in w * h:
		if cls[start] != 2 or seen[start] == 1:
			continue
		var comp := PackedInt32Array([start])
		seen[start] = 1
		var k := 0
		var field := 0
		var other := 0
		var edge := false
		while k < comp.size():
			var i := comp[k]
			k += 1
			var x := i % w
			var y := i / w
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = x + d.x
				var ny: int = y + d.y
				if nx < 0 or ny < 0 or nx >= w or ny >= h:
					edge = true
					continue
				var j := ny * w + nx
				if cls[j] == 2:
					if seen[j] == 0:
						seen[j] = 1
						comp.append(j)
				elif cls[j] == 1:
					field += 1
				else:
					other += 1
		if not edge and comp.size() >= 150 and field >= 0.85 * (field + other):
			for i in comp:
				mask[i] = 255
	var out := Image.create_from_data(w, h, false, Image.FORMAT_L8, mask)
	var res := {"tex": ImageTexture.create_from_image(out)}
	_charges[tex] = res
	return res


static func rgb_hue(c: Color) -> float:
	return c.h
