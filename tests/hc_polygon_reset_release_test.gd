extends Node
## Real save/load/build/validate/publish and WorldBackground collision factory.
## Publish is redirected to user://: never writes the formal tracked release.
const Fixtures := preload("res://tests/helpers/map_runtime_transaction_test_fixtures.gd")
const BuildService := preload("res://scripts/map_editor/map_editor_build_runtime_service.gd")
const LoadService := preload("res://scripts/map_editor/map_editor_load_service.gd")
const SaveService := preload("res://scripts/map_editor/map_editor_save_service.gd")
const RuntimeMap := preload("res://scripts/map_editor/map_editor_runtime_map_service.gd")
const Bridge := preload("res://scripts/layers/runtime/map_editor_runtime_bridge.gd")
const Background := preload("res://scripts/world_background.gd")
const Reset := preload("res://scripts/map_editor/polygon/poly_reset.gd")
const Geo := preload("res://scripts/map_editor/polygon/poly_geometry.gd")
const Author := preload("res://scripts/map_editor/polygon/poly_authoring.gd")
const Runtime := preload("res://scripts/map_editor/polygon/poly_runtime.gd")
const Terrain := preload("res://scripts/monster_terrain_navigation_policy.gd")
const Coord := preload("res://scripts/map_editor/map_editor_coordinate.gd")
const MAP_KEY := "hc_r3_reset_release"
const MAP_ID := 990994
const REG_PATH := "user://hc_r3_reset_release_registry.json"
const SAVE_PATH := "user://hc_r3_reset_release.editor.json"
var errors: Array[String] = []
var checks: int = 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		errors.append(message)
		push_error("HC_POLYGON_RESET_RELEASE: " + message)
func _ready() -> void:
	call_deferred("run")
func finish() -> void:
	Fixtures.reset_seams()
	Runtime.clear_loaded_cache()
	if errors.is_empty():
		print("HC_POLYGON_RESET_RELEASE_TEST_PASS checks=",checks)
	get_tree().quit(0 if errors.is_empty() else 1)

func run() -> void:
	Fixtures.reset_seams()
	var formal_registry_before: String = FileAccess.get_sha256(Bridge.RELEASE_REGISTRY_PATH)
	BuildService.test_formal_runtime_root_override = "user://hc_r3_formal/"
	Fixtures.write_registry(REG_PATH,[])
	Bridge.test_override_release_registry_path(REG_PATH)
	var document: Dictionary = Fixtures.make_document(MAP_KEY,MAP_ID,"HardCore R3 reset release")
	document.layers.collision = [
		{"collision_id":"manual_000001","shape":"rect","data":{"rect":[12,12,2,2]},
			"source":"manual","blocks_player":true,"blocks_monster":true,"content_layer":"personal_expansion"},
		{"collision_id":"manual_000002","shape":"polygon","data":{"points":[[18,18],[21,18],[20,21]]},
			"source":"manual","blocks_player":true,"blocks_monster":true,"content_layer":"personal_expansion"}]
	document.layers.collision_erase = [{"tile":[12,12],"source":"single_cell_erase"}]
	var prepared: Dictionary = Reset.plan(document,SAVE_PATH)
	check(prepared.ok,"legacy direct clean-slate plan")
	if not prepared.ok:
		finish()
		return
	var backup: Dictionary = Reset.write_backup(prepared.backup_payload,"user://hc_r3_release_backups")
	check(backup.ok,"backup before reset fixture commit")
	if not backup.ok:
		finish()
		return
	document = prepared.candidate
	document.editor_meta["collision_backup_path"] = backup.path
	var saved: Dictionary = SaveService.save_document(document,SAVE_PATH)
	check(saved.ok,"production SaveService persists clean slate: %s" % str(saved.get("errors",[])))
	if not saved.ok:
		finish()
		return
	var loaded: Dictionary = LoadService.load_document(SAVE_PATH)
	check(loaded.ok,"production LoadService reopens clean slate")
	if not loaded.ok:
		finish()
		return
	document = loaded.document
	check(Geo.enabled(document) and document.layers.collision.is_empty() and document.layers.collision_erase.is_empty(),
		"save/reload cannot resurrect old collision or erase cells")
	var approval: Dictionary = BuildService.approve_for_runtime(document)
	check(approval.ok,"actual build validation accepts zero authored obstacles: %s" % str(approval.get("errors",[])))
	if not approval.ok:
		finish()
		return
	var candidate: Dictionary = BuildService.build_candidate(document)
	check(candidate.ok,"actual Build Candidate succeeds")
	if not candidate.ok:
		finish()
		return
	check(str(candidate.candidate_path).begins_with("res://outputs/map_runtime_candidates/"),"candidate not a formal publish")
	var candidate_loaded: Dictionary = RuntimeMap.load_runtime(candidate.candidate_path)
	check(candidate_loaded.ok,"actual runtime checksum and polygon validation")
	if not candidate_loaded.ok:
		finish()
		return
	var runtime: Dictionary = candidate_loaded.runtime
	check(runtime.collision.convex_parts_ground_gu.is_empty(),"build convex parts zero")
	check(runtime.collision.authored_polygons_ground_gu.is_empty(),"build authored polygons zero")
	check(runtime.collision.blocked_tiles.is_empty(),"diagnostic cells zero, not an alternative physics source")
	check(not runtime.collision.has("manual_shapes"),"old runtime manual_shapes payload absent")
	check(not Bridge.is_formal_playable(MAP_ID),"Build does not grant playability")
	var published: Dictionary = BuildService.publish_runtime_release(candidate.candidate_path,MAP_ID,candidate.document_binding,REG_PATH)
	check(bool(published.get("success",false)),"transactional publish to scratch registry: %s" % str(published))
	if not bool(published.get("success",false)):
		finish()
		return
	var active: Dictionary = Bridge.load_map(MAP_ID)
	check(str(active.get("build_sha256",""))==str(candidate.build_sha256),"published identity resolves exact candidate")
	var terrain: Dictionary = Terrain.build_context(MAP_ID,active,Coord.GROUND_COORDINATE_CONTRACT_ID)
	check(Terrain.context_valid(terrain,MAP_ID),"actual navigation context valid after reset")
	if bool(terrain.get("valid",false)):
		check(terrain.poly_index.parts.is_empty(),"navigation obstacle set empty")
		check(not terrain.poly_index.capsule_blocked(Vector2(12,12),Vector2(22,22),0.3),"old obstacles no longer block interior travel")
		check(terrain.poly_index.point_blocked(Vector2(-1,-1)),"map outer boundary remains closed")
	var background := Background.new()
	background.defer_initial_legacy_build_to_coordinator()
	add_child(background)
	var descriptors: Array = background.build_collision_descriptors({"mapId":MAP_ID})
	var boundary_count: int = 0
	var obstacle_count: int = 0
	for descriptor: Dictionary in descriptors:
		if str(descriptor.get("kind",""))=="boundary_side":
			boundary_count += 1
		else:
			obstacle_count += 1
		var body: CollisionObject2D = background.build_one_collision(descriptor)
		check(body != null,"real collision factory accepts clean-slate descriptor")
	check(boundary_count==4 and obstacle_count==0,"real WorldBackground creates boundary only; no grid fallback")
	check(not background.is_environment_point_blocked(Coord.ground_position_gu_to_screen_position_px(Vector2(13,13),Vector2i(32,32))),
		"runtime query no longer blocks old cell")
	background.queue_free()
	await get_tree().process_frame
	# A new free contour is the ONLY obstacle in a new candidate. Building it
	# cannot retroactively mutate the active published empty release.
	var published_hash: String = Fixtures.file_sha256(BuildService.default_runtime_path(MAP_KEY))
	var new_points := PackedVector2Array([Vector2(12.137,12.241),Vector2(14.327,12.469),Vector2(13.179,14.113)])
	document.layers.collision.append(Author.entry("new_free_after_reset",new_points))
	document.editor_meta.revision = int(document.editor_meta.revision)+1
	check(BuildService.approve_for_runtime(document).ok,"new free contour validation")
	var next: Dictionary = BuildService.build_candidate(document)
	check(next.ok,"new free contour builds after clean slate")
	if next.ok:
		check(next.runtime.collision.authored_polygons_ground_gu.size()==1,"only newly drawn polygon exported")
		check(next.build_sha256!=candidate.build_sha256,"redraw creates new release identity")
		var ring: PackedVector2Array = Geo.decode(next.runtime.collision.authored_polygons_ground_gu[0].polygon_ground_gu)
		for point: Vector2 in new_points:
			check(ring.has(point),"authored off-grid point preserved exactly through build")
	check(Fixtures.file_sha256(BuildService.default_runtime_path(MAP_KEY))==published_hash,"new Build does not mutate previously published release")
	if next.ok:
		var republished: Dictionary = BuildService.publish_runtime_release(next.candidate_path,MAP_ID,next.document_binding,REG_PATH)
		check(bool(republished.get("success",false)),"publish redrawn contour to scratch only")
		if bool(republished.get("success",false)):
			var positive_background := Background.new()
			positive_background.defer_initial_legacy_build_to_coordinator()
			add_child(positive_background)
			var positive_descriptors: Array = positive_background.build_collision_descriptors({"mapId":MAP_ID})
			var positive_count: int = 0
			for descriptor: Dictionary in positive_descriptors:
				var body: CollisionObject2D = positive_background.build_one_collision(descriptor)
				if str(descriptor.get("kind","")) != "polygon_convex":
					continue
				positive_count += 1
				check(body != null,"redrawn continuous part creates physical body")
				if body == null:
					continue
				var expected_gu: PackedVector2Array = descriptor.payload.polygon
				var collision_shape: CollisionShape2D = body.get_child(0) as CollisionShape2D
				check(collision_shape != null and collision_shape.shape is ConvexPolygonShape2D,"actual convex polygon shape type")
				if collision_shape != null and collision_shape.shape is ConvexPolygonShape2D:
					var actual: PackedVector2Array = (collision_shape.shape as ConvexPolygonShape2D).points
					check(actual.size()==expected_gu.size(),"physical vertices not replaced by blocked cells")
					for point: Vector2 in expected_gu:
						var expected_world: Vector2 = Coord.ground_position_gu_to_screen_position_px(point,Vector2i(32,32))
						var minimum_error: float = INF
						for actual_point: Vector2 in actual:
							minimum_error = minf(minimum_error, (collision_shape.global_transform * actual_point).distance_to(expected_world))
						check(minimum_error < 0.001,"published GU equals physical world vertex without half/whole-cell offset")
			check(positive_count==next.runtime.collision.convex_parts_ground_gu.size(),"exact part count consumed by physical factory")
			positive_background.queue_free()
			await get_tree().process_frame
	check(FileAccess.get_sha256(Bridge.RELEASE_REGISTRY_PATH)==formal_registry_before,"tracked formal registry never changed")
	finish()
