extends "res://tests/hc_monster_ai/test_support.gd"
const GU := preload("res://scripts/ground_unit_space.gd")
const Terrain := preload("res://scripts/monster_terrain_navigation_policy.gd")
const Index := preload("res://scripts/runtime_combat_spatial_index.gd")
const Warrior := preload("res://scripts/skills/warrior_melee_geometry.gd")
var index := Index.new()
var player: PlayerCharacter
var serial := 0
var projection_probe_calls := 0

class RevisionProvider:
	extends Node
	var revision := 0
	func environment_collision_revision() -> int:
		return revision

class ProjectionProvider:
	extends Node
	func project(_screen_position_px: Vector2) -> Vector2:
		return Vector2(25,25)

func ground_to_screen(p: Vector2) -> Vector2:
	return GU.ground_delta_gu_to_screen_delta_px(p)

func screen_to_ground(p: Vector2) -> Vector2:
	return GU.screen_delta_px_to_ground_delta_gu(p)

func counted_screen_to_ground(p: Vector2) -> Vector2:
	projection_probe_calls += 1
	return screen_to_ground(p)

func shifted_screen_to_ground(p: Vector2) -> Vector2:
	projection_probe_calls += 1
	return screen_to_ground(p) + Vector2(3.0, 4.0)

func open_context() -> Dictionary:
	return {"valid":true,"contract_id":Terrain.CONTRACT_ID,"runtime_map_id":1,
		"build_sha256":"b".repeat(64),"coordinate_contract_id":Terrain.EXPECTED_GROUND_COORDINATE_CONTRACT_ID,
		"design_size":Vector2i(80,80),"blocked_cells":{}}

func make_enemy(position: Vector2, monster_id := 64) -> EnemyActor:
	var actor := EnemyActor.new()
	actor.setup(GameData.get_monster_by_id(monster_id),player,false)
	actor.global_position=ground_to_screen(position)
	actor.set_meta("spawn_position",actor.global_position)
	actor.set_meta("safe_zones",[])
	actor.set_meta("zone_generation",1)
	actor.configure_runtime_map_projection(1,Callable(self,"ground_to_screen"),Callable(self,"screen_to_ground"))
	actor.configure_terrain_navigation_context(open_context())
	add_child(actor)
	actor.set_physics_process(false)
	actor.target=player
	actor._retarget_timer=999.0
	actor._attack_timer=999.0
	actor._attack_hit_delay=0.0
	actor.attack_min=50
	actor.attack_max=50
	serial+=1
	actor.spatial_actor_runtime_id=serial
	actor.combat_spatial_index=index
	index.register(serial,1,position,actor.combat_radius_gu,serial,actor)
	actor.set_combat_position(ground_to_screen(position),&"hc_test_setup")
	return actor

func ready_cadence(actor: EnemyActor) -> void:
	var cadence=actor._movement_cadence
	check(cadence!=null,"fixture-cadence","Production cadence exists")
	if cadence==null:
		return
	var now:=Time.get_ticks_msec()
	cadence.walk_wait_locked=false
	cadence.walk_tick_ms=now-cadence.walk_interval_ms-1
	cadence.walk_wait_tick_ms=now
	cadence.last_evaluated_ms=now-1

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	PlayerState.test_mode=true
	player=PlayerCharacter.new()
	player.global_position=ground_to_screen(Vector2(20,20))
	player.set_meta("runtime_map_id",1)
	player.set_meta("zone_generation",1)
	add_child(player)
	player.set_physics_process(false)
	player.max_hp=1000000
	player.current_hp=player.max_hp
	player.current_mp=0
	player.shield_time=0.0
	var actor:=make_enemy(Vector2(22.001,20))
	check(actor._hc_standard_melee(),"R09-fixture","ID64 is a normal physical melee channel")
	check(actor._hc_access(player)=="OUT_OF_RANGE","R04","Footprint does not extend 2-GU centre gate")
	actor.set_combat_position(ground_to_screen(Vector2(21.8,20)),&"hc_test_position")
	await get_tree().physics_frame
	actor._attack_timer=0.0
	actor._movement_step_active=true
	actor._movement_step_reason=&"pursuit"
	var before:=actor._hc_starts
	actor._physics_process_internal(1.0/60.0)
	check(actor._hc_starts==before+1,"T01","Real EnemyActor movement branch starts in this tick")
	check(not actor._hc_try_start(player),"T06","Second start in same physics tick is refused")
	check(actor._hc_settlements>0,"T-hit","Accepted attack reaches the existing damage pipeline")
	# Post-movement opportunity; the motor's real physical displacement is tested.
	await get_tree().physics_frame
	actor.set_combat_position(ground_to_screen(Vector2(22.001,20)),&"hc_test_position")
	actor._clear_autonomous_step_state()
	actor._attack_timer=0.0
	actor._hc_close_session=false
	ready_cadence(actor)
	before=actor._hc_starts
	actor._physics_process_internal(1.0/60.0)
	check(actor._hc_starts==before+1,"T02","A legal opportunity after actual movement starts in same tick")
	# Cooldown does not pin the actor at the outer ring. Do not change speed.
	actor.set_combat_position(ground_to_screen(Vector2(21.8,20)),&"hc_test_position")
	actor._clear_autonomous_step_state()
	actor._attack_timer=999.0
	actor._hc_close_session=true
	var source_speed:=actor.move_speed_gu_per_sec
	for frame in range(120):
		await get_tree().physics_frame
		actor._physics_process_internal(1.0/60.0)
	var d:=screen_to_ground(actor.global_position).distance_to(Vector2(20,20))
	check(d<=actor._hc_preferred(player)+0.003,"S02-runtime","Cooldown actor converges toward preferred contact")
	check(is_equal_approx(actor.move_speed_gu_per_sec,source_speed),"S10-speed","Source movement speed remains unchanged")
	check(Warrior.thrust_footprint_slot_for_direction_ground_gu(Vector2(20,20),screen_to_ground(actor.global_position),actor.combat_radius_gu,Vector2.RIGHT)==1,"S04-runtime","Stationary warrior does not get a permanent outer-slot target")
	# Dynamic front obstacle, including same-tick movement and death.
	actor.set_combat_position(ground_to_screen(Vector2(22,20)),&"hc_test_position")
	var front:=make_enemy(Vector2(21,20))
	var ordered_candidates: Array = []
	var unordered_candidates: Array = []
	index.query_enemy_nodes_segment_into(1,Vector2(22,20),Vector2(20,20),1.0,ordered_candidates)
	index.query_enemy_nodes_segment_unsorted_into(1,Vector2(22,20),Vector2(20,20),1.0,unordered_candidates)
	var ordered_ids:=ordered_candidates.map(func(candidate: EnemyActor)->int:return candidate.spatial_actor_runtime_id)
	var unordered_ids:=unordered_candidates.map(func(candidate: EnemyActor)->int:return candidate.spatial_actor_runtime_id)
	var unordered_ids_sorted:=unordered_ids.duplicate()
	unordered_ids_sorted.sort()
	check(ordered_ids==unordered_ids_sorted,"O01-index-set","Unsorted blocking broadphase preserves the complete live candidate set")
	check(ordered_ids==[actor.spatial_actor_runtime_id,front.spatial_actor_runtime_id],"O01-index-order","Existing ordered broadphase retains stable combat order")
	check(actor._hc_access(player)=="FRONTLINE_BLOCKED","O01-runtime","Live front actor blocks rear start")
	actor._attack_timer=0.0
	before=actor._hc_starts
	check(not actor._hc_try_start(player) and actor._attack_timer==0.0 and actor._hc_starts==before,"O01-cooldown","Blocked start does not consume cooldown")
	front.set_combat_position(ground_to_screen(Vector2(25,25)),&"hc_test_position")
	check(actor._hc_access(player)=="CLEAR","O06-runtime","Moved front actor invalidates dynamic blockage without endpoint movement")
	# The live spatial-index transaction owns one exact projection snapshot.
	# Repeated narrow phases may reuse it, but map/projection/revision changes at
	# the same screen position must force a new formal projection.
	projection_probe_calls=0
	front.configure_runtime_map_projection(1,Callable(self,"ground_to_screen"),Callable(self,"counted_screen_to_ground"))
	front.set_combat_position(front.global_position,&"hc_projection_cache_setup")
	var cached_ground:=front.spatial_index_position()
	check(projection_probe_calls==1 and cached_ground==Vector2(25,25),"O06-cache","Unchanged indexed position reuses its formal projection snapshot")
	front.configure_runtime_map_projection(2,Callable(self,"ground_to_screen"),Callable(self,"counted_screen_to_ground"))
	check(front.spatial_index_position()==Vector2(25,25) and projection_probe_calls==2,"O06-map","Same screen position on another map invalidates the projection snapshot")
	front.configure_runtime_map_projection(2,Callable(self,"ground_to_screen"),Callable(self,"shifted_screen_to_ground"))
	check(front.spatial_index_position()==Vector2(28,29) and projection_probe_calls==3,"O06-projection","Changed formal projection cannot reuse an old ground position")
	var revision_provider:=RevisionProvider.new()
	add_child(revision_provider)
	front.environment_blocker=revision_provider
	front.set_combat_position(front.global_position,&"hc_projection_revision_setup")
	var calls_before_revision:=projection_probe_calls
	revision_provider.revision+=1
	check(front.spatial_index_position()==Vector2(28,29) and projection_probe_calls==calls_before_revision+1,"O06-revision","Projection context revision invalidates the same-position snapshot")
	revision_provider.queue_free()
	front.environment_blocker=null
	var projection_provider:=ProjectionProvider.new()
	add_child(projection_provider)
	front.configure_runtime_map_projection(1,Callable(self,"ground_to_screen"),Callable(projection_provider,"project"))
	front.set_combat_position(front.global_position,&"hc_projection_provider_setup")
	check(front.spatial_index_position()==Vector2(25,25),"O06-provider-setup","Live bound projection establishes an indexed snapshot")
	projection_provider.free()
	check(front.spatial_index_position()==Vector2.INF,"O06-provider-freed","Freed projection provider rejects its stale finite indexed snapshot")
	front.configure_runtime_map_projection(1,Callable(self,"ground_to_screen"),Callable(self,"screen_to_ground"))
	front.set_combat_position(ground_to_screen(Vector2(21,20)),&"hc_test_position")
	front.current_hp=0
	front._death_pending=true
	check(actor._hc_access(player)=="CLEAR","O07-runtime","Dead/pending-death front is not cover")
	index.unregister(front.spatial_actor_runtime_id)
	front.queue_free()
	actor.set_combat_position(ground_to_screen(Vector2(25,25)),&"hc_test_position")
	# C07: two legal front/rear lanes and a diagonal corner use the same live
	# spatial-index authority. Every witness is outside physical overlap.
	var rear_a:=make_enemy(Vector2(21.85,19.3))
	var front_a:=make_enemy(Vector2(21.1,19.6))
	var rear_b:=make_enemy(Vector2(21.85,20.7))
	var front_b:=make_enemy(Vector2(21.1,20.4))
	check(rear_a._hc_access(player)=="FRONTLINE_BLOCKED","C07-row-a","First legal front row blocks only through the live index")
	check(rear_b._hc_access(player)=="FRONTLINE_BLOCKED","C07-row-b","Second legal front row blocks in the same bounded query")
	front_a.set_combat_position(ground_to_screen(Vector2(25,24)),&"hc_test_position")
	check(rear_a._hc_access(player)=="CLEAR" and rear_b._hc_access(player)=="FRONTLINE_BLOCKED","C07-row-independent","Moving one front row clears that lane without invalidating the other")
	rear_a.set_combat_position(ground_to_screen(Vector2(26,24)),&"hc_test_position")
	rear_b.set_combat_position(ground_to_screen(Vector2(27,24)),&"hc_test_position")
	front_b.set_combat_position(ground_to_screen(Vector2(28,24)),&"hc_test_position")
	var corner_rear:=make_enemy(Vector2(21.4,21.4))
	var corner_front:=make_enemy(Vector2(20.75,20.75))
	check(corner_rear._hc_access(player)=="FRONTLINE_BLOCKED","C07-corner","Diagonal corner front body blocks the rear attacker")
	corner_front.set_combat_position(ground_to_screen(Vector2(20.5,22.0)),&"hc_test_position")
	check(corner_rear._hc_access(player)=="CLEAR","C07-corner-open","Moving the corner body off-lane immediately clears the rear attacker")
	for witness:EnemyActor in [rear_a,front_a,rear_b,front_b,corner_rear,corner_front]:
		index.unregister(witness.spatial_actor_runtime_id)
		witness.queue_free()
	# Pending attack is bound to target life. Revive-like epoch changes cancel it.
	await get_tree().physics_frame
	actor._attack_timer=0.0
	actor._attack_hit_delay=0.05
	actor.set_combat_position(ground_to_screen(Vector2(21.5,20)),&"hc_test_position")
	check(actor._hc_try_start(player),"T08-start","Delayed fixture accepts one release")
	var settlements:=actor._hc_settlements
	check(player.begin_combat_transition("hc-lifetime-test"),"T08-life-begin","Formal transition begins a new combat epoch")
	check(player.finish_combat_transition("hc-lifetime-test"),"T08-life-ready","Formal transition returns to READY before old impact")
	actor._update_pending_attack(0.10)
	check(actor._hc_settlements==settlements,"T08-life","Old release cannot hit a new target life epoch")
	# A local failed step retains legal actual position rather than rewinding.
	# A09 validates the HC-owned movement failure path. Generic direct movement
	# failure intentionally retains the legacy rollback contract and is covered by
	# monster_cadence_blocked_step_test.
	actor._movement_step_start_screen_px=ground_to_screen(Vector2(25,20))
	actor._movement_step_target_ground_gu=Vector2(21,20)
	var legal_position:=actor.global_position
	actor._hc_owned_movement_call = true
	actor._fail_autonomous_step_blocked()
	actor._hc_owned_movement_call = false
	check(actor.global_position==legal_position,"A09-retain","Failure handler retains current legal position")
	check(actor.target==player,"A08-target","Movement failure does not delete target")
	actor.take_damage(1,player)
	check(actor._hc_damage_dirty,"A03-dirty","Legal source event requests a next-tick decision")
	actor.control_time=0.2
	check(actor._hc_access(player)=="ACTION_LOCKED","T07-control","Early attack entry cannot bypass control")
	# C01: HC ownership flag must never leak outside _hc_tick_melee.
	check(not actor._hc_owned_movement_call,"C01-flag","Ownership flag is false after the HC tick path exits")
	index.unregister(actor.spatial_actor_runtime_id)
	actor.queue_free()
	# --- C02: production attack timers remain active while the residual close
	# debt converges. No cooldown, pending state or position is rewritten after
	# each window begins.
	# ID162 is exact TATMonster/race81 with no attack override: it preserves a
	# real ordinary-contact Boss lane after ID76 adopts CowKing mixed delivery.
	for monster_id: int in [64,162]:
		for start_distance: float in [1.8,1.99,2.0]:
			await _assert_outer_ring_real_cadence(monster_id,start_distance)
	# --- C03: pending victim A stays the only settle target after retarget or death ---
	await get_tree().physics_frame
	var player_b:=PlayerCharacter.new()
	player_b.name="RuntimePlayerB"
	player_b.global_position=ground_to_screen(Vector2(21.5,21.5))
	player_b.set_meta("runtime_map_id",1)
	player_b.set_meta("zone_generation",1)
	add_child(player_b)
	player_b.set_physics_process(false)
	player_b.max_hp=1000000
	player_b.current_hp=player_b.max_hp
	await get_tree().physics_frame
	var witness_actor:=make_enemy(Vector2(21.5,20))
	witness_actor._attack_timer=0.0
	witness_actor._attack_hit_delay=0.0
	var witness_hp:=player_b.current_hp
	check(witness_actor._hc_try_start(player_b),"C03-B-control-start","B is inside the legal 2 GU start band")
	check(player_b.current_hp<witness_hp,"C03-B-control-hit","B can receive a legal hit in the witness geometry")
	index.unregister(witness_actor.spatial_actor_runtime_id)
	witness_actor.queue_free()
	var retarget_actor:=make_enemy(Vector2(21.5,20))
	retarget_actor._attack_timer=0.0
	retarget_actor._attack_hit_delay=0.05
	check(retarget_actor._hc_try_start(player),"C03-start","Start binds pending victim A")
	check(retarget_actor._pending_attack_target==player,"C03-victim","Pending victim is player A")
	retarget_actor.target=player_b
	retarget_actor.primary_target=player_b
	retarget_actor._retarget(0.0)
	check(retarget_actor.target==player_b,"C03-retarget-owner","Production retarget owner keeps B selected")
	check(retarget_actor._pending_attack_target==player,"C03-retarget","Retarget to B does not rewrite the pending victim")
	var a_hp:=player.current_hp
	var b_hp:=player_b.current_hp
	retarget_actor._update_pending_attack(0.10)
	check(player.current_hp<a_hp and player_b.current_hp==b_hp,"C03-settle","Settle hits victim A only, B untouched")
	index.unregister(retarget_actor.spatial_actor_runtime_id)
	retarget_actor.queue_free()
	# C03-dead: fresh actor, fresh release bound to A; A dies before the hit
	# frame. The accepted release settles against A's record only, never B.
	await get_tree().physics_frame
	var death_actor:=make_enemy(Vector2(21.5,20))
	death_actor._attack_timer=0.0
	death_actor._attack_hit_delay=0.05
	player.current_hp=player.max_hp
	check(death_actor._hc_try_start(player),"C03-start-dead","Fresh release binds victim A")
	player.current_hp=0
	death_actor.target=player_b
	death_actor.primary_target=player_b
	death_actor._retarget(0.0)
	check(death_actor.target==player_b,"C03-dead-retarget","A death selects legal witness B")
	b_hp=player_b.current_hp
	death_actor._update_pending_attack(0.10)
	check(player_b.current_hp==b_hp,"C03-dead","A death cannot redirect the accepted release to B")
	player.current_hp=player.max_hp
	index.unregister(death_actor.spatial_actor_runtime_id)
	death_actor.queue_free()
	var generation_actor:=make_enemy(Vector2(21.5,20))
	generation_actor._attack_timer=0.0
	generation_actor._attack_hit_delay=0.05
	check(generation_actor._hc_try_start(player),"C03-generation-start","Generation fixture freezes A")
	a_hp=player.current_hp
	generation_actor.set_meta("zone_generation",2)
	generation_actor._update_pending_attack(0.10)
	check(player.current_hp==a_hp,"C03-generation","Old map generation release is rejected")
	index.unregister(generation_actor.spatial_actor_runtime_id)
	generation_actor.queue_free()
	player_b.queue_free()
	# --- C04: static navigation blocked-cell fixture; final position/flag only ---
	await get_tree().physics_frame
	var wall_actor:=make_enemy(Vector2(23.5,20))
	var wall_context:Dictionary=open_context()
	wall_context["blocked_cells"]={Vector2i(22,20):true,Vector2i(21,20):true}
	wall_actor.configure_terrain_navigation_context(wall_context)
	var wall_spawn:=wall_actor.global_position
	for frame in range(30):
		await get_tree().physics_frame
		wall_actor._physics_process_internal(1.0/60.0)
	check(not wall_actor._hc_owned_movement_call,"C04-flag","Ownership flag restored after every HC tick")
	check(screen_to_ground(wall_actor.global_position).distance_to(screen_to_ground(wall_spawn))<=1.0,"C04-wall","HC actor final position stays before the blocked navigation cells")
	index.unregister(wall_actor.spatial_actor_runtime_id)
	wall_actor.queue_free()
	# --- C05: static blocked-cell detour with production neighbour pursuit ---
	await get_tree().physics_frame
	var detour_actor:=make_enemy(Vector2(24.5,20))
	var detour_context:Dictionary=open_context()
	detour_context["blocked_cells"]={Vector2i(22,20):true}
	detour_actor.configure_terrain_navigation_context(detour_context)
	detour_actor._attack_timer=999.0
	for frame in range(420):
		await get_tree().physics_frame
		detour_actor._physics_process_internal(1.0/60.0)
	var detour_dist:=screen_to_ground(detour_actor.global_position).distance_to(Vector2(20,20))
	check(detour_dist<=detour_actor._hc_preferred(player)+0.003,"C05-reach","HC actor detours around the wall to the legal contact position (%.3f)"%detour_dist)
	check(screen_to_ground(detour_actor.global_position).floor()!=Vector2(22,20),"C05-final-cell","HC actor final cell is outside the blocked navigation cell")
	index.unregister(detour_actor.spatial_actor_runtime_id)
	detour_actor.queue_free()
	finish("runtime")


func _assert_outer_ring_real_cadence(monster_id: int,start_distance: float) -> void:
	await get_tree().physics_frame
	var cadence_actor:=make_enemy(Vector2(20.0+start_distance,20.0),monster_id)
	check(cadence_actor._hc_standard_melee(),"C02-channel-%d-%.2f"%[monster_id,start_distance],"Exact actor uses the ordinary HC physical channel")
	cadence_actor._attack_timer=0.0
	var starts_before:=cadence_actor._hc_starts
	var settlements_before:=cadence_actor._hc_settlements
	var hp_before:=player.current_hp
	var last_starts:=cadence_actor._hc_starts
	var release_distances:Array[float]=[]
	var trace:Array[float]=[]
	for frame in range(240):
		await get_tree().physics_frame
		cadence_actor._physics_process_internal(1.0/60.0)
		var distance:=screen_to_ground(cadence_actor.global_position).distance_to(Vector2(20,20))
		trace.append(distance)
		if cadence_actor._hc_starts>last_starts:
			release_distances.append(distance)
			last_starts=cadence_actor._hc_starts
	var starts_delta:=cadence_actor._hc_starts-starts_before
	var settlements_delta:=cadence_actor._hc_settlements-settlements_before
	var preferred:=cadence_actor._hc_preferred(player)
	var final_distance:=trace[-1] if not trace.is_empty() else INF
	check(starts_delta>=2,"C02-starts-%d-%.2f"%[monster_id,start_distance],"Real timer produces repeated starts (got %d)"%starts_delta)
	check(settlements_delta>=1 and player.current_hp<hp_before,"C02-damage-%d-%.2f"%[monster_id,start_distance],"Real releases settle and change HP")
	check(not release_distances.is_empty() and release_distances[0]>preferred+GU.EPSILON_GU,"C02-outer-start-%d-%.2f"%[monster_id,start_distance],"First real attack starts outside preferred contact")
	check(final_distance<=preferred+0.003,"C02-converge-%d-%.2f"%[monster_id,start_distance],"Real cadence closes %.2f GU to effective preferred %.3f (final %.3f)"%[start_distance,preferred,final_distance])
	check(trace.min()>=cadence_actor._contact_distance_gu_to_target(player)-0.003,"C02-no-overlap-%d-%.2f"%[monster_id,start_distance],"Closing cadence never overlaps the legal actor footprint")
	index.unregister(cadence_actor.spatial_actor_runtime_id)
	cadence_actor.queue_free()
