## Shared helpers for the world/meta parity tests (no tests of its own).
## Golden files were first recorded from the archived TypeScript game by
## tools/parity/{maps,meta,setup,campaign}_golden.ts; those whose tests can
## re-record (`MERIDIUS_RECORD=1`) are now written by the port itself.
extends RefCounted

const JS = preload("res://scripts/core/js.gd")

const GOLDEN := "res://tests/fixtures/golden/"


## Whether this run re-records golden files (MERIDIUS_RECORD=1) instead of comparing.
static func recording() -> bool:
	return OS.get_environment("MERIDIUS_RECORD") == "1"


## A deep copy as a golden file holds it (the live game goes on changing what
## a snapshot refers to); non-finite numbers become null, as the original's
## JSON.stringify wrote them.
static func jsonable(v: Variant) -> Variant:
	if v is float:
		return v if is_finite(v) else null
	if v is Array:
		return v.map(func(x): return jsonable(x))
	if v is Dictionary:
		var d := {}
		for k in v:
			d[k] = jsonable(v[k])
		return d
	if typeof(v) >= TYPE_PACKED_BYTE_ARRAY and typeof(v) <= TYPE_PACKED_VECTOR4_ARRAY:
		return jsonable(Array(v))
	return v


## Writes a golden file (compact, keys in their order, numbers in full precision).
static func write_golden(path: String, data: Variant) -> void:
	var f := FileAccess.open(path if path.begins_with("res://") else GOLDEN + path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data, "", false, true) + "\n")
	f.close()


## Parses a golden JSON file. `normalize` turns integral numbers into ints (use
## it for data fed back into the game code; comparisons accept either).
static func load_golden(name: String, normalize := true) -> Variant:
	var f := FileAccess.open(GOLDEN + name, FileAccess.READ)
	if f == null:
		push_error("missing golden file " + name)
		return null
	var v: Variant = JSON.parse_string(f.get_as_text())
	return JS.normalize(v) if normalize else v


## "" when `a` (Godot) equals `b` (golden), else a description of the first
## difference. Absent keys equal null; numbers compare with 1e-12 relative
## tolerance (ints and floats alike).
static func diff(a: Variant, b: Variant, path := "$") -> String:
	if a == null and b == null:
		return ""
	var an := a is int or a is float
	var bn := b is int or b is float
	if an and bn:
		var fa := float(a)
		var fb := float(b)
		if fa == fb or absf(fa - fb) <= 1e-12 * maxf(1.0, maxf(absf(fa), absf(fb))):
			return ""
		return "%s: %s != golden %s" % [path, a, b]
	if a is Array and b is Array:
		if a.size() != b.size():
			return "%s: array size %d != golden %d (%s vs %s)" % [path, a.size(), b.size(), _short(a), _short(b)]
		for i in a.size():
			var d := diff(a[i], b[i], "%s[%d]" % [path, i])
			if d != "":
				return d
		return ""
	if a is Dictionary and b is Dictionary:
		for k in a:
			var d := diff(a[k], b.get(k), "%s.%s" % [path, k])
			if d != "":
				return d
		for k in b:
			if not a.has(k):
				var d := diff(null, b[k], "%s.%s" % [path, k])
				if d != "":
					return d
		return ""
	if typeof(a) == typeof(b) and a == b:
		return ""
	if a is String and b is String and a == b:
		return ""
	return "%s: %s != golden %s" % [path, _short(a), _short(b)]


static func _short(v: Variant) -> String:
	var s := JSON.stringify(v) if (v is Array or v is Dictionary) else str(v)
	return s if s.length() < 300 else s.substr(0, 300) + "…"
