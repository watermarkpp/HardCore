extends Node2D

const ProjectileEffectScript := preload(
	"res://scripts/monster_ranged_projectile_effect.gd"
)
const WorldSpatialRulesScript := preload("res://scripts/world_spatial_rules.gd")
const SOURCE_MANIFEST_PATH := (
	"res://assets/data/monster_physical_projectile_sources_v1.json"
)


func _ready() -> void:
	_assert_source_manifest()
	_assert_no_procedural_fallback()
	await _assert_directional_source_frame()
	await _assert_dynamic_world_cutoff()
	print(
		"MONSTER_PHYSICAL_PROJECTILE_VISUAL_SOURCE_PASS "
		+ "Effect.wil=272..287 TFlyingArrow=source_frames "
		+ "dynamic_world_cutoff=1 damage_owner=enemy"
	)
	get_tree().quit(0)


func _assert_source_manifest() -> void:
	var manifest_text := FileAccess.get_file_as_string(SOURCE_MANIFEST_PATH)
	assert(not manifest_text.is_empty(), "projectile source manifest is missing")
	var manifest: Variant = JSON.parse_string(manifest_text)
	assert(manifest is Dictionary, "projectile source manifest must be JSON object")
	assert(
		str((manifest as Dictionary).get("effect_id", ""))
		== ProjectileEffectScript.EFFECT_ID
	)
	var source_library: Dictionary = (manifest as Dictionary).get(
		"source_library", {}
	)
	assert(
		str(source_library.get("wil", ""))
		== "dev_art_sources/reference/mir2_client_raw/Data/Effect.wil"
	)
	assert(
		str(source_library.get("wix", ""))
		== "dev_art_sources/reference/mir2_client_raw/Data/Effect.WIX"
	)
	assert(
		str(source_library.get("wil_sha256", "")).length() == 64,
		"primary Effect.wil SHA256 is required",
	)
	var source_rule: Dictionary = (manifest as Dictionary).get(
		"source_rule", {}
	)
	assert(int(source_rule.get("base_index", -1)) == 272)
	assert(int(source_rule.get("direction_count", 0)) == 16)
	assert(
		str(source_rule.get("index_expression", ""))
		== "ARCHERBASE2 + Dir16 + curframe"
	)
	var frames: Array = (manifest as Dictionary).get("frames", [])
	assert(frames.size() == ProjectileEffectScript.SOURCE_FRAME_COUNT)
	for direction16: int in range(ProjectileEffectScript.SOURCE_FRAME_COUNT):
		var frame: Dictionary = frames[direction16]
		assert(int(frame.get("direction16", -1)) == direction16)
		assert(int(frame.get("library_index", -1)) == 272 + direction16)
		assert(int(frame.get("wil_offset", 0)) > 0)
		assert(str(frame.get("raw_sprite_sha256", "")).length() == 64)
		assert(str(frame.get("asset_sha256", "")).length() == 64)
		var asset_path := "res://" + str(frame.get("asset", ""))
		assert(FileAccess.file_exists(asset_path), "missing extracted source frame %s" % asset_path)


func _assert_no_procedural_fallback() -> void:
	var script_text := FileAccess.get_file_as_string(
		"res://scripts/monster_ranged_projectile_effect.gd"
	)
	assert(not script_text.contains("draw_line"))
	assert(not script_text.contains("draw_colored_polygon"))
	assert(script_text.contains("PhysicsRayQueryParameters2D"))
	assert(script_text.contains("WorldSpatialRulesScript.WORLD_MASK"))
	assert(script_text.contains("transparent_source_wil_frame"))


func _assert_directional_source_frame() -> void:
	var effect := ProjectileEffectScript.new()
	effect.setup({
		"effect_id": ProjectileEffectScript.EFFECT_ID,
		"release_id": "visual-source-test",
		"origin_world_px": Vector2.ZERO,
		"target_world_px": Vector2(100.0, 0.0),
		"duration_seconds": 1.0,
	})
	add_child(effect)
	effect.set_process(false)
	await get_tree().process_frame
	assert(effect.visible)
	assert(effect.source_texture_path().ends_with("Effect_00276.png"))
	var source_frame := effect.get_node_or_null("SourceFrame")
	assert(source_frame is Sprite2D, "TFlyingArrow must render a source PNG frame")
	assert((source_frame as Sprite2D).texture != null)
	var descriptor: Dictionary = effect.visual_descriptor()
	assert(
		str(descriptor.get("source_manifest_path", ""))
		== ProjectileEffectScript.SOURCE_MANIFEST_PATH
	)
	assert(int(descriptor.get("source_frame_index", -1)) == 276)
	assert(
		str(descriptor.get("background_policy", ""))
		== "transparent_source_wil_frame"
	)
	effect.queue_free()
	await get_tree().process_frame


func _assert_dynamic_world_cutoff() -> void:
	var effect := ProjectileEffectScript.new()
	effect.setup({
		"effect_id": ProjectileEffectScript.EFFECT_ID,
		"release_id": "dynamic-world-test",
		"origin_world_px": Vector2.ZERO,
		"target_world_px": Vector2(100.0, 0.0),
		"duration_seconds": 1.0,
	})
	add_child(effect)
	effect.set_process(false)
	await get_tree().process_frame

	var wall := StaticBody2D.new()
	wall.collision_layer = WorldSpatialRulesScript.WORLD_LAYER
	wall.collision_mask = 0
	wall.position = Vector2(40.0, 0.0)
	var wall_shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(4.0, 80.0)
	wall_shape.shape = rectangle
	wall.add_child(wall_shape)
	add_child(wall)
	await get_tree().physics_frame

	effect.call("_process", 0.5)
	assert(effect.is_finished(), "world blocker must stop the visual immediately")
	assert(effect.collision_interrupted())
	assert(not effect.visible)
	assert(
		str(effect.visual_descriptor().get("damage_owner", ""))
		== "enemy.physical_projectile_release"
	)
	effect.queue_free()
	wall.queue_free()
	await get_tree().process_frame
