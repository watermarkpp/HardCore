class_name MapEditorRuntimeVisualGeometryService
extends RefCounted

const VISUAL_GEOMETRY_CONTRACT_ID := "map_editor_runtime_visual_geometry_v6"
const EDITOR_LAYOUT_CONTRACT_ID := "map_editor_authoritative_layout_v1"
const OCCLUSION_SORT_CONTRACT_ID := "map_actor_occlusion_sort_v6"
const RENDER_DOMAIN_STATIC_BACKGROUND := "static_background"
const RENDER_DOMAIN_ACTOR_Y_SORT := "actor_y_sort"
const WALL_PART_SORT_BASELINE_TILE_OFFSET := Vector2(0.5, 0.5)
const STATIC_WALL_BRIDGE_CONTRACT_ID := "static_authored_atomic_wall_bridge_v1"
const MATERIAL_LAYER_NAMES := [
	"terrain_base", "terrain_front", "object_base", "object_front",
]
const SEMANTIC_LAYER_NAMES := [
	"npc_points", "monster_spawn", "boss_spawn", "door_points",
	"map_entrance_points", "map_exit_points", "respawn_points",
	"safe_area", "light", "region_trigger",
]


static func instance_foot_tile(
	instance: Dictionary,
	asset: Dictionary
) -> Vector2:
	var tile: Array = instance.get("tile", [0, 0])
	var footprint: Array = instance.get(
		"footprint_tiles", asset.get("footprint_tiles", [1, 1])
	)
	if str(asset.get("asset_type", "")) == "wall_module":
		return Vector2(float(tile[0]) + 0.5, float(tile[1]) + 0.5)
	return Vector2(
		float(tile[0]) + float(footprint[0]) * 0.5,
		float(tile[1]) + float(footprint[1]) * 0.5
	)


static func instance_sort_baseline_tile(
	instance: Dictionary,
	asset: Dictionary
) -> Vector2:
	# Occlusion depth is an authored visual contract. It must not be inferred
	# from collision cells, sprite anchor pixels, or the far corner used to
	# order build commands. Ordinary props default to the same world foot that
	# anchors their runtime visual, while an author may supply either an
	# absolute per-instance baseline or a reusable tile offset.
	var explicit: Array = instance.get("sort_baseline_tile", [])
	if explicit.size() == 2:
		return Vector2(float(explicit[0]), float(explicit[1]))
	var result := instance_foot_tile(instance, asset)
	var raw_offset: Array = instance.get(
		"sort_baseline_tile_offset",
		asset.get("sort_baseline_tile_offset", [0, 0])
	)
	if raw_offset.size() == 2:
		result += Vector2(float(raw_offset[0]), float(raw_offset[1]))
	return result


static func instance_sort_baseline_world_offset(
	instance: Dictionary,
	asset: Dictionary
) -> Vector2:
	# offset_px moves the authored visual foot in world pixels, so the default
	# sort baseline follows it. A dedicated override keeps that decision
	# separate from sprite geometry when an asset needs a different cut line.
	var visual_offset: Array = instance.get("offset_px", [0, 0])
	var raw_offset: Array = instance.get(
		"sort_baseline_offset_px",
		asset.get("sort_baseline_offset_px", visual_offset)
	)
	if raw_offset.size() != 2:
		return Vector2.ZERO
	return Vector2(float(raw_offset[0]), float(raw_offset[1]))


static func resolved_anchor_px(
	instance: Dictionary,
	asset: Dictionary,
	command_anchor: Array = []
) -> Vector2:
	if command_anchor.size() == 2:
		return Vector2(float(command_anchor[0]), float(command_anchor[1]))
	var raw: Array = instance.get(
		"anchor_px",
		instance.get(
			"placement_anchor_px", asset.get("anchor_px", [0, 0])
		)
	)
	return Vector2(float(raw[0]), float(raw[1]))


static func editor_instance_geometry(
	instance: Dictionary,
	asset: Dictionary,
	design_size: Vector2i,
	draw_offset: Vector2,
	draw_scale: float,
	texture_size: Vector2,
	command_anchor: Array = []
) -> Dictionary:
	var offset_px: Array = instance.get("offset_px", [0, 0])
	var authored_center := (
		MapEditorCoordinate.tile_to_ground_px(
			instance_foot_tile(instance, asset), design_size
		)
		+ Vector2(float(offset_px[0]), float(offset_px[1]))
	)
	return _geometry_from_center(
		instance,
		asset,
		draw_offset + authored_center * draw_scale,
		draw_scale,
		texture_size,
		command_anchor
	)


static func runtime_instance_geometry(
	instance: Dictionary,
	asset: Dictionary,
	design_size: Vector2i,
	texture_size: Vector2,
	command_anchor: Array = []
) -> Dictionary:
	var offset_px: Array = instance.get("offset_px", [0, 0])
	var world_center := (
		MapEditorCoordinate.ground_position_gu_to_screen_position_px(
			instance_foot_tile(instance, asset), design_size
		)
		+ Vector2(float(offset_px[0]), float(offset_px[1]))
	)
	return _geometry_from_center(
		instance,
		asset,
		world_center,
		1.0,
		texture_size,
		command_anchor
	)


static func editor_command_geometry(
	command: Dictionary,
	design_size: Vector2i,
	draw_offset: Vector2,
	draw_scale: float,
	texture_size: Vector2
) -> Dictionary:
	return editor_instance_geometry(
		command.instance,
		command.asset,
		design_size,
		draw_offset,
		draw_scale,
		texture_size,
		command.get("anchor", [])
	)


static func runtime_command_geometry(
	command: Dictionary,
	design_size: Vector2i,
	texture_size: Vector2
) -> Dictionary:
	return runtime_instance_geometry(
		command.instance,
		command.asset,
		design_size,
		texture_size,
		command.get("anchor", [])
	)


static func apply_runtime_sprite_geometry(
	sprite: Sprite2D,
	command: Dictionary,
	geometry: Dictionary,
	parent_world_origin := Vector2.ZERO
) -> void:
	# Y-sorted occluders are reparented under a wrapper at their sort foot. The
	# wrapper changes only the sprite's local position: anchor, scale, rotation,
	# and material configuration must remain identical to ordinary instances.
	var center: Vector2 = geometry.get("center", Vector2.ZERO)
	var anchor: Vector2 = geometry.get("anchor", Vector2.ZERO)
	var visual_scale: Vector2 = geometry.get("visual_scale", Vector2.ONE)
	var instance: Dictionary = command.get("instance", {})
	sprite.position = center - parent_world_origin
	sprite.offset = -anchor
	sprite.scale = visual_scale
	sprite.rotation = float(geometry.get("rotation", 0.0))
	MapEditorInstanceService.configure_runtime_material_canvas_item(
		sprite, instance
	)


static func _geometry_from_center(
	instance: Dictionary,
	asset: Dictionary,
	center: Vector2,
	draw_scale: float,
	texture_size: Vector2,
	command_anchor: Array
) -> Dictionary:
	var instance_scale: Array = instance.get("scale", [1.0, 1.0])
	var visual_scale := Vector2(
		float(instance_scale[0]), float(instance_scale[1])
	) * draw_scale
	var anchor := resolved_anchor_px(instance, asset, command_anchor)
	var top_left := center - anchor * visual_scale
	var selection_bounds: Array = asset.get("selection_bounds_px", [])
	var visual_rect := Rect2(top_left, texture_size * visual_scale)
	if command_anchor.is_empty() and selection_bounds.size() == 4:
		visual_rect = Rect2(
			top_left + Vector2(
				float(selection_bounds[0]), float(selection_bounds[1])
			) * visual_scale,
			Vector2(
				float(selection_bounds[2]), float(selection_bounds[3])
			) * visual_scale
		)
	return {
		"center": center,
		"anchor": anchor,
		"visual_scale": visual_scale,
		"rotation": deg_to_rad(float(instance.get("rotation_deg", 0.0))),
		"top_left": top_left,
		"rect": visual_rect,
	}


static func instance_draw_commands(
	instance: Dictionary,
	asset: Dictionary,
	layer_index := 0,
	sequence := 0
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var tile_raw: Array = instance.get("tile", [0, 0])
	var footprint: Array = instance.get(
		"footprint_tiles", asset.get("footprint_tiles", [1, 1])
	)
	var instance_tile := Vector2i(int(tile_raw[0]), int(tile_raw[1]))
	var adaptive_raw: Array = instance.get(
		"adaptive_corner_sort_tile_offset", [0, 0]
	)
	var adaptive := Vector2i(
		int(adaptive_raw[0]) if adaptive_raw.size() >= 1 else 0,
		int(adaptive_raw[1]) if adaptive_raw.size() >= 2 else 0
	)
	var render_parts: Array = asset.get("render_parts", [])
	var split_wall := (
		str(asset.get("asset_type", "")) == "wall_module"
		and not render_parts.is_empty()
	)
	var occlusion_segments: Array = instance.get(
		"occlusion_segments", asset.get("occlusion_segments", [])
	)
	if (
		str(asset.get("asset_type", "")) != "wall_module"
		and not occlusion_segments.is_empty()
	):
		var base_image := str(asset.get("occlusion_base_image", ""))
		if not base_image.is_empty():
			result.append({
				"instance": instance,
				"asset": asset,
				"image_path": base_image,
				"anchor": asset.get("anchor_px", [0, 0]),
				"sort_tile": instance_tile,
				"sort_baseline_tile": instance_sort_baseline_tile(
					instance, asset
				),
				"sort_baseline_offset_px": instance_sort_baseline_world_offset(
					instance, asset
				),
				"layer_index": layer_index,
				"image_pass": 1,
				"render_domain": RENDER_DOMAIN_STATIC_BACKGROUND,
				"occlusion_contract_id": OCCLUSION_SORT_CONTRACT_ID,
				"part_order": -1,
				"sequence": sequence,
			})
		for segment_index in occlusion_segments.size():
			var segment: Dictionary = occlusion_segments[segment_index]
			var segment_image := str(segment.get("image", ""))
			if segment_image.is_empty():
				continue
			var segment_baseline := instance_sort_baseline_tile(instance, asset)
			var raw_tile_offset: Array = segment.get(
				"sort_baseline_tile_offset", [0, 0]
			)
			if raw_tile_offset.size() == 2:
				segment_baseline += Vector2(
					float(raw_tile_offset[0]), float(raw_tile_offset[1])
				)
			var segment_world_offset := instance_sort_baseline_world_offset(
				instance, asset
			)
			var raw_pixel_offset: Array = segment.get(
				"sort_baseline_offset_px", [0, 0]
			)
			if raw_pixel_offset.size() == 2:
				segment_world_offset += Vector2(
					float(raw_pixel_offset[0]), float(raw_pixel_offset[1])
				)
			result.append({
				"instance": instance,
				"asset": asset,
				"image_path": segment_image,
				"anchor": segment.get(
					"anchor", asset.get("anchor_px", [0, 0])
				),
				"sort_tile": instance_tile,
				"sort_baseline_tile": segment_baseline,
				"sort_baseline_offset_px": segment_world_offset,
				"layer_index": layer_index,
				"image_pass": 2,
				"render_domain": RENDER_DOMAIN_ACTOR_Y_SORT,
				"occlusion_contract_id": OCCLUSION_SORT_CONTRACT_ID,
				"part_order": int(segment.get(
					"draw_order_index", segment_index
				)),
				"sequence": sequence + segment_index,
			})
		return result
	var has_split_foreground := false
	for part: Dictionary in render_parts:
		if not str(part.get("front_image", "")).is_empty():
			has_split_foreground = true
			break
	if (
		split_wall
	):
		for part_index in render_parts.size():
			var part: Dictionary = render_parts[part_index]
			var sort_offset_raw: Array = part.get(
				"sort_tile_offset", part.get("tile_offset", [0, 0])
			)
			var sort_tile := instance_tile + Vector2i(
				int(sort_offset_raw[0]), int(sort_offset_raw[1])
			) + adaptive
			# Wall part offsets identify occupied cells, not world-space feet.
			# Actors stand at cell centres.  Sorting a foreground part at the
			# integer cell corner makes the open cell immediately behind it
			# share the exact same world Y, so scene-tree insertion order can
			# expose an actor through the wall.  Keep the authored per-part
			# split, but place its sort cut at the centre of that occupied cell.
			var part_sort_baseline := (
				Vector2(sort_tile) + WALL_PART_SORT_BASELINE_TILE_OFFSET
			)
			var anchor: Array = part.get(
				"anchor", asset.get("anchor_px", [0, 0])
			)
			for image_pass: Dictionary in [
				{"field": "shadow_image", "pass": 0},
				{"field": "base_image", "pass": 1},
				{"field": "front_image", "pass": 2},
			]:
				var image_path := str(part.get(str(image_pass.field), ""))
				if image_path.is_empty():
					continue
				var pass_index := int(image_pass.pass)
				var render_domain := render_domain_for_pass(
					instance, asset, pass_index, has_split_foreground
				)
				var actor_sort_group := ""
				if (
					pass_index > 0
					and render_domain == RENDER_DOMAIN_ACTOR_Y_SORT
				):
					# A wall part is one opaque occluder relative to actors.  Its
					# base and front images remain separate children only to retain
					# their authored pass order; they share one Y-sort wrapper.
					actor_sort_group = "wall_part:%s:%d:%d" % [
						str(instance.get("instance_id", "")), sequence, part_index,
					]
				result.append({
					"instance": instance,
					"asset": asset,
					"image_path": image_path,
					"anchor": anchor,
					"sort_tile": sort_tile,
					# Split wall parts retain their authored front/base contract.
					# Their part offset selects the occupied cell; the actual
					# actor crossing baseline is that cell's physical centre.
					"sort_baseline_tile": part_sort_baseline,
					"sort_baseline_offset_px": Vector2.ZERO,
					"layer_index": layer_index,
					"image_pass": pass_index,
					"render_domain": render_domain,
					"actor_sort_group": actor_sort_group,
					"occlusion_contract_id": OCCLUSION_SORT_CONTRACT_ID,
					"part_order": int(part.get("draw_order_index", 0)),
					"sequence": sequence,
				})
		return result
	var sort_tile := instance_tile + Vector2i(
		maxi(0, int(footprint[0]) - 1),
		maxi(0, int(footprint[1]) - 1)
	) + adaptive
	result.append({
		"instance": instance,
		"asset": asset,
		"image_path": str(asset.get("image", "")),
		"anchor": [],
		"sort_tile": sort_tile,
		"sort_baseline_tile": instance_sort_baseline_tile(instance, asset),
		"sort_baseline_offset_px": instance_sort_baseline_world_offset(
			instance, asset
		),
		"layer_index": layer_index,
		"image_pass": 1,
		"render_domain": render_domain_for_pass(
			instance, asset, 1, false
		),
		"occlusion_contract_id": OCCLUSION_SORT_CONTRACT_ID,
		"part_order": 0,
		"sequence": sequence,
	})
	return result


static func instance_is_occluder(
	instance: Dictionary,
	asset: Dictionary
) -> bool:
	# Runtime instances snapshot the author's occlusion choice. Older published
	# maps may not carry that field, so retain the calibrated asset as fallback.
	# Wall modules are structural occluders even when a legacy catalog omitted
	# the flag; this also covers unsplit wall assets.
	if str(asset.get("asset_type", "")) == "wall_module":
		return true
	if instance.has("occlusion"):
		return bool(instance.get("occlusion", false))
	return bool(asset.get("occlusion", false))


static func render_domain_for_pass(
	instance: Dictionary,
	asset: Dictionary,
	image_pass: int,
	has_split_foreground: bool
) -> String:
	# Ground shadows stay baked behind actors.  Both opaque halves of a split
	# wall sort at the same authored foot: base contains real lower-facade pixels,
	# so leaving it static lets every world object paint into the wall.  Ordinary
	# unsplit occluders continue to sort as one unit.
	if image_pass == 0:
		return RENDER_DOMAIN_STATIC_BACKGROUND
	if has_split_foreground:
		return RENDER_DOMAIN_ACTOR_Y_SORT
	return (
		RENDER_DOMAIN_ACTOR_Y_SORT
		if instance_is_occluder(instance, asset)
		else RENDER_DOMAIN_STATIC_BACKGROUND
	)


static func legacy_profile_prop_render_domain(prop: Dictionary) -> String:
	# Profile props are world-space objects, not ground decoration. The legacy
	# renderer historically duplicated canopies at a fixed z, which made actors
	# visible through objects from one side and permanently hidden from the
	# other. Unless a profile explicitly opts out, sort the complete prop by its
	# foot position in the actor domain.
	return (
		RENDER_DOMAIN_ACTOR_Y_SORT
		if bool(prop.get("occlusion", true))
		else RENDER_DOMAIN_STATIC_BACKGROUND
	)


static func legacy_profile_prop_actor_sort_world(prop: Dictionary) -> Vector2:
	return prop.get("position", Vector2.ZERO)


static func sorted_draw_commands(instances: Array) -> Array[Dictionary]:
	var commands: Array[Dictionary] = []
	var asset_cache := {}
	var sequence := 0
	for instance: Dictionary in instances:
		var asset_id := str(instance.get("asset_id", ""))
		if not asset_cache.has(asset_id):
			asset_cache[asset_id] = MapAssetCatalogService.find_asset(asset_id)
		var asset: Dictionary = asset_cache[asset_id]
		var layer_index := MATERIAL_LAYER_NAMES.find(
			str(instance.get("layer", "object_base"))
		)
		for command: Dictionary in instance_draw_commands(
			instance, asset, maxi(0, layer_index), sequence
		):
			commands.append(command)
		sequence += 1
	commands.sort_custom(draw_command_less)
	for command_index in commands.size():
		commands[command_index]["command_index"] = command_index
	return commands


static func is_atomic_wall_pass(command: Dictionary) -> bool:
	return (
		str(command.get("asset", {}).get("asset_type", "")) == "wall_module"
		and not str(command.get("actor_sort_group", "")).is_empty()
		and int(command.get("image_pass", -1)) in [1, 2]
	)


static func is_static_authored_wall_bridge_candidate(command: Dictionary) -> bool:
	# Eligibility is intentionally semantic and public.  The original authored
	# static command remains untouched; this only identifies commands whose
	# pixels may need their pre-atomic-wall relation restored over a wall base.
	var instance: Dictionary = command.get("instance", {})
	var asset: Dictionary = command.get("asset", {})
	var layer := str(instance.get("layer", ""))
	return (
		str(command.get("render_domain", "")) == RENDER_DOMAIN_STATIC_BACKGROUND
		and not instance_is_occluder(instance, asset)
		and layer in ["object_base", "object_front"]
		and int(command.get("image_pass", -1)) > 0
		and str(asset.get("asset_type", "")) != "wall_module"
		and not command_is_terrain_floor_or_shadow(command)
	)


static func command_is_terrain_floor_or_shadow(command: Dictionary) -> bool:
	var instance: Dictionary = command.get("instance", {})
	var asset: Dictionary = command.get("asset", {})
	var layer := str(instance.get("layer", "")).to_lower()
	var category := str(asset.get("category", "")).to_lower()
	var asset_type := str(asset.get("asset_type", "")).to_lower()
	return (
		layer in ["terrain_base", "terrain_front", "floor", "ground"]
		or int(command.get("image_pass", -1)) == 0
		or category in ["terrain", "floor", "ground", "shadow"]
		or asset_type in ["terrain_tile", "floor_tile", "ground_tile", "shadow"]
	)


static func static_wall_bridge_source_over(
	source: Color,
	destination: Color
) -> Color:
	var out_alpha := source.a + destination.a * (1.0 - source.a)
	if out_alpha <= 0.0:
		return Color(0, 0, 0, 0)
	var premultiplied := (
		Vector3(source.r, source.g, source.b) * source.a
		+ Vector3(destination.r, destination.g, destination.b)
			* destination.a * (1.0 - source.a)
	)
	return Color(
		premultiplied.x / out_alpha,
		premultiplied.y / out_alpha,
		premultiplied.z / out_alpha,
		out_alpha
	)


static func static_wall_bridge_compose_ordered_colors(colors: Array[Color]) -> Color:
	var result := Color(0, 0, 0, 0)
	for color: Color in colors:
		result = static_wall_bridge_source_over(color, result)
	return result


static func command_texture_transform(
	command: Dictionary,
	design_size: Vector2i,
	texture_size: Vector2
) -> Transform2D:
	# Maps source texture coordinates directly to world pixels.  Keeping this
	# transform public makes the bridge consume the exact same anchor, scale and
	# rotation contract as the runtime Sprite2D; dormant flip fields stay inert.
	var geometry := runtime_command_geometry(command, design_size, texture_size)
	var basis := Transform2D(
		float(geometry.get("rotation", 0.0)),
		Vector2(geometry.get("visual_scale", Vector2.ONE)),
		0.0,
		Vector2.ZERO
	)
	var anchor := Vector2(geometry.get("anchor", Vector2.ZERO))
	basis.origin = Vector2(geometry.get("center", Vector2.ZERO)) - basis.basis_xform(anchor)
	return basis


static func transformed_texture_aabb(
	texture_transform: Transform2D,
	texture_size: Vector2
) -> Rect2i:
	var points := [
		texture_transform * Vector2.ZERO,
		texture_transform * Vector2(texture_size.x, 0.0),
		texture_transform * texture_size,
		texture_transform * Vector2(0.0, texture_size.y),
	]
	var minimum: Vector2 = points[0]
	var maximum: Vector2 = points[0]
	for point: Vector2 in points:
		minimum = minimum.min(point)
		maximum = maximum.max(point)
	var begin := Vector2i(floori(minimum.x), floori(minimum.y))
	var finish := Vector2i(ceili(maximum.x), ceili(maximum.y))
	return Rect2i(begin, (finish - begin).max(Vector2i.ONE))


static func command_actor_sort_world(
	command: Dictionary,
	design_size: Vector2i
) -> Vector2:
	var raw_baseline: Variant = command.get(
		"sort_baseline_tile", command.get("sort_tile", Vector2i.ZERO)
	)
	var baseline_tile := Vector2(raw_baseline)
	var raw_offset: Variant = command.get(
		"sort_baseline_offset_px", Vector2.ZERO
	)
	return (
		MapEditorCoordinate.ground_position_gu_to_screen_position_px(
			baseline_tile, design_size
		)
		+ Vector2(raw_offset)
	)


static func static_authored_sort_world(
	command: Dictionary,
	design_size: Vector2i
) -> Vector2:
	# Static authored materials retain their established far-corner draw plane.
	# Compare the centre of that occupied cell with an atomic wall's occupied-
	# cell centre; this raises the decoration group as a unit without deriving a
	# new foot from sprite alpha, anchor, asset identity, or collision geometry.
	var sort_tile := Vector2(command.get("sort_tile", Vector2i.ZERO))
	var raw_offset: Variant = command.get(
		"sort_baseline_offset_px", Vector2.ZERO
	)
	return (
		MapEditorCoordinate.ground_position_gu_to_screen_position_px(
			sort_tile + WALL_PART_SORT_BASELINE_TILE_OFFSET, design_size
		)
		+ Vector2(raw_offset)
	)


static func static_authored_command_is_in_front_of_wall(
	static_command: Dictionary,
	wall_command: Dictionary,
	design_size: Vector2i
) -> bool:
	return (
		static_authored_sort_world(static_command, design_size).y
		> command_actor_sort_world(wall_command, design_size).y
	)


static func static_wall_bridge_pair_is_candidate(
	static_command: Dictionary,
	wall_base_command: Dictionary,
	design_size: Vector2i,
	static_aabb: Rect2i,
	wall_group_aabb: Rect2i
) -> bool:
	return (
		is_static_authored_wall_bridge_candidate(static_command)
		and is_atomic_wall_pass(wall_base_command)
		and int(wall_base_command.get("image_pass", -1)) == 1
		and static_authored_command_is_in_front_of_wall(
			static_command, wall_base_command, design_size
		)
		and static_aabb.intersects(wall_group_aabb)
	)


static func draw_command_less(a: Dictionary, b: Dictionary) -> bool:
	var a_order := MapEditorInstanceService.material_layer_order(a.instance)
	var b_order := MapEditorInstanceService.material_layer_order(b.instance)
	if a_order != b_order:
		return a_order < b_order
	var a_tile: Vector2i = a.sort_tile
	var b_tile: Vector2i = b.sort_tile
	var a_depth := a_tile.x + a_tile.y
	var b_depth := b_tile.x + b_tile.y
	if a_depth != b_depth:
		return a_depth < b_depth
	if a_tile.x != b_tile.x:
		return a_tile.x < b_tile.x
	if int(a.layer_index) != int(b.layer_index):
		return int(a.layer_index) < int(b.layer_index)
	if int(a.image_pass) != int(b.image_pass):
		return int(a.image_pass) < int(b.image_pass)
	if int(a.part_order) != int(b.part_order):
		return int(a.part_order) < int(b.part_order)
	return int(a.sequence) < int(b.sequence)


static func geometry_payload(instances: Array) -> Array[Dictionary]:
	var payload: Array[Dictionary] = []
	for instance: Dictionary in instances:
		var entry := {}
		for field: String in [
			"instance_id", "asset_id", "layer", "tile", "tile_anchor",
			"footprint_tiles", "offset_px", "anchor_px",
			"placement_anchor_px", "scale", "rotation_deg",
			"material_layer_order", "adaptive_corner_sort_tile_offset",
		]:
			if instance.has(field):
				entry[field] = instance[field]
		payload.append(entry)
	payload.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return str(a.get("instance_id", "")) < str(b.get("instance_id", ""))
	)
	return payload


static func geometry_sha256(instances: Array) -> String:
	return _sha256_text(MapEditorJsonCodec.encode({
		"contract_id": VISUAL_GEOMETRY_CONTRACT_ID,
		"instances": geometry_payload(instances),
		"draw_commands": draw_command_payload(instances),
	}))


static func draw_command_payload(instances: Array) -> Array[Dictionary]:
	var payload: Array[Dictionary] = []
	for command: Dictionary in sorted_draw_commands(instances):
		var sort_tile: Vector2i = command.sort_tile
		var sort_baseline_tile := Vector2(command.get(
			"sort_baseline_tile", sort_tile
		))
		var sort_baseline_offset_px := Vector2(command.get(
			"sort_baseline_offset_px", Vector2.ZERO
		))
		payload.append({
			"instance_id": str(command.instance.get("instance_id", "")),
			"asset_id": str(command.instance.get("asset_id", "")),
			"asset_type": str(command.asset.get("asset_type", "")),
			"image_path": str(command.image_path),
			"anchor": command.get("anchor", []).duplicate(),
			"sort_tile": [sort_tile.x, sort_tile.y],
			"sort_baseline_tile": [
				sort_baseline_tile.x, sort_baseline_tile.y,
			],
			"sort_baseline_offset_px": [
				sort_baseline_offset_px.x, sort_baseline_offset_px.y,
			],
			"layer_index": int(command.layer_index),
			"image_pass": int(command.image_pass),
			"render_domain": str(command.get(
				"render_domain", RENDER_DOMAIN_STATIC_BACKGROUND
			)),
			"actor_sort_group": str(command.get("actor_sort_group", "")),
			"occlusion_contract_id": str(command.get(
				"occlusion_contract_id", OCCLUSION_SORT_CONTRACT_ID
			)),
			"part_order": int(command.part_order),
			"sequence": int(command.sequence),
		})
	return payload


static func document_content_sha256(document: Dictionary) -> String:
	return _sha256_text(MapEditorJsonCodec.encode(document))


static func editor_layout_sha256(document: Dictionary) -> String:
	var semantics: Array[Dictionary] = []
	for layer_name: String in SEMANTIC_LAYER_NAMES:
		for entry: Dictionary in document.get("layers", {}).get(layer_name, []):
			semantics.append({
				"layer": layer_name,
				"semantic_id": str(entry.get("semantic_id", "")),
				"kind": str(entry.get("kind", "")),
				"tile": entry.get("tile", []).duplicate(),
				"radius_gu": entry.get("radius_gu", 0.0),
				"display_name": str(entry.get("display_name", "")),
			})
	semantics.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return (
				str(a.layer) + ":" + str(a.semantic_id)
				< str(b.layer) + ":" + str(b.semantic_id)
			)
	)
	var instances := MapEditorInstanceService.all_instances(document)
	return _sha256_text(MapEditorJsonCodec.encode({
		"contract_id": EDITOR_LAYOUT_CONTRACT_ID,
		"design_size": document.get("design", {}).get("design_size", []),
		"geometry": geometry_payload(instances),
		"semantics": semantics,
	}))


static func _sha256_text(value: String) -> String:
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(value.to_utf8_buffer())
	return hashing.finish().hex_encode()
