extends SceneTree

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	assert(args.size() == 1, "Pass the absolute Mixar review directory")
	var folder: String = args[0]
	var png := Image.load_from_file(folder.path_join("verification.png"))
	assert(png != null and png.get_size() == Vector2i(512, 512))
	assert(png.get_pixel(0, 0).a == 0.0, "Sprite corner must be transparent")
	assert(png.get_pixel(256, 256).a > 0.99, "Sprite centre must be opaque")
	var texture := ImageTexture.create_from_image(png)
	assert(texture.get_width() == 512)
	var gltf := GLTFDocument.new()
	var state := GLTFState.new()
	assert(gltf.append_from_file(folder.path_join("verification.glb"), state) == OK)
	var model := gltf.generate_scene(state)
	assert(model != null)
	var meshes := model.find_children("*", "MeshInstance3D", true, false)
	assert(meshes.size() == 1)
	var mesh: MeshInstance3D = meshes[0]
	assert(mesh.mesh.get_surface_count() == 1)
	var material: StandardMaterial3D = mesh.mesh.surface_get_material(0)
	assert(material != null and material.albedo_texture != null)
	var bounds := mesh.mesh.get_aabb().size
	assert(bounds.is_equal_approx(Vector3.ONE), "Export must remain one metre")
	var live_state := GLTFState.new()
	assert(gltf.append_from_file(folder.path_join("meridius-mcp-test/meridius-mcp-test.glb"), live_state) == OK)
	var live_model := gltf.generate_scene(live_state)
	assert(live_model != null)
	var live_meshes := live_model.find_children("*", "MeshInstance3D", true, false)
	assert(live_meshes.size() == 2)
	for item in live_meshes:
		assert(item.mesh.surface_get_material(0) is StandardMaterial3D)
	var live_cube := live_model.find_child("Meridius_MCP_Test_Cube", true, false) as MeshInstance3D
	assert(live_cube != null and live_cube.mesh.get_aabb().size.is_equal_approx(Vector3.ONE))
	assert(is_equal_approx(live_cube.mesh.get_aabb().position.y, 0.0), "Export must be Y-up and on the ground")
	var report := {"godot_version": Engine.get_version_info().string,
		"png_load": true, "alpha": true, "texture_creation": true,
		"glb_load": true, "mesh_count": meshes.size(), "textured_material": true,
		"metre_scale": true, "live_mcp_export": true, "live_mesh_count": live_meshes.size(), "live_y_up": true}
	var file := FileAccess.open(folder.path_join("godot-checks.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  ") + "\n")
	file.close()
	print("MIXAR_GODOT_OK ", JSON.stringify(report))
	model.free()
	live_model.free()
	quit(0)
