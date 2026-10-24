## Port of Roster.tsx `RosterPanel`: the company in a three-column grid of
## soldier cards (click one for the detail), sorted line-first.
##
##   const RosterPanel = preload("res://scripts/ui/screens/roster_panel.gd")
##   RosterPanel.make() -> PanelContainer   (a .panel.dialog, 900 px)
extends RefCounted

const UI = preload("res://scripts/ui/ui.gd")
const Deps = preload("res://scripts/ui/deps.gd")
const Modal = preload("res://scripts/ui/widgets/modal.gd")
const ScrollBox = preload("res://scripts/ui/widgets/scroll_box.gd")
const SoldierCard = preload("res://scripts/ui/widgets/soldier_card.gd")


static func make(viewport_h := 1080.0) -> PanelContainer:
	var g: Dictionary = App.game
	var Game = Deps.game()
	var d := Modal.dialog(900)
	d.name = "RosterPanel"
	var col := UI.vbox(0)
	d.add_child(col)
	var men := 0
	for so in g.roster:
		men += so.men
	col.add_child(UI.title_block_rich("The Amberfeld Company [font_size=13][color=#8a7356](%d/%d squads · %d soldiers)[/color][/font_size]" % [g.roster.size(), Game.roster_cap(g), men]))
	var cards: Array = []
	for so in SoldierCard.sort_roster(g.roster):
		cards.append(SoldierCard.make(so, App.open_soldier.bind(so.id)))
	var grid := UI.equal_grid(cards, 3, 8, 8)
	col.add_child(ScrollBox.make(grid, viewport_h * 0.62))
	col.add_child(UI.gap(0, 12))
	var foot := UI.hbox(8)
	var hint := UI.rich("Click a squad for details. Veteran squads cost more command points but fight far better. Refill thinned squads at the Barracks.", "SmallMutedText")
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot.add_child(hint)
	var close := UI.button("Close", "Button", func(): App.open_panel(null))
	close.name = "Close"
	close.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot.add_child(close)
	col.add_child(foot)
	return d
