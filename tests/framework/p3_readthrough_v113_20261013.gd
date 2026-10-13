extends Node

## Final draft-only P3 read-through prototype.
## It is a narrow experiment for the registered P3 apparatus, not a product
## change. It keeps the original identity cache, counters, AABB/core checks,
## stage short-circuiting and live radius/eligibility reads.
const Index := preload("res://scripts/runtime_combat_spatial_index.gd")
const GU := preload("res://scripts/ground_unit_space.gd")
const Terrain := preload("res://tests/helpers/monster_open_terrain_test_fixture.gd")
const Background := preload("res://scripts/world_background.gd")
const PolyIndex := preload("res://scripts/map_editor/polygon/poly_index.gd")
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const HCPolicy := preload("res://scripts/monster_ai_package/policy.gd")
const SCENE_ID := "p3_readthrough_v113_20261013"
const MAP_ID := 92014
const ZONE_GENERATION := 1

var proof := Proof.new()
var failures := 0
var current_provider: Node = null
var current_map_id := MAP_ID
var _zone_generation := ZONE_GENERATION
var projection_calls := 0
var gate_proof_rows: Array[Dictionary] = []

class ViewEnemy extends EnemyActor:
	## Warm buffer is positions only. It grows to the largest candidate list and
	## is never cleared/shrunk; ordinal means the original candidates slot.
	var readthrough_positions := PackedVector2Array()
	var readthrough_active := false
	var readthrough_direction_enabled := false
	var readthrough_phase := 0 # 0 stage0, 1 stage1, 2 destination
	var readthrough_guard_depth := 0
	var readthrough_miss := false
	var readthrough_scope_provider: Node = null
	var readthrough_fallbacks := 0
	var readthrough_preflight_usec := 0
	var readthrough_motion_usec := 0
	var readthrough_destination_usec := 0
	var readthrough_shadow_checks := 0
	var readthrough_mismatches := 0
	var readthrough_verify := false

	func _scope_allowed(peer: EnemyActor) -> bool:
		return peer.get_script() == get_script() and peer.environment_blocker == readthrough_scope_provider

	func _begin_readthrough() -> void:
		readthrough_active = true
		readthrough_direction_enabled = false
		readthrough_phase = 0
		readthrough_miss = false

	func _end_readthrough() -> void:
		readthrough_active = false
		readthrough_direction_enabled = false
		readthrough_phase = 0
		readthrough_miss = false

	func _read_position(peer: EnemyActor, slot: int, capture: bool) -> Vector2:
		if not readthrough_direction_enabled:
			return peer.spatial_index_position()
		if not capture:
			return readthrough_positions[slot]
		if not _scope_allowed(peer):
			readthrough_direction_enabled = false
			readthrough_miss = true
			return peer.spatial_index_position()
		if peer._spatial_index_projection_cache_matches():
			var point: Vector2 = peer._last_spatial_index_ground_position_gu
			if point.is_finite(): readthrough_positions[slot] = point
			else:
				readthrough_direction_enabled = false
				readthrough_miss = true
			return point
		# Abandon before invoking precisely the original getter's miss branch.
		readthrough_direction_enabled = false
		readthrough_miss = true
		return peer._screen_position_px_to_ground_position_gu(peer.global_position)

	func _motion_from_positions(a: Vector2, b: Vector2, candidates: Array, capture := false) -> bool:
		_record_performance_counter(&"enemy_motion_candidate_checks", candidates.size())
		var low := Vector2(minf(a.x,b.x), minf(a.y,b.y))
		var high := Vector2(maxf(a.x,b.x), maxf(a.y,b.y))
		for ordinal in range(candidates.size()):
			var raw: Variant = candidates[ordinal]
			if not is_instance_valid(raw) or not raw is EnemyActor:
				continue
			var other := raw as EnemyActor
			if other == self or other == target or other.runtime_map_id != runtime_map_id:
				continue
			_record_performance_counter(&"enemy_motion_body_checks")
			var center := _read_position(other,ordinal,capture)
			var radius := maxf(0.0, combat_radius_gu + other.combat_radius_gu) + HCPolicy.EPS
			if center.x < low.x-radius or center.x > high.x+radius or center.y < low.y-radius or center.y > high.y+radius:
				continue
			# Radius and eligibility remain live, exactly at the original access.
			if not other.can_receive_damage() or not bool(other.behavior_profile.get("worldCollision", true)):
				continue
			if HCPolicy.core_crossed(a,b,center,combat_radius_gu,other.combat_radius_gu):
				return false
		return true

	func _destination_from_positions(point: Vector2, candidates: Array) -> bool:
		for ordinal in range(candidates.size()):
			var raw: Variant = candidates[ordinal]
			if not is_instance_valid(raw) or not raw is EnemyActor:
				continue
			var other := raw as EnemyActor
			if other == self or other == target or other.runtime_map_id != runtime_map_id:
				continue
			var radius := maxf(0.0, combat_radius_gu + other.combat_radius_gu)
			if point.distance_squared_to(readthrough_positions[ordinal]) >= radius*radius-HCPolicy.EPS:
				continue
			if other.can_receive_damage() and bool(other.behavior_profile.get("worldCollision",true)):
				return false
		return true

	func _shadow_motion(a: Vector2,b: Vector2,candidates: Array,result: bool) -> void:
		if not readthrough_verify:
			return
		readthrough_shadow_checks += 1
		var original := super._hc_motion_candidates(a,b,candidates)
		if original != result:
			readthrough_mismatches += 1

	func _hc_far_approach_waypoint(current: Vector2, anchor: Vector2, cell: Vector2i, preferred_sign: float) -> Vector2:
		if readthrough_guard_depth > 0:
			readthrough_direction_enabled = false
			readthrough_miss = true
			readthrough_guard_depth += 1
			var nested := super._hc_far_approach_waypoint(current,anchor,cell,preferred_sign)
			readthrough_guard_depth -= 1
			return nested
		if not readthrough_active or _hc_surround_goal.is_finite() or not is_instance_valid(readthrough_scope_provider) or readthrough_scope_provider.get_script() != Background:
			return super._hc_far_approach_waypoint(current,anchor,cell,preferred_sign)
		readthrough_guard_depth = 1
		_begin_readthrough()
		var result := super._hc_far_approach_waypoint(current,anchor,cell,preferred_sign)
		_end_readthrough()
		readthrough_guard_depth = 0
		return result

	func _hc_motion_candidates(a: Vector2,b: Vector2,candidates: Array) -> bool:
		if not readthrough_active or readthrough_guard_depth != 1:
			return super._hc_motion_candidates(a,b,candidates)
		if readthrough_phase == 0:
			readthrough_direction_enabled = true
			readthrough_miss = false
			if readthrough_positions.size() < candidates.size():
				readthrough_positions.resize(candidates.size())
			var stage0 := _motion_from_positions(a,b,candidates,true)
			_shadow_motion(a,b,candidates,stage0)
			if not stage0:
				readthrough_direction_enabled = false
				readthrough_phase = 0
				return stage0
			readthrough_phase = 1
			return stage0
		if readthrough_phase == 1:
			var stage1: bool
			if not readthrough_direction_enabled:
				stage1 = super._hc_motion_candidates(a,b,candidates)
			else:
				stage1 = _motion_from_positions(a,b,candidates)
				_shadow_motion(a,b,candidates,stage1)
			readthrough_phase = 2 if stage1 else 0
			if not stage1:
				readthrough_direction_enabled = false
			return stage1
		return super._hc_motion_candidates(a,b,candidates)

	func _hc_flank_destination_candidates_clear(point: Vector2,candidates:Array) -> bool:
		if not readthrough_active or readthrough_guard_depth != 1:
			return super._hc_flank_destination_candidates_clear(point,candidates)
		var result: bool
		if not readthrough_direction_enabled:
			result = super._hc_flank_destination_candidates_clear(point,candidates)
		else:
			result = _destination_from_positions(point,candidates)
			if readthrough_verify:
				readthrough_shadow_checks += 1
				var original := super._hc_flank_destination_candidates_clear(point,candidates)
				if original != result:
					readthrough_mismatches += 1
		readthrough_phase = 0
		readthrough_direction_enabled = false
		return result

class CountingViewEnemy extends ViewEnemy:
	var gate_calls := 0
	func _spatial_index_projection_cache_matches() -> bool:
		gate_calls += 1
		return super._spatial_index_projection_cache_matches()

func _ground_to_screen(p: Vector2) -> Vector2:
	return GU.ground_delta_gu_to_screen_delta_px(p)

func _screen_to_ground(p: Vector2) -> Vector2:
	projection_calls += 1
	return GU.screen_delta_px_to_ground_delta_gu(p)

func _check(ok: bool,label: String) -> void:
	proof.record(ok,label)
	failures += 0 if ok else 1

func _make_actor(index: Index,player: PlayerCharacter,serial:int,position:Vector2,provider:Node,counted := false) -> ViewEnemy:
	var actor: ViewEnemy = CountingViewEnemy.new() if counted else ViewEnemy.new()
	actor.setup(GameData.get_monster_by_id(64),player,false)
	actor.set_meta("safe_zones",[])
	actor.environment_blocker = provider
	actor.readthrough_scope_provider = provider
	actor.set_meta("zone_generation",ZONE_GENERATION)
	actor.configure_runtime_map_projection(MAP_ID,Callable(self,"_ground_to_screen"),Callable(self,"_screen_to_ground"))
	actor.configure_terrain_navigation_context(Terrain.build(MAP_ID))
	actor.configure_spatial_index(index,serial)
	add_child(actor)
	actor.set_physics_process(false)
	actor.target=player
	actor.primary_target=player
	index.register(serial,MAP_ID,position,actor.combat_radius_gu,serial,actor)
	actor.set_combat_position(_ground_to_screen(position),&"p3_readthrough_spawn")
	return actor

func _case(peer_count:int,fractional:bool,all_clear:bool) -> Dictionary:
	var index := Index.new()
	var provider := Background.new()
	var geometry := PolyIndex.new()
	_check(geometry.setup(Vector2i(128,128),[]),"formal polygon setup")
	provider._editor_runtime_collision_snapshot={"design_size":Vector2i(128,128),"poly_index":geometry}
	current_provider=provider
	var player := PlayerCharacter.new()
	player.set_meta("runtime_map_id",MAP_ID)
	player.set_meta("zone_generation",ZONE_GENERATION)
	player.global_position=_ground_to_screen(Vector2(36.5,20.5))
	add_child(player)
	player.set_physics_process(false)
	var peers:Array[ViewEnemy]=[]
	for i in range(peer_count):
		var x:=30.5+float(i%10)
		var y:float=(18.75 if i%2==0 else 22.25) if all_clear else (19.3 if i%2==0 else 21.7)
		peers.append(_make_actor(index,player,i+1,Vector2(x,y),provider))
	var actor:=_make_actor(index,player,peer_count+1,Vector2(30.25 if fractional else 30.5,20.5),provider)
	var current:=actor.spatial_index_position()
	var anchor:=Vector2(36.5,20.5)
	var expected:=actor._hc_far_approach_waypoint(current,anchor,Vector2i(current.floor()),1.0)
	actor.readthrough_active=true
	actor.readthrough_verify=true
	var observed:=actor._hc_far_approach_waypoint(current,anchor,Vector2i(current.floor()),1.0)
	var leg := actor._hc_flank_leg_endpoint(current,observed)
	if fractional:
		_check(leg != observed,"fractional origin produces distinct canonical leg")
	_check(expected==observed,"waypoint equality peer=%d fractional=%s clear=%s"%[peer_count,fractional,all_clear])
	_check(actor.readthrough_mismatches==0 and actor.readthrough_shadow_checks>0,"shadow predicate parity peer=%d"%peer_count)
	actor.readthrough_verify=false
	var pairs:Array[Dictionary]=[]
	var completion := 0
	for pair in range(8):
		var old_usec:=0
		var new_usec:=0
		for arm in ([false,true] if pair%2==0 else [true,false]):
			actor.readthrough_active=arm
			actor._hc_far_approach_waypoint(current,anchor,Vector2i(current.floor()),1.0)
			var started:=Time.get_ticks_usec()
			for repeat in range(128):
				actor.readthrough_active=arm
				var value:=actor._hc_far_approach_waypoint(current,anchor,Vector2i(current.floor()),1.0)
				completion += 1 if value == expected else 0
			var elapsed:=Time.get_ticks_usec()-started
			if arm:new_usec=elapsed
			else:old_usec=elapsed
		pairs.append({"pair":pair,"order":"AB" if pair%2==0 else "BA","control_usec":old_usec,"prototype_usec":new_usec,"calls_each":128})
	_check(completion == 8*2*128,"all timed completions equal original")
	var result={"current":str(current),"waypoint":str(observed),"leg":str(leg),"equal_calls":completion,"positions_only":true,"scene_id":SCENE_ID,"peer_count":peer_count,"fractional_current":fractional,"all_clear":all_clear,"pairs":pairs,"preflight_usec":actor.readthrough_preflight_usec,"view_motion_usec":actor.readthrough_motion_usec,"view_destination_usec":actor.readthrough_destination_usec,"fallbacks":actor.readthrough_fallbacks,"shadow_checks":actor.readthrough_shadow_checks,"mismatches":actor.readthrough_mismatches,"production_safety":"NOT_PROVEN_SCOPE_EXPERIMENT"}
	for peer:ViewEnemy in peers:
		index.unregister(peer.spatial_actor_runtime_id)
		peer.queue_free()
	index.unregister(actor.spatial_actor_runtime_id)
	actor.queue_free()
	player.queue_free()
	provider.free()
	current_provider=null
	return result

func _prove_gates() -> void:
	var index := Index.new()
	var provider := Background.new()
	var geometry := PolyIndex.new()
	_check(geometry.setup(Vector2i(128,128),[]),"gate proof polygon setup")
	provider._editor_runtime_collision_snapshot = {"design_size":Vector2i(128,128),"poly_index":geometry}
	var player := PlayerCharacter.new()
	player.set_meta("runtime_map_id",MAP_ID);player.set_meta("zone_generation",1)
	player.global_position = _ground_to_screen(Vector2(26.5,20.5))
	add_child(player);player.set_physics_process(false)
	var peers: Array[CountingViewEnemy] = []
	for i in range(12):
		peers.append(_make_actor(index,player,i+1,Vector2(20.5+float(i%6),18.75 if i<6 else 22.25),provider,true) as CountingViewEnemy)
	var actor := _make_actor(index,player,13,Vector2(20.5,20.5),provider,true)
	var current := actor.spatial_index_position()
	for miss: bool in [false,true]:
		if miss:
			for peer: CountingViewEnemy in peers: peer._last_spatial_index_projection = Callable()
		var old_reads := 0
		for peer: CountingViewEnemy in peers: peer.gate_calls = 0
		projection_calls = 0
		actor.readthrough_active = false
		var expected := actor._hc_far_approach_waypoint(current,Vector2(26.5,20.5),Vector2i(current.floor()),1.0)
		var old_projection := projection_calls
		for peer: CountingViewEnemy in peers: old_reads += peer.gate_calls;peer.gate_calls = 0
		projection_calls = 0
		actor.readthrough_active = true
		var observed := actor._hc_far_approach_waypoint(current,Vector2(26.5,20.5),Vector2i(current.floor()),1.0)
		var new_projection := projection_calls
		var new_reads := 0
		for peer: CountingViewEnemy in peers: new_reads += peer.gate_calls
		_check(expected == observed,"gate-count same actual waypoint")
		if miss:
			_check(old_reads == new_reads and old_projection == new_projection and old_projection > 0,"miss preserves exact original gates and external projection count")
		else:
			_check(old_reads == 3*new_reads and new_reads > 0 and old_projection == 0 and new_projection == 0,"hit reduces gates threefold while external projection remains zero")
		gate_proof_rows.append({"miss":miss,"old_gates":old_reads,"new_gates":new_reads,"old_projection":old_projection,"new_projection":new_projection,"waypoint":str(observed)})
	for peer: CountingViewEnemy in peers:
		index.unregister(peer.spatial_actor_runtime_id);peer.queue_free()
	index.unregister(actor.spatial_actor_runtime_id);actor.queue_free();player.queue_free();provider.free()

func _ready()->void:
	_run.call_deferred()

func _run()->void:
	PlayerState.test_mode=true
	_prove_gates()
	await get_tree().process_frame
	var rows:Array=[]
	for count in [4,12,30,40]:
		for clear in [false,true]:
			rows.append(_case(count,false,clear))
		rows.append(_case(count,true,true))
		await get_tree().process_frame
	var result={"schema":"p3_readthrough_v113_20261013_v1","scene_id":SCENE_ID,"rows":rows,"gate_proof":gate_proof_rows,"failures":failures,"source_content_sha256":OS.get_environment("HARDCORE_R3_CONTENT_SHA256"),"framework_run_id":OS.get_environment("HARDCORE_FRAMEWORK_RUN_ID"),"framework_invocation_id":OS.get_environment("HARDCORE_FRAMEWORK_INVOCATION_ID"),"status":"EXPERIMENT_ONLY"}
	var file:=FileAccess.open("res://outputs/collision_prepare_next_v113_20261013/P3_READTHROUGH.json",FileAccess.WRITE)
	_check(file!=null,"report opened")
	if file!=null:
		file.store_string(JSON.stringify(result,"\t"));file.close()
	var ok:=proof.write_receipt(SCENE_ID,proof.records.size(),failures)
	print("P3_READTHROUGH_", "PASS" if failures==0 and ok else "FAIL", " ",JSON.stringify(result))
	get_tree().quit(0 if failures==0 and ok else 1)

