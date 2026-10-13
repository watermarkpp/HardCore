extends "res://tests/hc_monster_combat_r4/d3_boundary_runtime_test.gd"

## Independent contract for the bounded membership proof and live collision.
## Frozen scalar reference below is bd73a256 policy.gd, never the candidate.
const Policy := preload("res://scripts/monster_ai_package/policy.gd")
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const SCENE_ID := "crowd_compute_contract_v113_20261013"
var proof := Proof.new()
var checks := 0
var geometry_cases := 0

class LivePoint extends Node2D:
	func point() -> Vector2:
		return position

func _check(ok: bool, message: String) -> void:
	checks += 1
	proof.record(ok, message)
	if not ok:
		failures.append(message)

func _run() -> void:
	PlayerState.test_mode = true
	EnemyActor.compute_optimization_test_mode = 1
	Index.compute_optimization_journal_enabled = true
	_geometry_contract()
	# Dynamic invocation lets baseline production parse and fail meaningfully.
	_check(index.has_method("enemy_bucket_pool_unchanged_since"), "MISSING_API: enemy_bucket_pool_unchanged_since")
	if index.has_method("enemy_bucket_pool_unchanged_since"):
		_journal_contract()
		_history_contract()
		_live_cache_contract()
	var evidence := {"schema": "crowd_compute_contract_v113_v1", "checks": checks,
		"geometry_cases": geometry_cases, "failures": failures}
	FileAccess.open("user://crowd_compute_contract.json", FileAccess.WRITE).store_string(JSON.stringify(evidence, "  "))
	var receipt_ok := proof.write_receipt(SCENE_ID, checks, failures.size())
	print("CROWD_COMPUTE_CONTRACT_", "PASS" if failures.is_empty() and receipt_ok else "FAIL", " ", JSON.stringify(evidence))
	get_tree().quit(0 if failures.is_empty() and receipt_ok else 1)

static func _original_core(a: Vector2, b: Vector2, c: Vector2, ra: float, rb: float) -> bool:
	var r := maxf(0.0, ra + rb)
	var before := a.distance_squared_to(c)
	var after := b.distance_squared_to(c)
	if before < r * r:
		return (b - a).dot(a - c) < -Policy.EPS or after < before - Policy.EPS
	var q := Geometry2D.get_closest_point_to_segment(c, a, b)
	return q.distance_squared_to(c) < r * r - Policy.EPS

func _geometry_contract() -> void:
	# Literal separated / overlap outward / inward / through centre / degenerate
	# and tangent cases catch threshold, dot, radius and short-circuit changes.
	var cases: Array = [
		[Vector2.ZERO, Vector2(2,0), Vector2(1,0), 0.5, 0.5],
		[Vector2.ZERO, Vector2(-2,0), Vector2(0.5,0), 0.5, 0.5],
		[Vector2.ZERO, Vector2(0.1,0), Vector2(0.5,0), 0.5, 0.5],
		[Vector2.ZERO, Vector2(3,0), Vector2(0.5,0), 0.5, 0.5],
		[Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, 0.5, 0.5],
		[Vector2.ZERO, Vector2(2,0), Vector2(1,1), 0.5, 0.5],
		[Vector2.ZERO, Vector2(2,0), Vector2(1,0), 0.0, 0.0],
		[Vector2.ZERO, Vector2(2,0), Vector2(1,0), -2.0, 0.5],
	]
	for epsilon_scale: float in [-2.0, -1.0, 0.0, 1.0, 2.0]:
		var offset := Policy.EPS * epsilon_scale
		cases.append([Vector2.ZERO, Vector2(2,0), Vector2(1,1 + offset), 0.5, 0.5])
		cases.append([Vector2.ZERO, Vector2(offset,0), Vector2(0.5,0), 0.5, 0.5])
		cases.append([Vector2.ZERO, Vector2(1,0), Vector2(1 + offset,0), 0.5, 0.5])
	for sample: Array in cases:
		_compare_core(sample)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261013
	for trial in range(4096):
		var a := Vector2(rng.randf_range(-50,50), rng.randf_range(-50,50))
		var b := a if trial % 13 == 0 else a + Vector2(rng.randf_range(-4,4), rng.randf_range(-4,4))
		var c := a + Vector2(rng.randf_range(-4,4), rng.randf_range(-4,4))
		_compare_core([a,b,c,rng.randf_range(-1,2),rng.randf_range(-1,2)])

func _compare_core(sample: Array) -> void:
	geometry_cases += 1
	_check(Policy.core_crossed(sample[0],sample[1],sample[2],sample[3],sample[4]) ==
		_original_core(sample[0],sample[1],sample[2],sample[3],sample[4]), "core exact mismatch case %d" % geometry_cases)

func _unchanged(idx: RuntimeCombatSpatialIndex, map_id: int, rect: Rect2i, revision: int) -> bool:
	return bool(idx.call("enemy_bucket_pool_unchanged_since", map_id, rect, revision))

func _journal_contract() -> void:
	var idx := Index.new()
	var node := LivePoint.new()
	var size: float = idx.bucket_size_gu()
	var rect := Rect2i(-1,-1,3,3)
	idx.register(1, MAP_ID, Vector2(100,100) * size, 1.0, 1, node)
	var rev: int = idx.bucket_membership_revision
	_check(_unchanged(idx,MAP_ID,rect,rev), "unchanged revision rejected")
	_check(not _unchanged(idx,MAP_ID,Rect2i(),rev), "empty covered rectangle accepted")
	_check(not _unchanged(idx,MAP_ID,Rect2i(0,0,-1,2),rev), "negative rectangle accepted")
	_check(not _unchanged(idx,MAP_ID,rect,-1), "negative revision accepted")
	_check(not _unchanged(idx,MAP_ID,rect,rev+1), "future revision accepted")
	idx.update_actor(1, Vector2(101,100) * size)
	_check(_unchanged(idx,MAP_ID,rect,rev), "remote crossing invalidated local pool")
	idx.register(2, MAP_ID+1, Vector2.ZERO, 1.0, 2, node)
	_check(_unchanged(idx,MAP_ID,rect,rev), "other map registration invalidated local pool")
	idx.clear_map(MAP_ID+1)
	_check(_unchanged(idx,MAP_ID,rect,rev), "other map clear invalidated local pool")
	idx.register(2, MAP_ID, Vector2(2,0)*size, 1.0, 2, node)
	_check(_unchanged(idx,MAP_ID,rect,rev), "half-open positive edge falsely intersects")
	rev = idx.bucket_membership_revision
	idx.update_actor(2, Vector2(1.5,0)*size)
	_check(not _unchanged(idx,MAP_ID,rect,rev), "outside-to-inside crossing missed")
	rev = idx.bucket_membership_revision
	idx.update_actor(2, Vector2(-0.5,0)*size)
	_check(not _unchanged(idx,MAP_ID,rect,rev), "inside-to-inside crossing missed")
	rev = idx.bucket_membership_revision
	idx.update_actor(2, Vector2(-2,0)*size)
	_check(not _unchanged(idx,MAP_ID,rect,rev), "inside-to-outside crossing missed")
	rev = idx.bucket_membership_revision
	idx.register(3, MAP_ID, Vector2.ZERO, 1.0, 3, node)
	_check(not _unchanged(idx,MAP_ID,rect,rev), "zero bucket registration missed")
	rev = idx.bucket_membership_revision
	idx.unregister(3)
	idx.register(4, MAP_ID, Vector2.ZERO, 1.0, 4, node)
	_check(not _unchanged(idx,MAP_ID,rect,rev), "same-count replacement accepted")
	rev = idx.bucket_membership_revision
	idx.register(4, MAP_ID, Vector2(200,200)*size, 1.0, 4, node)
	_check(not _unchanged(idx,MAP_ID,rect,rev), "runtime ID replacement omitted old bucket")
	idx.register(5, MAP_ID, Vector2.ZERO, 1.0, 5, node)
	rev = idx.bucket_membership_revision
	idx.clear_map(MAP_ID)
	_check(not _unchanged(idx,MAP_ID,rect,rev), "map clear missed live former members")
	idx.register(1, MAP_ID, Vector2(100,100)*size, 1.0, 1, node)
	rev = idx.bucket_membership_revision
	idx.register(2, MAP_ID+1, Vector2(100,100)*size, 5.0, 2, node)
	_check(not _unchanged(idx,MAP_ID,rect,rev), "cross-map max growth missed")
	idx.unregister(2)
	idx.query_segment_candidates(MAP_ID,Vector2.ZERO,Vector2.ONE,0.0)
	rev = idx.bucket_membership_revision
	idx.register(2, MAP_ID+1, Vector2(100,100)*size, 2.0, 2, node)
	_check(not _unchanged(idx,MAP_ID,rect,rev), "growth after lazy shrink missed")
	# Live-provider rehome must record both integer buckets.
	node.position = Vector2.ZERO
	idx.register(9,MAP_ID,Vector2.ZERO,1.0,9,node,node.point)
	rev = idx.bucket_membership_revision
	node.position = Vector2(10,10)*size
	idx.query_segment_candidates(MAP_ID,Vector2.ZERO,Vector2.ONE,0.0)
	_check(not _unchanged(idx,MAP_ID,rect,rev), "lazy provider rehome omitted old bucket")
	var stale := LivePoint.new()
	idx.register(10,MAP_ID,Vector2.ZERO,1.0,10,stale)
	rev = idx.bucket_membership_revision
	stale.free()
	idx.query_segment_candidates(MAP_ID,Vector2.ZERO,Vector2.ONE,0.0)
	_check(not _unchanged(idx,MAP_ID,rect,rev), "stale erase omitted old bucket")
	node.free()

func _history_contract() -> void:
	var idx := Index.new()
	var node := LivePoint.new()
	var rect := Rect2i(-1,-1,3,3)
	idx.register(1,MAP_ID,Vector2(100,100),1.0,1,node)
	var rev: int = idx.bucket_membership_revision
	for mutation in range(128):
		idx.update_actor(1,Vector2(200+mutation,100)*idx.bucket_size_gu())
	_check(_unchanged(idx,MAP_ID,rect,rev), "exactly 128 retained unrelated mutations rejected")
	idx.update_actor(1,Vector2(400,100)*idx.bucket_size_gu())
	_check(not _unchanged(idx,MAP_ID,rect,rev), "129 overwritten mutations accepted")
	for lap in range(4):
		rev = idx.bucket_membership_revision
		for mutation in range(128):
			idx.update_actor(1,Vector2(500+lap*128+mutation,100)*idx.bucket_size_gu())
		_check(_unchanged(idx,MAP_ID,rect,rev), "ring wrap lost complete history lap %d" % lap)
	var journal: Variant = idx.get("_bucket_membership_journal")
	_check(journal is PackedInt64Array and journal.size() == 128*7, "journal is not bounded 7168-byte int64 payload")
	if journal is PackedInt64Array and journal.size() == 128*7:
		rev = idx.bucket_membership_revision-1
		journal[(idx.bucket_membership_revision % 128)*7] = -99
		idx.set("_bucket_membership_journal",journal)
		_check(not _unchanged(idx,MAP_ID,rect,rev), "mismatched record revision accepted")
	for edge: int in [2147483647,4294967295]:
		idx.bucket_membership_revision = edge-1
		rev = idx.bucket_membership_revision
		idx.update_actor(1,Vector2(1700,100)*idx.bucket_size_gu())
		idx.update_actor(1,Vector2(1701,100)*idx.bucket_size_gu())
		_check(idx.bucket_membership_revision == edge+1, "int64 revision truncated at %d" % edge)
		_check(_unchanged(idx,MAP_ID,rect,rev), "int64 journal truncated at %d" % edge)
	idx.bucket_membership_revision += 1 # Deliberately missing hook must fail closed.
	_check(not _unchanged(idx,MAP_ID,rect,idx.bucket_membership_revision-1), "unrecorded revision accepted")
	_check(not _unchanged(idx,MAP_ID,rect,idx.bucket_membership_revision+1), "G<R accepted")
	rev = idx.bucket_membership_revision
	Index.compute_optimization_journal_enabled = false
	idx.update_actor(1,Vector2(1800,100)*idx.bucket_size_gu())
	_check(idx.bucket_membership_revision == rev+1,"CONTROL must retain original revision increment")
	Index.compute_optimization_journal_enabled = true
	_check(not _unchanged(idx,MAP_ID,rect,rev),"CONTROL write gap must fail closed after re-enable")
	rev = idx.bucket_membership_revision
	idx.update_actor(1,Vector2(1801,100)*idx.bucket_size_gu())
	_check(_unchanged(idx,MAP_ID,rect,rev),"fresh retained history did not recover after gap")
	node.free()

func _reference_clear(actor: EnemyActor, a: Vector2, b: Vector2, live: Array) -> bool:
	if actor._hc_surround_goal.is_finite() and is_instance_valid(actor.target):
		if _original_core(a,b,_screen_to_ground(actor.target.global_position),actor.combat_radius_gu,actor._target_combat_radius_gu(actor.target)):
			return false
	for other: EnemyActor in live:
		if not is_instance_valid(other) or other == actor or other == actor.target or other.runtime_map_id != actor.runtime_map_id:
			continue
		if not other.can_receive_damage() or not bool(other.behavior_profile.get("worldCollision",true)):
			continue
		if _original_core(a,b,other.spatial_index_position(),actor.combat_radius_gu,other.combat_radius_gu):
			return false
	return true

func _compare_live(actor: EnemyActor, a: Vector2, b: Vector2, live: Array, label: String, refill: int = -1) -> void:
	var before: int = index.index_enemy_node_segment_query_count
	var actual: bool = actor._hc_motion_clear(a,b)
	if refill >= 0:
		_check(index.index_enemy_node_segment_query_count == before+refill,label+": refill count")
	_check(actual == _reference_clear(actor,a,b,live),label+": exhaustive frozen geometry mismatch")
	var complete: Array = []
	index.query_enemy_nodes_bucket_segment_into(MAP_ID,a,b,actor.combat_radius_gu,complete)
	_check(actual == _reference_clear(actor,a,b,complete),label+": original complete-query mismatch")

func _live_cache_contract() -> void:
	PlayerState.reset_progress(false)
	player = PlayerCharacter.new()
	player.set_meta("runtime_map_id",MAP_ID)
	player.global_position = _ground_to_screen(Vector2(-100,-100))
	add_child(player)
	player.set_physics_process(false)
	var a := Vector2(16.2,16.2)
	var b := a+Vector2(0.025,0)
	var actor := _spawn(24,a)
	var near := _spawn(24,a+Vector2(0,3))
	var remote := _spawn(24,Vector2(100,100))
	var live: Array = [actor,near,remote]
	_compare_live(actor,a,b,live,"initial",1)
	remote.set_combat_position(_ground_to_screen(Vector2(102,100)),&"contract_remote")
	_compare_live(actor,a,b,live,"remote crossing",0)
	index.unregister(remote.spatial_actor_runtime_id)
	_compare_live(actor,a,b,[actor,near],"remote removal",0)
	index.register(remote.spatial_actor_runtime_id,MAP_ID+1,Vector2.ZERO,remote.combat_radius_gu,serial,remote)
	_compare_live(actor,a,b,[actor,near],"other map registration",0)
	near.set_combat_position(_ground_to_screen(a+Vector2(0.65,0)),&"contract_incoming")
	_compare_live(actor,a,b,[actor,near],"same-frame entering blocker",1)
	_check(not _reference_clear(actor,a,b,[near]),"fixture incoming body must block")
	# Live state is tested without a reference index cleanup between death and
	# revival, since an actual cleanup deliberately unregisters dead identities.
	for property: String in ["current_hp","_death_pending","_dying"]:
		var prior: Variant = near.get(property)
		near.set(property,0 if property == "current_hp" else true)
		var count: int = index.index_enemy_node_segment_query_count
		_check(actor._hc_motion_clear(a,b),"live "+property+" retained stale hit")
		_check(index.index_enemy_node_segment_query_count == count,"live state rebuilt identities")
		near.set(property,prior)
		_check(not actor._hc_motion_clear(a,b),"live "+property+" did not restore collision")
	near.behavior_profile["worldCollision"] = false
	_compare_live(actor,a,b,[actor,near],"worldCollision disabled",0)
	near.behavior_profile["worldCollision"] = true
	_compare_live(actor,a,b,[actor,near],"worldCollision restored",0)
	var prior_bucket := index._bucket_key(near.spatial_index_position())
	near.set_combat_position(_ground_to_screen(a+Vector2(0.65,0.1)),&"contract_same_bucket")
	_check(index._bucket_key(near.spatial_index_position()) == prior_bucket,"same bucket fixture crossed boundary")
	_compare_live(actor,a,b,[actor,near],"same-bucket forced movement",0)
	for scope: String in ["zone_generation","hc_combat_life_epoch"]:
		actor.set_meta(scope,int(actor.get_meta(scope,0))+1)
		_compare_live(actor,a,b,[actor,near],scope,1)
	actor.combat_radius_gu += 0.01
	_compare_live(actor,a,b,[actor,near],"self radius",1)
	# Clearing retains live Nodes; old candidate identities must disappear.
	index.clear_map(MAP_ID)
	_compare_live(actor,a,b,[],"clear map with live nodes",1)
	index.register(near.spatial_actor_runtime_id,MAP_ID,near.spatial_index_position(),near.combat_radius_gu,serial,near)
	_compare_live(actor,a,b,[near],"same bucket reborn",1)
	index.clear_map(MAP_ID)
	_compare_live(actor,a,b,[],"empty before bounds growth",1)
	var old_rect: Rect2i = actor._hc_motion_candidate_buckets
	var big_point := Vector2(old_rect.end+Vector2i(1,0))*index.bucket_size_gu()
	var big := _spawn(24,big_point)
	big.combat_radius_gu = big_point.distance_to(a)+1.0
	index.register(big.spatial_actor_runtime_id,MAP_ID,big_point,big.combat_radius_gu,serial,big)
	_check(not old_rect.has_point(index._bucket_key(big_point)),"large fixture centre must be outside covered pool")
	_compare_live(actor,a,b,[big],"outside-centre bounds growth",1)
	_check(not _reference_clear(actor,a,b,[big]),"large fixture must block")
	index.clear_map(MAP_ID)
	_compare_live(actor,a,b,[],"station empty baseline",1)
	# setup stores primary_target but intentionally leaves target null until
	# acquisition. Bind this isolated station fixture as the existing route
	# contract does; disabled physics never runs that acquisition for us.
	actor.target = player
	_check(actor.target == player,"station target fixture must bind current target")
	actor._hc_surround_goal = a
	player.global_position = _ground_to_screen(a+Vector2(0.65,0))
	_compare_live(actor,a,b,[],"live station target",0)
	_check(not _reference_clear(actor,a,b,[]),"station target fixture must block")
	player.global_position = _ground_to_screen(Vector2(-100,-100))
	_compare_live(actor,a,b,[],"live station target moves away",0)
	_check(_reference_clear(actor,a,b,[]),"station target leaving must clear")
	for item: EnemyActor in [actor,near,remote,big]:
		item.free()
	player.free()
	index.clear_map(MAP_ID)
	index.clear_map(MAP_ID+1)
