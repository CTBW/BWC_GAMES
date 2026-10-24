## Deterministic, serialisable RNG (mulberry32), a bit-exact port of src/core/rng.ts.
## Every random decision in the game flows through an Rng so campaigns and
## battles can be replayed by seed. Values are kept as uint32 in a 64-bit int.
##
## Name mapping from the TypeScript class: int() -> rint(), range() -> frange().
extends RefCounted

const JS = preload("res://scripts/core/js.gd")
const U32 := 0xFFFFFFFF

var state: int


func _init(seed: Variant = 0) -> void:
	if seed is String:
		state = hash_string(seed)
	else:
		state = JS.to_u32(seed)
	if state == 0:
		state = 0x9e3779b9


func next() -> float:
	state = (state + 0x6d2b79f5) & U32
	var t: int = state
	t = JS.imul_u32(t ^ (t >> 15), t | 1)
	t = t ^ ((t + JS.imul_u32(t ^ (t >> 7), t | 61)) & U32)
	return float(t ^ (t >> 14)) / 4294967296.0


## Integer in [min, max] inclusive (TS: int).
func rint(min_v: int, max_v: int) -> int:
	return min_v + int(floor(next() * (max_v - min_v + 1)))


## Float in [min, max) (TS: range).
func frange(min_v: float, max_v: float) -> float:
	return min_v + next() * (max_v - min_v)


func chance(p: float) -> bool:
	return next() < p


func pick(arr: Array) -> Variant:
	return arr[int(floor(next() * arr.size()))]


## Picks one item with probability proportional to weight(item) (negative weights count as 0).
func weighted(items: Array, weight: Callable) -> Variant:
	var total := 0.0
	for it in items:
		total += maxf(0.0, float(weight.call(it)))
	var r := next() * total
	for it in items:
		r -= maxf(0.0, float(weight.call(it)))
		if r <= 0:
			return it
	return items[items.size() - 1]


## Fisher-Yates shuffle in place; returns the array.
func shuffle(arr: Array) -> Array:
	var i := arr.size() - 1
	while i > 0:
		var j := int(floor(next() * (i + 1)))
		var tmp: Variant = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
		i -= 1
	return arr


## A child generator whose sequence depends on this one and a label.
func fork(label: String) -> RefCounted:
	var mixed: int = hash_string(label) ^ int(floor(next() * 4294967296.0))
	return get_script().new(mixed & U32)


static func hash_string(s: String) -> int:
	var h: int = 2166136261
	for i in s.length():
		h = (h ^ s.unicode_at(i)) & U32
		h = JS.imul_u32(h, 16777619)
	return h


## Cheap stateless hash noise for rendering details (not gameplay).
## The first sum is done in doubles exactly as JS does before `>>> 0`.
static func hash2(x: float, y: float, seed: float = 0.0) -> float:
	var v: float = x * 374761393.0 + y * 668265263.0 + seed * 2147483647.0
	var h: int = JS.to_u32(v)
	h = JS.imul_u32(h ^ (h >> 13), 1274126177)
	return float(h ^ (h >> 16)) / 4294967296.0
