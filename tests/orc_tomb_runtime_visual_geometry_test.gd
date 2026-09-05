extends Node

const GeometryService := preload(
	"res://scripts/map_editor/map_editor_runtime_visual_geometry_service.gd"
)
const MAPS := [
	{"map_id": "bich_orc_tomb_f1", "runtime_map_id": 911001},
	{"map_id": "bich_orc_tomb_f2", "runtime_map_id": 911002},
	{"map_id": "bich_orc_tomb_f3", "runtime_map_id": 911003},
]


func _ready() -> void:
	var total_instances := 0
	var total_commands := 0
	var total_wall_instances := 0
	var total_wall_commands := 0
	var layout_hashes := {}
	var unpublished_divergence_count := 0
	for config: Dictionary in MAPS:
		var map_id := str(config.map_id)
		var loaded := MapEditorLoadService.load_document(
			MapEditorSaveService.default_path(map_id)
		)
		assert(loaded.ok, "%s:%s" % [map_id, loaded.get("errors", [])])
		var document: Dictionary = loaded.document
		assert(int(document.runtime_map_id) == int(config.runtime_map_id))
		var runtime_map_id := int(config.runtime_map_id)
		assert(
			MapEditorRuntimeBridge.has_runtime_map(runtime_map_id),
			"%s published runtime is not approved" % map_id
		)
		var runtime_loaded := MapEditorRuntimeMapService.load_runtime(
			MapEditorRuntimeBridge.runtime_path(runtime_map_id)
		)
		assert(
			runtime_loaded.ok,
			"%s:%s" % [map_id, runtime_loaded.get("errors", [])]
		)
		var runtime: Dictionary = runtime_loaded.runtime
		assert(int(runtime.get("source", {}).get("runtime_map_id", -1)) == runtime_map_id)
		assert(str(runtime.get("source", {}).get("map_id", "")) == map_id)
		var source_instances: Array = []
		for instance: Dictionary in MapEditorInstanceService.all_instances(document):
			if bool(instance.get("runtime_export", true)):
				source_instances.append(instance)
		var runtime_instances: Array = runtime.instances
		var published_binding: Dictionary = runtime.get("source", {}).get(
			"candidate_binding", {}
		)
		assert(
			str(published_binding.get("contract_id", ""))
			== MapEditorBuildRuntimeService.CANDIDATE_BINDING_CONTRACT_ID,
			"%s published candidate binding contract is invalid" % map_id
		)
		assert(
			str(published_binding.get("map_key", "")) == map_id
			and int(published_binding.get("runtime_map_id", -1)) == runtime_map_id,
			"%s published candidate binding identity drifted" % map_id
		)
		var editor_matches_published: bool = (
			MapEditorBuildRuntimeService.candidate_matches_document(
				{"document_binding": published_binding}, document
			)
		)
		var geometry_matches_published: bool = (
			runtime_instances.size() == source_instances.size()
			and GeometryService.geometry_sha256(runtime_instances)
			== GeometryService.geometry_sha256(source_instances)
		)
		if not geometry_matches_published:
			unpublished_divergence_count += 1
			assert(
				not editor_matches_published,
				"%s binding claims parity while geometry diverges" % map_id
			)
			assert(
				map_id == "bich_orc_tomb_f2",
				"unexpected editor/published geometry divergence:%s" % map_id
			)
			assert(
				int(document.get("editor_meta", {}).get("runtime_approved_revision", -1))
				< int(document.get("editor_meta", {}).get("revision", -1)),
				"%s divergence is not marked as an unpublished revision" % map_id
			)
		var source_commands: Array = (
			GeometryService.sorted_draw_commands(source_instances)
			if geometry_matches_published
			else []
		)
		var runtime_commands := GeometryService.sorted_draw_commands(
			runtime_instances
		)
		if geometry_matches_published:
			assert(runtime_commands.size() == source_commands.size(), map_id)
		var design_raw: Array = runtime.design.design_size
		var design_size := Vector2i(int(design_raw[0]), int(design_raw[1]))
		var editor_draw_offset := (
			-Vector2(MapEditorCoordinate.ground_image_size(design_size)) * 0.5
		)
		for command_index in runtime_commands.size():
			var runtime_command: Dictionary = runtime_commands[command_index]
			if geometry_matches_published:
				var source_command: Dictionary = source_commands[command_index]
				_assert_same_command(source_command, runtime_command, map_id)
			if command_index > 0:
				assert(
					not GeometryService.draw_command_less(
						runtime_command,
						runtime_commands[command_index - 1]
					),
					"%s command order regressed at %d"
						% [map_id, command_index]
				)
			var image_path := str(runtime_command.image_path)
			var texture := load(image_path) as Texture2D
			assert(texture != null, image_path)
			var editor_geometry := GeometryService.editor_command_geometry(
				runtime_command,
				design_size,
				editor_draw_offset,
				1.0,
				texture.get_size()
			)
			var runtime_geometry := GeometryService.runtime_command_geometry(
				runtime_command, design_size, texture.get_size()
			)
			_assert_same_geometry(
				editor_geometry,
				runtime_geometry,
				(
					-editor_draw_offset
					- MapEditorCoordinate.ground_pixel_center(design_size)
				),
				map_id,
				command_index
			)
			_assert_sprite_geometry(
				runtime_command, runtime_geometry, design_size, map_id,
				command_index
			)
			var instance: Dictionary = runtime_command.instance
			var asset: Dictionary = runtime_command.asset
			var tile: Array = instance.get("tile", [0, 0])
			var foot := GeometryService.instance_foot_tile(instance, asset)
			if str(asset.get("asset_type", "")) == "wall_module":
				assert(
					foot.is_equal_approx(Vector2(
						float(tile[0]) + 0.5, float(tile[1]) + 0.5
					)),
					"%s wall foot anchor diverged" % map_id
				)
				total_wall_commands += 1
			else:
				var footprint: Array = instance.get(
					"footprint_tiles", asset.get("footprint_tiles", [1, 1])
				)
				assert(foot.is_equal_approx(Vector2(
					float(tile[0]) + float(footprint[0]) * 0.5,
					float(tile[1]) + float(footprint[1]) * 0.5
				)), "%s ordinary footprint anchor diverged" % map_id)
		for instance: Dictionary in runtime_instances:
			var asset := MapAssetCatalogService.find_asset(
				str(instance.get("asset_id", ""))
			)
			if str(asset.get("asset_type", "")) == "wall_module":
				total_wall_instances += 1
		total_instances += runtime_instances.size()
		total_commands += runtime_commands.size()
		var layout_sha := GeometryService.geometry_sha256(runtime_instances)
		assert(not layout_sha.is_empty(), map_id)
		layout_hashes[layout_sha] = true
	assert(layout_hashes.size() == 3, "three published runtime layouts must remain distinct")
	assert(total_wall_instances > 0)
	assert(
		total_wall_commands > total_wall_instances,
		"wall render_parts were flattened to one sprite per instance"
	)
	print(
		("ORC_TOMB_RUNTIME_VISUAL_GEOMETRY_PASS "
		+ "contract=%s maps=911001,911002,911003 instances=%d commands=%d "
		+ "walls=%d unpublished_divergence=%d")
		% [
			GeometryService.VISUAL_GEOMETRY_CONTRACT_ID,
			total_instances,
			total_commands,
			total_wall_instances,
			unpublished_divergence_count,
		]
	)
	get_tree().quit(0)


func _assert_same_command(
	source: Dictionary,
	runtime: Dictionary,
	map_id: String
) -> void:
	for field: String in [
		"image_path", "anchor", "sort_tile", "layer_index", "image_pass",
		"part_order", "sequence",
	]:
		assert(source.get(field) == runtime.get(field), "%s:%s" % [map_id, field])
	assert(
		str(source.instance.get("instance_id", ""))
		== str(runtime.instance.get("instance_id", "")),
		"%s instance command mismatch" % map_id
	)


func _assert_same_geometry(
	editor: Dictionary,
	runtime: Dictionary,
	editor_to_runtime: Vector2,
	map_id: String,
	command_index: int
) -> void:
	var context := "%s command=%d" % [map_id, command_index]
	for field: String in ["anchor", "visual_scale"]:
		var editor_value: Vector2 = editor[field]
		var runtime_value: Vector2 = runtime[field]
		assert(editor_value.is_equal_approx(runtime_value), "%s:%s" % [context, field])
	for field: String in ["center", "top_left"]:
		var editor_value: Vector2 = editor[field]
		var runtime_value: Vector2 = runtime[field]
		assert(
			(editor_value + editor_to_runtime).is_equal_approx(runtime_value),
			"%s:%s" % [context, field]
		)
	assert(is_equal_approx(float(editor.rotation), float(runtime.rotation)), context)
	var editor_rect: Rect2 = editor.rect
	var runtime_rect: Rect2 = runtime.rect
	assert(
		(editor_rect.position + editor_to_runtime).is_equal_approx(
			runtime_rect.position
		),
		context
	)
	assert(editor_rect.size.is_equal_approx(runtime_rect.size), context)


func _assert_sprite_geometry(
	command: Dictionary,
	geometry: Dictionary,
	design_size: Vector2i,
	map_id: String,
	command_index: int
) -> void:
	var context := "%s command=%d" % [map_id, command_index]
	var parent_origin := Vector2.ZERO
	if str(command.get("render_domain", "")) == GeometryService.RENDER_DOMAIN_ACTOR_Y_SORT:
		parent_origin = GeometryService.command_actor_sort_world(
			command, design_size
		)
	var sprite := Sprite2D.new()
	sprite.centered = false
	GeometryService.apply_runtime_sprite_geometry(
		sprite, command, geometry, parent_origin
	)
	assert(
		(sprite.position + parent_origin).is_equal_approx(geometry.center),
		"%s parent-relative center shifted" % context
	)
	assert(sprite.offset.is_equal_approx(-geometry.anchor), "%s anchor" % context)
	assert(sprite.scale.is_equal_approx(geometry.visual_scale), "%s scale" % context)
	assert(
		is_equal_approx(sprite.rotation, float(geometry.rotation)),
		"%s rotation" % context
	)
	sprite.free()
