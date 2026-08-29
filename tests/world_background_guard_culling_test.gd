extends Node

const MapEditorRuntimeBridge := preload(
	"res://scripts/layers/runtime/map_editor_runtime_bridge.gd"
)


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var camera := Camera2D.new()
	camera.name = "GuardCullingTestCamera"
	camera.position_smoothing_enabled = false
	camera.zoom = Vector2.ONE * 1.06
	add_child(camera)
	camera.make_current()

	var background := WorldBackground.new()
	add_child(background)
	background.set_zone_data(
		"比奇省",
		{"mapId": MapEditorRuntimeBridge.BICH_MAP_ID, "name": "比奇省"}
	)
	await get_tree().process_frame
	await get_tree().process_frame

	var guard := _guard_for(background)
	assert(guard != null, "formal runtime guard was not built")
	assert(
		str(guard.get_meta("editor_runtime_edge_skirt_contract_id", ""))
		== "map_runtime_nonwalkable_edge_skirt_v1",
		"guard edge-skirt contract changed"
	)
	assert(bool(guard.get_meta("editor_runtime_guard_non_walkable", false)))
	assert(guard.z_index == -30, "guard z-index changed")
	assert(guard.material is ShaderMaterial, "guard material changed")
	var guard_shader := (guard.material as ShaderMaterial).shader
	assert(guard_shader != null, "guard shader is missing")
	assert(
		not guard_shader.code.contains("sin(")
		and not guard_shader.code.contains("terrain_hash")
		and not guard_shader.code.contains("edge_mark"),
		"Bich guard must retain the simplified shader"
	)

	var initial_environment_count := background._environment_nodes.size()
	var initial_collision_count := background.source_collision_shape_count()
	assert(background.editor_runtime_chunk_texture_count() == 13)
	assert(not guard.visible, "central camera must hide the discard-only guard")

	# Move the actual Camera2D outside the authored inner boundary. The guard
	# must return as soon as any viewport corner leaves the ground diamond.
	camera.global_position = Vector2(3000.0, 0.0)
	await get_tree().process_frame
	await get_tree().process_frame
	assert(guard.visible, "edge camera must restore the guard")

	# Return to the centre and change zoom. Both transforms must be evaluated
	# from the active camera viewport, not from the player's position.
	camera.global_position = Vector2.ZERO
	camera.zoom = Vector2.ONE * 1.16
	await get_tree().process_frame
	await get_tree().process_frame
	assert(not guard.visible, "central camera must hide the guard after zoom change")

	# An unavailable active camera is an uncertain state: fail safe to visible.
	camera.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	assert(guard.visible, "missing camera must fail safe to visible")

	assert(background.editor_runtime_chunk_texture_count() == 13)
	assert(
		background._environment_nodes.size() == initial_environment_count,
		"camera changes must not rebuild environment nodes"
	)
	assert(
		background.source_collision_shape_count() == initial_collision_count,
		"camera changes must not rebuild collision"
	)
	assert(background._source_collision_nodes.is_empty())
	print(
		"WORLD_BACKGROUND_GUARD_CULLING_PASS center_hidden=true "
		+ "edge_visible=true zoom_switch=true no_camera_fail_safe=true "
		+ "chunks=13 environment_nodes=%d collisions=%d" % [
			initial_environment_count,
			initial_collision_count,
		]
	)
	get_tree().quit(0)


func _guard_for(background: WorldBackground) -> Polygon2D:
	for child: Node in background.get_children():
		if bool(child.get_meta("editor_runtime_guard_band", false)):
			return child as Polygon2D
	return null
