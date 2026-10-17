extends RefCounted

## Main-only boundary. This does not own a new texture cache, coordinator,
## timeline or actor state. Capture results at the original operation site.
const OriginalVisual := preload("res://scripts/monster_visual.gd")
const Identity := preload("res://scripts/monster_identity.gd")
const SourceFrames := preload("res://scripts/monster_source_frames.gd")
const Ring := preload("res://scripts/monster_target_ring_geometry.gd")

func _main() -> void:
	assert(OS.get_thread_caller_id() == OS.get_main_thread_id())

func capture_catalog(monster_ids: PackedInt32Array) -> Dictionary:
	_main()
	var result := {"appearances": {}, "source_profiles": {}, "direction_offsets": {},
		"ground_contact": OriginalVisual._ground_contact_manifest().duplicate(true),
		"manual_alignment": OriginalVisual._manual_alignment_manifest().duplicate(true),
		"overhead": OriginalVisual._overhead_anchor_manifest().duplicate(true)}
	for id: int in monster_ids:
		assert(id > 0)
		result.appearances[str(id)] = Identity.appearance_profile(id).duplicate(true)
		result.source_profiles[str(id)] = SourceFrames.profile_for_id(id).duplicate(true)
		result.direction_offsets[str(id)] = Ring.direction_offsets(id).duplicate(true)
	return result

func capture_viewport(actor: Node2D) -> Dictionary:
	_main()
	var viewport := actor.get_viewport()
	return {"viewport_available": viewport != null,
		"canvas_transform": actor.get_canvas_transform(),
		"visible_rect": viewport.get_visible_rect() if viewport != null else Rect2()}

func capture_operation_result(operation: StringName, canonical_visual_service_id: int, arguments: Array, actual_result: Variant) -> Dictionary:
	_main()
	assert(canonical_visual_service_id > 0)
	return {"operation": operation, "service_id": canonical_visual_service_id,
		"arguments": arguments.duplicate(true), "result": _plain_result(actual_result)}

func _plain_result(value: Variant) -> Variant:
	if value is Texture2D:
		# Exact current Resource identity, not a filename/content hash. The
		# existing coordinator/renderer retains it according to original W/L.
		return value.get_instance_id()
	if value is Dictionary:
		var result := {}
		for key in value:
			assert(not key is Object)
			result[key] = _plain_result(value[key])
		return result
	if value is Array:
		var result := []
		for item in value: result.append(_plain_result(item))
		return result
	assert(not value is Object and not value is Callable and not value is Signal,
		"unexpected live object in numerical visual publication")
	return value

func texture_from_token(token: int) -> Texture2D:
	_main()
	assert(token != 0)
	var texture: Object = instance_from_id(token)
	assert(texture is Texture2D and texture.get_instance_id() == token,
		"Main texture identity retired before original visual application")
	return texture as Texture2D
