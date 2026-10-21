## The RNG and hashes must match the original TypeScript bit for bit: every
## battle, map and campaign is replayed from seeds.
## Golden data: tools/parity/core_vectors.ts -> tests/fixtures/golden/core_vectors.json
extends "res://tests/test_case.gd"

const Rng = preload("res://scripts/core/rng.gd")
const JS = preload("res://scripts/core/js.gd")

var golden: Dictionary


func before_all() -> void:
	var f := FileAccess.open("res://tests/fixtures/golden/core_vectors.json", FileAccess.READ)
	golden = JSON.parse_string(f.get_as_text())


func test_rng_sequences_match_typescript() -> void:
	for g in golden.rng:
		var seed: Variant = g.seed
		var label := "seed %s" % str(seed)
		var r = Rng.new(seed)
		assert_eq(r.state, g.state0, label + " state0")
		for v in g.next:
			assert_eq(r.next(), v, label + " next")
		for v in g.ints:
			assert_eq(r.rint(-3, 11), v, label + " int")
		for v in g.ranges:
			assert_eq(r.frange(0.5, 2.5), v, label + " range")
		for v in g.chances:
			assert_eq(r.chance(0.4), v, label + " chance")
		for v in g.pick:
			assert_eq(r.pick(["a", "b", "c", "d", "e"]), v, label + " pick")
		for v in g.weighted:
			assert_eq(r.weighted([1, 2, 3, 4], func(x): return 0 if x == 2 else x * 1.5), v, label + " weighted")
		assert_eq(r.shuffle([1, 2, 3, 4, 5, 6, 7, 8, 9]), g.shuffled, label + " shuffle")
		var child = r.fork("child")
		assert_eq(child.state, g.fork[0], label + " fork state")
		assert_eq(child.next(), g.fork[1], label + " fork next 1")
		assert_eq(child.next(), g.fork[2], label + " fork next 2")
		assert_eq(r.state, g.stateEnd, label + " end state")


func test_hash_string_matches_typescript() -> void:
	for h in golden.hashes:
		assert_eq(Rng.hash_string(h[0]), h[1], "hashString(%s)" % h[0])


func test_hash2_matches_typescript() -> void:
	for h in golden.hash2:
		assert_eq(Rng.hash2(h[0], h[1], h[2]), h[3], "hash2(%s, %s, %s)" % [h[0], h[1], h[2]])


func test_js_round_and_sort() -> void:
	assert_eq(JS.rnd(2.5), 3)
	assert_eq(JS.rnd(-2.5), -2)
	assert_eq(JS.rnd(-2.6), -3)
	# Stable: equal keys keep their order.
	var arr := [[1, "a"], [0, "b"], [1, "c"], [0, "d"], [2, "e"], [1, "f"]]
	JS.sort(arr, func(a, b): return a[0] - b[0])
	assert_eq(arr.map(func(p): return p[1]), ["b", "d", "a", "c", "f", "e"])
	assert_eq(JS.num_str(12.0), "12")
	assert_eq(JS.num_str(1.5), "1.5")
	assert_eq(JS.to_u32(-1.0), 4294967295)
	assert_eq(JS.imul(0x7fffffff, 3), 2147483645)
	assert_eq(JS.imul(-5, 12345678), -61728390)
