## Clips kept out of Git, added to a unit's model at run time where they are
## on disk. A profile's `local_clips` names an FBX of its rig alone (no meshes)
## with one take, by its path from the repository root without the extension,
## and the take's sidecar (.json) beside it: the succubus's Sovereign Kiss,
## made from a Mixamo clip, in local/succubus_3d/godot/ (exported by
## art/succubus_3d/tools/export_kiss_godot.py). The take becomes the clip the
## sidecar names, in an animation library "local" on the unit's player, its
## tracks put on the model's skeleton. Without the files the unit keeps its
## committed clips only, and the profile's attacks that need the clip are not
## offered (unit3d.gd actions()).
extends RefCounted

const LIBRARY := "local"


## The file `base` names, with `ext`, in the repository (res:// is four
## folders down, in projects/meridius/source/godot).
static func file(base: String, ext: String) -> String:
	return ProjectSettings.globalize_path("res://").path_join("../../../../" + base + ext).simplify_path()


static func available(base: String) -> bool:
	return FileAccess.file_exists(file(base, ".fbx")) and FileAccess.file_exists(file(base, ".json"))


## Loads `base` onto `player`, whose model's skeleton is `skeleton`; returns
## the sidecar's clips ({name: info}, to merge into the unit's), or {} when
## the files are missing or do not load.
##
## The take's tracks are each bone's pose, not an offset from its rest, so
## they play on the model's skeleton as they are, although its rests differ.
## A bone the take holds at its rig's rest has no track; the player would put
## it at the model's own rest instead, so it gets a held key of the take's
## rest. Bones the model lacks (KissSocket) are dropped.
static func add(player: AnimationPlayer, skeleton: Skeleton3D, base: String) -> Dictionary:
	if not available(base):
		return {}
	var sidecar: Variant = JSON.parse_string(FileAccess.get_file_as_string(file(base, ".json")))
	if not (sidecar is Dictionary and sidecar.get("clips") is Dictionary and sidecar.clips.size() == 1):
		return {}
	var doc := FBXDocument.new()
	var state := FBXState.new()
	if doc.append_from_file(file(base, ".fbx"), state) != OK:
		return {}
	var scene := doc.generate_scene(state)
	if scene == null:
		return {}
	var players := scene.find_children("*", "AnimationPlayer", true, false)
	var sks := scene.find_children("*", "Skeleton3D", true, false)
	var take: Animation = null
	if not players.is_empty() and not sks.is_empty():
		var src: AnimationPlayer = players[0]
		var names := src.get_animation_list()
		if not names.is_empty():
			take = src.get_animation(names[0]).duplicate(true)
	if take == null:
		scene.free()
		return {}
	var rig: Skeleton3D = sks[0]
	# The model's tracks address its skeleton from the player's root.
	var root := player.get_node(player.root_node)
	var to_skeleton := String(root.get_path_to(skeleton))
	var keyed := {}
	for i in range(take.get_track_count() - 1, -1, -1):
		var bone := String(take.track_get_path(i).get_concatenated_subnames())
		if skeleton.find_bone(bone) < 0:
			take.remove_track(i)
			continue
		take.track_set_path(i, NodePath(to_skeleton + ":" + bone))
		keyed["%s/%d" % [bone, take.track_get_type(i)]] = true
	for b in rig.get_bone_count():
		var bone := rig.get_bone_name(b)
		var mb := skeleton.find_bone(bone)
		if mb < 0:
			continue
		var rest := rig.get_bone_rest(b)
		var own := skeleton.get_bone_rest(mb)
		var path := NodePath(to_skeleton + ":" + bone)
		if not keyed.has("%s/%d" % [bone, Animation.TYPE_ROTATION_3D]) \
				and not rest.basis.get_rotation_quaternion().is_equal_approx(own.basis.get_rotation_quaternion()):
			take.rotation_track_insert_key(_track(take, path, Animation.TYPE_ROTATION_3D), 0.0, rest.basis.get_rotation_quaternion())
		if not keyed.has("%s/%d" % [bone, Animation.TYPE_POSITION_3D]) and not rest.origin.is_equal_approx(own.origin):
			take.position_track_insert_key(_track(take, path, Animation.TYPE_POSITION_3D), 0.0, rest.origin)
		if not keyed.has("%s/%d" % [bone, Animation.TYPE_SCALE_3D]) and not rest.basis.get_scale().is_equal_approx(own.basis.get_scale()):
			take.scale_track_insert_key(_track(take, path, Animation.TYPE_SCALE_3D), 0.0, rest.basis.get_scale())
	scene.free()
	var clip := String(sidecar.clips.keys()[0])
	var lib: AnimationLibrary
	if player.has_animation_library(LIBRARY):
		lib = player.get_animation_library(LIBRARY)
	else:
		lib = AnimationLibrary.new()
		player.add_animation_library(LIBRARY, lib)
	lib.add_animation(clip, take)
	return sidecar.clips


static func _track(a: Animation, path: NodePath, type: int) -> int:
	var i := a.add_track(type)
	a.track_set_path(i, path)
	a.track_set_interpolation_type(i, Animation.INTERPOLATION_LINEAR)
	return i
