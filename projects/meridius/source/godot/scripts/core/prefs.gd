## Per-player conveniences remembered on this machine: sound and battle speed.
## Port of src/core/prefs.ts (localStorage there, user://prefs.json here).
## Storage can be missing or unreadable, so every access falls back to defaults.
## The volume sliders (Godot addition, 0..1, scripts/audio/sfx.gd): volMaster,
## volMusic, volAmbience, volSfx, volVoice.
extends RefCounted

const JS = preload("res://scripts/core/js.gd")
const PATH := "user://prefs.json"
const DEFAULTS := {
	"muted": false, "battleSpeed": 1,
	"volMaster": 1.0, "volMusic": 1.0, "volAmbience": 1.0, "volSfx": 1.0, "volVoice": 1.0,
}


static func prefs() -> Dictionary:
	var out: Dictionary = DEFAULTS.duplicate()
	if FileAccess.file_exists(PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if parsed is Dictionary:
			JS.assign(out, JS.normalize(parsed))
	return out


static func set_pref(key: String, value: Variant) -> void:
	set_prefs({key: value})


## Several at once (one write).
static func set_prefs(values: Dictionary) -> void:
	var p := prefs()
	p.merge(values, true)
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f != null:
		# Not remembered when storage fails; the setting still applies for this session.
		f.store_string(JSON.stringify(p))
