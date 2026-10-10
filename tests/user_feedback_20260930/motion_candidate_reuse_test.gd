extends "res://tests/hc_monster_combat_r4/d3_boundary_runtime_test.gd"
const Positions := preload("res://scripts/monster_crowd_attack_position_policy.gd")

class EligibilityProbe:
	extends EnemyActor
	var eligibility_reads := 0
	func can_receive_damage() -> bool:
		eligibility_reads += 1
		return current_hp > 0

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	player = PlayerCharacter.new()
	player.set_meta("runtime_map_id", MAP_ID)
	player.set_meta("zone_generation", 1)
	player.global_position = _ground_to_screen(CENTER)
	add_child(player)
	player.set_physics_process(false)
	var origin := CENTER + Vector2(4, 0)
	var actor := _spawn(24, origin)
	var peer := _spawn(24, CENTER + Vector2(8, 8))
	_check(actor._hc_motion_clear(origin, origin + Vector2(-1, 0)), "initial full leg unexpectedly blocked")
	var queries := index.index_enemy_node_segment_query_count
	_check(actor._hc_motion_clear(origin, origin + Vector2(-0.05, 0)), "subsegment unexpectedly blocked")
	_check(index.index_enemy_node_segment_query_count == queries, "same synchronous leg/subsegment repeated the bucket query")
	actor.set_combat_position(_ground_to_screen(origin + Vector2(-0.01, 0)), &"candidate_reuse_own_prefix")
	_check(actor._hc_motion_clear(origin + Vector2(-0.01, 0), origin + Vector2(-0.025, 0)), "own legal prefix unexpectedly blocked")
	_check(index.index_enemy_node_segment_query_count == queries, "self movement invalidated other-body candidate identities")
	# Forced movement into the envelope must invalidate identities in the
	# same physics frame; only the existing position transaction is used.
	peer.set_combat_position(_ground_to_screen(origin + Vector2(-0.7, 0)), &"candidate_reuse_incoming_body")
	_check(not actor._hc_motion_clear(origin, origin + Vector2(-0.05, 0)), "same-frame incoming body was missed")
	_check(index.index_enemy_node_segment_query_count == queries + 1, "incoming body did not invalidate the candidate query")
	queries = index.index_enemy_node_segment_query_count
	# Current damage eligibility is still read live; there is no cached hit.
	peer.current_hp = 0
	_check(actor._hc_motion_clear(origin, origin + Vector2(-0.025, 0)), "cached identities became a stale body hit")
	_check(index.index_enemy_node_segment_query_count == queries, "live eligibility required another unchanged bucket query")
	var born := _spawn(24, origin + Vector2(-0.7, 0))
	_check(not actor._hc_motion_clear(origin, origin + Vector2(-0.025, 0)), "newly registered same-frame body was missed")
	_check(index.index_enemy_node_segment_query_count == queries + 1, "registration did not invalidate candidate identities")
	# Coarse bucket identities remain complete while a body moves inside
	# its bucket. The exact old hit is never cached, even across physics ticks.
	# Construct the SAME-bucket case from the configured partition, rather
	# than assuming a 4-GU bucket. The incoming body remains in that bucket.
	var second_origin := Vector2(24, 24) + Vector2.ONE * index.bucket_size_gu() * 0.1
	var second := _spawn(24, second_origin)
	var same_bucket := _spawn(24, second_origin + Vector2.ONE * index.bucket_size_gu() * 0.8)
	_check(second._hc_motion_clear(second_origin, second_origin + Vector2(0, 1)), "coarse pool initial path blocked")
	queries = index.index_enemy_node_segment_query_count
	await get_tree().physics_frame
	same_bucket.set_combat_position(_ground_to_screen(second_origin + Vector2(0, 0.65)), &"candidate_reuse_same_bucket_body")
	_check(not second._hc_motion_clear(second_origin, second_origin + Vector2(0, 0.025)), "body moving within the same bucket was missed")
	_check(index.index_enemy_node_segment_query_count == queries, "unchanged bucket membership repeated its identity query")
	index.clear_map(MAP_ID)
	_check(actor._hc_motion_clear(origin, origin + Vector2(-0.025, 0)), "map teardown reused removed candidate identities")
	_advancing_bucket_case(Vector2(18,18))
	_advancing_bucket_case(Vector2(-18,-18))
	_motion_envelope_prefilter_case(actor, origin)
	_station_envelope_prefilter_case(actor, origin)
	for item in [actor, peer, born, second, same_bucket]: item.free()
	player.free()
	print("MOTION_CANDIDATE_REUSE_", "PASS" if failures.is_empty() else "FAIL", " ", failures)
	get_tree().quit(0 if failures.is_empty() else 1)

func _advancing_bucket_case(center: Vector2) -> void:
	index.clear_map(MAP_ID)
	var mover := _spawn(24,center)
	# This receiver exists before the cached query, outside its coarse pool.
	# A later segment must expand the query even without a membership change.
	var blocker := _spawn(24,center+Vector2(2.9,0))
	_check(mover._hc_motion_clear(center,center+Vector2(0.025,0)),"initial advancing leg blocked")
	var queries := index.index_enemy_node_segment_query_count
	var revision := index.bucket_membership_revision
	for step in range(1,9):
		var point := center+Vector2(step*0.025,0)
		mover.set_combat_position(_ground_to_screen(point),&"candidate_advancing_same_bucket")
		_check(mover._hc_motion_clear(point,point+Vector2(0.025,0)),"live advancing subleg blocked")
	_check(index.bucket_membership_revision == revision,"advancing fixture must keep exact bucket membership")
	_check(index.index_enemy_node_segment_query_count == queries,"advancing disjoint legs in an already complete bucket pool must not repeat identity queries: "+str(center))
	_check(not mover._hc_motion_clear(center+Vector2(0.2,0),center+Vector2(2.8,0)),"newly intersected bucket's pre-existing blocker must be found")
	_check(index.index_enemy_node_segment_query_count == queries+1,"escaping the covered bucket range must perform a fresh query")
	queries = index.index_enemy_node_segment_query_count
	mover.set_meta("zone_generation",2)
	_check(not mover._hc_motion_clear(center+Vector2(0.2,0),center+Vector2(2.8,0)),"new generation preserves actual blocking")
	_check(index.index_enemy_node_segment_query_count == queries+1,"world generation still invalidates the identity pool")
	mover.free(); blocker.free()
	index.clear_map(MAP_ID)

func _motion_envelope_prefilter_case(actor: EnemyActor, origin: Vector2) -> void:
	# A complete coarse-bucket pool deliberately includes distant bodies.
	# Compare the exact original core predicate over crossing, separating and
	# grazing segments, and count avoided eligibility work for those bodies.
	var probes: Array = []
	for n in range(32):
		var probe := EligibilityProbe.new()
		probe.runtime_map_id = MAP_ID
		probe.combat_radius_gu = 0.25 + float(n % 3) * 0.25
		probe.current_hp = 100
		probe.behavior_profile = {"worldCollision": true}
		probe.configure_runtime_map_projection(MAP_ID, Callable(self, "_ground_to_screen"), Callable(self, "_screen_to_ground"))
		add_child(probe)
		probe.set_physics_process(false)
		probes.append(probe)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261001
	for trial in range(160):
		var endpoint := origin + Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0))
		var expected_clear := true
		for n in range(probes.size()):
			var probe: EligibilityProbe = probes[n]
			var point := origin + Vector2(8.0 + n, 8.0)
			if n < 3:
				point = origin + Vector2(rng.randf_range(-1.5, 1.5), rng.randf_range(-1.5, 1.5))
			probe.global_position = _ground_to_screen(point)
			if actor.HCPolicy.core_crossed(origin, endpoint, point, actor.combat_radius_gu, probe.combat_radius_gu):
				expected_clear = false
		_check(actor._hc_motion_candidates(origin, endpoint, probes) == expected_clear, "live envelope changed original core result at trial %d" % trial)
	var far_eligibility_reads := 0
	for n in range(3, probes.size()):
		far_eligibility_reads += probes[n].eligibility_reads
	_check(far_eligibility_reads == 0, "distant coarse-pool bodies incurred %d unnecessary eligibility checks" % far_eligibility_reads)
	for probe in probes: probe.free()

func _station_envelope_prefilter_case(actor: EnemyActor, origin: Vector2) -> void:
	var probes: Array = []
	for n in range(32):
		var probe := EligibilityProbe.new()
		probe.runtime_map_id = MAP_ID
		probe.combat_radius_gu = 0.25 + float(n % 3) * 0.25
		probe.configure_runtime_map_projection(MAP_ID, Callable(self, "_ground_to_screen"), Callable(self, "_screen_to_ground"))
		add_child(probe)
		probe.set_physics_process(false)
		probes.append(probe)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261002
	for trial in range(160):
		var point := origin + Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0))
		var expected_available := true
		for n in range(probes.size()):
			var probe: EligibilityProbe = probes[n]
			var position := origin + Vector2(8.0 + n, 8.0) if n >= 3 else origin + Vector2(rng.randf_range(-1.5, 1.5), rng.randf_range(-1.5, 1.5))
			probe.global_position = _ground_to_screen(position)
			probe.current_hp = 0 if (trial + n) % 7 == 0 else 100
			probe.behavior_profile = {"worldCollision": (trial + n) % 5 != 0}
			# Independent no-claim physical contender oracle. Read the actual
			# projected pose; eligibility and overlap remain live each trial.
			var actual := probe.spatial_index_position()
			var radius := actor.combat_radius_gu + probe.combat_radius_gu
			var contender := actual.distance_squared_to(point)
			if probe.current_hp > 0 and probe.behavior_profile.worldCollision and contender < radius * radius - GU.EPSILON_GU:
				expected_available = false
		_check(Positions.available(actor, player, point, probes) == expected_available, "station envelope changed live contender result at trial %d" % trial)
	var far_reads := 0
	for n in range(3, probes.size()): far_reads += probes[n].eligibility_reads
	_check(far_reads == 0, "distant station candidates incurred %d unnecessary eligibility checks" % far_reads)
	for probe in probes: probe.free()
