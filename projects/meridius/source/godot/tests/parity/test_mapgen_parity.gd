## Battle maps must match the original generator tile for tile: every template,
## every option set the game uses, many seeds.
## Golden: tools/parity/maps_golden.ts -> tests/fixtures/golden/map_golden.json
extends "res://tests/test_case.gd"

const H = preload("res://tests/parity/test_meta_support.gd")
const MapGen = preload("res://scripts/rules/mapgen.gd")

var golden: Dictionary


func before_all() -> void:
	golden = H.load_golden("map_golden.json")


func _opts(o: Variant) -> Dictionary:
	return o if o is Dictionary else {}


func test_every_template_and_option_set_matches() -> void:
	var by_template := {}
	for c in golden.cases:
		var m := MapGen.generate_map(c.template, c.seed, _opts(c.opts))
		var d := H.diff(m, c.map)
		by_template[c.template] = by_template.get(c.template, 0) + 1
		if not assert_eq(d, "", "%s seed %d opts %s" % [c.template, c.seed, JSON.stringify(c.opts)]):
			return
	assert_eq(by_template.keys().size(), 5, "templates covered")


func test_in_approach_matches() -> void:
	for c in golden.cases:
		var m := MapGen.generate_map(c.template, c.seed, _opts(c.opts))
		for s in c.approach:
			assert_eq(MapGen.in_approach(m, s[0], s[1]), s[2], "%s seed %d inApproach(%d, %d)" % [c.template, c.seed, s[0], s[1]])


func test_prop_blocks_matches() -> void:
	for p in golden.propBlocks:
		assert_eq(MapGen.prop_blocks(p[0] if p[0] != "" else null), p[1], "propBlocks(%s)" % p[0])
