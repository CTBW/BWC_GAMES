## Writes assets/ui/theme.tres from scripts/ui/theme_builder.gd (and the dark
## sub-theme to assets/ui/theme_dark.tres):
##   tools/godot.sh --headless --path . -s res://scripts/ui/theme_build_cli.gd
## The game builds the theme at startup; the saved files are for the editor and
## for the project setting gui/theme/custom.
extends SceneTree

const ThemeBuilder = preload("res://scripts/ui/theme_builder.gd")


func _initialize() -> void:
	var err := ResourceSaver.save(ThemeBuilder.theme(), "res://assets/ui/theme.tres")
	var err2 := ResourceSaver.save(ThemeBuilder.dark_theme(), "res://assets/ui/theme_dark.tres")
	print("theme.tres: ", error_string(err), "; theme_dark.tres: ", error_string(err2))
	quit(0 if err == OK and err2 == OK else 1)
