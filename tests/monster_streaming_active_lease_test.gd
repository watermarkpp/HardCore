extends Node

## Monster streaming residency contract:
## R(register) -> W(explicit demand) -> L(successful apply) -> R(release),
## with generation fencing and exact decoded RGBA8 cache accounting.

const Fixtures := preload(
	"res://tests/helpers/monster_streaming_test_fixtures.gd"
)
const CoordinatorScript := preload(
	"res://scripts/monster_visual_streaming_coordinator.gd"
)
const RELOAD_PREFETCH_IDS := [18, 19, 21, 24, 26]
## These profiles are rejected by the decoded-RGBA8 pin budget. Requesting
## them in this order reproduces the production 2-loaded + 1-queued HOL shape.
const RELOAD_DEMAND_IDS := [24, 26, 18]

var _coordinator
var _player: PlayerCharacter
var _enemies: Array[EnemyActor] = []
var _owners: Array[Node] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	_coordinator = CoordinatorScript.new()
	MonsterVisual.set_streaming_coordinator(_coordinator)
	MonsterVisual.reset_client_resource_cache()
	_player = Fixtures.make_player(self)
	MonsterVisual.set_synchronous_loading_for_tests(true)

	# The real MonsterVisual enters R, explicitly requests W, then obtains L only
	# after _activate_resources has applied the idle frame.
	var live_enemy := Fixtures.make_enemy(
		self,
		_player,
		Fixtures.catalog_ids()[0],
		1
	)
	_enemies.append(live_enemy)
	await get_tree().process_frame
	var live_visual: MonsterVisual = live_enemy.visual
	var live_mapping := live_visual._client_mapping_for(live_enemy.monster_data)
	var live_key := live_visual._client_resource_cache_key(live_mapping)
	assert(_coordinator.visual_resource_state(live_visual) == "leased")
	assert(_coordinator.waiting_visual_count_for_resource(live_key) == 0)
	assert(_coordinator.active_lease_count_for_resource(live_key) == 1)
	var apply_count := int(_coordinator.monster_streaming_diagnostics().resource_apply_count)
	assert(_coordinator.notify_visual_applied(live_visual, live_key, 0))
	assert(int(_coordinator.monster_streaming_diagnostics().resource_apply_count) == apply_count, "duplicate apply must not duplicate a lease")

	# R does not become W merely because a far-away visual is registered.
	_player.global_position = Vector2(50000, 50000)
	var far_enemy := Fixtures.make_enemy(
		self,
		_player,
		Fixtures.catalog_ids()[0],
		2,
		1,
		Vector2.ZERO
	)
	_enemies.append(far_enemy)
	await get_tree().process_frame
	assert(_coordinator.visual_resource_state(far_enemy.visual) == "registered")
	assert(_coordinator.waiting_visual_count() == 0, "far registered visual must not be a permanent waiter")

	# A profile larger than the hard budget is retained while W protects it even
	# when map pin admission is rejected; no demanded profile may be immediately
	# evicted before its first apply.
	var large_key := "active_lease_large"
	var waiter := _new_owner(large_key, 10)
	assert(_coordinator.declare_visual_need(waiter.get_instance_id(), large_key, 0))
	var large_profile := _large_profile()
	var large_bytes: int = int(_coordinator._decoded_rgba8_profile_bytes(large_profile))
	assert(large_bytes > CoordinatorScript.CLIENT_RESOURCE_CACHE_BUDGET_DECODED_RGBA8_BYTES)
	assert(not _coordinator._try_pin_map_profile(large_key, large_bytes))
	assert(int(_coordinator.monster_streaming_diagnostics().pin_rejection_count) == 1)
	_coordinator._dispatch_loaded_job(
		large_key,
		{
			"state": "loaded",
			"resources": large_profile,
			"map_generation": 0,
			"request_sequence": 1,
		},
		false
	)
	var protected_diag: Dictionary = _coordinator.monster_streaming_diagnostics()
	assert(_coordinator.cached_client_profile_decoded_rgba8_bytes() == large_bytes)
	assert(_coordinator.waiting_visual_count_for_resource(large_key) == 1)
	assert(int(protected_diag.immediate_eviction_count) == 0)
	assert(int(protected_diag.protected_overbudget_bytes) == large_bytes - CoordinatorScript.CLIENT_RESOURCE_CACHE_BUDGET_DECODED_RGBA8_BYTES)

	# W -> L is per visual and idempotent; two visuals share one profile but own
	# independent leases.
	assert(_coordinator.notify_visual_applied(waiter, large_key, 0))
	var resident_idle: Texture2D = large_profile["idle"]
	_coordinator.retain_client_resource_profile(large_key, _small_profile())
	var late_diag: Dictionary = _coordinator.monster_streaming_diagnostics()
	var leased_resident: Dictionary = _coordinator.client_resources(large_key)
	assert(int(late_diag.late_completion_resident_skip_count) == 1)
	assert(leased_resident["idle"] == resident_idle, "late completion must not replace a leased resident")
	assert(_coordinator.cached_client_profile_decoded_rgba8_bytes() == large_bytes)
	var second := _new_owner(large_key, 11)
	assert(_coordinator.declare_visual_need(second.get_instance_id(), large_key, 0))
	assert(_coordinator.notify_visual_applied(second, large_key, 0))
	assert(_coordinator.notify_visual_applied(second, large_key, 0))
	assert(_coordinator.active_lease_count_for_resource(large_key) == 2)
	assert(_coordinator.leased_profile_count() == 1)
	assert(_coordinator.leased_visual_count() == 2)
	_coordinator.release_visual_resource(waiter, large_key)
	assert(_coordinator.active_lease_count_for_resource(large_key) == 1)
	assert(_coordinator.cached_client_profile_count() == 1, "one remaining lease must protect the profile")
	_coordinator.unregister_visual(second.get_instance_id())
	assert(_coordinator.active_lease_count_for_resource(large_key) == 0)
	assert(_coordinator.cached_client_profile_count() == 0, "last lease release must immediately run the LRU boundary")
	assert(_coordinator.cached_client_profile_decoded_rgba8_bytes() <= CoordinatorScript.CLIENT_RESOURCE_CACHE_BUDGET_DECODED_RGBA8_BYTES)

	# A waiter that is cancelled before apply may be evicted, and that event is
	# diagnosed separately from the forbidden immediate demanded eviction.
	var cancelled_key := "cancelled_waiter_large"
	var cancelled := _new_owner(cancelled_key, 12)
	assert(_coordinator.declare_visual_need(cancelled.get_instance_id(), cancelled_key, 0))
	_coordinator._dispatch_loaded_job(
		cancelled_key,
		{
			"state": "loaded",
			"resources": large_profile,
			"map_generation": 0,
			"request_sequence": 2,
		},
		false
	)
	_coordinator.release_visual_resource(cancelled, cancelled_key)
	assert(_coordinator.cached_client_profile_count() == 0)
	assert(int(_coordinator.monster_streaming_diagnostics().evicted_before_first_apply_count) >= 1)
	_coordinator.unregister_visual(cancelled.get_instance_id())

	# Generation fence clears old W/L state and rejects stale notifications; a
	# same-key new-generation visual can still acquire the published resource.
	_coordinator.set_generation_for_tests(1)
	var stale := _new_owner("generation_shared", 20)
	assert(_coordinator.declare_visual_need(stale.get_instance_id(), "generation_shared", 1))
	_coordinator.set_generation_for_tests(2)
	assert(_coordinator.visual_resource_state(stale) == "unregistered")
	assert(_coordinator.waiting_visual_count_for_resource("generation_shared") == 0)
	assert(not _coordinator.notify_visual_applied(stale, "generation_shared", 1))
	var current := _new_owner("generation_shared", 21)
	assert(_coordinator.declare_visual_need(current.get_instance_id(), "generation_shared", 2))
	_coordinator.retain_client_resource_profile("generation_shared", _small_profile())
	assert(_coordinator.notify_visual_applied(current, "generation_shared", 2))
	assert(_coordinator.active_lease_count_for_resource("generation_shared") == 1)
	assert(not _coordinator.notify_visual_applied(stale, "generation_shared", 2))

	# A cached same-key request is a hit, not another five-atlas load.
	var same_key_owner := _new_owner(live_key, 22)
	_coordinator.retain_client_resource_profile(live_key, _small_profile())
	var before_requests: int = _coordinator.threaded_texture_request_count()
	var cached_hit: Dictionary = _coordinator.request_visual_resources(
		same_key_owner,
		live_mapping,
		live_enemy.monster_id,
		true
	)
	assert(not cached_hit.is_empty(), "cached same-key request must return its profile")
	assert(_coordinator.threaded_texture_request_count() == before_requests)

	_cleanup()
	await get_tree().process_frame
	await _verify_runtime_reload_lane()
	await _verify_bootstrap_handoff_hold()
	print(
		"MONSTER_STREAMING_ACTIVE_LEASE_PASS "
		+ "RGBA8/W-L/generation-safe/runtime-reload-lane"
	)
	get_tree().quit(0)


func _new_owner(resource_key: String, serial: int) -> Node:
	var owner := Node.new()
	add_child(owner)
	_owners.append(owner)
	_coordinator.register_visual(
		owner,
		serial,
		1,
		_coordinator.current_world_generation(),
		resource_key,
		{},
		serial
	)
	return owner


func _large_profile() -> Dictionary:
	var image := Image.create(2048, 2048, false, Image.FORMAT_RGBA8)
	var texture := ImageTexture.create_from_image(image)
	return {
		"idle": texture,
		"walk": texture,
		"attack": texture,
		"hit": texture,
		"death": texture,
	}


func _small_profile() -> Dictionary:
	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	var texture := ImageTexture.create_from_image(image)
	return {
		"idle": texture,
		"walk": texture,
		"attack": texture,
		"hit": texture,
		"death": texture,
	}


func _verify_runtime_reload_lane() -> void:
	# Production order: GameRoot finishes map prefetch before spawning visuals.
	_coordinator = CoordinatorScript.new()
	MonsterVisual.set_streaming_coordinator(_coordinator)
	MonsterVisual.reset_client_resource_cache()
	MonsterVisual.set_synchronous_loading_for_tests(false)
	var helper := MonsterVisual.new()
	var mappings := {}
	var keys := {}
	for monster_id: int in RELOAD_PREFETCH_IDS:
		var mapping := helper._client_mapping_for(
			GameData.get_monster_by_id(monster_id)
		)
		assert(
			not mapping.is_empty(),
			"missing formal mapping for monster_id=%d" % monster_id
		)
		mappings[monster_id] = mapping
		keys[monster_id] = helper._client_resource_cache_key(mapping)
	helper.free()

	var prefetch: Dictionary = _coordinator.begin_map_prefetch(
		RELOAD_PREFETCH_IDS
	)
	var prefetch_deadline := Time.get_ticks_msec() + 30000
	while (
		not bool(prefetch.get("complete", false))
		and Time.get_ticks_msec() < prefetch_deadline
	):
		_coordinator.poll_once(Engine.get_process_frames())
		await get_tree().process_frame
		prefetch = _coordinator.map_prefetch_status()
	assert(
		bool(prefetch.get("complete", false)),
		"initial map prefetch timed out: %s" % prefetch
	)
	assert(
		int(prefetch.get("failed", -1)) == 0,
		"initial map prefetch failed: %s" % prefetch
	)
	assert(
		int(prefetch.get("pinned", -1)) == 2,
		"RGBA8 pin priority drifted: %s" % prefetch
	)
	assert(
		int(prefetch.get("streamed", -1)) == 3,
		"test requires three completed/evicted profiles: %s" % prefetch
	)
	for monster_id: int in RELOAD_DEMAND_IDS:
		assert(
			_coordinator.client_resources(str(keys[monster_id])).is_empty(),
			"rejected profile %d unexpectedly remained resident" % monster_id
		)

	# Spawn-time W demand re-requests the completed map keys out of prefetch
	# order. These jobs belong to runtime delivery and must not reopen the
	# already-complete map-prefetch lane.
	var reload_owners: Array[Node] = []
	var completed_before: int = (
		_coordinator._map_prefetch_completed_keys.size()
	)
	for monster_id: int in RELOAD_DEMAND_IDS:
		var owner := Node.new()
		add_child(owner)
		reload_owners.append(owner)
		var mapping: Dictionary = mappings[monster_id]
		var cache_key := str(keys[monster_id])
		_coordinator.register_visual(
			owner,
			monster_id,
			910001,
			_coordinator.current_world_generation(),
			cache_key,
			{},
			monster_id
		)
		assert(
			_coordinator.request_visual_resources(
				owner, mapping, monster_id, true
			).is_empty(),
			"evicted profile %d unexpectedly resolved synchronously" % monster_id
		)
		assert(
			str(
				_coordinator._threaded_profile_requests[cache_key].get(
					"lane", ""
				)
			) == CoordinatorScript.JOB_LANE_RUNTIME_DEMAND,
			"runtime reload %d entered the map-prefetch lane" % monster_id
		)
	assert(
		_coordinator._map_prefetch_completed_keys.size() == completed_before,
		"runtime reload reopened completed map-prefetch keys"
	)
	var queued_shape: Dictionary = (
		_coordinator.monster_streaming_diagnostics()
	)
	assert(
		int(queued_shape.get("loading_request_count", -1)) == 2,
		"expected two loading slots: %s" % queued_shape
	)
	assert(
		int(queued_shape.get("queued_request_count", -1)) == 1,
		"expected one queued reload: %s" % queued_shape
	)

	var reload_deadline := Time.get_ticks_msec() + 30000
	while (
		_coordinator.pending_request_count() > 0
		and Time.get_ticks_msec() < reload_deadline
	):
		_coordinator.poll_once(Engine.get_process_frames())
		await get_tree().process_frame
	var final_diag: Dictionary = _coordinator.monster_streaming_diagnostics()
	assert(
		_coordinator.pending_request_count() == 0,
		"runtime reload lane deadlocked: %s" % final_diag
	)
	assert(
		int(final_diag.get("queued_request_count", -1)) == 0
		and int(final_diag.get("loading_request_count", -1)) == 0
		and int(final_diag.get("loaded_request_count", -1)) == 0,
		"reload jobs survived completion: %s" % final_diag
	)
	assert(
		int(final_diag.get("failed_request_count", -1)) == 0,
		"runtime reload failed: %s" % final_diag
	)
	assert(
		int(final_diag.get("same_key_reload_count", -1))
			== RELOAD_DEMAND_IDS.size()
	)
	for monster_id: int in RELOAD_DEMAND_IDS:
		assert(
			not _coordinator.client_resources(str(keys[monster_id])).is_empty(),
			"runtime-demand profile %d was never published" % monster_id
		)
	for owner: Node in reload_owners:
		if is_instance_valid(owner):
			_coordinator.release_visual_resource(owner)
			_coordinator.unregister_visual(owner.get_instance_id())
			owner.queue_free()
	await get_tree().process_frame
	MonsterVisual.reset_client_resource_cache()


func _verify_bootstrap_handoff_hold() -> void:
	# A bootstrap handoff is intentionally independent of the normal pin budget:
	# several low-budget profiles must survive until their first real visual
	# lease, without being re-requested at spawn time.
	_coordinator = CoordinatorScript.new()
	MonsterVisual.set_streaming_coordinator(_coordinator)
	var helper := MonsterVisual.new()
	var hold_keys: Array[String] = []
	for monster_id: int in RELOAD_PREFETCH_IDS:
		var mapping := helper._client_mapping_for(
			GameData.get_monster_by_id(monster_id)
		)
		hold_keys.append(helper._client_resource_cache_key(mapping))
	helper.free()
	var prefetch: Dictionary = _coordinator.begin_map_prefetch(
		RELOAD_PREFETCH_IDS,
		true
	)
	var deadline := Time.get_ticks_msec() + 30000
	while (
		not bool(prefetch.get("complete", false))
		and Time.get_ticks_msec() < deadline
	):
		_coordinator.poll_once(Engine.get_process_frames())
		await get_tree().process_frame
		prefetch = _coordinator.map_prefetch_status()
	assert(bool(prefetch.get("complete", false)), "handoff prefetch timed out")
	assert(int(prefetch.get("failed", -1)) == 0)
	assert(
		int(_coordinator.bootstrap_handoff_status().get("hold_count", -1))
			== hold_keys.size()
	)
	var held_diag: Dictionary = _coordinator.monster_streaming_diagnostics()
	assert(
		_coordinator.cached_client_profile_count() == hold_keys.size(),
		"handoff hold must prevent low-budget prefetch eviction"
	)
	assert(
		int(held_diag.get("bootstrap_handoff_hold_count", -1))
			== hold_keys.size()
	)
	assert(
		int(held_diag.get("same_key_reload_count", -1)) == 0,
		"handoff admission must not trigger same-key reload"
	)
	var handoff_owner := _new_owner(hold_keys[0], 50)
	assert(_coordinator.declare_visual_need(
		handoff_owner.get_instance_id(), hold_keys[0], 1
	))
	assert(_coordinator.notify_visual_applied(
		handoff_owner, hold_keys[0], 1
	))
	assert(
		int(_coordinator.bootstrap_handoff_status().get("hold_count", -1))
			== hold_keys.size() - 1,
		"first visual lease must release only its profile hold"
	)
	assert(
		_coordinator.active_lease_count_for_resource(hold_keys[0]) == 1
	)
	_coordinator.set_generation_for_tests(2)
	assert(
		int(_coordinator.bootstrap_handoff_status().get("hold_count", -1)) == 0,
		"generation fence must clear bootstrap handoff holds"
	)
	_coordinator.release_bootstrap_handoff_hold()


func _cleanup() -> void:
	for enemy: EnemyActor in _enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()
	_enemies.clear()
	for owner: Node in _owners:
		if is_instance_valid(owner):
			owner.queue_free()
	_owners.clear()
	if _player != null and is_instance_valid(_player):
		_player.queue_free()
	MonsterVisual.reset_client_resource_cache()
