## A parchment confirmation dialog, standing in for the browser's `confirm()`
## the original uses (new company over a save, discharging a squad).
##
##   const Confirm = preload("res://scripts/ui/widgets/confirm.gd")
##   Confirm.ask(host: Control, text: String, on_ok: Callable, ok_text := "OK", cancel_text := "Cancel") -> Control
##       Adds a modal over `host` (full rect); OK runs on_ok then closes; Cancel,
##       Esc or a click outside closes. Returns the modal (name "Confirm").
extends RefCounted

const UI = preload("res://scripts/ui/ui.gd")
const Modal = preload("res://scripts/ui/widgets/modal.gd")


static func ask(host: Control, text: String, on_ok: Callable, ok_text := "OK", cancel_text := "Cancel") -> Control:
	var d := Modal.dialog(460, [20, 24])
	var col := UI.vbox(14)
	var msg := UI.rich("[center]%s[/center]" % UI.esc(text), "DialogText")
	col.add_child(msg)
	var row := UI.hbox(10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	# Lambdas capture locals by value: keep the modal in a shared array.
	var holder: Array = [null]
	var close := func():
		if holder[0] != null and is_instance_valid(holder[0]):
			holder[0].queue_free()
	var cancel := UI.button(cancel_text, "Button", close)
	cancel.name = "Cancel"
	var ok := UI.button(ok_text, "RedButton", func():
		close.call()
		on_ok.call())
	ok.name = "OK"
	row.add_child(cancel)
	row.add_child(ok)
	col.add_child(row)
	d.add_child(col)
	var modal := Modal.make(d, close)
	holder[0] = modal
	modal.name = "Confirm"
	modal.set_meta("on_cancel", close)
	host.add_child(modal)
	return modal
