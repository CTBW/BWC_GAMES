## The loading screen warms what the first expedition and battle would
## otherwise stop to load and compile (scripts/app/main.gd `warm_steps`,
## `_warm_battle`): the battle view and HUD, the campaign view and HUD, the
## battle rules and the screens. A renamed path would silently skip the warm,
## so every step must resolve.
extends "res://tests/test_case.gd"

const Main = preload("res://scripts/app/main.gd")
const Deps = preload("res://scripts/ui/deps.gd")


func test_every_warm_step_loads() -> void:
	var steps: Array = Main.warm_steps()
	for k in ["battle_view_scene", "battle_hud", "campaign_view_scene", "campaign_hud", "setup", "ai"]:
		assert_true(steps.has(k), "warms " + k)
	for k in steps:
		if Deps.PATHS.has(k):
			assert_not_null(Deps.mod(k), "Deps.%s loads" % k)
		else:
			assert_true(ResourceLoader.exists(k) and load(k) != null, "%s loads" % k)


func test_warm_battle_encounter_exists() -> void:
	# The warm-up battle rolls this encounter for a fresh company of its own.
	var found := false
	for e in load("res://scripts/data/db.gd").ENCOUNTERS:
		if e.id == "raiding_party":
			found = true
	assert_true(found, "the warm-up encounter exists")
