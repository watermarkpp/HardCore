extends Node


func _ready() -> void:
	_assert_world_background_props()
	_assert_gothic_bich_fallback()
	print(
		"LEGACY_PROFILE_ACTOR_OCCLUSION_RUNTIME_PASS contract=%s"
		% MapEditorRuntimeVisualGeometryService.OCCLUSION_SORT_CONTRACT_ID
	)
	get_tree().quit(0)


func _assert_world_background_props() -> void:
	var actor_plane := Node2D.new()
	actor_plane.y_sort_enabled = true
	var background := WorldBackground.new()
	actor_plane.add_child(background)
	var bich_foot := Vector2(120, 75)
	background._add_prop(0, bich_foot, true, {
		"position": bich_foot,
		"occlusion": true,
	})
	var tomb_foot := Vector2(-80, 135)
	background._add_tomb_prop(1, tomb_foot, true, {
		"position": tomb_foot,
		"occlusion": true,
	})
	var roots: Array[Node2D] = []
	for child: Node in actor_plane.get_children():
		if child is Node2D and child.has_meta("legacy_profile_actor_occluder"):
			roots.append(child)
	assert(roots.size() == 2, "legacy props did not create one Y-sort unit each")
	for root: Node2D in roots:
		assert(root.get_parent() == actor_plane)
		assert(root.z_index == 0 and not root.z_as_relative)
		assert(root.get_child_count() == 1, "fixed-z canopy duplicate still exists")
		var sprite := root.get_child(0) as Sprite2D
		assert(sprite != null and sprite.z_index == 0)
		assert(
			str(root.get_meta("map_occlusion_sort_contract_id", ""))
			== MapEditorRuntimeVisualGeometryService.OCCLUSION_SORT_CONTRACT_ID
		)
	assert(roots.any(func(root: Node2D) -> bool: return root.position == bich_foot))
	assert(roots.any(func(root: Node2D) -> bool: return root.position == tomb_foot))
	actor_plane.free()


func _assert_gothic_bich_fallback() -> void:
	var actor_plane := Node2D.new()
	actor_plane.y_sort_enabled = true
	var background := Node2D.new()
	actor_plane.add_child(background)
	var built := GothicBichCampBuilder.build(background, Vector2.ZERO)
	var layout: Dictionary = built.layout
	var expected_actor_props := 0
	var expected_ground_props := 0
	for record: Dictionary in layout.get("props", []):
		var resource_path := (
			"res://assets/presentation/skins/gothic_bich_camp/sprites/"
			+ str(record.get("asset", ""))
			+ ".png"
		)
		if not ResourceLoader.exists(resource_path):
			continue
		if str(record.get("layer", "")) == "ground":
			expected_ground_props += 1
		else:
			expected_actor_props += 1
	var actor_props := 0
	for child: Node in actor_plane.get_children():
		if child.has_meta("gothic_bich_camp_actor_occluder"):
			actor_props += 1
			assert(child.get_child_count() == 1)
			assert((child as Node2D).z_index == 0)
	var ground_props := 0
	for child: Node in background.get_children():
		if child is Sprite2D and (child as Sprite2D).z_index == -17:
			ground_props += 1
	assert(actor_props == expected_actor_props)
	assert(ground_props == expected_ground_props)
	assert(built.collisions.size() > 0, "gothic fallback collisions were lost")
	actor_plane.free()
