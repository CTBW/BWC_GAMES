extends "res://tests/test_case.gd"

## The 3D battlefields (prototypes/battlefields3d): its four fields as maps the
## battle's rules can read, the fog of war over them, and the paintings they
## draw, which all come from the prototype's art or the game's sprites.

const Fields = preload("res://prototypes/battlefields3d/scripts/bf_fields.gd")
const Field = preload("res://prototypes/battlefields3d/scripts/bf_field.gd")
const Fog = preload("res://prototypes/battlefields3d/scripts/bf_fog.gd")
const Relief = preload("res://scripts/render/relief.gd")
const Visibility = preload("res://scripts/rules/visibility.gd")
const Grid = preload("res://scripts/rules/grid.gd")
const DB = preload("res://scripts/data/db.gd")

var fields := {}
var art: Dictionary


func before_all() -> void:
	for id in Fields.IDS:
		fields[id] = Fields.make(id)
	art = JSON.parse_string(FileAccess.get_file_as_string(Field.ART))


## A field's woods and pieces only, without the ground, its bakes and the water.
func _field(id: String) -> Node3D:
	var f: Node3D = Field.new()
	f.data = fields[id]
	f.map = f.data.map
	f._outer = f.data.outer
	f.season = f.data.season
	f._sprites = JSON.parse_string(FileAccess.get_file_as_string("res://assets/sprites.json"))
	f._art = art
	f.relief = Relief.new(Field.W, Field.H, Field.BORDER, f.map.tiles + f._outer, f.data.seed)
	return f


func test_four_fields_in_four_seasons_are_rules_maps() -> void:
	var seasons := {}
	for id in Fields.IDS:
		var d: Dictionary = fields[id]
		if not assert_false(d.is_empty(), id + " is made"):
			continue
		seasons[d.season] = id
		var m: Dictionary = d.map
		assert_eq([m.w, m.h], [Fields.W, Fields.H], id + " size")
		assert_eq(m.tiles.size(), Fields.W * Fields.H, id + " tiles")
		var kinds := {}
		for i in m.tiles.size():
			var t: Dictionary = m.tiles[i]
			assert_eq([t.x, t.y], [i % Fields.W, i / Fields.W], "%s tile %d in row order" % [id, i])
			kinds[t.terrain] = true
			assert_true(DB.TERRAIN.has(t.terrain), "%s terrain %s is the rules'" % [id, t.terrain])
			if t.has("prop"):
				assert_true(DB.PROPS.has(t.prop), "%s prop %s is the rules'" % [id, t.prop])
		for k in ["grass", "forest"]:
			assert_true(kinds.has(k), "%s has %s" % [id, k])
		assert_true(kinds.has("water") or kinds.has("shallows"), id + " has water")
		# Each house, mill and ruin stands on tiles that carry its rules prop.
		assert_true(d.pieces.size() >= 3, "%s has pieces (%d)" % [id, d.pieces.size()])
		for pc in d.pieces:
			for c in pc.tiles:
				if not assert_true(c.x >= 0 and c.y >= 0 and c.x < Fields.W and c.y < Fields.H, "%s %s inside the field" % [id, pc.key]):
					continue
				var t: Dictionary = m.tiles[c.y * Fields.W + c.x]
				if pc.rules != "":
					assert_eq(t.get("prop", ""), pc.rules, "%s %s at %s carries its rules prop" % [id, pc.key, c])
		# The scouts it opens with are eyes, not units: anywhere in the field.
		assert_true(d.scouts.size() >= 2, id + " opens with scouts")
		for s in d.scouts:
			assert_true(s.x >= 0 and s.y >= 0 and s.x < Fields.W and s.y < Fields.H, "%s scout at %s in the field" % [id, s])
	assert_eq(seasons.keys().size(), 4, "four seasons")
	for s in ["summer", "autumn", "winter", "spring"]:
		assert_true(seasons.has(s), s)
	assert_true(fields.frosthollow.frozen, "the winter field's water is frozen")


func test_fog_of_war_follows_the_battles_sight_rules() -> void:
	for id in Fields.IDS:
		var d: Dictionary = fields[id]
		var eyes: Array = []
		for s in d.scouts:
			eyes.append({"x": s.x, "y": s.y})
		var fog = Fog.new(d.map)
		fog.update(eyes, 0.1)
		var rules := Visibility.field(d.map, eyes)
		assert_eq(fog.seen.size(), rules.size(), id + ": the scouts see what the rules see")
		for k in rules:
			assert_true(fog.seen.has(k), "%s %s seen" % [id, k])
		for e in eyes:
			assert_true(fog.seen.has(Grid.key(e.x, e.y)), "%s scout tile %s seen" % [id, e])
		assert_true(fog.seen.size() < Fields.W * Fields.H, id + ": the rest lies in the fog")
		fog.forget()
		assert_eq(fog.explored.size(), fog.seen.size(), id + ": forgetting keeps what is seen")


func test_every_painting_loads_and_stands_on_its_anchor() -> void:
	assert_true(art.size() >= 60, "the prototype's art (%d keys)" % art.size())
	for key in art:
		for e in art[key]:
			var tex := load(e.file) as Texture2D
			if not assert_true(tex != null, "%s: %s loads" % [key, e.file]):
				continue
			assert_eq(tex.get_size(), Vector2(e.w, e.h), "%s size" % key)
			assert_true(float(e.ax) >= 0.0 and float(e.ax) <= float(e.w) and float(e.ay) >= 0.0 and float(e.ay) <= float(e.h),
				"%s anchor (%s, %s) inside %s x %s" % [key, e.ax, e.ay, e.w, e.h])
			assert_true(float(e.scale) > 0.0, "%s scale" % key)


func test_fields_build_their_woods_and_pieces_without_a_willow() -> void:
	for id in Fields.IDS:
		var f := _field(id)
		f._build_woodland()
		f._build_pieces()
		var d: Dictionary = f.data
		var kinds := {}
		var files := {}
		for c in f.cards:
			kinds[c.kind] = int(kinds.get(c.kind, 0)) + 1
			files[String(c.node.material_override.get_shader_parameter("tex").resource_path)] = true
			assert_almost(c.foot.y, f.ground_y(c.foot.x, c.foot.z), 1e-4, "%s %s on the ground" % [id, c.key])
		# Every piece and every placed thing has its painting.
		assert_eq(kinds.get("piece", 0), d.pieces.size(), id + " pieces drawn")
		assert_eq(kinds.get("decor", 0), d.decor.size(), id + " decor drawn")
		assert_true(int(kinds.get("tree_oak", 0)) + int(kinds.get("tree_pine", 0)) > 100, "%s woods (%s)" % [id, kinds])
		assert_false(files.has(""), id + " paintings are files")
		assert_true(files.size() >= 20, "%s paintings (%d)" % [id, files.size()])
		for file in files:
			assert_false(file.contains("willow"), "%s draws no weeping willow (%s)" % [id, file])
		if d.season == "winter":
			for c in f.cards:
				if c.kind.begins_with("tree"):
					assert_true(c.key.begins_with("w_"), "%s %s is a winter tree" % [id, c.key])
		f.free()
