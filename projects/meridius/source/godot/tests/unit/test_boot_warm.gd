## The loading screen warms what the first battle would otherwise stop to load
## and compile (scripts/app/main.gd `warm_steps`): the 3D battle view, its HUD,
## the battle rules and the screens. A renamed path would silently skip the
## warm, so every step must resolve.
extends "res://tests/test_case.gd"

const Main = preload("res://scripts/app/main.gd")
const Deps = preload("res://scripts/ui/deps.gd")


func test_every_warm_step_loads() -> void:
	var steps: Array = Main.warm_steps()
	for k in ["battle3d", "battle_hud", "battle", "battlefields", "expedition"]:
		assert_true(steps.has(k), "warms " + k)
	for k in steps:
		if Deps.PATHS.has(k):
			assert_not_null(Deps.mod(k), "Deps.%s loads" % k)
		else:
			assert_true(ResourceLoader.exists(k) and load(k) != null, "%s loads" % k)
