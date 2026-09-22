extends Node

## WALL-P1R C9: twelve negative-path proofs (advisor ruling).
## Every plan-corruption fixture is an INDEPENDENT copy of the committed
## valid plan with exactly ONE mutation, written under user://wall_render_c9/
## (committed plans/store are never modified; no stacked mutations).
## Each case asserts the precise fallback boundary - never just
## mode == LEGACY - and the consumer-level cases additionally assert a
## complete legacy descriptor set (zero partial optimized) and zero
## unexpected synchronous loads.

const RUNTIME_SERVICE := preload(
	"res://scripts/map_editor/map_editor_wall_render_plan_runtime_service.gd"
)
const GEOMETRY_SERVICE := preload(
	"res://scripts/map_editor/map_editor_runtime_visual_geometry_service.gd"
)
const PLAN_DIR := "res://assets/data/runtime/map_editor/wall_render_plans"
const DARK_MAP_ID := 913203
const CHIYUE_MAP_ID := 916001
const LEGACY_MAP_ID := 911002
const FIXTURE_DIR := "wall_render_c9"

var _failures: PackedStringArray = []


func _ready() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _copy_committed_plan(map_key: String, case_name: String) -> Dictionary:
	var raw := FileAccess.get_file_as_string(
		"%s/%s.wall_render_plan.json" % [PLAN_DIR, map_key]
	)
	var parsed: Variant = JSON.parse_string(raw)
	_check(parsed is Dictionary, "%s fixture base unparsable" % case_name)
	var plan: Dictionary = parsed
	DirAccess.open("user://").make_dir_recursive(FIXTURE_DIR)
	var fixture_path := "user://%s/%s.json" % [FIXTURE_DIR, case_name]
	var file := FileAccess.open(fixture_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(plan, "\t"))
	file.close()
	plan["_fixture_path"] = fixture_path
	return plan


func _write_fixture(plan: Dictionary, case_name: String) -> String:
	var fixture_path: String = plan["_fixture_path"]
	var file := FileAccess.open(fixture_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(plan, "\t"))
	file.close()
	return fixture_path


func _service_case(
	case_name: String,
	mutate: Callable,
	expected_prefix: String,
	map_key: String
) -> void:
	var plan := _copy_committed_plan(map_key, case_name)
	mutate.call(plan)
	var fixture_path := _write_fixture(plan, case_name)
	var runtime_path := (
		"res://assets/data/runtime/map_editor/%s.runtime.json" % map_key
	)
	var runtime: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string(runtime_path)
	)
	var design: Array = runtime.get("design", {}).get("design_size", [])
	var commands: Array = GEOMETRY_SERVICE.sorted_draw_commands(
		runtime.get("instances", [])
	)
	var candidate: Dictionary = RUNTIME_SERVICE.load_candidate(
		fixture_path, runtime_path, map_key,
		Vector2i(int(design[0]), int(design[1])), commands
	)
	_check(
		not bool(candidate.get("ok", true)),
		"%s must reject" % case_name
	)
	_check(
		str(candidate.get("reason", "")).begins_with(expected_prefix),
		"%s reason '%s' must hit prefix '%s'" % [
			case_name, str(candidate.get("reason", "")), expected_prefix,
		]
	)
	_check(
		candidate.get("plan", {}).is_empty(),
		"%s must not return a plan" % case_name
	)
	print("C9_CASE %s -> %s" % [case_name, str(candidate.get("reason", ""))])


func _store_name() -> String:
	# Valid 64-lowercase-hex store name that passes filename discipline but
	# whose file does not exist - hits the resource boundary, not the
	# format boundary.
	return "deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef"


# ── Service-level validator boundaries (independent single mutations) ──

func _mut_contract(plan: Dictionary) -> void:
	plan["contract_id"] = "hardcore.wall_render_plan.v0"


func _mut_runtime_sha(plan: Dictionary) -> void:
	plan["source_runtime_json_sha256"] = (
		"0000000000000000000000000000000000000000000000000000000000000000"
	)


func _mut_commands_digest(plan: Dictionary) -> void:
	plan["source_commands_sha256"] = (
		"0000000000000000000000000000000000000000000000000000000000000000"
	)


func _mut_page_path(plan: Dictionary) -> void:
	plan["atlas_pages"][0]["path"] = (
		"assets/data/runtime/map_editor/wall_render_store/%s.png" % _store_name()
	)
	plan["atlas_pages"][0]["sha256"] = _store_name()


func _mut_chunk_path(plan: Dictionary) -> void:
	plan["shadow_chunks"][0]["path"] = (
		"assets/data/runtime/map_editor/wall_render_store/%s.png" % _store_name()
	)
	plan["shadow_chunks"][0]["sha256"] = _store_name()


func _mut_mapping_index(plan: Dictionary) -> void:
	plan["atlas_entries"][0]["group_mappings"][0]["command_indices"][0] = 999999


func _mut_duplicate_group(plan: Dictionary) -> void:
	# Append a self-copy of the first mapping: the group_key now appears
	# twice while every per-command agreement stays internally consistent,
	# so the GLOBAL duplicate-group boundary is the first thing hit.
	var copy: Dictionary = (
		plan["atlas_entries"][0]["group_mappings"][0].duplicate(true)
	)
	plan["atlas_entries"][0]["group_mappings"].append(copy)


func _mut_union_break(plan: Dictionary) -> void:
	# Remove a NON-representative command so the mapping itself stays
	# structurally valid but the mapping union no longer covers the atlas
	# command set.
	var indices: Array = (
		plan["atlas_entries"][0]["group_mappings"][0]["command_indices"]
	)
	indices.remove_at(indices.size() - 1)


func _mut_compiler_version(plan: Dictionary) -> void:
	plan["compiler_version"] = 1


func _mut_map_key(plan: Dictionary) -> void:
	plan["map_key"] = "not_the_real_map"


func _run_service_cases() -> void:
	_service_case(
		"case2_contract_id", _mut_contract,
		"contract id mismatch", "mengzhong_dark_area"
	)
	_service_case(
		"case3_runtime_sha", _mut_runtime_sha,
		"runtime json sha mismatch", "mengzhong_dark_area"
	)
	_service_case(
		"case4_commands_digest", _mut_commands_digest,
		"commands digest mismatch", "mengzhong_dark_area"
	)
	# Cases 5/6: the corrupted store path is INSIDE the contract dir with a
	# valid 64-hex name equal to its sha field, so only the resource
	# boundary can reject it.
	_service_case(
		"case5_page_resource_missing", _mut_page_path,
		"page resource missing", "mengzhong_dark_area"
	)
	_service_case(
		"case6_chunk_resource_missing", _mut_chunk_path,
		"chunk resource missing", "mengzhong_dark_area"
	)
	_service_case(
		"case8_mapping_index_out_of_range", _mut_mapping_index,
		"mapping index out of range", "mengzhong_dark_area"
	)
	_service_case(
		"case9_duplicate_group", _mut_duplicate_group,
		"group mapping empty or duplicated", "mengzhong_dark_area"
	)
	_service_case(
		"case10_mapping_union_break", _mut_union_break,
		"mapping union size != atlas set", "mengzhong_dark_area"
	)
	_service_case(
		"case11_compiler_version", _mut_compiler_version,
		"compiler version mismatch", "mengzhong_dark_area"
	)
	_service_case(
		"case12_map_key", _mut_map_key,
		"map key mismatch", "chiyue_valley"
	)


# ── Consumer-level boundaries ──

func _wait_transition(game: Node) -> void:
	var deadline := Time.get_ticks_msec() + 20000
	while bool(game._map_transition_in_progress) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame


func _wait_bootstrap_idle(game: Node) -> void:
	var deadline := Time.get_ticks_msec() + 30000
	while bool(game._world_bootstrap_in_progress) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame


## Travels to a legacy map first (real transition cleans the tree), then
## re-prepares the target map on a FRESH coordinator attached to the same
## real background - the exact production prepare sequence with a
## controlled stage boundary for C9-B mutations.
func _fresh_prepare(game: Node, map_id: int) -> Array:
	# Travel away for a clean tree - but never to the map we are already
	# on (same-map travel requests are rejected by production).
	var away_id := (
		CHIYUE_MAP_ID
		if int(game.current_map_id) == LEGACY_MAP_ID
		else LEGACY_MAP_ID
	)
	await _travel(game, away_id)
	var background = game.background
	var coord = load(
		"res://scripts/world_bootstrap_coordinator.gd"
	).new()
	background.bootstrap_coordinator = coord
	var map_data: Dictionary = GameData.get_map_by_id(map_id)
	var prepared: Dictionary = background.prepare_map_build(
		map_id, coord, map_data
	)
	_check(bool(prepared.get("ok", false)), "fresh prepare ok (%d)" % map_id)
	return [background, coord]


func _descriptor_kinds(descriptors: Array) -> Dictionary:
	var kinds := {}
	for descriptor: Dictionary in descriptors:
		kinds[str(descriptor.get("kind", ""))] = true
	return kinds


func _travel(game: Node, map_id: int) -> void:
	assert(bool(game._request_map_travel(map_id)))
	game.hud.loading_transition_covered.emit({
		"contract_id": "ui.loading.transition.v1",
		"transition_id": game._active_map_transition_id,
	})
	await _wait_transition(game)
	await _wait_bootstrap_idle(game)


func _assert_no_optimized_nodes(game: Node, label: String) -> void:
	var stack: Array = [game]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		stack.append_array(node.get_children())
		if node is Sprite2D:
			_check(
				not bool(node.get_meta("editor_runtime_wall_composite", false)),
				"%s: partial optimized atlas node survived fallback" % label
			)
			_check(
				not bool(node.get_meta("wall_static_chunk", false)),
				"%s: partial optimized chunk node survived fallback" % label
			)


func _run_case1(game: Node) -> void:
	# Case 1: a map without any plan file - consumer must report
	# plan_found=false / plan_valid=false / LEGACY and still build the
	# complete legacy scene with zero synchronous loads.
	await _travel(game, LEGACY_MAP_ID)
	var stats: Dictionary = game.background.wall_render_stats()
	_check(not bool(stats["wall_render_plan_found"]), "case1 plan_found")
	_check(not bool(stats["wall_render_plan_valid"]), "case1 plan_valid")
	_check(str(stats["wall_render_mode"]) == "LEGACY", "case1 mode")
	_check(
		str(stats["wall_render_fallback_reason"]).begins_with(
			"plan file missing"
		),
		"case1 precise reason, got '%s'" % str(stats["wall_render_fallback_reason"])
	)
	_check(
		int(game.background._pending_map_descriptors.size()) > 0,
		"case1 legacy descriptors must exist"
	)
	_assert_no_optimized_nodes(game, "case1")
	_check(
		int(game._world_bootstrap_coordinator.unexpected_sync_load_count) == 0,
		"case1 zero sync loads"
	)
	print("C9_CASE case1_plan_missing -> %s" % str(stats["wall_render_fallback_reason"]))


func _run_case7(game: Node) -> void:
	# Case 7: full validation + real prefetch first, THEN swap one derived
	# Texture2D for a wrong-size one, then run the real submit selection.
	# Must fall back LEGACY with the precise size-mismatch reason and never
	# create partial optimized nodes.
	#
	# Sequence: real travel to the dark map proves the candidate validates
	# and prefetches (OPTIMIZED); a real travel away then cleans the tree;
	# the mutated-selection replay runs on a FRESH coordinator attached to
	# the same real background, so "no optimized nodes" is an unambiguous
	# assertion about THIS build only.
	await _travel(game, DARK_MAP_ID)
	await _travel(game, LEGACY_MAP_ID)
	var background = game.background
	# The game's coordinator already finished its bootstrap; run the C7
	# sequence on a FRESH coordinator instance attached to the same real
	# background (production functions, real order, controlled mutation).
	var coord = load(
		"res://scripts/world_bootstrap_coordinator.gd"
	).new()
	background.bootstrap_coordinator = coord
	# Re-run the exact production stage sequence on the same real nodes.
	# map_data mirrors game_root: the GameData record, not the runtime json.
	var map_data: Dictionary = GameData.get_map_by_id(DARK_MAP_ID)
	var prepared: Dictionary = background.prepare_map_build(
		DARK_MAP_ID, coord, map_data
	)
	_check(bool(prepared.get("ok", false)), "case7 re-prepare ok")
	var stats_before: Dictionary = background.wall_render_stats()
	_check(
		str(stats_before["wall_render_fallback_reason"]) == "",
		"case7 preflight clean before swap"
	)
	coord.advance(WorldBootstrapCoordinator.Stage.REQUEST_RESOURCES)
	coord.request_threaded_prefetch()
	coord.advance(WorldBootstrapCoordinator.Stage.WAIT_RESOURCES)
	_check(
		coord.poll_threaded_prefetch_blocking(),
		"case7 derived prefetch complete"
	)
	var plan: Dictionary = background._wall_render_candidate["plan"]
	var page_record: Dictionary = plan["atlas_pages"][0]
	var page_path := "res://" + str(page_record["path"]).lstrip("/")
	var wrong_texture := ImageTexture.create_from_image(
		Image.create(4, 4, false, Image.FORMAT_RGBA8)
	)
	_check(
		coord._prefetched_resources.has(page_path),
		"case7 page texture was prefetched"
	)
	coord._prefetched_resources[page_path] = wrong_texture
	# B4b: exact legacy authority snapshot BEFORE the selection runs.
	var legacy_before: Array = background._pending_map_descriptors.duplicate(
		true
	)
	background.submit_staged_build()
	var stats: Dictionary = background.wall_render_stats()
	_check(str(stats["wall_render_mode"]) == "LEGACY", "case7 mode")
	_check(
		str(stats["wall_render_fallback_reason"]).begins_with(
			"derived texture size mismatch"
		),
		"case7 precise reason, got '%s'" % str(stats["wall_render_fallback_reason"])
	)
	_check(
		int(stats["derived_prefetch_failure_count"]) >= 1,
		"case7 failure counted"
	)
	var kinds := _descriptor_kinds(background._pending_map_descriptors)
	_check(
		not kinds.has("wall_atlas_sprite") and not kinds.has("wall_chunk_sprite"),
		"case7 zero partial optimized descriptors"
	)
	_check(
		background._pending_map_descriptors == legacy_before,
		"case7 legacy authority preserved exactly (content + order)"
	)
	coord.advance(WorldBootstrapCoordinator.Stage.BUILD_MAP)
	await coord.process_map_queue(
		Callable(background, "build_one_map_item"),
		int(ProjectSettings.get_setting(
			"world/loading/max_items_per_frame", 64
		)),
		8.0
	)
	_assert_no_optimized_nodes(game, "case7")
	_check(
		int(coord.unexpected_sync_load_count) == 0,
		"case7 zero sync loads"
	)
	# B4c: the fallback path must survive the FULL production finish
	# (bridge + finalize), not stop after bare node construction.
	background.finish_map_build()
	_assert_no_optimized_nodes(game, "case7 finish")
	_check(
		int(coord.unexpected_sync_load_count) == 0,
		"case7 zero sync loads after finish_map_build"
	)
	print("C9_CASE case7_texture_size_swap -> %s" % str(stats["wall_render_fallback_reason"]))
	# Restore the game's own coordinator for the tree teardown.
	background.bootstrap_coordinator = game._world_bootstrap_coordinator


# ── C9-B consumer supplement ──

func _count_meta_nodes(game: Node, meta: String) -> int:
	var count := 0
	var stack: Array = [game]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		stack.append_array(node.get_children())
		if node is Sprite2D and bool(node.get_meta(meta, false)):
			count += 1
	return count


func _assert_no_legacy_residue_in_wall_wrappers(game: Node, label: String) -> void:
	var stack: Array = [game]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		stack.append_array(node.get_children())
		if (
			node is Sprite2D
			and bool(node.get_meta("editor_runtime_wall_composite", false))
		):
			for child in node.get_parent().get_children():
				if child is Sprite2D and bool(
					child.get_meta("editor_runtime_instance", false)
				):
					_check(
						false,
						"%s: legacy instance residue in wall wrapper %s" % [
							label, str(node.get_parent().name),
						]
					)
					return


## B1: SIMULATED_OPTIONAL_PREFETCH_FAILURE - the manifest entry for a real
## derived atlas page is redirected to a valid-looking but nonexistent
## store path BEFORE REQUEST_RESOURCES. The serial test load then fails
## that optional entry: no required failure, no prefetch_failure_count,
## candidate still valid, whole map falls back LEGACY on the selection
## cache miss. (Real Android threaded/PCK failures remain C11 scope.)
func _run_b1(game: Node) -> void:
	var prepared_pair: Array = await _fresh_prepare(game, DARK_MAP_ID)
	var background = prepared_pair[0]
	var coord = prepared_pair[1]
	var page_entry = null
	for path: Variant in coord.resource_manifest:
		var entry: Dictionary = coord.resource_manifest[path]
		if bool(entry.get("optional_prefetch", false)) and (
			entry.get("owners", []) as Array
		).has("wall_render_derived"):
			page_entry = entry
			coord.resource_manifest.erase(path)
			coord.resource_manifest[
				"res://assets/data/runtime/map_editor/wall_render_store/%s.png"
				% "0".repeat(64)
			] = entry
			break
	_check(page_entry != null, "B1 optional derived entry found")
	var legacy_before: Array = background._pending_map_descriptors.duplicate(
		true
	)
	coord.advance(WorldBootstrapCoordinator.Stage.REQUEST_RESOURCES)
	coord.request_threaded_prefetch()
	coord.advance(WorldBootstrapCoordinator.Stage.WAIT_RESOURCES)
	_check(coord.poll_threaded_prefetch_blocking(), "B1 poll done")
	_check(
		page_entry["status"] in ["load_failed", "request_failed"],
		"B1 optional entry status %s" % str(page_entry["status"])
	)
	_check(
		int(coord.diagnostic.get("prefetch_failure_count", 0)) == 0,
		"B1 prefetch_failure_count must stay 0"
	)
	_check(
		not coord.has_failed_required_resource(),
		"B1 required gate must not fail"
	)
	_check(
		bool(background.wall_render_stats()["wall_render_plan_valid"]),
		"B1 candidate still valid"
	)
	background.submit_staged_build()
	var stats: Dictionary = background.wall_render_stats()
	_check(str(stats["wall_render_mode"]) == "LEGACY", "B1 mode")
	_check(
		str(stats["wall_render_fallback_reason"]).begins_with(
			"derived texture not prefetched"
		),
		"B1 precise reason, got '%s'" % str(stats["wall_render_fallback_reason"])
	)
	var kinds := _descriptor_kinds(background._pending_map_descriptors)
	_check(
		not kinds.has("wall_atlas_sprite") and not kinds.has("wall_chunk_sprite"),
		"B1 zero partial optimized descriptors"
	)
	_check(
		background._pending_map_descriptors == legacy_before,
		"B1 legacy authority preserved exactly"
	)
	_check(
		int(coord.unexpected_sync_load_count) == 0,
		"B1 zero sync loads"
	)
	print(
		"C9_CASE B1_optional_prefetch_failure [SIMULATED_OPTIONAL_PREFETCH_FAILURE] -> %s"
		% str(stats["wall_render_fallback_reason"])
	)
	background.bootstrap_coordinator = game._world_bootstrap_coordinator


## B2: the mutation happens INSIDE the in-memory validated plan, so the
## size gate passes and selection truly enters
## _apply_wall_render_optimized_descriptors(); its preflight must reject
## without moving a single descriptor byte (P0-3 atomicity).
func _run_b2(game: Node) -> void:
	var prepared_pair: Array = await _fresh_prepare(game, DARK_MAP_ID)
	var background = prepared_pair[0]
	var coord = prepared_pair[1]
	coord.advance(WorldBootstrapCoordinator.Stage.REQUEST_RESOURCES)
	coord.request_threaded_prefetch()
	coord.advance(WorldBootstrapCoordinator.Stage.WAIT_RESOURCES)
	_check(
		coord.poll_threaded_prefetch_blocking(),
		"B2 derived prefetch complete"
	)
	var legacy_before: Array = background._pending_map_descriptors.duplicate(
		true
	)
	var plan: Dictionary = background._wall_render_candidate["plan"]
	plan["atlas_entries"][0]["group_mappings"][0][
		"representative_command_index"
	] = 999999
	background.submit_staged_build()
	var stats: Dictionary = background.wall_render_stats()
	_check(str(stats["wall_render_mode"]) == "LEGACY", "B2 mode")
	_check(
		str(stats["wall_render_fallback_reason"]).begins_with(
			"atlas representative descriptor missing: 999999"
		),
		"B2 precise reason, got '%s'" % str(stats["wall_render_fallback_reason"])
	)
	_check(
		background._pending_map_descriptors == legacy_before,
		"B2 _pending_map_descriptors byte-identical after transform failure"
	)
	var kinds := _descriptor_kinds(background._pending_map_descriptors)
	_check(
		not kinds.has("wall_atlas_sprite") and not kinds.has("wall_chunk_sprite"),
		"B2 zero partial optimized descriptors"
	)
	_check(
		int(coord.unexpected_sync_load_count) == 0,
		"B2 zero sync loads"
	)
	print(
		"C9_CASE B2_transform_atomicity -> %s"
		% str(stats["wall_render_fallback_reason"])
	)
	background.bootstrap_coordinator = game._world_bootstrap_coordinator


## B3: full-path mode isolation on a FRESH main.tscn instance - five real
## travels prove candidate/mode/roots/nodes/stats never leak across maps
## and that clear_environment resets the five wall-render fields.
func _run_b3() -> void:
	PlayerState.reset_progress()
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	var deadline := Time.get_ticks_msec() + 20000
	while not bool(game.gameplay_input_is_enabled()) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	await _wait_bootstrap_idle(game)
	game._monster_prefetch_enabled = false

	await _travel(game, LEGACY_MAP_ID)
	var stats: Dictionary = game.background.wall_render_stats()
	_check(not bool(stats["wall_render_plan_found"]), "B3.1 plan_found")
	_check(not bool(stats["wall_render_plan_valid"]), "B3.1 plan_valid")
	_check(str(stats["wall_render_mode"]) == "LEGACY", "B3.1 mode")
	_check(
		str(stats["wall_render_fallback_reason"]).begins_with(
			"plan file missing"
		),
		"B3.1 reason"
	)
	_check(
		_count_meta_nodes(game, "editor_runtime_wall_composite") == 0
		and _count_meta_nodes(game, "wall_static_chunk") == 0,
		"B3.1 zero P1R nodes"
	)
	_check(
		int(stats["dynamic_group_count"]) == 0
		and int(stats["static_chunk_count"]) == 0,
		"B3.1 no plan stats"
	)
	_check(
		int(game._world_bootstrap_coordinator.unexpected_sync_load_count) == 0,
		"B3.1 zero sync loads"
	)

	await _travel(game, DARK_MAP_ID)
	stats = game.background.wall_render_stats()
	_check(bool(stats["wall_render_plan_valid"]), "B3.2 plan_valid")
	_check(str(stats["wall_render_mode"]) == "OPTIMIZED", "B3.2 mode")
	_check(
		_count_meta_nodes(game, "editor_runtime_wall_composite") == 325,
		"B3.2 325 composites"
	)
	_check(_count_meta_nodes(game, "wall_static_chunk") == 35, "B3.2 35 chunks")
	_assert_no_legacy_residue_in_wall_wrappers(game, "B3.2")
	_check(
		int(game._world_bootstrap_coordinator.unexpected_sync_load_count) == 0,
		"B3.2 zero sync loads"
	)

	await _travel(game, LEGACY_MAP_ID)
	stats = game.background.wall_render_stats()
	_check(str(stats["wall_render_mode"]) == "LEGACY", "B3.3 mode")
	_check(
		str(stats["wall_render_fallback_reason"]).begins_with(
			"plan file missing"
		),
		"B3.3 reason"
	)
	_check(
		int(stats["dynamic_group_count"]) == 0
		and int(stats["static_chunk_count"]) == 0,
		"B3.3 dark stats must not leak"
	)
	_check(
		_count_meta_nodes(game, "editor_runtime_wall_composite") == 0
		and _count_meta_nodes(game, "wall_static_chunk") == 0,
		"B3.3 zero P1R nodes after dark"
	)
	_check(
		int(game._world_bootstrap_coordinator.unexpected_sync_load_count) == 0,
		"B3.3 zero sync loads"
	)

	await _travel(game, CHIYUE_MAP_ID)
	stats = game.background.wall_render_stats()
	_check(bool(stats["wall_render_plan_valid"]), "B3.4 plan_valid")
	_check(str(stats["wall_render_mode"]) == "OPTIMIZED", "B3.4 mode")
	_check(
		_count_meta_nodes(game, "editor_runtime_wall_composite") == 511,
		"B3.4 511 composites"
	)
	_check(_count_meta_nodes(game, "wall_static_chunk") == 0, "B3.4 0 chunks")
	_assert_no_legacy_residue_in_wall_wrappers(game, "B3.4")
	_check(
		int(game._world_bootstrap_coordinator.unexpected_sync_load_count) == 0,
		"B3.4 zero sync loads"
	)

	await _travel(game, LEGACY_MAP_ID)
	stats = game.background.wall_render_stats()
	_check(str(stats["wall_render_mode"]) == "LEGACY", "B3.5 mode")
	_check(
		_count_meta_nodes(game, "editor_runtime_wall_composite") == 0
		and _count_meta_nodes(game, "wall_static_chunk") == 0,
		"B3.5 zero P1R nodes after chiyue"
	)
	_check(
		int(stats["dynamic_group_count"]) == 0
		and int(stats["static_chunk_count"]) == 0,
		"B3.5 chiyue stats must not leak"
	)
	_check(
		int(game._world_bootstrap_coordinator.unexpected_sync_load_count) == 0,
		"B3.5 zero sync loads"
	)
	print("C9_CASE B3_full_path_mode_isolation legacy->dark->legacy->chiyue->legacy OK")
	game.queue_free()
	await get_tree().process_frame


func _run() -> void:
	_run_service_cases()
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	var deadline := Time.get_ticks_msec() + 20000
	while not bool(game.gameplay_input_is_enabled()) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_check(bool(game.gameplay_input_is_enabled()), "initial world ready")
	await _wait_bootstrap_idle(game)
	game._monster_prefetch_enabled = false
	PlayerState.test_mode = false
	await _run_case1(game)
	await _run_case7(game)
	await _run_b1(game)
	await _run_b2(game)
	game.queue_free()
	await get_tree().process_frame
	await _run_b3()
	if _failures.is_empty():
		print("WALL_RENDER_C9_PASS validator_cases=12 consumer_supplement=3")
		get_tree().quit(0)
	else:
		for failure: String in _failures:
			print("C9_FAIL ", failure)
		print("C9_NEGATIVE_PATHS_RESULT FAIL")
		get_tree().quit(1)
