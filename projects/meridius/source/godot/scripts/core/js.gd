## JavaScript-compatible helpers for the port of the original TypeScript game.
##
## The original rules ran on JS numbers (IEEE doubles) with JS semantics. These
## helpers keep the GDScript port faithful where GDScript behaves differently:
## rounding of halves, 32-bit integer maths, stable sorting and number printing.
## Use them through `const JS = preload("res://scripts/core/js.gd")`.
extends RefCounted

const TWO32 := 4294967296.0
const U32 := 0xFFFFFFFF


## Math.round: halves round toward +infinity (GDScript roundi rounds them away from zero).
static func rnd(x: float) -> int:
	return int(floor(x + 0.5))


## Math.round kept as a float, for values that stay fractional elsewhere.
static func rndf(x: float) -> float:
	return floor(x + 0.5)


## Math.trunc.
static func trunc(x: float) -> float:
	return float(int(x)) if absf(x) < 9.0e18 else x


## ToUint32 (`x >>> 0`) of any number.
static func to_u32(x: Variant) -> int:
	if x is int:
		return x & U32
	var f: float = x
	if is_nan(f) or is_inf(f):
		return 0
	var t: float = floor(absf(f)) * signf(f)
	return int(fposmod(t, TWO32))


## ToInt32 (`x | 0`) of any number.
static func to_i32(x: Variant) -> int:
	var u := to_u32(x)
	return u - 0x100000000 if u >= 0x80000000 else u


## `x >>> n` for any number.
static func ushr(x: Variant, n: int) -> int:
	return to_u32(x) >> (n & 31)


## Low 32 bits of a * b for two uint32 values (Math.imul, unsigned view).
static func imul_u32(a: int, b: int) -> int:
	a &= U32
	b &= U32
	var lo: int = (a * (b & 0xFFFF)) & U32
	var hi: int = ((a * (b >> 16)) & 0xFFFF) << 16
	return (lo + hi) & U32


## Math.imul with the signed int32 result.
static func imul(a: Variant, b: Variant) -> int:
	return to_i32(imul_u32(to_u32(a), to_u32(b)))


## Math.hypot for two values, with V8's algorithm (scale by the larger value):
## the naive sqrt(x*x + y*y) is one ulp off for some inputs, e.g. (2, 3).
static func hypot(x: float, y: float) -> float:
	var ax := absf(x)
	var ay := absf(y)
	var m := ax if ax > ay else ay
	if m == 0.0:
		return 0.0
	if is_inf(m):
		return INF
	var a := ax / m
	var b := ay / m
	return sqrt(a * a + b * b) * m


## Math.sign (0 stays 0).
static func sign(x: float) -> float:
	return signf(x)


## Math.max over an array (-INF when empty, like Math.max()).
static func max_of(arr: Array) -> float:
	var m := -INF
	for v in arr:
		if v > m:
			m = v
	return m


## Math.min over an array (INF when empty).
static func min_of(arr: Array) -> float:
	var m := INF
	for v in arr:
		if v < m:
			m = v
	return m


## Array.prototype.sort with a comparator: stable, in place, returns the array.
## `cmp(a, b)` returns a number: negative puts a first, positive puts b first.
## (GDScript's sort_custom is not stable, so ties would come out differently.)
static func sort(arr: Array, cmp: Callable) -> Array:
	var n := arr.size()
	if n < 2:
		return arr
	var src: Array = arr.duplicate()
	var dst: Array = []
	dst.resize(n)
	var width := 1
	while width < n:
		var i := 0
		while i < n:
			var mid: int = mini(i + width, n)
			var hi: int = mini(i + 2 * width, n)
			var a := i
			var b := mid
			var k := i
			while a < mid and b < hi:
				# Take from the right only when strictly smaller: keeps ties in order.
				if float(cmp.call(src[b], src[a])) < 0.0:
					dst[k] = src[b]
					b += 1
				else:
					dst[k] = src[a]
					a += 1
				k += 1
			while a < mid:
				dst[k] = src[a]
				a += 1
				k += 1
			while b < hi:
				dst[k] = src[b]
				b += 1
				k += 1
			i += 2 * width
		var tmp := src
		src = dst
		dst = tmp
		width *= 2
	for j in n:
		arr[j] = src[j]
	return arr


## Sort by a numeric key, ascending and stable: `arr.sort((a, b) => key(a) - key(b))`.
static func sort_by(arr: Array, key: Callable) -> Array:
	return sort(arr, func(a, b): return float(key.call(a)) - float(key.call(b)))


## Array.prototype.find: the first element matching, or null.
static func find(arr: Array, pred: Callable) -> Variant:
	for v in arr:
		if pred.call(v):
			return v
	return null


## Array.prototype.findIndex.
static func find_index(arr: Array, pred: Callable) -> int:
	for i in arr.size():
		if pred.call(arr[i]):
			return i
	return -1


## Sum of key(v) over an array (`arr.reduce((s, v) => s + key(v), 0)`).
static func sum(arr: Array, key: Callable = Callable()) -> float:
	var s := 0.0
	for v in arr:
		s += float(key.call(v)) if key.is_valid() else float(v)
	return s


## String(x) for a number, as JS prints it: integral values without ".0".
static func num_str(x: Variant) -> String:
	if x is int:
		return str(x)
	if x is float:
		var f: float = x
		if is_nan(f):
			return "NaN"
		if is_inf(f):
			return "Infinity" if f > 0 else "-Infinity"
		if f == floor(f) and absf(f) < 1e21:
			return str(int(f))
		return str(f)
	return str(x)


## Number.prototype.toFixed.
static func to_fixed(x: float, digits: int) -> String:
	return ("%." + str(digits) + "f") % x


## Deep-converts integral floats (as JSON.parse_string returns every number) to ints.
## Applied to the data tables and to loaded saves, so counts, coordinates and ids
## are ints while fractions stay floats.
static func normalize(v: Variant) -> Variant:
	if v is float:
		var f: float = v
		if f == floor(f) and absf(f) < 9.0e15:
			return int(f)
		return f
	if v is Array:
		var out: Array = []
		out.resize(v.size())
		for i in v.size():
			out[i] = normalize(v[i])
		return out
	if v is Dictionary:
		var d: Dictionary = {}
		for k in v:
			d[k] = normalize(v[k])
		return d
	return v


## Object.assign-style shallow merge, returns `into`.
static func assign(into: Dictionary, from: Dictionary) -> Dictionary:
	for k in from:
		into[k] = from[k]
	return into


## The value of `d[k]`, or `fallback` when the key is absent or null (`d.k ?? fallback`).
static func get_or(d: Dictionary, k: Variant, fallback: Variant) -> Variant:
	var v: Variant = d.get(k)
	return fallback if v == null else v
