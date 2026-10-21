## The UI theme: the contract variations of ARCHITECTURE.md exist with the right
## bases, fonts and icons load, the dark sub-theme recolours text, the saved
## theme resource loads.
extends "res://tests/test_case.gd"

const ThemeBuilder = preload("res://scripts/ui/theme_builder.gd")
const UI = preload("res://scripts/ui/ui.gd")
const Icon = preload("res://scripts/ui/widgets/icon.gd")

const CONTRACT := {
	"ParchmentPanel": "PanelContainer", "ParchmentCard": "PanelContainer", "DarkPanel": "PanelContainer",
	"TopBar": "PanelContainer", "TitleLabel": "Label", "HeadingLabel": "Label", "BodyLabel": "Label",
	"SmallLabel": "Label", "MutedLabel": "Label", "GoodLabel": "Label", "BadLabel": "Label",
	"GoldButton": "Button", "DarkButton": "Button", "RedButton": "Button", "IconButton": "Button",
	"HpBar": "ProgressBar", "MoraleBar": "ProgressBar",
}


func test_contract_variations() -> void:
	var t := ThemeBuilder.theme()
	for name in CONTRACT:
		assert_eq(String(t.get_type_variation_base(name)), CONTRACT[name], "variation " + name)


func test_more_variations() -> void:
	var t := ThemeBuilder.theme()
	for name in ["SmallButton", "BigButton", "RedBigButton", "BlueBigButton", "GoldSmallButton", "GhostSmallButton",
			"ButtonActive", "SmallButtonActive", "IconButtonActive", "ChoiceButton", "AbilityButton", "AbilityButtonActive"]:
		assert_eq(String(t.get_type_variation_base(name)), "Button", name)
	for name in ["HpLowBar", "FatigueBar", "XpBar", "CpBar", "OverBar"]:
		assert_eq(String(t.get_type_variation_base(name)), "ProgressBar", name)
	for name in ["BodyText", "SmallText", "DialogText", "ManualText", "TitleText", "TooltipText"]:
		assert_eq(String(t.get_type_variation_base(name)), "RichTextLabel", name)
	for name in ["Tag", "TagRed", "TagBlue", "TagGold", "TagGreen", "ModalBack", "TooltipPanel", "ParchmentCardSelected"]:
		assert_eq(String(t.get_type_variation_base(name)), "PanelContainer", name)
	assert_true(t.has_stylebox("normal", "NameEdit"), "NameEdit")
	assert_true(t.has_stylebox("separator", "TitleRule"), "TitleRule")


func test_button_states() -> void:
	var t := ThemeBuilder.theme()
	for name in ["Button", "RedButton", "GoldButton", "GhostButton", "IconButton"]:
		for st in ["normal", "hover", "pressed", "disabled", "focus"]:
			assert_true(t.has_stylebox(st, name), "%s/%s" % [name, st])
		assert_true(t.has_font("font", name), name + " font")
	assert_eq(t.get_font_size("font_size", "SmallButton"), 12)
	assert_eq(t.get_font_size("font_size", "BigButton"), 19)
	assert_eq(t.get_color("font_color", "GoldButton"), UI.INK, "gold buttons have ink text")


func test_fonts_load() -> void:
	for f in [["cinzel", 400], ["cinzel", 700], ["cinzel", 900], ["alegreya", 400], ["alegreya", 500], ["alegreya", 700], ["sans", 400]]:
		var font := UI.font(f[0], f[1])
		assert_not_null(font, "%s %d" % f)
		assert_true(font.get_string_size("Meridius", HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x > 20.0, "%s %d measures" % f)
	assert_not_null(UI.font("alegreya", 400, true), "italic")


func test_icons_load() -> void:
	for n in Icon.NAMES:
		var tex := Icon.tex(n)
		assert_not_null(tex, n)
		assert_true(tex.get_width() >= 48, "%s imported at a crisp scale" % n)
	assert_eq(Icon.type_icon_name("crossbowman"), "crossbow")
	assert_eq(Icon.type_icon_name("collie_guard"), "shield")
	assert_eq(Icon.type_icon_name("goblin_archer"), "crossbow")
	assert_eq(Icon.type_icon_name("orc_warrior"), "sword")


func test_dark_sub_theme() -> void:
	var d := ThemeBuilder.dark_theme()
	assert_eq(d.get_color("font_color", "MutedLabel"), Color("#b8a27c"), "muted on dark")
	assert_eq(d.get_color("font_color", "TitleLabel"), Color("#f6e7c2"), "title on dark")
	assert_eq(d.get_color("font_color", "BodyLabel"), Color("#f0e2c0"))
	assert_true(d.has_stylebox("normal", "GhostSmallButton"), "light ghost buttons")


func test_saved_theme_loads() -> void:
	if not ResourceLoader.exists(ThemeBuilder.SAVE_PATH):
		skip("assets/ui/theme.tres not written yet")
		return
	var t: Theme = load(ThemeBuilder.SAVE_PATH)
	assert_not_null(t)
	assert_eq(String(t.get_type_variation_base("ParchmentPanel")), "PanelContainer")
	assert_true(t.get_stylebox("panel", "ParchmentPanel") is StyleBox)
