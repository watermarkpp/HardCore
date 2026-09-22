extends Node2D

## WALL-P0 wall stress fixture ("wall_perf_lab").
##
## Builds a synthetic wall field through the REAL production path
## (WorldBackground._build_editor_runtime_instances over
## MapEditorRuntimeVisualGeometryService.sorted_draw_commands), then applies
## a mode-specific PHYSICAL transform without touching the logical command
## authority:
##
##   MODE A - production as-is: per segment one Y-sort wrapper with
##            base + front Sprite2D children and the static wall bridge.
##   MODE B - Physical CanvasItem Collapse (P1A preview): the two dynamic
##            sprites of each segment are replaced by one custom CanvasItem
##            that replays each sprite's exact transform/texture/material as
##            draw commands. Bridge overlay kept as a sibling child.
##   MODE C - Composite preview (P1B preview): for unrotated, unscaled
##            segments the base+front textures are blended once into a
##            single ImageTexture (front OVER base) and drawn as one sprite.
##            Segments that are rotated/scaled fall back to MODE B canvas.
##   MODE D - Diagnostic static/no-y-sort: every command is forced to
##            RENDER_DOMAIN_STATIC_BACKGROUND with no actor_sort_group and
##            rebuilt through the production sprite builder. Benchmark only.
##
## The logical command set, transforms, and bridge inputs stay identical
## across A/B/C; D is a diagnostic lower bound. This scene is not part of
## the release registry and is never shipped as a formal map.
##
## Usage:
##   godot --path . res://tools/wall_perf_lab.tscn -- mode=A walls=100 seconds=20

const WALL_L1_X := "cave_granite_straight_x_l1_v01"
const WALL_L2_X := "cave_granite_straight_x_l2_v01"
const WALL_L3_X := "cave_granite_straight_x_l3_v03"
const WALL_L4_X := "cave_granite_straight_x_l4_v01"
const WALL_L4_Y := "cave_granite_straight_y_l4_v01"
const WALL_CORNER_SE := "cave_granite_outer_se_v01"
const WALL_CORNER_SW := "cave_granite_outer_sw_v01"
const DECORATION_A := "user.f0d72af3638e0c81"
const TIER_ASSETS := [WALL_L1_X, WALL_L2_X, WALL_L3_X, WALL_L4_X]
const TIER_LEVELS := [1, 2, 3, 4]
const ROWS_PER_TIER := 5
const WALLS_PER_ROW := 20
const DESIGN_TILES := 64
const ACTOR_COUNT := 24
const WallProbe := preload("res://scripts/wall_runtime_perf_probe.gd")

var mode := "A"
var walls_per_tier := 100
var window_seconds := 20.0
var screenshot := false
var background: WorldBackground = null
var _actors: Array[Sprite2D] = []
var _actor_base: Array[Vector2] = []
var _actor_phase: Array[float] = []
var _elapsed := 0.0
var _camera_anchor := Vector2.ZERO
var _expected := {}


func _ready() -> void:
	y_sort_enabled = true
	_parse_args()
	_build_field()
	_attach_camera()
	_spawn_actors()
	_validate()
	var probe := WallProbe.new()
	probe.configure(background, self, false)
	add_child(probe)
	probe.start_window(
		"lab_mode_%s_walls_%d" % [mode, walls_per_tier], window_seconds
	)
	probe.window_finished.connect(_on_window_finished)


func _parse_args() -> void:
	for arg: String in OS.get_cmdline_user_args():
		var pair := arg.split("=", true, 1)
		if pair.size() != 2:
			continue
		match pair[0]:
			"mode":
				mode = pair[1].to_upper()
			"walls":
				walls_per_tier = int(pair[1])
			"seconds":
				window_seconds = float(pair[1])
			"screenshot":
				screenshot = pair[1] == "1"
	assert(mode in ["A", "B", "C", "D", "E"], "mode must be A|B|C|D|E")
	assert(walls_per_tier > 0, "walls must be positive")


func _process(delta: float) -> void:
	# Actor patrol keeps Y-sort re-ordering live like walking characters.
	_elapsed += delta
	for index: int in _actors.size():
		var actor := _actors[index]
		actor.position = _actor_base[index] + Vector2(
			sin(_elapsed * (0.6 + 0.05 * float(index % 7)) + _actor_phase[index])
			* 96.0,
			0.0
		)


func _on_window_finished(summary: Dictionary) -> void:
	if screenshot:
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		var path := ProjectSettings.globalize_path(
			"res://outputs/wall_perf/lab_mode_%s_walls_%d.png" % [
				mode, walls_per_tier,
			]
		)
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		image.save_png(path)
		print("WALL_PERF_LAB_SCREENSHOT path=%s" % path)
	print(
		"WALL_PERF_LAB_DONE mode=%s walls=%d" % [mode, walls_per_tier]
	)
	get_tree().quit()


func _build_field() -> void:
	var instances := _synthetic_instances()
	background = WorldBackground.new()
	background.defer_initial_legacy_build_to_coordinator()
	add_child(background)
	var runtime := {
		"design": {"design_size": [DESIGN_TILES, DESIGN_TILES]},
		"instances": instances,
	}
	background._build_editor_runtime_instances(runtime)
	# Production maps carry an editor runtime visual, so WorldBackground._draw
	# renders one ground polygon + chunk canvases. Without it the lab falls
	# into the legacy per-cell ground fill (~6.5k polygon draws of pure noise
	# that buries the wall-content signal). Mirror the production shape.
	if background.get("_editor_runtime_visual").is_empty():
		background.set("_editor_runtime_visual", {
			"design_size": [DESIGN_TILES, DESIGN_TILES],
			"base_color": "#465827",
		})
	# Snapshot the centroid BEFORE mode transforms: E removes shadow sprites,
	# which would drift the camera and break A-vs-E screenshot comparability.
	_camera_anchor = _field_centroid()
	if OS.has_environment("HC_LAB_DEBUG"):
		var sample: Node = null
		var stack: Array[Node] = [background]
		while not stack.is_empty():
			var node: Node = stack.pop_back()
			if node is Sprite2D and node.has_meta("editor_runtime_instance"):
				sample = node
				break
			for child: Node in node.get_children():
				stack.append(child)
		if sample is Sprite2D:
			print(
				"LAB_DEBUG first static tex=%s size=%s filter=%d" % [
					(sample as Sprite2D).texture.resource_path.get_file(),
					str((sample as Sprite2D).texture.get_size()),
					(sample as Sprite2D).texture_filter,
				]
			)
		var wrap_sample := _find_wrappers()
		if not wrap_sample.is_empty():
			for child: Node in wrap_sample[0].get_children():
				if child is Sprite2D:
					print(
						"LAB_DEBUG first dynamic tex=%s size=%s" % [
							(child as Sprite2D).texture.resource_path.get_file(),
							str((child as Sprite2D).texture.get_size()),
						]
					)
					break
		print(
			"LAB_DEBUG anchor=%s statics=%d wrappers=%d" % [
				str(_camera_anchor),
				background.get_child_count(),
				_find_wrappers().size(),
			]
		)
	if mode == "B":
		_collapse_to_canvas()
	elif mode == "C":
		_collapse_to_composite()
	elif mode == "D":
		_rebuild_as_static(instances)
	elif mode == "E":
		_compile_wall_e()


const ATLAS_WIDTH := 2048
const CHUNK_SIZE := 1024


## MODE E: production-target structure preview (WALL-P1R Phase 2+4 shape).
## 1. Wall shadows bake into painter-run static chunk canvases (order-true).
## 2. Per (asset, part) base+front composites are built in TEXTURE space and
##    packed into ONE shared atlas; every wrapper keeps exactly one sprite
##    with an atlas region plus the instance rotation/scale. No per-instance
##    ImageTexture, no runtime baking. Y-sort wrappers are preserved.
func _compile_wall_e() -> void:
	_bake_shadow_runs()
	_compile_dynamic_atlas()


func _is_wall_shadow(node: Node) -> bool:
	return (
		node is Sprite2D
		and node.has_meta("editor_runtime_instance")
		and bool(node.get_meta("editor_runtime_wall_asset", false))
		and int(node.get_meta("editor_runtime_image_pass", -1)) == 0
	)


func _bake_shadow_runs() -> void:
	# Runs are CONSECUTIVE bakeable shadow children only; a fallback shadow
	# (rotated/scaled) breaks the run so painter order and alpha-over order
	# stay exactly as authored.
	var children := background.get_children()
	var runs: Array = []
	var current: Array = []
	var current_start := -1
	for index: int in children.size():
		var child: Node = children[index]
		var plan := {}
		if _is_wall_shadow(child):
			plan = _shadow_bake_plan(child)
		if not plan.is_empty():
			if current.is_empty():
				current_start = index
			current.append({"sprite": child, "plan": plan})
		elif not current.is_empty():
			runs.append({"items": current, "start": current_start})
			current = []
	if not current.is_empty():
		runs.append({"items": current, "start": current_start})
	var baked := 0
	var fallback := 0
	var total_chunks := 0
	# Reverse order keeps earlier insertion indices valid.
	for run_index: int in range(runs.size() - 1, -1, -1):
		var run: Dictionary = runs[run_index]
		var items: Array = run["items"]
		var start_index := int(run["start"])
		var cells := {}
		for entry: Dictionary in items:
			var work: Image = entry["plan"]["image"]
			var world_at: Vector2 = entry["plan"]["world_origin"]
			baked += 1
			var rect := Rect2i(
				Vector2i(world_at.floor()), Vector2i(work.get_size())
			)
			for cx: int in range(
				floori(float(rect.position.x) / CHUNK_SIZE),
				floori(float(rect.end.x - 1) / CHUNK_SIZE) + 1
			):
				for cy: int in range(
					floori(float(rect.position.y) / CHUNK_SIZE),
					floori(float(rect.end.y - 1) / CHUNK_SIZE) + 1
				):
					var key := Vector2i(cx, cy)
					if not cells.has(key):
						cells[key] = []
					cells[key].append({"image": work, "at": rect.position})
		for entry: Dictionary in items:
			var node: Node = entry["sprite"]
			background.remove_child(node)
			node.free()
		var chunk_keys: Array = cells.keys()
		chunk_keys.sort_custom(
			func(a: Vector2i, b: Vector2i) -> bool:
				return a.y < b.y if a.y == b.y else a.x < b.x
		)
		total_chunks += chunk_keys.size()
		for offset: int in chunk_keys.size():
			var key: Vector2i = chunk_keys[offset]
			var chunk := Image.create(
				CHUNK_SIZE, CHUNK_SIZE, false, Image.FORMAT_RGBA8
			)
			chunk.fill(Color(0, 0, 0, 0))
			var origin := Vector2(key) * float(CHUNK_SIZE)
			for cell_entry: Dictionary in cells[key]:
				var work: Image = cell_entry["image"]
				var at: Vector2i = Vector2i(
					(Vector2(cell_entry["at"]) - origin).round()
				)
				var src := Rect2i(
					Vector2i.ZERO, Vector2i(work.get_size())
				)
				var dst := at
				if dst.x < 0:
					src.position.x -= dst.x
					src.size.x += dst.x
					dst.x = 0
				if dst.y < 0:
					src.position.y -= dst.y
					src.size.y += dst.y
					dst.y = 0
				src.size.x = mini(src.size.x, CHUNK_SIZE - dst.x)
				src.size.y = mini(src.size.y, CHUNK_SIZE - dst.y)
				if src.size.x <= 0 or src.size.y <= 0:
					continue
				chunk.blend_rect(work, src, dst)
			var sprite := Sprite2D.new()
			sprite.name = "WallShadowChunk_%d_%d" % [key.x, key.y]
			sprite.texture = ImageTexture.create_from_image(chunk)
			sprite.centered = false
			sprite.position = origin
			sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			sprite.set_meta("wall_static_chunk", true)
			background.add_child(sprite)
			background.move_child(sprite, start_index + offset)
	for child: Node in background.get_children():
		if _is_wall_shadow(child):
			fallback += 1
	print(
		"LAB_MODE_E_SHADOWS baked=%d fallback=%d chunks=%d" % [
			baked, fallback, total_chunks,
		]
	)


func _shadow_bake_plan(sprite: Sprite2D) -> Dictionary:
	var rotation_deg := rad_to_deg(sprite.rotation)
	var quantized := wrapf(rotation_deg, 0.0, 360.0)
	var scaled := sprite.scale != Vector2.ONE
	# Conservative bake contract: only axis-aligned, unscaled shadows are
	# baked in the lab. CPU resize/rotate cannot bit-match the GPU's NEAREST
	# sampling phases for transformed sprites, and the visual oracle demands
	# exactness. Transformed shadows stay as individual sprites (rare in
	# production); Phase 2 owns the error-budget decision for them.
	if scaled or quantized != 0.0:
		return {}
	var image: Image = sprite.texture.get_image()
	if image.is_compressed():
		image.decompress()
	var origin := sprite.position + sprite.offset
	return {"image": image, "world_origin": origin}


func _composite_key(sprites: Array[Sprite2D]) -> String:
	var parts: PackedStringArray = []
	for sprite: Sprite2D in sprites:
		parts.append("%s|%s|%s" % [
			str(sprite.texture.resource_path), str(sprite.offset),
			str(Vector2(sprite.texture.get_size())),
		])
	return "|".join(parts)


func _compile_dynamic_atlas() -> void:
	var wrappers := _find_wrappers()
	var groups := {}  # key -> {"sprites": [...], "image": Image, "min": Vector2}
	for wrapper: Node2D in wrappers:
		var sprites := _wrapper_wall_sprites(wrapper)
		if sprites.size() < 2:
			continue
		var key := _composite_key(sprites)
		if not groups.has(key):
			groups[key] = _build_part_composite(sprites)
	var entries: Array = groups.keys()
	entries.sort()
	var regions := _pack_atlas(entries, groups)
	var atlas: Texture2D = groups["__atlas_texture__"]
	var replaced := 0
	for wrapper: Node2D in wrappers:
		var sprites := _wrapper_wall_sprites(wrapper)
		if sprites.size() < 2:
			continue
		var key := _composite_key(sprites)
		var plan: Dictionary = groups[key]
		var sprite := Sprite2D.new()
		sprite.name = "WallAtlasPart"
		sprite.texture = atlas
		sprite.region_enabled = true
		sprite.region_rect = regions[key]
		sprite.centered = false
		sprite.position = sprites[0].position
		sprite.offset = plan["min"]
		sprite.rotation = sprites[0].rotation
		sprite.scale = sprites[0].scale
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.set_meta("editor_runtime_wall_composite", true)
		for old: Sprite2D in sprites:
			wrapper.remove_child(old)
			old.free()
		wrapper.add_child(sprite)
		wrapper.move_child(sprite, 0)
		replaced += 1
	print(
		"LAB_MODE_E_ATLAS unique_composites=%d replaced_wrappers=%d" % [
			entries.size(), replaced,
		]
	)


func _wrapper_wall_sprites(wrapper: Node2D) -> Array[Sprite2D]:
	var sprites: Array[Sprite2D] = []
	for child: Node in wrapper.get_children():
		if child is Sprite2D and child.has_meta("editor_runtime_instance"):
			sprites.append(child)
	sprites.sort_custom(
		func(a: Sprite2D, b: Sprite2D) -> bool:
			return int(a.get_meta("editor_runtime_image_pass", 0)) < int(
				b.get_meta("editor_runtime_image_pass", 0)
			)
	)
	return sprites


## Composite in TEXTURE space: sources placed at their own offsets relative
## to the shared minimum corner. Instance rotation/scale are NOT baked, so
## identical assets share one atlas region across all instances.
func _build_part_composite(sprites: Array[Sprite2D]) -> Dictionary:
	var minimum: Vector2 = sprites[0].offset
	var maximum: Vector2 = sprites[0].offset + Vector2(
		sprites[0].texture.get_size()
	)
	for sprite: Sprite2D in sprites:
		minimum = minimum.min(sprite.offset)
		maximum = maximum.max(
			sprite.offset + Vector2(sprite.texture.get_size())
		)
	var size := (maximum - minimum).ceil()
	var composite := Image.create(
		int(size.x), int(size.y), false, Image.FORMAT_RGBA8
	)
	composite.fill(Color(0, 0, 0, 0))
	for sprite: Sprite2D in sprites:
		var image: Image = sprite.texture.get_image()
		if image.is_compressed():
			image.decompress()
		var at := Vector2i((sprite.offset - minimum).round())
		var src := Rect2i(Vector2i.ZERO, Vector2i(image.get_size()))
		if int(sprite.get_meta("editor_runtime_image_pass", 1)) == 1:
			composite.blit_rect(image, src, at)
		else:
			composite.blend_rect(image, src, at)
	return {"image": composite, "min": minimum}


func _pack_atlas(keys: Array, groups: Dictionary) -> Dictionary:
	keys.sort_custom(
		func(a: String, b: String) -> bool:
			var sa: Vector2 = Vector2(groups[a]["image"].get_size())
			var sb: Vector2 = Vector2(groups[b]["image"].get_size())
			return sa.y > sb.y if sa.y != sb.y else sa.x > sb.x
	)
	var rows: Array[Rect2i] = []
	var regions := {}
	var cursor_y := 0
	for key: String in keys:
		var image: Image = groups[key]["image"]
		var rect := Rect2i(Vector2i.ZERO, Vector2i(image.get_size()))
		var placed := false
		for row_index: int in rows.size():
			var row := rows[row_index]
			if row.position.x + row.size.x + rect.size.x <= ATLAS_WIDTH:
				rect.position = Vector2i(
					row.position.x + row.size.x, row.position.y
				)
				row.size.x += rect.size.x
				rows[row_index] = row
				placed = true
				break
		if not placed:
			rect.position = Vector2i(0, cursor_y)
			rows.append(rect)
			cursor_y += rect.size.y
		regions[key] = rect
	var atlas := Image.create(
		ATLAS_WIDTH, maxi(cursor_y, 1), false, Image.FORMAT_RGBA8
	)
	atlas.fill(Color(0, 0, 0, 0))
	for key: String in keys:
		atlas.blend_rect(
			groups[key]["image"],
			Rect2i(Vector2i.ZERO, Vector2i(groups[key]["image"].get_size())),
			regions[key].position
		)
	groups["__atlas_texture__"] = ImageTexture.create_from_image(atlas)
	return regions


func _synthetic_instances() -> Array:
	var instances: Array = []
	for tier: int in TIER_ASSETS.size():
		var placed := 0
		var asset := str(TIER_ASSETS[tier])
		var level := int(TIER_LEVELS[tier])
		for row: int in ROWS_PER_TIER:
			for slot: int in WALLS_PER_ROW:
				if placed >= walls_per_tier:
					break
				placed += 1
				var tile := Vector2i(
					2 + slot * 3 + (1 if row == 4 else 0),
					2 + tier * 16 + row * 3
				)
				var opts := {}
				var row_asset := asset
				if row == 1:
					opts["rotation_deg"] = 90.0
				elif row == 2:
					opts["scale"] = [0.85, 0.85]
				elif row == 3:
					row_asset = (
						WALL_CORNER_SE if slot % 2 == 0 else WALL_CORNER_SW
					)
					opts["asset"] = row_asset
				elif row == 4 and level == 4:
					opts["asset"] = WALL_L4_Y
					row_asset = WALL_L4_Y
				instances.append(_make_instance(row_asset, tile, tier, opts))
				if row == 4 and slot % 4 == 0:
					instances.append(_make_instance(
						DECORATION_A,
						tile + Vector2i(0, 2),
						tier,
						{"role": "decoration"}
					))
	return instances


func _make_instance(asset: String, tile: Vector2i, tier: int, opts: Dictionary) -> Dictionary:
	var actual_asset: String = opts.get("asset", asset)
	return {
		"instance_id": "lab_%s_%04d" % [actual_asset, tile.x * 131 + tile.y],
		"asset_id": actual_asset,
		"tile": [tile.x, tile.y],
		"tile_anchor": [tile.x, tile.y],
		"anchor_mode": "foot_tile",
		"position_mode": "tile_anchor",
		"footprint_tiles": [1.0, 1.0],
		"scale": opts.get("scale", [1.0, 1.0]),
		"rotation_deg": opts.get("rotation_deg", 0.0),
		"offset_px": [0.0, 0.0],
		"material_layer_order": 0.0,
		"object_role": opts.get("role", "terrain"),
		"layer": "terrain_base" if opts.get("role", "") != "decoration" else "object_base",
		"content_layer": "personal_expansion",
		"occlusion": true,
		"runtime_export": true,
		"movable": true,
		"flip_x": false,
		"flip_y": false,
		"scene_intent": "wall_perf_lab",
	}


func _collapse_to_canvas() -> void:
	# P1A preview: replace each segment's two dynamic sprites with one
	# CanvasItem replaying the exact production transforms.
	var wrappers := _find_wrappers()
	for wrapper: Node2D in wrappers:
		var sprites: Array[Sprite2D] = []
		for child: Node in wrapper.get_children():
			if child is Sprite2D and child.has_meta("editor_runtime_instance"):
				sprites.append(child)
		if sprites.size() < 2:
			continue
		var canvas := SegmentCanvas.new()
		canvas.name = "WallDynamicPartCanvas"
		canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		for sprite: Sprite2D in sprites:
			canvas.draws.append({
				"texture": sprite.texture,
				"position": sprite.position,
				"offset": sprite.offset,
				"rotation": sprite.rotation,
				"scale": sprite.scale,
			})
			wrapper.remove_child(sprite)
			sprite.free()
		canvas.set_meta(
			"physical_draw_bounds", _draw_bounds(canvas.draws)
		)
		wrapper.add_child(canvas)
		wrapper.move_child(canvas, 0)


func _draw_bounds(draws: Array[Dictionary]) -> Rect2:
	var bounds := Rect2()
	var first := true
	for entry: Dictionary in draws:
		var texture: Texture2D = entry["texture"]
		var transform := Transform2D(
			float(entry["rotation"]), entry["scale"]
		)
		var offset: Vector2 = entry["offset"]
		var size: Vector2 = texture.get_size()
		var origin: Vector2 = entry["position"] + transform * offset
		var corner: Vector2 = origin + transform * size
		var corner_a: Vector2 = (
			entry["position"] + transform * (offset + Vector2(size.x, 0.0))
		)
		var corner_b: Vector2 = (
			entry["position"] + transform * (offset + Vector2(0.0, size.y))
		)
		var rect := Rect2(origin, Vector2.ZERO)
		rect = rect.expand(corner).expand(corner_a).expand(corner_b)
		if first:
			bounds = rect
			first = false
		else:
			bounds = bounds.merge(rect)
	return bounds


class SegmentCanvas extends Node2D:
	var draws: Array[Dictionary] = []

	func _draw() -> void:
		for entry: Dictionary in draws:
			draw_set_transform(
				entry["position"], float(entry["rotation"]), entry["scale"]
			)
			draw_texture(entry["texture"], entry["offset"])


func _collapse_to_composite() -> void:
	var wrappers := _find_wrappers()
	for wrapper: Node2D in wrappers:
		var sprites: Array[Sprite2D] = []
		for child: Node in wrapper.get_children():
			if child is Sprite2D and child.has_meta("editor_runtime_instance"):
				sprites.append(child)
		if sprites.size() < 2:
			continue
		var rotatable := true
		for sprite: Sprite2D in sprites:
			if sprite.rotation != 0.0 or sprite.scale != Vector2.ONE:
				rotatable = false
				break
		if rotatable:
			_composite_segment(wrapper, sprites)
		else:
			_collapse_one_canvas(wrapper, sprites)


func _composite_segment(wrapper: Node2D, sprites: Array[Sprite2D]) -> void:
	var images: Array[Image] = []
	var positions: Array[Vector2] = []
	for sprite: Sprite2D in sprites:
		var image: Image = sprite.texture.get_image()
		if image.is_compressed():
			image.decompress()
		images.append(image)
		positions.append(sprite.position + sprite.offset)
	var minimum := positions[0]
	var maximum := positions[0] + Vector2(images[0].get_size())
	for index: int in images.size():
		minimum = minimum.min(positions[index])
		maximum = maximum.max(positions[index] + Vector2(images[index].get_size()))
	var size := (maximum - minimum).ceil()
	var composite := Image.create(
		int(size.x), int(size.y), false, Image.FORMAT_RGBA8
	)
	composite.fill(Color(0, 0, 0, 0))
	for index: int in images.size():
		var at: Vector2 = positions[index] - minimum
		if index == 0:
			composite.blit_rect(
				images[index], Rect2i(Vector2i.ZERO, images[index].get_size()),
				Vector2i(at)
			)
		else:
			composite.blend_rect(
				images[index], Rect2i(Vector2i.ZERO, images[index].get_size()),
				Vector2i(at)
			)
	var canvas := SegmentCanvas.new()
	canvas.name = "WallCompositeCanvas"
	canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	canvas.draws.append({
		"texture": ImageTexture.create_from_image(composite),
		"position": Vector2.ZERO,
		"offset": minimum,
		"rotation": 0.0,
		"scale": Vector2.ONE,
	})
	canvas.set_meta("physical_draw_bounds", _draw_bounds(canvas.draws))
	for sprite: Sprite2D in sprites:
		wrapper.remove_child(sprite)
		sprite.free()
	wrapper.add_child(canvas)
	wrapper.move_child(canvas, 0)


func _collapse_one_canvas(wrapper: Node2D, sprites: Array[Sprite2D]) -> void:
	var canvas := SegmentCanvas.new()
	canvas.name = "WallDynamicPartCanvas"
	canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for sprite: Sprite2D in sprites:
		canvas.draws.append({
			"texture": sprite.texture,
			"position": sprite.position,
			"offset": sprite.offset,
			"rotation": sprite.rotation,
			"scale": sprite.scale,
		})
		wrapper.remove_child(sprite)
		sprite.free()
	canvas.set_meta("physical_draw_bounds", _draw_bounds(canvas.draws))
	wrapper.add_child(canvas)
	wrapper.move_child(canvas, 0)


func _rebuild_as_static(instances: Array) -> void:
	# MODE D: diagnostic lower bound - identical commands, zero Y-sort.
	# Segment wrappers are siblings of the background under the lab root, so
	# freeing the background alone would leave the old dynamic field alive.
	for wrapper: Node2D in _find_wrappers():
		wrapper.free()
	background.free()
	background = WorldBackground.new()
	background.defer_initial_legacy_build_to_coordinator()
	add_child(background)
	var size := Vector2i(DESIGN_TILES, DESIGN_TILES)
	var commands := (
		MapEditorRuntimeVisualGeometryService.sorted_draw_commands(instances)
	)
	background._editor_runtime_bridge_commands = commands
	background._editor_runtime_bridge_size = size
	for index: int in commands.size():
		var command: Dictionary = commands[index]
		command["render_domain"] = (
			MapEditorRuntimeVisualGeometryService.RENDER_DOMAIN_STATIC_BACKGROUND
		)
		command["actor_sort_group"] = ""
		background._build_one_editor_runtime_instance(
			command, index, size, null, null
		)


func _find_wrappers() -> Array[Node2D]:
	# Segment wrappers are siblings of the background under the Y-sort root
	# (production _append_actor_sort_node adds them to background's parent),
	# so scan from the lab root, not from the background itself.
	var wrappers: Array[Node2D] = []
	var stack: Array[Node] = [self]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node != self and node.has_meta("editor_runtime_actor_occluder"):
			wrappers.append(node)
		for child: Node in node.get_children():
			stack.append(child)
	return wrappers


func _spawn_actors() -> void:
	var texture: Texture2D = _first_wall_texture()
	for index: int in ACTOR_COUNT:
		var actor := Sprite2D.new()
		actor.name = "LabActor_%d" % index
		actor.texture = texture
		actor.centered = true
		actor.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var tier := index % TIER_LEVELS.size()
		var base := Vector2(
			(96.0 + float(index % 12) * 192.0),
			(2.0 + float(tier) * 16.0 + 1.5) * 64.0
		)
		actor.position = base
		_actors.append(actor)
		_actor_base.append(base)
		_actor_phase.append(float(index) * 0.7)
		add_child(actor)


func _first_wall_texture() -> Texture2D:
	var stack: Array[Node] = [background]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is Sprite2D and node.has_meta("editor_runtime_instance"):
			return (node as Sprite2D).texture
		for child: Node in node.get_children():
			stack.append(child)
	return null


func _attach_camera() -> void:
	var camera := Camera2D.new()
	camera.name = "LabCamera"
	camera.position = _camera_anchor
	# Diagnostic override: park the camera away from the field to separate
	# scene-constant draw overhead from field-visible draw cost.
	var override := OS.get_environment("HC_LAB_CAMPOS")
	if not override.is_empty():
		var parts := override.split(",")
		if parts.size() == 2:
			camera.position = Vector2(float(parts[0]), float(parts[1]))
	add_child(camera)
	camera.make_current()


func _field_centroid() -> Vector2:
	# Static sprites + segment wrapper feet; canvases sit at wrapper space so
	# wrapper positions represent them too.
	var sum := Vector2.ZERO
	var count := 0
	for child: Node in background.get_children():
		if child is Sprite2D and child.has_meta("editor_runtime_instance"):
			sum += (child as Sprite2D).position
			count += 1
			if OS.has_environment("HC_LAB_DEBUG") and count <= 3:
				print("LAB_DEBUG static sample pos=%s" % str(child.position))
	for wrapper: Node2D in _find_wrappers():
		sum += wrapper.position
		count += 1
		if OS.has_environment("HC_LAB_DEBUG") and count in [201, 202, 203]:
			print("LAB_DEBUG wrapper sample pos=%s" % str(wrapper.position))
	if count == 0:
		return Vector2.ZERO
	if OS.has_environment("HC_LAB_DEBUG"):
		print(
			"LAB_DEBUG centroid sum=%s count=%d mean=%s" % [
				str(sum), count, str(sum / float(count)),
			]
		)
	return sum / float(count)


func _validate() -> void:
	var wrappers := _find_wrappers()
	var dynamic_children := 0
	var overlays := 0
	for wrapper: Node2D in wrappers:
		for child: Node in wrapper.get_children():
			if child.has_meta("static_authored_wall_bridge"):
				overlays += 1
			else:
				dynamic_children += 1
	var static_sprites := 0
	for child: Node in background.get_children():
		if child.has_meta("editor_runtime_instance"):
			static_sprites += 1
	var commands: Array = background._editor_runtime_bridge_commands
	var logical_y_sort := 0
	for command: Dictionary in commands:
		if str(command.get("render_domain", "")) == (
			MapEditorRuntimeVisualGeometryService.RENDER_DOMAIN_ACTOR_Y_SORT
		):
			logical_y_sort += 1
	print(
		"LAB_VALIDATE mode=%s logical=%d y_sort=%d wrappers=%d dynamic_children=%d overlays=%d static_sprites=%d actors=%d" % [
			mode, commands.size(), logical_y_sort, wrappers.size(),
			dynamic_children, overlays, static_sprites, _actors.size(),
		]
	)
