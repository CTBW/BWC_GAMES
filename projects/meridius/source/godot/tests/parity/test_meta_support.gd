## Shared helpers for the world/meta parity tests (no tests of its own).
## Golden files come from tools/parity/{maps,meta,setup,campaign}_golden.ts.
extends RefCounted

const JS = preload("res://scripts/core/js.gd")

const GOLDEN := "res://tests/fixtures/golden/"


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
