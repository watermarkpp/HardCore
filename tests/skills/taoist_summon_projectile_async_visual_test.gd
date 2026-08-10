extends Node

const SummonVisualRegistryScript := preload("res://scripts/summon_visual_registry.gd")

var _owner: PlayerCharacter


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_owner = PlayerCharacter.new()
	_owner.current_hp = 100
	SummonVisualRegistryScript.clear_cache_for_tests()

	var summon := _spawn_summon("skeleton")
	var diagnostics := SummonVisualRegistryScript.async_diagnostics()
	assert(
		diagnostics.sync_image_load_count == 0,
		"_ready/add_child must not synchronously decode raw summon atlases"
	)
	assert(
		diagnostics.async_request_count == 1,
		"summon visual request must start on the threaded path"
	)
	assert(
		diagnostics.threaded_resource_request_count == 5,
		"skeleton must request its five imported atlases through ResourceLoader"
	)
	assert(
		diagnostics.main_thread_blocking_load_count == 0,
		"cold production request must not call blocking load(path)"
	)
	assert(
		summon._animation_resources.is_empty(),
		"cold-cache visuals must not be installed synchronously"
	)

	## Existing 0.25s retry cadence: first _process schedules the poll window
	## and a second call inside the window must not re-issue the request.
	summon._process(0.0)
	assert(is_equal_approx(summon._visual_activation_retry, 0.25))
	summon._process(0.01)
	assert(
		SummonVisualRegistryScript.async_diagnostics().async_request_count == 1,
		"pending visual request must not be re-issued inside the 0.25s window"
	)

	await _wait_for_visual_ready(summon)
	diagnostics = SummonVisualRegistryScript.async_diagnostics()
	assert(
		diagnostics.sync_image_load_count == 0,
		"production summon path must never fall back to sync Image.load_from_file"
	)
	assert(not summon._animation_resources.is_empty())
	assert(summon._sprite.texture != null)
	assert(
		diagnostics.async_ready_count == 1,
		"threaded profile must be assembled and cached exactly once"
	)
	assert(
		diagnostics.last_loaded_image_count == 5,
		"all five threaded skeleton resources must be finalized"
	)
	assert(
		diagnostics.ready_count == 5,
		"all formal ResourceLoader requests must reach ready"
	)
	assert(
		diagnostics.max_resources_finalized_in_one_poll == 1,
		"one poll must finalize at most one texture"
	)
	assert(
		diagnostics.main_thread_blocking_load_count == 0,
		"threaded completion must not hide a blocking main-thread load"
	)
	_verify_sustained_frame_cost_and_foot_anchor(summon)

	## Warm cache: a second summon installs immediately with no new request and
	## no raw decode.
	var second := _spawn_summon("skeleton")
	assert(
		not second._animation_resources.is_empty(),
		"warm-cache summon must install visuals synchronously"
	)
	diagnostics = SummonVisualRegistryScript.async_diagnostics()
	assert(diagnostics.async_request_count == 1, "cache must be reused")
	assert(diagnostics.sync_image_load_count == 0, "cache hit must not decode")
	assert(diagnostics.threaded_resource_request_count == 5, "cache hit must not re-request atlases")
	assert(diagnostics.main_thread_blocking_load_count == 0, "cache hit must remain non-blocking")

	## Divine beast exercises the sixth fire atlas on the same bounded finalize
	## path. The profile becomes visible only after all six resources are ready.
	var divine_beast := _spawn_summon("divine_beast")
	assert(divine_beast._animation_resources.is_empty())
	await _wait_for_visual_ready(divine_beast)
	diagnostics = SummonVisualRegistryScript.async_diagnostics()
	assert(diagnostics.async_request_count == 2)
	assert(diagnostics.threaded_resource_request_count == 11)
	assert(diagnostics.ready_count == 11)
	assert(diagnostics.max_resources_finalized_in_one_poll == 1)
	assert(diagnostics.main_thread_blocking_load_count == 0)
	assert(divine_beast._animation_resources.has("fire"))
	_verify_divine_beast_foot_anchors(divine_beast)

	## Failure path: a finished-but-failed request becomes terminal; further
	## requests return REQUEST_FAILED without issuing new ResourceLoader jobs, so the
	## request counter stays flat while the summon lives.
	SummonVisualRegistryScript.clear_cache_for_tests()
	var failed_request := SummonVisualRegistryScript.request_profile("skeleton")
	assert(
		failed_request > SummonVisualRegistryScript.REQUEST_UNKNOWN,
		"failure fixture needs a real in-flight request"
	)
	SummonVisualRegistryScript._finish_request(
		failed_request,
		{"ok": false, "error": "test_injected_failure", "loaded_image_count": 0}
	)
	for attempt_index: int in range(12):
		assert(
			SummonVisualRegistryScript.request_profile("skeleton")
				== SummonVisualRegistryScript.REQUEST_FAILED,
			"failed profile must stay terminal and never respawn a thread"
		)
	var failure_diagnostics := SummonVisualRegistryScript.async_diagnostics()
	assert(
		failure_diagnostics.async_request_count == 1,
		"failed profile must never start additional async requests"
	)
	assert(
		failure_diagnostics.async_failure_count == 1,
		"failure must be recorded exactly once"
	)
	assert(
		failure_diagnostics.failed_profile_count == 1,
		"failed summon must be tracked as terminal"
	)
	assert(
		failure_diagnostics.pending_request_count == 0,
		"failed request must leave no pending thread"
	)
	assert(
		failure_diagnostics.async_ready_count == 0,
		"failed profile must never be cached as ready"
	)

	## Actor-level terminal state: a summon spawned after the failure keeps
	## REQUEST_FAILED and its 0.25s retry polls never start another request.
	var failed_summon := SummonActor.new()
	failed_summon.setup(
		_owner,
		"failed visual fixture",
		1,
		0,
		"taoist.summon_skeleton",
		19,
		1
	)
	add_child(failed_summon)
	failed_summon.set_process(false)
	assert(
		failed_summon._visual_request_id
			== SummonVisualRegistryScript.REQUEST_FAILED,
		"actor must adopt the terminal failure state without a new request"
	)
	for attempt_index: int in range(12):
		failed_summon._process(0.26)
	assert(
		SummonVisualRegistryScript.async_diagnostics().async_request_count == 1,
		"actor retry polls must never spawn additional threads after failure"
	)
	failed_summon.queue_free()

	_owner.free()
	print(
		"TAOIST_SUMMON_PROJECTILE_ASYNC_VISUAL_PASS: imported Texture2D resources "
		+ "use ResourceLoader threaded requests; each poll finalizes at most one; "
		+ "warm cache and terminal failure state confirmed"
	)
	get_tree().quit(0)


func _spawn_summon(summon_id: String) -> SummonActor:
	var summon := SummonActor.new()
	summon.setup(
		_owner,
		"async visual fixture",
		1,
		0,
		"taoist.summon_divine_beast" if summon_id == "divine_beast" else "taoist.summon_skeleton",
		19,
		1
	)
	add_child(summon)
	summon.set_process(false)
	return summon


func _wait_for_visual_ready(summon: SummonActor) -> void:
	for frame_index: int in range(240):
		if not summon._animation_resources.is_empty():
			return
		summon._process(0.26)
		await get_tree().process_frame
	assert(false, "summon visual never became ready")


func _verify_sustained_frame_cost_and_foot_anchor(summon: SummonActor) -> void:
	var profile: Dictionary = summon._animation_resources
	var authored_foot_anchor: Vector2i = profile.get("foot_anchor", Vector2i.ZERO)
	var legacy_ground_offset: Vector2i = profile.get(
		"actor_ground_offset",
		Vector2i.ZERO
	)
	assert(authored_foot_anchor != Vector2i.ZERO)
	assert(
		summon._sprite.position + Vector2(authored_foot_anchor) == Vector2.ZERO,
		"authored summon foot anchor must land exactly on actor gameplay origin"
	)
	assert(
		summon._sprite.position
			!= -Vector2(authored_foot_anchor + legacy_ground_offset),
		"canonical summon footpoint must not receive legacy actor offset twice"
	)

	summon.reset_performance_diagnostics_for_tests()
	for frame_index: int in range(120):
		summon._process(1.0 / 60.0)
		summon._physics_process(1.0 / 60.0)
	var performance := summon.performance_diagnostics()
	assert(
		performance.contract_id
			== "skills.summon.sustained_frame_cost.bounded.v1"
	)
	assert(
		performance.visual_foot_anchor_contract_id
			== "skills.summon.visual_foot_anchor_at_actor_origin.v1"
	)
	assert(
		int(performance.target_scan_count) <= 9,
		"two idle seconds must not scan the complete enemy group every physics frame"
	)
	assert(
		int(performance.custom_draw_request_count) == 0,
		"unchanged idle summon must not rebuild custom draw commands every frame"
	)
	assert(
		int(performance.sprite_frame_apply_count) <= 12,
		"idle atlas region must update at authored frame cadence, not every frame"
	)
	assert(not bool(performance.visual_request_active))


func _verify_divine_beast_foot_anchors(summon: SummonActor) -> void:
	var profile: Dictionary = summon._animation_resources
	var body_anchor: Vector2i = profile.get("foot_anchor", Vector2i.ZERO)
	var fire_anchor: Vector2i = profile.get("fire_foot_anchor", Vector2i.ZERO)
	assert(body_anchor != Vector2i.ZERO and fire_anchor != Vector2i.ZERO)
	assert(summon._sprite.position + Vector2(body_anchor) == Vector2.ZERO)
	assert(summon._fire_sprite.position + Vector2(fire_anchor) == Vector2.ZERO)
