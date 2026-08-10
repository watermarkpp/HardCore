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
		diagnostics.threaded_resource_request_count == 1,
		"cold skeleton must start only the idle atlas request"
	)
	assert(diagnostics.max_resources_in_flight_per_profile == 1)
	assert(
		diagnostics.streaming_contract_id
			== "summon.visual.streaming.serial_idle_preview.v1"
	)
	assert(
		diagnostics.main_thread_blocking_load_count == 0,
		"cold production request must not call blocking load(path)"
	)
	assert(
		summon._animation_resources.is_empty(),
		"cold-cache visuals must not be installed synchronously"
	)
	summon.apply_stealth(60.0, "buff.taoist.mass_invisibility")
	summon._update_stealth_visual()
	assert(is_equal_approx(summon.modulate.a, 1.0))
	assert(is_equal_approx(summon._sprite.self_modulate.a, 0.60))
	var cold_shadow := summon.ground_shadow_layout_snapshot()
	assert(
		cold_shadow.contract_id
			== "skills.summon.ground_shadow.authored_body_frames.v2"
	)
	assert(not bool(cold_shadow.procedural_fallback_drawn))

	## Idle-first activation: the body becomes visible and fully opaque after
	## only one atlas is finalized, while remaining atlases continue serially.
	await _wait_for_visual_preview(summon)
	assert(
		SummonVisualRegistryScript.async_diagnostics().async_request_count == 1,
		"preview activation must not re-issue the profile request"
	)
	assert(summon._visual_preview_active)
	assert(not summon._visual_profile_complete)
	assert(summon._sprite.texture != null)
	assert(is_equal_approx(summon.modulate.a, 1.0))
	assert(is_equal_approx(summon._sprite.self_modulate.a, 0.60))
	var preview_shadow := summon.ground_shadow_layout_snapshot()
	assert(preview_shadow.ground_shadow_mode == "authored_body_frames")
	assert(bool(preview_shadow.authored_body_texture_active))
	assert(not bool(preview_shadow.procedural_fallback_drawn))
	assert(
		SummonVisualRegistryScript.request_active(summon._visual_request_id),
		"remaining atlases must continue loading after the preview appears"
	)

	await _wait_for_visual_ready(summon)
	diagnostics = SummonVisualRegistryScript.async_diagnostics()
	assert(
		diagnostics.sync_image_load_count == 0,
		"production summon path must never fall back to sync Image.load_from_file"
	)
	assert(not summon._animation_resources.is_empty())
	assert(summon._visual_profile_complete)
	assert(not summon._visual_preview_active)
	assert(summon._sprite.texture != null)
	assert(is_equal_approx(summon.modulate.a, 1.0))
	assert(is_equal_approx(summon._sprite.self_modulate.a, 0.60))
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
	assert(diagnostics.max_resources_in_flight_per_profile == 1)
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
	assert(is_equal_approx(second.modulate.a, 1.0))
	assert(is_equal_approx(second._sprite.self_modulate.a, 1.0))
	diagnostics = SummonVisualRegistryScript.async_diagnostics()
	assert(diagnostics.async_request_count == 1, "cache must be reused")
	assert(diagnostics.sync_image_load_count == 0, "cache hit must not decode")
	assert(diagnostics.threaded_resource_request_count == 5, "cache hit must not re-request atlases")
	assert(diagnostics.main_thread_blocking_load_count == 0, "cache hit must remain non-blocking")

	## Divine beast exercises the sixth fire atlas on the same bounded finalize
	## path, while its idle body preview appears after the first resource.
	var divine_beast := _spawn_summon("divine_beast")
	assert(divine_beast._animation_resources.is_empty())
	divine_beast.apply_stealth(60.0, "buff.taoist.mass_invisibility")
	divine_beast._update_stealth_visual()
	assert(is_equal_approx(divine_beast.modulate.a, 1.0))
	assert(is_equal_approx(divine_beast._sprite.self_modulate.a, 0.60))
	await _wait_for_visual_preview(divine_beast)
	assert(divine_beast._sprite.texture != null)
	assert(is_equal_approx(divine_beast.modulate.a, 1.0))
	assert(is_equal_approx(divine_beast._sprite.self_modulate.a, 0.60))
	assert(not divine_beast._visual_profile_complete)
	var beast_preview_shadow := divine_beast.ground_shadow_layout_snapshot()
	assert(beast_preview_shadow.ground_shadow_mode == "authored_body_frames")
	assert(bool(beast_preview_shadow.authored_body_texture_active))
	assert(not bool(beast_preview_shadow.procedural_fallback_drawn))
	await _wait_for_visual_ready(divine_beast)
	diagnostics = SummonVisualRegistryScript.async_diagnostics()
	assert(diagnostics.async_request_count == 2)
	assert(diagnostics.threaded_resource_request_count == 11)
	assert(diagnostics.ready_count == 11)
	assert(diagnostics.max_resources_finalized_in_one_poll == 1)
	assert(diagnostics.main_thread_blocking_load_count == 0)
	assert(divine_beast._animation_resources.has("fire"))
	assert(is_equal_approx(divine_beast.modulate.a, 1.0))
	assert(is_equal_approx(divine_beast._sprite.self_modulate.a, 0.60))
	assert(is_equal_approx(divine_beast._fire_sprite.self_modulate.a, 0.60))
	_verify_divine_beast_foot_anchors(divine_beast)
	var beast_full_shadow := divine_beast.ground_shadow_layout_snapshot()
	assert(bool(beast_full_shadow.authored_body_texture_active))
	assert(not bool(beast_full_shadow.procedural_fallback_drawn))

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
	## REQUEST_FAILED and frame polls never start another request.
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
	for frame_index: int in range(600):
		if summon._visual_profile_complete:
			return
		summon._process(1.0 / 60.0)
		await get_tree().process_frame
	assert(false, "summon visual never became ready")


func _wait_for_visual_preview(summon: SummonActor) -> void:
	for frame_index: int in range(600):
		if summon._visual_preview_active:
			return
		summon._process(1.0 / 60.0)
		await get_tree().process_frame
	assert(false, "summon idle preview never became ready")


func _verify_sustained_frame_cost_and_foot_anchor(summon: SummonActor) -> void:
	var profile: Dictionary = summon._animation_resources
	var authored_foot_anchor: Vector2i = profile.get("foot_anchor", Vector2i.ZERO)
	var authored_ground_offset: Vector2i = profile.get(
		"actor_ground_offset",
		Vector2i.ZERO
	)
	assert(authored_foot_anchor != Vector2i.ZERO)
	assert(profile.get("ground_shadow_mode", "") == "authored_body_frames")
	assert(
		summon._sprite.position
			+ Vector2(authored_foot_anchor + authored_ground_offset)
			== Vector2.ZERO,
		"authored composite ground point must land on actor gameplay origin"
	)
	var shadow_layout := summon.ground_shadow_layout_snapshot()
	assert(
		shadow_layout.contract_id
			== "skills.summon.ground_shadow.authored_body_frames.v2"
	)
	assert(shadow_layout.actor_ground_origin_local_px == Vector2.ZERO)
	assert(shadow_layout.ground_shadow_mode == "authored_body_frames")
	assert(bool(shadow_layout.authored_body_texture_active))
	assert(
		not bool(shadow_layout.procedural_fallback_drawn),
		"authored WIL body frames must never receive a second ellipse shadow"
	)
	var saved_profile := summon._animation_resources
	summon._animation_resources = {
		"ground_shadow_mode": "procedural_fallback",
	}
	assert(
		bool(summon.ground_shadow_layout_snapshot().procedural_fallback_drawn),
		"only an explicit procedural fallback profile may draw an ellipse"
	)
	summon._animation_resources = saved_profile
	_verify_level_label(summon)

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
			== "skills.summon.visual_authored_ground_point_at_actor_origin.v2"
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
	var body_ground_offset: Vector2i = profile.get(
		"actor_ground_offset", Vector2i.ZERO
	)
	var fire_anchor: Vector2i = profile.get("fire_foot_anchor", Vector2i.ZERO)
	var fire_ground_offset: Vector2i = profile.get(
		"fire_actor_ground_offset", Vector2i.ZERO
	)
	assert(body_anchor != Vector2i.ZERO and fire_anchor != Vector2i.ZERO)
	assert(
		summon._sprite.position
			+ Vector2(body_anchor + body_ground_offset) == Vector2.ZERO
	)
	assert(
		summon._fire_sprite.position
			+ Vector2(fire_anchor + fire_ground_offset) == Vector2.ZERO
	)


func _verify_level_label(summon: SummonActor) -> void:
	summon.summon_exp_level = 0
	var internal_zero := summon.level_label_layout_snapshot()
	assert(
		internal_zero.contract_id
			== "skills.summon.level_label.current_pet_level.v1"
	)
	assert(internal_zero.text == "Lv.1")
	assert(int(internal_zero.internal_pet_level) == 0)
	assert(int(internal_zero.display_level) == 1)
	var one_bounds: Rect2 = internal_zero.bounds
	assert(is_equal_approx(one_bounds.get_center().x, 0.0))
	assert(one_bounds.end.y < float(internal_zero.health_bar_y))

	var expected_levels := {
		1: 1,
		3: 3,
		6: 6,
		7: 7,
	}
	for internal_level: int in expected_levels:
		summon.summon_exp_level = internal_level
		var layout := summon.level_label_layout_snapshot()
		var display_level := int(expected_levels[internal_level])
		assert(layout.text == "Lv.%d" % display_level)
		assert(int(layout.internal_pet_level) == internal_level)
		assert(int(layout.display_level) == display_level)
		var bounds: Rect2 = layout.bounds
		assert(is_equal_approx(bounds.get_center().x, 0.0))
		assert(bounds.end.y < float(layout.health_bar_y))
