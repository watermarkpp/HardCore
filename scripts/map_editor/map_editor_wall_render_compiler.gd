class_name MapEditorWallRenderCompiler
extends RefCounted
## WALL-P1R Phase 2+4 build-time compiler (pure logic + CPU materialization).
##
## Partitions sorted_draw_commands into:
##   - shadow chunk bucket: contiguous pass-0 wall-module shadow commands
##     baked into fixed ground-space grid pages (painter-order preserving);
##   - dynamic atlas bucket: every ACTOR_Y_SORT wall group with 1..N layers
##     becomes one texture-space composite entry shared across instances
##     (single-layer groups use their source image directly);
##   - legacy bucket: everything else (bridges stay runtime overlays).
##
## Hard contracts (advisor review 2026-09-17):
##   1. atlas covers 1-sprite / 2-sprite / N-sprite wall groups;
##   2. deterministic atlas paging with a hard page height cap;
##   3. full command accounting - every command lands in exactly one bucket;
##   4. fail-closed: any structural violation demotes affected commands to
##      the legacy bucket instead of guessing.

const PLAN_CONTRACT_ID := "hardcore.wall_render_plan.v1"
const PAGE_WIDTH := 2048
const PAGE_MAX_HEIGHT := 4096
const SHADOW_CHUNK_SIZE := 1024
const GEOMETRY_SERVICE := preload(
	"res://scripts/map_editor/map_editor_runtime_visual_geometry_service.gd"
)


## Pure partition over sorted commands. `image_size_resolver` receives an
## image_path and returns Vector2i.ZERO when the image cannot be resolved
## (entry demoted to legacy, fail-closed).
static func compile_plan(
	commands: Array,
	design_size: Vector2i,
	image_size_resolver: Callable
) -> Dictionary:
	var groups: Dictionary = {}
	var group_order: Array[String] = []
	var legacy_indices: Array[int] = []
	var seen_shadow := false
	var first_shadow := -1
	var last_shadow := -1
	for index: int in commands.size():
		var command: Dictionary = commands[index]
		var domain := str(command.get("render_domain", ""))
		var asset_type := str(command.get("asset", {}).get("asset_type", ""))
		var pass_index := int(command.get("image_pass", -1))
		if domain == GEOMETRY_SERVICE.RENDER_DOMAIN_STATIC_BACKGROUND:
			if asset_type == "wall_module" and pass_index == 0:
				if first_shadow < 0:
					first_shadow = index
				last_shadow = index
				seen_shadow = true
			continue
		if domain == GEOMETRY_SERVICE.RENDER_DOMAIN_ACTOR_Y_SORT:
			var group_key := str(command.get("actor_sort_group", ""))
			if group_key.is_empty() or pass_index <= 0:
				legacy_indices.append(index)
				continue
			if not groups.has(group_key):
				groups[group_key] = []
				group_order.append(group_key)
			groups[group_key].append(index)
			continue
		legacy_indices.append(index)
	# Static-span bake: bake ALL static commands from the first to the last
	# wall shadow (in painter order) into one grid chunk set. Non-shadow
	# statics inside the span blend into the chunks in their authored order,
	# so the single chunk layer is painter-exact; statics outside the span
	# stay legacy sprites. Dynamics are plane-separated and unaffected.
	# Static-span bake with transform-aware segmentation: bakeable statics
	# (identity transform) between the first and last wall shadow form
	# consecutive segments; any non-identity-transform static breaks the
	# segment and stays a legacy sprite at its exact painter position.
	var span_statics: Array[int] = []
	for index: int in commands.size():
		var command: Dictionary = commands[index]
		if str(command.get("render_domain", "")) != (
			GEOMETRY_SERVICE.RENDER_DOMAIN_STATIC_BACKGROUND
		):
			continue
		if seen_shadow and index >= first_shadow and index <= last_shadow:
			span_statics.append(index)
		else:
			legacy_indices.append(index)
	var shadow_segments: Array = []
	var current_segment: Array = []
	for static_index: int in span_statics:
		if _static_is_bakeable(commands[static_index]):
			current_segment.append(static_index)
			continue
		legacy_indices.append(static_index)
		if not current_segment.is_empty():
			shadow_segments.append(current_segment)
			current_segment = []
	if not current_segment.is_empty():
		shadow_segments.append(current_segment)
	var entries: Array = []
	for group_key: String in group_order:
		var indices: Array = groups[group_key]
		indices.sort()
		var layers: Array = []
		var entry_key_parts: PackedStringArray = []
		var failed := false
		for command_index: int in indices:
			var command: Dictionary = commands[command_index]
			var image_path := str(command.get("image_path", ""))
			var size := Vector2i.ZERO
			if image_size_resolver.is_valid():
				size = image_size_resolver.call(image_path)
			if size == Vector2i.ZERO or image_path.is_empty():
				failed = true
				break
			var anchor: Array = command.get("anchor", [0, 0])
			# Sprite offset semantics: offset = -anchor (the runtime builder
			# sets sprite.offset = -anchor), so atlas layers must key on the
			# same sign for pixel-exact placement.
			var offset := Vector2.ZERO
			if anchor.size() == 2:
				offset = -Vector2(float(anchor[0]), float(anchor[1]))
			layers.append({
				"command_index": command_index,
				"image_path": image_path,
				"offset": [offset.x, offset.y],
				"size": [size.x, size.y],
			})
			entry_key_parts.append(
				"%s@%s" % [image_path, str(offset)]
			)
		if failed:
			legacy_indices.append_array(indices)
			continue
		entries.append({
			"key": "|".join(entry_key_parts),
			"layers": layers,
			"group_keys": [str(commands[indices[0]].get(
				"actor_sort_group", ""
			))],
			"command_indices": indices.duplicate(),
		})
	# Merge entries with identical keys (shared composite across instances).
	var unique: Dictionary = {}
	var unique_order: Array[String] = []
	for entry: Dictionary in entries:
		var key := str(entry["key"])
		if unique.has(key):
			unique[key]["group_keys"].append_array(entry["group_keys"])
			unique[key]["command_indices"].append_array(
				entry["command_indices"]
			)
		else:
			unique[key] = entry
			unique_order.append(key)
	var packed := _pack_pages(unique_order, unique)
	# Oversized / unplaced entries demote their commands to legacy BEFORE
	# accounting (advisor P0-3: no covered-but-absent commands).
	var final_atlas_indices: Array[int] = []
	var final_legacy_indices: Array[int] = []
	final_legacy_indices.append_array(legacy_indices)
	for key: String in unique_order:
		var entry: Dictionary = unique[key]
		if packed["placements"][key] == null:
			final_legacy_indices.append_array(entry["command_indices"])
			continue
		final_atlas_indices.append_array(entry["command_indices"])
	var chunk_command_indices: Array[int] = []
	for segment: Array in shadow_segments:
		chunk_command_indices.append_array(segment)
	# Contract verification: the three sets must be pairwise disjoint and
	# cover every command exactly once; violation fails the whole plan.
	var covered := {}
	var contract_ok := true
	for index: int in final_atlas_indices:
		if covered.has(index):
			contract_ok = false
		covered[index] = true
	for index: int in chunk_command_indices:
		if covered.has(index):
			contract_ok = false
		covered[index] = true
	for index: int in final_legacy_indices:
		if covered.has(index):
			contract_ok = false
		covered[index] = true
	if covered.size() != commands.size():
		contract_ok = false
	if not contract_ok:
		return {"contract_violation": true}
	final_legacy_indices.sort()
	var accounting := {
		"total_commands": commands.size(),
		"atlas_commands": final_atlas_indices.size(),
		"shadow_chunk_commands": chunk_command_indices.size(),
		"legacy_commands": final_legacy_indices.size(),
	}
	return {
		"contract_id": PLAN_CONTRACT_ID,
		"source_commands_sha256": commands_digest(commands),
		"design_size": [design_size.x, design_size.y],
		"atlas_entries": _serialized_entries(packed, unique),
		"atlas_page_heights": packed["page_heights"],
		"shadow_segments": _serialized_segments(shadow_segments),
		"atlas_command_indices": final_atlas_indices,
		"shadow_chunk_command_indices": chunk_command_indices,
		"legacy_command_indices": final_legacy_indices,
		"accounting": accounting,
	}


## Deterministic shelf packing across bounded pages. Unplaceable entries get
## a null placement so the caller can demote their commands to legacy before
## accounting.
static func _pack_pages(
	order: Array[String],
	unique: Dictionary
) -> Dictionary:
	var sized: Array = []
	for key: String in order:
		var entry: Dictionary = unique[key]
		var min_offset := Vector2.ZERO
		var max_corner := Vector2.ZERO
		var first := true
		for layer: Dictionary in entry["layers"]:
			var offset := Vector2(layer["offset"][0], layer["offset"][1])
			var size := Vector2(layer["size"][0], layer["size"][1])
			min_offset = offset if first else min_offset.min(offset)
			max_corner = (
				offset + size if first
				else max_corner.max(offset + size)
			)
			first = false
		entry["min_offset"] = [min_offset.x, min_offset.y]
		entry["composite_size"] = [
			int(ceil(max_corner.x - min_offset.x)),
			int(ceil(max_corner.y - min_offset.y)),
		]
		sized.append(entry)
	sized.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			var sa: Array = a["composite_size"]
			var sb: Array = b["composite_size"]
			if sa[1] != sb[1]:
				return sa[1] > sb[1]
			if sa[0] != sb[0]:
				return sa[0] > sb[0]
			return str(a["key"]) < str(b["key"])
	)
	var page_heights: Array[int] = []
	var placements: Dictionary = {}
	var cursor_y := 0
	var row_x := 0
	var row_height := 0
	for entry: Dictionary in sized:
		var size: Array = entry["composite_size"]
		if size[0] > PAGE_WIDTH or size[1] > PAGE_MAX_HEIGHT:
			entry["page"] = -1
			entry["region"] = []
			placements[str(entry["key"])] = null
			continue
		if row_x + int(size[0]) > PAGE_WIDTH:
			cursor_y += row_height
			row_x = 0
			row_height = 0
		if cursor_y + int(size[1]) > PAGE_MAX_HEIGHT:
			# Close the open page; its full height includes the last row.
			page_heights.append(cursor_y + row_height)
			cursor_y = 0
			row_x = 0
			row_height = 0
		var page_index: int = page_heights.size()
		var region := [row_x, cursor_y, int(size[0]), int(size[1])]
		entry["page"] = page_index
		entry["region"] = region
		placements[str(entry["key"])] = {
			"page": page_index,
			"region": region,
			"min_offset": entry["min_offset"],
		}
		row_x += int(size[0])
		row_height = maxi(row_height, int(size[1]))
	if row_x > 0 or row_height > 0 or cursor_y > 0:
		page_heights.append(cursor_y + row_height)
	return {"page_heights": page_heights, "placements": placements}


static func _serialized_entries(
	packed: Dictionary,
	unique: Dictionary
) -> Array:
	var out: Array = []
	for key: String in packed["placements"]:
		var placement: Variant = packed["placements"][key]
		if placement == null:
			continue
		var entry: Dictionary = unique[key]
		out.append({
			"key": key,
			"layers": entry["layers"],
			"composite_size": entry["composite_size"],
			"min_offset": entry["min_offset"],
			"page": placement["page"],
			"region": placement["region"],
			"group_keys": entry["group_keys"],
			"command_indices": entry["command_indices"],
		})
	out.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return str(a["key"]) < str(b["key"])
	)
	return out


static func _serialized_segments(segments: Array) -> Array:
	var out: Array = []
	for segment_index: int in segments.size():
		var indices: Array = segments[segment_index]
		if indices.is_empty():
			continue
		out.append({
			"segment_index": segment_index,
			"insert_command_index": int(indices[0]),
			"command_indices": indices,
		})
	return out


## A static command is bakeable only with an identity transform: CPU Image
## ops cannot reproduce GPU sampling for scaled or rotated sprites, so any
## non-identity transform stays a legacy sprite (advisor P0-4).
static func _static_is_bakeable(command: Dictionary) -> bool:
	var instance: Dictionary = command.get("instance", {})
	var scale: Array = instance.get("scale", [1.0, 1.0])
	if scale.size() != 2:
		return false
	if absf(float(scale[0]) - 1.0) > 0.001 or absf(float(scale[1]) - 1.0) > 0.001:
		return false
	if absf(float(instance.get("rotation_deg", 0.0))) > 0.001:
		return false
	if bool(instance.get("flip_x", false)) or bool(instance.get("flip_y", false)):
		return false
	return true


## Stable digest over every field that can change rendering or sort
## behavior. Build side and runtime side MUST call this same function on
## their respective command arrays; a mismatch fail-closes the runtime
## consumer to legacy rendering. Image CONTENT drift is covered by the
## sha-named content-addressed PNG store written at publish time.
static func commands_digest(commands: Array) -> String:
	var parts: PackedStringArray = []
	for command: Dictionary in commands:
		var instance: Dictionary = command.get("instance", {})
		var asset: Dictionary = command.get("asset", {})
		parts.append("%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s" % [
			str(instance.get("instance_id", "")),
			str(asset.get("asset_id", "")),
			str(command.get("image_path", "")),
			str(command.get("anchor", [])),
			str(instance.get("offset_px", [])),
			str(instance.get("scale", [])),
			str(instance.get("rotation_deg", 0.0)),
			str(instance.get("flip_x", false)),
			str(instance.get("flip_y", false)),
			str(instance.get("material_layer_order", [])),
			str(command.get("sort_tile", [])),
			str(command.get("sort_baseline_tile", [])),
			str(command.get("render_domain", "")),
			str(command.get("actor_sort_group", "")),
			str(command.get("image_pass", -1)),
			str(command.get("part_order", -1)),
			str(command.get("layer_index", -1)),
			str(command.get("sequence", -1)),
		])
	return "|".join(parts).sha256_text()


## CPU materialization for the build side: bakes shadow chunks over a fixed
## grid covering the shadow bounding box (static-sprite position space, the
## same space runtime_command_geometry centers live in) and blends atlas page
## images. `image_loader` receives a res:// image_path and returns an Image
## (or null on failure).
static func materialize(
	plan: Dictionary,
	commands: Array,
	image_loader: Callable
) -> Dictionary:
	var design_raw: Array = plan["design_size"]
	var design_size := Vector2i(int(design_raw[0]), int(design_raw[1]))
	var chunks: Array = []
	for segment: Dictionary in plan["shadow_segments"]:
		var placed: Array = []
		for index: int in segment["command_indices"]:
			var command: Dictionary = commands[index]
			var image: Image = image_loader.call(
				str(command.get("image_path", ""))
			)
			if image == null:
				return {"error": "shadow image unresolvable: %d" % index}
			var geometry: Dictionary = (
				GEOMETRY_SERVICE.runtime_command_geometry(
					command, design_size, Vector2(image.get_size())
				)
			)
			var center: Vector2 = geometry.get("center", Vector2.ZERO)
			var resolved_anchor: Vector2 = geometry.get(
				"anchor", Vector2.ZERO
			)
			placed.append({
				"image": image,
				"origin": center - resolved_anchor,
			})
		var bounds := Rect2i()
		var bounds_first := true
		for entry: Dictionary in placed:
			var rect := Rect2i(
				Vector2i(entry["origin"].floor()), entry["image"].get_size()
			)
			bounds = rect if bounds_first else bounds.merge(rect)
			bounds_first = false
		var chunk_cells := {}
		for entry: Dictionary in placed:
			var rect := Rect2i(
				Vector2i(entry["origin"].floor()), entry["image"].get_size()
			)
			for cx in range(
				floori(float(rect.position.x) / SHADOW_CHUNK_SIZE),
				floori(float(rect.end.x - 1) / SHADOW_CHUNK_SIZE) + 1
			):
				for cy in range(
					floori(float(rect.position.y) / SHADOW_CHUNK_SIZE),
					floori(float(rect.end.y - 1) / SHADOW_CHUNK_SIZE) + 1
				):
					var key := Vector2i(cx, cy)
					if not chunk_cells.has(key):
						chunk_cells[key] = []
					chunk_cells[key].append({
						"image": entry["image"], "at": rect.position,
					})
		var chunk_keys: Array = chunk_cells.keys()
		chunk_keys.sort_custom(
			func(a: Vector2i, b: Vector2i) -> bool:
				return a.y < b.y if a.y == b.y else a.x < b.x
		)
		for key: Vector2i in chunk_keys:
			var chunk := Image.create(
				SHADOW_CHUNK_SIZE, SHADOW_CHUNK_SIZE, false,
				Image.FORMAT_RGBA8
			)
			chunk.fill(Color(0, 0, 0, 0))
			var origin := Vector2(key) * float(SHADOW_CHUNK_SIZE)
			for cell_entry: Dictionary in chunk_cells[key]:
				_blit_clipped(
					chunk, cell_entry["image"],
					Vector2(cell_entry["at"]) - origin
				)
			chunks.append({
				"segment_index": int(segment["segment_index"]),
				"insert_command_index": int(segment["insert_command_index"]),
				"grid_cell": [key.x, key.y],
				"position_px": [origin.x, origin.y],
				"size_px": [SHADOW_CHUNK_SIZE, SHADOW_CHUNK_SIZE],
				"image": chunk,
			})
	var page_heights: Array = plan["atlas_page_heights"]
	var page_images: Array = []
	for page_height: int in page_heights:
		var image := Image.create(
			PAGE_WIDTH, maxi(page_height, 1), false, Image.FORMAT_RGBA8
		)
		image.fill(Color(0, 0, 0, 0))
		page_images.append(image)
	for entry: Dictionary in plan["atlas_entries"]:
		var page_index := int(entry["page"])
		var region: Array = entry["region"]
		if (
			page_index < 0 or page_index >= page_images.size()
			or region.size() != 4
			or int(region[0]) < 0 or int(region[1]) < 0
			or int(region[0]) + int(region[2]) > PAGE_WIDTH
			or int(region[1]) + int(region[3]) > int(page_heights[page_index])
		):
			return {
				"error": "atlas region out of bounds: %s" % str(entry["key"]),
			}
		var composite := _composite_for_entry(entry, image_loader)
		if composite == null:
			return {
				"error": "atlas composite unresolvable: %s" % str(entry["key"]),
			}
		if (
			composite.get_width() != int(region[2])
			or composite.get_height() != int(region[3])
		):
			return {
				"error": "atlas composite size mismatch: %s"
					% str(entry["key"]),
			}
		page_images[page_index].blit_rect(
			composite,
			Rect2i(Vector2i.ZERO, composite.get_size()),
			Vector2i(int(region[0]), int(region[1]))
		)
	return {"shadow_chunks": chunks, "atlas_pages": page_images}


static func _composite_for_entry(
	entry: Dictionary,
	image_loader: Callable
) -> Image:
	var layers: Array = entry.get("layers", [])
	if layers.is_empty():
		return null
	var min_raw: Array = entry["min_offset"]
	var min_offset := Vector2(min_raw[0], min_raw[1])
	var size_raw: Array = entry["composite_size"]
	var composite := Image.create(
		int(size_raw[0]), int(size_raw[1]), false, Image.FORMAT_RGBA8
	)
	composite.fill(Color(0, 0, 0, 0))
	var first := true
	for layer: Dictionary in layers:
		var image: Image = image_loader.call(str(layer["image_path"]))
		if image == null:
			return null
		var offset := Vector2(layer["offset"][0], layer["offset"][1])
		var at := Vector2i((offset - min_offset).round())
		var src := Rect2i(Vector2i.ZERO, image.get_size())
		if first:
			composite.blit_rect(image, src, at)
			first = false
		else:
			composite.blend_rect(image, src, at)
	return composite


static func _blit_clipped(
	target: Image, source: Image, at: Vector2
) -> void:
	var dst := Vector2i(at.round())
	var src := Rect2i(Vector2i.ZERO, source.get_size())
	if dst.x < 0:
		src.position.x -= dst.x
		src.size.x += dst.x
		dst.x = 0
	if dst.y < 0:
		src.position.y -= dst.y
		src.size.y += dst.y
		dst.y = 0
	src.size.x = mini(src.size.x, target.get_width() - dst.x)
	src.size.y = mini(src.size.y, target.get_height() - dst.y)
	if src.size.x <= 0 or src.size.y <= 0:
		return
	target.blend_rect(source, src, dst)
