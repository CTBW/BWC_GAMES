## Headless test runner for Meridius.
##
##   godot --headless --path <project> -s res://tests/run_tests.gd [-- [--quick] filter...]
##
## Runs every `test_*` method in res://tests/unit/test_*.gd and
## res://tests/parity/test_*.gd (or only scripts/methods whose name contains a
## filter). Any engine or script error logged during a test fails it. Exits
## with code 0 when everything passed, 1 otherwise.
extends SceneTree

const DIRS := ["res://tests/unit", "res://tests/parity"]


class ErrorCatcher extends Logger:
	var mutex := Mutex.new()
	var errors: Array[String] = []

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, editor_notify: bool, error_type: int, script_backtrace: Array[ScriptBacktrace]) -> void:
		# Warnings are reported but do not fail a test.
		if error_type == ERROR_TYPE_WARNING:
			return
		mutex.lock()
		errors.append("%s (%s:%d %s)" % [rationale if rationale != "" else code, file, line, function])
		mutex.unlock()

	func take() -> Array[String]:
		mutex.lock()
		var out := errors.duplicate()
		errors.clear()
		mutex.unlock()
		return out


var catcher := ErrorCatcher.new()


func _initialize() -> void:
	OS.add_logger(catcher)
	var filters: PackedStringArray = OS.get_cmdline_user_args()
	# --quick skips tests that call slow(); it is not a name filter.
	var quick := filters.has("--quick")
	if quick:
		filters.remove_at(filters.find("--quick"))
	var files: Array[String] = []
	for d in DIRS:
		var da := DirAccess.open(d)
		if da == null:
			continue
		for f in da.get_files():
			if f.begins_with("test_") and f.ends_with(".gd"):
				files.append(d + "/" + f)
	files.sort()

	var passed := 0
	var failed: Array[String] = []
	var skipped := 0
	var t0 := Time.get_ticks_msec()
	for path in files:
		var script: GDScript = load(path)
		var load_errors := catcher.take()
		if script == null or not script.can_instantiate() or load_errors.size() > 0:
			failed.append("%s: failed to load %s" % [path, "; ".join(load_errors)])
			print("FAIL  %s (load error)" % path)
			continue
		var methods: Array[String] = []
		for m in script.get_script_method_list():
			var n: String = m.name
			if n.begins_with("test_") and not methods.has(n):
				if filters.is_empty() or _matches(path, n, filters):
					methods.append(n)
		if methods.is_empty():
			continue
		var inst: Object = script.new()
		if inst.has_method("before_all"):
			inst.call("before_all")
		var setup_errors := catcher.take()
		if setup_errors.size() > 0:
			failed.append("%s: before_all: %s" % [path, "; ".join(setup_errors)])
			print("FAIL  %s before_all" % path)
			continue
		for m in methods:
			inst._failures.clear()
			inst._skipped = ""
			var mt := Time.get_ticks_msec()
			if inst.has_method("before_each"):
				inst.call("before_each")
			inst.call(m)
			if inst.has_method("after_each"):
				inst.call("after_each")
			var errs := catcher.take()
			var name := "%s::%s" % [path.get_file().get_basename(), m]
			var ms := Time.get_ticks_msec() - mt
			if inst._skipped != "":
				skipped += 1
				print("SKIP  %s — %s" % [name, inst._skipped])
			elif inst._failures.is_empty() and errs.is_empty():
				passed += 1
				print("ok    %s (%d ms)" % [name, ms])
			else:
				var why: Array[String] = []
				why.append_array(inst._failures)
				for e in errs:
					why.append("error: " + e)
				failed.append("%s\n        %s" % [name, "\n        ".join(why)])
				print("FAIL  %s (%d ms)\n        %s" % [name, ms, "\n        ".join(why)])
		if inst.has_method("after_all"):
			inst.call("after_all")
		catcher.take()

	var secs := (Time.get_ticks_msec() - t0) / 1000.0
	print("")
	print("==== %d passed, %d failed, %d skipped in %.1f s ====" % [passed, failed.size(), skipped, secs])
	for f in failed:
		print("  FAILED " + f)
	quit(0 if failed.is_empty() and passed > 0 else 1)


func _matches(path: String, method: String, filters: PackedStringArray) -> bool:
	for f in filters:
		if path.contains(f) or method.contains(f):
			return true
	return false
