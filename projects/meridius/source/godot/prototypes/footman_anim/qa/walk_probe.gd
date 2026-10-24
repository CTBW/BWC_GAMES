extends SceneTree
const Rig = preload("res://prototypes/footman_anim/scripts/footman_rig.gd")
func _initialize() -> void:
	var r := Rig.new()
	root.add_child(r)
	r.setup("se", 0.178)
	r.player.play("walk", 0.0)
	r.player.seek(0.0, true)
	r.update_parts(0.0)
	var a: Animation = r.player.get_animation("walk")
	for tr in a.get_track_count():
		var p := String(a.track_get_path(tr))
		if p.ends_with("foot_r:rotation") or p.ends_with("shin_r:rotation") or p.ends_with("shin_r:position"):
			var ks := []
			for k in mini(6, a.track_get_key_count(tr)):
				ks.append(a.track_get_key_value(tr, k))
			print(p, " ", ks, " interp ", a.track_get_interpolation_type(tr))
	for i in 9:
		print(i, " foot ", r.joint("foot_r"), " shin ", r.joint("shin_r"), " rot ", r.bones["foot_r"].rotation, " ", r.bones["shin_r"].rotation)
		r.player.advance(1.0 / 60.0)
		r.update_parts(1.0 / 60.0)
	quit()
