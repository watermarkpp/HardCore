extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Root := preload("res://tests/framework/fixtures/lease_probe_root.gd")
const Budget := preload("res://scripts/layers/runtime/execution/frame_budget.gd")
const REGISTRY := "res://assets/data/features/validation/resource_world_registry.json"
const FIRST := "hc.resource_world_probe"
const SECOND := "hc.resource_world_other"
var proof := Proof.new()
var checks := 0
var failures: Array[String] = []

func check(value: bool, label: String) -> void:
	proof.record(value, label)
	checks += 1
	if not value: failures.append(label)

func _ready() -> void:
	_run.call_deferred()

func _capture_enable(id: String, enabled: bool, box: Dictionary) -> void:
	box.success = await ContentLayers.set_feature_module_enabled_async(id, enabled)
	box.finished = true

func _wait(box: Dictionary) -> void:
	for index in range(180):
		if box.finished: return
		await get_tree().process_frame

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	PlayerState.active_profile_id = ""
	PlayerState.profession = "法师"
	PlayerState.level = 50
	PlayerState.recalculate_stats(false)
	check(ContentLayers.reload_feature_catalog(REGISTRY), "register disabled resource-backed world-ready modules before attachment")
	check(ContentLayers.has_method("set_feature_module_enabled_async"), "formal module activation has a nonempty resource preparation entry")
	if not ContentLayers.has_method("set_feature_module_enabled_async"):
		ContentLayers.reload_feature_catalog()
		_finish()
		return
	var game := Root.new()
	add_child(game)
	var deadline := Time.get_ticks_msec() + 20000
	while not game.gameplay_input_is_enabled() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(game.gameplay_input_is_enabled(), "real mapped world reaches its existing READY input boundary")
	if not game.gameplay_input_is_enabled():
		game.queue_free()
		await get_tree().process_frame
		_finish()
		return
	game.set_process(false)
	game.set_physics_process(false)
	game.player.set_physics_process(false)
	for actor: Node in get_tree().get_nodes_in_group("enemies"): actor.set_physics_process(false)
	var before := ContentLayers.feature_configuration()
	var bundle := PlayerState.feature_bundle()
	var stats := PlayerState.computed_stats.duplicate(true)
	check(not await ContentLayers.set_feature_module_enabled_async("hc.publication_probe", true), "async preparation cannot bypass startup-only activation inside a live world")
	game._acquire_gameplay_input_lock(&"resource_start_probe")
	check(not await ContentLayers.set_feature_module_enabled_async(FIRST, true), "locked input rejects activation before preparing any resource")
	game._release_gameplay_input_lock(&"resource_start_probe")
	get_tree().paused = true
	check(not await ContentLayers.set_feature_module_enabled_async(FIRST, true), "paused world rejects activation before resource preparation")
	get_tree().paused = false
	var blocked := {"finished":false, "success":true}
	_capture_enable(FIRST, true, blocked)
	check(not blocked.finished and ContentLayers._feature_publication_in_progress, "real preparation is pending before any candidate is exposed")
	check(is_same(ContentLayers.feature_configuration().catalog, before.catalog) and is_same(PlayerState.feature_bundle(), bundle) and PlayerState.computed_stats == stats, "old effective directory bundle and stats remain intact while resources prepare")
	check(not await ContentLayers.set_feature_module_enabled_async(SECOND, true) and not ContentLayers.set_feature_module_enabled(SECOND, true), "a second activation cannot supersede the in-flight candidate")
	game._acquire_gameplay_input_lock(&"resource_completion_probe")
	await _wait(blocked)
	check(blocked.finished and not blocked.success, "input becoming locked during preparation rejects final promotion")
	game._release_gameplay_input_lock(&"resource_completion_probe")
	check(is_same(PlayerState.feature_bundle(), bundle) and PlayerState.computed_stats == stats and ContentLayers.feature_configuration().enabled_modules.is_empty(), "failed ready promotion retains the entire previous publication")
	var application := {"scopes":0}
	var observe := func() -> void: application.scopes = Budget.snapshot().open_scopes
	ContentLayers.feature_catalog_changed.connect(observe)
	check(await ContentLayers.set_feature_module_enabled_async(FIRST, true), "lawful world-ready grant prepares and publishes through the real active world")
	ContentLayers.feature_catalog_changed.disconnect(observe)
	var first := ContentLayers.feature_configuration()
	var path: String = GameData.get_item_art_path("hc.item.910007", "inventoryIcon")
	check(first.resource_lease != null and first.resource_lease.resource_at(path) is Texture2D and int(PlayerState.computed_stats.accuracy) == int(stats.accuracy) + 1, "real ready texture and its +1 rule publish atomically")
	check(first.resource_lease.retain_subset(first.catalog, [FIRST, SECOND]) == null, "a retained subset cannot add a new grant even when both modules declare the same path")
	check(application.scopes > 0 and Budget.snapshot().open_scopes == 0, "module promotion is accounted without a frame scope surviving the await")
	var stale := {"finished":false, "success":true}
	_capture_enable(SECOND, true, stale)
	check(game.player.begin_combat_transition("resource_life_probe"), "existing player transition authority advances the accepted actor generation")
	check(game.player.finish_combat_transition("resource_life_probe"), "the same formal transition token closes without replacing the player")
	check(game.gameplay_input_is_enabled() and bool(PlayerState.feature_publication_context().world_ready), "old and new life boundaries can both be READY before completion")
	await _wait(stale)
	check(stale.finished and not stale.success, "prepared work from a retired actor generation cannot grant the new generation")
	check(ContentLayers.feature_configuration().enabled_modules == [FIRST] and int(PlayerState.computed_stats.accuracy) == int(stats.accuracy) + 1, "life-stale work preserves the current published grant")
	if SECOND in ContentLayers.feature_configuration().enabled_modules:
		await ContentLayers.set_feature_module_enabled_async(SECOND, false)
	var service: Node = ContentLayers._feature_resource_service
	var calls: int = service.metrics().request_calls
	check(await ContentLayers.set_feature_module_enabled_async(SECOND, true), "a fresh legal request can enable the second shared-resource source")
	var combined := ContentLayers.feature_configuration()
	check(int(PlayerState.computed_stats.accuracy) == int(stats.accuracy) + 3 and is_same(combined.resource_lease.resource_at(path), first.resource_lease.resource_at(path)) and service.metrics().request_calls == calls, "independent +1 and +2 grants share a ready texture without another physical request")
	check(ContentLayers.set_feature_module_enabled(SECOND, false), "withdrawing one source stays synchronous when another source owns the same prepared resource")
	check(ContentLayers.feature_configuration().enabled_modules == [FIRST] and int(PlayerState.computed_stats.accuracy) == int(stats.accuracy) + 1 and ContentLayers.feature_configuration().resource_lease.resource_at(path) is Texture2D, "withdrawal keeps the remaining grant and its exact ready resource closure")
	var retired := {"finished":false, "success":true}
	_capture_enable(SECOND, true, retired)
	check(not retired.finished and ContentLayers._feature_publication_in_progress, "world retirement case begins with a distinct real pending activation")
	game.queue_free()
	await _wait(retired)
	check(retired.finished and not retired.success, "world retirement cannot turn an old pending activation into a startup grant")
	await get_tree().process_frame
	check(ContentLayers.feature_configuration().enabled_modules == [FIRST], "world-stale completion preserves the prior configuration")
	check(ContentLayers.reload_feature_catalog(), "retired world restores the original empty configuration")
	first = {}
	combined = {}
	before = {}
	for index in range(180):
		if service.pending_count() == 0: break
		await get_tree().process_frame
	check(service.pending_count() == 0 and Budget.snapshot().open_scopes == 0, "all failed candidates and retired shared leases drain their owned work")
	_finish()

func _finish() -> void:
	if not proof.write_receipt("feature_resource_world_activation_test", checks, failures.size()): failures.append("receipt")
	print("FEATURE_RESOURCE_WORLD_ACTIVATION_%s checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL", checks, str(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)
