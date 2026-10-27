extends "res://tests/test_case.gd"
const Motion = preload("res://tools/motion_study/motion.gd")

func test_planted_feet_do_not_slide() -> void:
	for clip in Motion.CLIPS:
		var previous := Motion.sample(clip, 0)
		for frame in range(1, ceili(Motion.LENGTHS[clip] * 240)):
			var p := Motion.sample(clip, frame / 240.0)
			for side in ["left", "right"]:
				if p[side + "_down"] and previous[side + "_down"]:
					if not assert_almost(p[side].distance_to(previous[side]), 0.0, 0.00001, clip + " planted " + side): return
				if not assert_true(p[side].y >= Motion.SOLE - 0.00001, clip + " sole below floor"): return
			previous = p

func test_limbs_remain_in_reach() -> void:
	for clip in Motion.CLIPS:
		for frame in range(0, ceili(Motion.LENGTHS[clip] * 120)):
			var p := Motion.sample(clip, frame / 120.0)
			var torso := Basis(Vector3.UP, p.twist) * Basis(Vector3.BACK, -p.lean)
			for side in ["left", "right"]:
				var s := -1.0 if side == "left" else 1.0
				var h: Vector3 = p.root + Vector3(0, -0.025, s * 0.135)
				if not assert_true(h.distance_to(p[side]) < 0.89, "%s %.3f %s leg overstretched" % [clip, frame / 120.0, side]): return
				var shoulder := torso * Vector3(0, 0.45, s * 0.265)
				var hand: Vector3 = p["hand_l" if side == "left" else "hand_r"]
				if not assert_true(shoulder.distance_to(hand) < 0.59, "%s %.3f %s arm overstretched" % [clip, frame / 120.0, side]): return

func test_contact_is_after_plant_and_bodies_stay_apart() -> void:
	for clip in ["attack", "shield_bash", "charge"]:
		var impact: float = Motion.IMPACTS[clip]
		var p := Motion.sample(clip, impact)
		assert_true(p.left_down and p.right_down, clip + " impact must have support")
		for frame in range(0, ceili(Motion.LENGTHS[clip] * 120)):
			p = Motion.sample(clip, frame / 120.0)
			var target := Motion.target_position(clip)
			if not assert_true(target.x - p.root.x >= 0.85, clip + " body envelopes overlap"): return
		if clip != "attack":
			p = Motion.sample(clip, impact)
			var shield_front: float = p.root.x + p.hand_l.x + 0.055
			var target_front: float = Motion.target_position(clip).x - 0.43 - 0.055
			assert_almost(shield_front, target_front, 0.001, clip + " shield plane contact")

func test_charge_stops_before_contact_and_settles() -> void:
	var a := Motion.sample("charge", 3.30)
	var b := Motion.sample("charge", 3.40)
	var c := Motion.sample("charge", 4.75)
	assert_almost(a.root.x, b.root.x, 0.00001)
	assert_almost(b.root.x, c.root.x, 0.00001)
	assert_true(a.left_down and a.right_down and c.left_down and c.right_down)

func test_run_has_flight_walk_retains_support() -> void:
	var flight := false
	for frame in 600:
		var t := frame / 120.0
		var walk := Motion.sample("move", t)
		assert_true(walk.left_down or walk.right_down, "walking must retain ground support")
		var run := Motion.sample("charge", t)
		if not run.left_down and not run.right_down: flight = true
	assert_true(flight, "charge needs a distinct running gait")
