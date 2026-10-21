## Base class for Meridius tests. Test scripts extend this file by path:
##   extends "res://tests/test_case.gd"
## Every method whose name starts with `test_` is run by tests/run_tests.gd.
## Optional hooks: before_all(), before_each(), after_each(), after_all().
## A test fails when an assertion fails or when any engine/script error is
## logged while it runs.
extends RefCounted

var _failures: Array[String] = []
var _skipped := ""
var _asserts := 0


func fail(msg: String) -> void:
	_failures.append(msg)


func skip(reason: String) -> void:
	_skipped = reason


## True (and the test is skipped) in quick mode (`tools/test.sh --quick`):
## start long tests with `if slow(): return`.
func slow(reason := "slow test; run the full suite") -> bool:
	if OS.get_cmdline_user_args().has("--quick"):
		skip(reason)
		return true
	return false


func assert_true(cond: bool, msg := "expected true") -> bool:
	_asserts += 1
	if not cond:
		fail(msg)
	return cond


func assert_false(cond: bool, msg := "expected false") -> bool:
	return assert_true(not cond, msg)


func assert_eq(actual: Variant, expected: Variant, msg := "") -> bool:
	_asserts += 1
	if not _same(actual, expected):
		fail("%s: expected %s, got %s" % [msg if msg != "" else "assert_eq", _show(expected), _show(actual)])
		return false
	return true


func assert_ne(actual: Variant, other: Variant, msg := "") -> bool:
	_asserts += 1
	if _same(actual, other):
		fail("%s: did not expect %s" % [msg if msg != "" else "assert_ne", _show(other)])
		return false
	return true


func assert_almost(actual: float, expected: float, eps := 1e-9, msg := "") -> bool:
	_asserts += 1
	if absf(actual - expected) > eps:
		fail("%s: expected %s ± %s, got %s" % [msg if msg != "" else "assert_almost", expected, eps, actual])
		return false
	return true


func assert_between(v: float, lo: float, hi: float, msg := "") -> bool:
	_asserts += 1
	if v < lo or v > hi:
		fail("%s: %s not in [%s, %s]" % [msg if msg != "" else "assert_between", v, lo, hi])
		return false
	return true


func assert_not_null(v: Variant, msg := "expected a value") -> bool:
	return assert_true(v != null, msg)


## Ints and integral floats compare equal (JSON loads numbers as floats);
## arrays and dictionaries compare deeply. Fractions may differ by 1e-12
## (relative): Godot's string-to-double parse of a 17-digit golden value can be
## one ulp off the double JavaScript printed.
func _same(a: Variant, b: Variant) -> bool:
	if (a is int or a is float) and (b is int or b is float):
		var fa := float(a)
		var fb := float(b)
		if fa == fb:
			return true
		return absf(fa - fb) <= 1e-12 * maxf(1.0, maxf(absf(fa), absf(fb)))
	if a is Array and b is Array:
		if a.size() != b.size():
			return false
		for i in a.size():
			if not _same(a[i], b[i]):
				return false
		return true
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size():
			return false
		for k in a:
			if not b.has(k) or not _same(a[k], b[k]):
				return false
		return true
	return typeof(a) == typeof(b) and a == b


func _show(v: Variant) -> String:
	var s := JSON.stringify(v) if (v is Array or v is Dictionary) else str(v)
	return s if s.length() < 400 else s.substr(0, 400) + "…"
