extends "res://tests/hc_monster_ai/test_support.gd"
const Terrain := preload("res://scripts/monster_terrain_navigation_policy.gd")
const Search := preload("res://scripts/monster_ai_package/path_search.gd")
const Scheduler := preload("res://scripts/monster_ai_package/path_scheduler.gd")
const GU := preload("res://scripts/ground_unit_space.gd")

class JobOwner:
	extends Node
	var completed := false
	var status := ""
	var callback_count := 0
	func _hc_path_job_current(token: int) -> bool:
		return token == 1
	func _hc_path_completed(_token: int, state: String, _path: PackedVector2Array) -> void:
		completed = true
		status = state
		callback_count += 1

class RevisionProvider:
	extends Node2D
	var revision := 0
	func environment_collision_revision() -> int:
		return revision

class ReferenceSearch:
	extends Search
	static func reference_less(a: Array, b: Array) -> bool:
		for index in range(4):
			if a[index] < b[index]:
				return true
			if a[index] > b[index]:
				return false
		return false
	func _push(item: Array) -> void:
		heap.append(item)
		var index := heap.size() - 1
		while index > 0:
			var up: int = (index - 1) >> 1
			if not reference_less(heap[index], heap[up]):
				break
			var swap: Array = heap[index]
			heap[index] = heap[up]
			heap[up] = swap
			index = up
	func _pop() -> Array:
		var first: Array = heap[0]
		var last: Array = heap.pop_back()
		if heap.is_empty():
			return first
		heap[0] = last
		var index := 0
		while true:
			var left := index * 2 + 1
			if left >= heap.size():
				break
			var right := left + 1
			var best := left
			if right < heap.size() and reference_less(heap[right], heap[left]):
				best = right
			if not reference_less(heap[best], heap[index]):
				break
			var swap: Array = heap[index]
			heap[index] = heap[best]
			heap[best] = swap
			index = best
		return first

func context(blocked: Dictionary = {}) -> Dictionary:
	return {"valid":true,"contract_id":Terrain.CONTRACT_ID,"runtime_map_id":1,
		"build_sha256":"a".repeat(64),"coordinate_contract_id":Terrain.EXPECTED_GROUND_COORDINATE_CONTRACT_ID,
		"design_size":Vector2i(16,16),"blocked_cells":blocked}

func readonly_context(blocked: Dictionary = {}) -> Dictionary:
	var frozen_blocked := blocked.duplicate()
	frozen_blocked.make_read_only()
	var frozen := context(frozen_blocked)
	frozen.make_read_only()
	return frozen

func readonly_context_sized(size: Vector2i, blocked: Dictionary = {}) -> Dictionary:
	var frozen_blocked := blocked.duplicate()
	frozen_blocked.make_read_only()
	var frozen := {"valid":true,"contract_id":Terrain.CONTRACT_ID,"runtime_map_id":1,
		"build_sha256":"b".repeat(64),"coordinate_contract_id":Terrain.EXPECTED_GROUND_COORDINATE_CONTRACT_ID,
		"design_size":size,"blocked_cells":frozen_blocked}
	frozen.make_read_only()
	return frozen

func solve(search: Search, slice_size: int) -> void:
	for index in range(1000):
		if search.state != "SEARCHING":
			return
		var previous := search.expansions
		search.advance(slice_size)
		check(search.expansions-previous<=slice_size,"A16-%d"%index,"Bounded expansion slice")
	check(false,"A16-timeout","Reference graph did not finish")

func path_cost(from_cell: Vector2i, route: PackedVector2Array) -> float:
	var previous := Vector2(from_cell) + Vector2(.5,.5)
	var total := 0.0
	for point: Vector2 in route:
		total += previous.distance_to(point)
		previous = point
	return total

func no_failed_edge(_from: Vector2i, _to: Vector2i) -> bool:
	return false

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var search := Search.new()
	var goals := {Vector2i(8,8):Vector2(8.5,8.5)}
	search.configure(context(),Vector2i(1,1),goals,.35,Callable())
	solve(search,1)
	check(search.state=="FOUND" and search.path[-1]==Vector2(8.5,8.5),"A11-basic","Incremental search reaches exact goal")
	# Two compatible jobs share one bounded reverse static field. It preserves
	# shortest cost and exact endpoint values while a discarded third request
	# cannot cancel progress owned by the remaining jobs.
	var shared_blocked:Dictionary={}
	for y in range(11): shared_blocked[Vector2i(4,y)]=true
	var shared_context:=readonly_context(shared_blocked)
	var shared_scope:Array=["map1","provider1",7]
	var shared_goals:Dictionary={Vector2i(8,2):Vector2(8.5,2.5)}
	var shared_a:=Search.new()
	var shared_b:=Search.new()
	var shared_cancelled:=Search.new()
	for spec:Array in [[shared_a,Vector2i(2,2)],[shared_b,Vector2i(2,8)],[shared_cancelled,Vector2i(2,5)]]:
		var candidate:Search=spec[0]
		candidate.configure(shared_context,spec[1],shared_goals,.35,Callable())
		candidate.shared_static_scope=shared_scope
		candidate._try_attach_shared_goal_field()
	check(shared_a.shared_goal_field==shared_b.shared_goal_field and shared_b.shared_goal_field==shared_cancelled.shared_goal_field,"A-field-exact-share","Compatible jobs attach one exact static goal field")
	shared_cancelled.detach_shared_goal_field()
	shared_cancelled=null
	for field_step in range(1000):
		if shared_a.state=="SEARCHING": shared_a.advance(16,0)
		if shared_b.state=="SEARCHING": shared_b.advance(16,0)
		if shared_a.state!="SEARCHING" and shared_b.state!="SEARCHING": break
	check(shared_a.state=="FOUND" and shared_b.state=="FOUND","A-field-cancel-progress","Cancelled peer does not stop compatible live jobs")
	for spec:Array in [[shared_a,Vector2i(2,2)],[shared_b,Vector2i(2,8)]]:
		var reference:=ReferenceSearch.new()
		reference.configure(context(shared_blocked),spec[1],shared_goals,.35,Callable())
		solve(reference,384)
		check(is_equal_approx(path_cost(spec[1],(spec[0] as Search).path),path_cost(spec[1],reference.path)),"A-field-shortest-%d"%spec[1].y,"Shared reverse field retains original shortest cost")
		check((spec[0] as Search).path[-1]==shared_goals[Vector2i(8,2)],"A-field-endpoint-%d"%spec[1].y,"Shared route retains exact mapped endpoint")
	# Reaching one registered start must settle all of that cell's outgoing
	# edges before rotating. Otherwise the first start becomes an artificial
	# cut in a one-cell corridor and the second request is falsely unreachable.
	var corridor_blocked:Dictionary={}
	for x in range(10):
		corridor_blocked[Vector2i(x,0)]=true
		corridor_blocked[Vector2i(x,2)]=true
	var corridor_context:=readonly_context_sized(Vector2i(10,3),corridor_blocked)
	var corridor_goal:Dictionary={Vector2i(1,1):Vector2(1.5,1.5)}
	var corridor_first:=Search.new()
	var corridor_second:=Search.new()
	for spec:Array in [[corridor_first,Vector2i(4,1)],[corridor_second,Vector2i(7,1)]]:
		var candidate:Search=spec[0]
		candidate.configure(corridor_context,spec[1],corridor_goal,.35,Callable())
		candidate.shared_static_scope=["corridor",1]
		candidate._try_attach_shared_goal_field()
	for field_step in range(100):
		if corridor_first.state=="SEARCHING":corridor_first.advance(1,0)
		if corridor_second.state=="SEARCHING":corridor_second.advance(1,0)
		if corridor_first.state!="SEARCHING" and corridor_second.state!="SEARCHING":break
	for spec:Array in [[corridor_first,Vector2i(4,1)],[corridor_second,Vector2i(7,1)]]:
		var reference:=ReferenceSearch.new()
		reference.configure(context(corridor_blocked),spec[1],corridor_goal,.35,Callable())
		solve(reference,384)
		check((spec[0] as Search).state=="FOUND","A-field-corridor-state-%d"%spec[1].x,"Both corridor starts remain reachable through the earlier settled start")
		check(is_equal_approx(path_cost(spec[1],(spec[0] as Search).path),path_cost(spec[1],reference.path)),"A-field-corridor-cost-%d"%spec[1].x,"Shared corridor route matches independent A star shortest cost")
	var mapped_goal:=Search.new()
	mapped_goal.configure(shared_context,Vector2i(2,3),{Vector2i(8,2):Vector2(8.75,2.5)},.35,Callable())
	mapped_goal.shared_static_scope=shared_scope
	mapped_goal._try_attach_shared_goal_field()
	check(mapped_goal.shared_goal_field!=shared_a.shared_goal_field,"A-field-goal-value","Same goal cell with different exact endpoint never aliases")
	var changed_context_search:=Search.new()
	changed_context_search.configure(readonly_context({Vector2i(5,5):true}),Vector2i(2,2),shared_goals,.35,Callable())
	changed_context_search.shared_static_scope=shared_scope
	changed_context_search._try_attach_shared_goal_field()
	check(changed_context_search.shared_goal_field!=shared_a.shared_goal_field,"A-field-context","Changed immutable map snapshot never aliases")
	var changed_scope_search:=Search.new()
	changed_scope_search.configure(shared_context,Vector2i(2,2),shared_goals,.35,Callable())
	changed_scope_search.shared_static_scope=["map1","provider1",8]
	changed_scope_search._try_attach_shared_goal_field()
	check(changed_scope_search.shared_goal_field!=shared_a.shared_goal_field,"A-field-revision","Changed provider revision never aliases")
	var changed_radius_search:=Search.new()
	changed_radius_search.configure(shared_context,Vector2i(2,2),shared_goals,.76,Callable())
	changed_radius_search.shared_static_scope=shared_scope
	changed_radius_search._try_attach_shared_goal_field()
	check(changed_radius_search.shared_goal_field!=shared_a.shared_goal_field,"A-field-radius","Changed footprint never aliases")
	var failed_edge_search:=Search.new()
	failed_edge_search.configure(shared_context,Vector2i(2,2),shared_goals,.35,Callable(self,"no_failed_edge"))
	failed_edge_search.shared_static_scope=shared_scope
	failed_edge_search._try_attach_shared_goal_field()
	check(failed_edge_search.shared_goal_field==null,"A-field-dynamic-fallback","Any actor-specific failed-edge filter uses independent A star")
	var blocked_start_context:=readonly_context({Vector2i(2,2):true})
	var blocked_start_search:=Search.new()
	blocked_start_search.configure(blocked_start_context,Vector2i(2,2),shared_goals,.35,Callable())
	blocked_start_search.shared_static_scope=shared_scope
	blocked_start_search._try_attach_shared_goal_field()
	check(blocked_start_search.shared_goal_field==null,"A-field-start-fallback","Unwalkable start uses the existing independent path result")
	var closed_context:=readonly_context_sized(Vector2i(16,16),{})
	var closed_mutable:Dictionary={}
	for y in range(16): closed_mutable[Vector2i(7,y)]=true
	closed_context=readonly_context_sized(Vector2i(16,16),closed_mutable)
	var no_route_a:=Search.new()
	var no_route_b:=Search.new()
	for candidate:Search in [no_route_a,no_route_b]:
		candidate.configure(closed_context,Vector2i(2,2),{Vector2i(12,2):Vector2(12.5,2.5)},.35,Callable())
		candidate.shared_static_scope=["closed",1]
		candidate._try_attach_shared_goal_field()
	for field_step in range(1000):
		if no_route_a.state=="SEARCHING": no_route_a.advance(32,0)
		if no_route_b.state=="SEARCHING": no_route_b.advance(32,0)
		if no_route_a.state!="SEARCHING" and no_route_b.state!="SEARCHING": break
	check(no_route_a.state=="NO_ROUTE_FOR_CURRENT_GRAPH" and no_route_b.state=="NO_ROUTE_FOR_CURRENT_GRAPH","A-field-no-route","Exhausted shared static graph reports terminal no route")
	var large_context:=readonly_context_sized(Vector2i(100,100),{})
	var capacity_a:=Search.new()
	var capacity_b:=Search.new()
	for candidate:Search in [capacity_a,capacity_b]:
		candidate.configure(large_context,Vector2i(99,99),{Vector2i(0,0):Vector2(.5,.5)},.35,Callable())
		candidate.shared_static_scope=["large",1]
		candidate._try_attach_shared_goal_field()
	for field_step in range(1000):
		if capacity_a.state=="SEARCHING": capacity_a.advance(384,0)
		if capacity_b.state=="SEARCHING": capacity_b.advance(384,0)
		if capacity_a.state!="SEARCHING" and capacity_b.state!="SEARCHING": break
	check(capacity_a.state=="FOUND" and capacity_b.state=="FOUND","A-field-capacity-fallback","Shared field capacity falls back to independent bounded A star")
	check(Search.shared_goal_fields.size()<=Search.MAX_SHARED_GOAL_FIELDS,"A-field-cache-bounded","Shared field count is strictly bounded")
	# Scheduler cancellation removes the live request registration. A cancelled
	# unreachable priority start must not keep owning service or count as a peer.
	var cancel_scheduler:=Scheduler.new()
	add_child(cancel_scheduler)
	cancel_scheduler.set_physics_process(false)
	var cancel_blocked:Dictionary={}
	for y in range(16):cancel_blocked[Vector2i(3,y)]=true
	var cancel_context:=readonly_context_sized(Vector2i(16,16),cancel_blocked)
	var cancel_goals:Dictionary={Vector2i(10,5):Vector2(10.5,5.5)}
	var cancel_owners:Array[JobOwner]=[]
	var cancel_searches:Array[Search]=[]
	for start_cell:Vector2i in [Vector2i(2,1),Vector2i(5,5),Vector2i(5,7)]:
		var owner:=JobOwner.new()
		add_child(owner)
		cancel_owners.append(owner)
		var candidate:=Search.new()
		candidate.configure(cancel_context,start_cell,cancel_goals,.35,Callable())
		candidate.shared_static_scope=["cancel",1]
		candidate._try_attach_shared_goal_field()
		cancel_searches.append(candidate)
		cancel_scheduler.submit(owner,1,candidate)
	var cancel_field=cancel_searches[0].shared_goal_field
	check(cancel_field.active_start==Vector2i(2,1),"A-field-cancel-priority","Unreachable first start initially owns the deterministic priority")
	cancel_scheduler.cancel(cancel_owners[0].get_instance_id())
	check(cancel_field.attached_searches==2 and not cancel_field.registered_starts.has(Vector2i(2,1)),"A-field-cancel-detach","Cancellation removes its active start registration and peer count")
	for frame in range(30):
		await get_tree().physics_frame
		cancel_scheduler.pump(0)
		if cancel_owners[1].completed and cancel_owners[2].completed:break
	check(not cancel_owners[0].completed and cancel_owners[1].status=="FOUND" and cancel_owners[2].status=="FOUND","A-field-cancel-live-progress","Cancelled unreachable request cannot delay the remaining reachable requests")
	check(cancel_scheduler.jobs.is_empty(),"A-field-cancel-drain","Cancellation and live completions leave no scheduler jobs")
	for owner:JobOwner in cancel_owners:owner.queue_free()
	cancel_scheduler.queue_free()
	# Optimized heap operations retain the exact original f/g/y/x tie-break.
	var random := RandomNumberGenerator.new()
	random.seed = 0xA57A2026
	for graph_index in range(24):
		var random_blocked: Dictionary = {}
		for y in range(1, 15):
			for x in range(1, 15):
				if random.randf() < 0.16:
					random_blocked[Vector2i(x,y)] = true
		var random_start := Vector2i(1 + graph_index % 3, 1 + graph_index % 5)
		var random_goal := Vector2i(14 - graph_index % 4, 14 - graph_index % 3)
		random_blocked.erase(random_start)
		random_blocked.erase(random_goal)
		var optimized := Search.new()
		var reference := ReferenceSearch.new()
		var random_goals := {random_goal: Vector2(random_goal) + Vector2(.5,.5)}
		optimized.configure(context(random_blocked),random_start,random_goals,.35,Callable())
		reference.configure(context(random_blocked),random_start,random_goals,.35,Callable())
		solve(optimized,384)
		solve(reference,384)
		check(optimized.state==reference.state,"A-heap-state-%d"%graph_index,"Optimized heap preserves terminal state")
		check(optimized.expansions==reference.expansions,"A-heap-expansions-%d"%graph_index,"Optimized heap preserves exact expansion count")
		check(optimized.path==reference.path,"A-heap-path-%d"%graph_index,"Optimized heap preserves exact route")
		var field_start_b:=Vector2i(1,14-graph_index%5)
		random_blocked.erase(field_start_b)
		var field_context:=readonly_context(random_blocked)
		var field_a:=Search.new()
		var field_b:=Search.new()
		for spec:Array in [[field_a,random_start],[field_b,field_start_b]]:
			var candidate:Search=spec[0]
			candidate.configure(field_context,spec[1],random_goals,.35,Callable())
			candidate.shared_static_scope=["random",graph_index]
			candidate._try_attach_shared_goal_field()
		for field_step in range(1000):
			if field_a.state=="SEARCHING": field_a.advance(32,0)
			if field_b.state=="SEARCHING": field_b.advance(32,0)
			if field_a.state!="SEARCHING" and field_b.state!="SEARCHING": break
		for spec:Array in [[field_a,random_start],[field_b,field_start_b]]:
			var field_reference:=ReferenceSearch.new()
			field_reference.configure(context(random_blocked),spec[1],random_goals,.35,Callable())
			solve(field_reference,384)
			check((spec[0] as Search).state==field_reference.state,"A-field-random-state-%d-%d"%[graph_index,spec[1].y],"Shared field preserves random graph reachability")
			if field_reference.state=="FOUND":
				check(is_equal_approx(path_cost(spec[1],(spec[0] as Search).path),path_cost(spec[1],field_reference.path)),"A-field-random-cost-%d-%d"%[graph_index,spec[1].y],"Shared field preserves random graph shortest cost")
	var blocked: Dictionary = {}
	for y in range(11):
		blocked[Vector2i(4,y)] = true
	search.configure(context(blocked),Vector2i(2,2),{Vector2i(7,2):Vector2(7.5,2.5)},.35,Callable())
	solve(search,16)
	check(search.state=="FOUND","A14","Detour can initially move away from target")
	var detoured := false
	for point: Vector2 in search.path:
		if point.y>10.0:
			detoured=true
	check(detoured,"A14-route","Path goes around the wall end")
	for y in range(16):
		blocked[Vector2i(4,y)]=true
	search.configure(context(blocked),Vector2i(2,2),{Vector2i(7,2):Vector2(7.5,2.5)},.35,Callable())
	solve(search,16)
	check(search.state=="NO_ROUTE_FOR_CURRENT_GRAPH","A23","Exhausted graph is distinguishable from budget wait")
	search.configure(context(),Vector2i(1,1),{},.35,Callable())
	check(search.state=="NO_VALID_GOAL_IN_CURRENT_SAMPLE","A13","No goal samples is not a global no-path proof")
	search.configure({},Vector2i(1,1),goals,.35,Callable())
	check(search.state=="INVALID_CONTEXT","A-context","Missing navigation authority fails closed")
	# Shared heuristic memoization is keyed by the complete sorted goal cells,
	# rather than a collision-prone aggregate hash, and each set stays bounded.
	var same_goals := Search.new()
	same_goals.configure(context(),Vector2i(2,1),goals,.35,Callable())
	check(is_same(search.heuristic_cache, same_goals.heuristic_cache)==false,"A-heuristic-invalid-not-shared","Invalid search has no shared heuristic state")
	search.configure(context(),Vector2i(1,1),goals,.35,Callable())
	same_goals.configure(context(),Vector2i(2,1),goals,.35,Callable())
	check(is_same(search.heuristic_cache, same_goals.heuristic_cache),"A-heuristic-exact-share","Exact goal sets share nearest-goal cells")
	var nearby_goals := Search.new()
	nearby_goals.configure(context(),Vector2i(2,1),{Vector2i(8,9):Vector2(8.5,9.5)},.35,Callable())
	check(not is_same(search.heuristic_cache, nearby_goals.heuristic_cache),"A-heuristic-nearby-isolated","Nearby but unequal goal sets never alias")
	for cell_index in range(Search.MAX_SHARED_HEURISTIC_CELLS_PER_SET + 1):
		search._heuristic(Vector2i(cell_index,0))
	check(search.heuristic_cache.size()<=Search.MAX_SHARED_HEURISTIC_CELLS_PER_SET,"A-heuristic-bounded","Shared goal set cell memo is strictly bounded")
	# Static footprint checks may share only an exact deeply read-only authored
	# context and radius. Dynamic edge occupancy remains a separate callback.
	var frozen_context_a := readonly_context({Vector2i(4, 4): true})
	var frozen_context_b := readonly_context({Vector2i(4, 4): true})
	var frozen_context_changed := readonly_context({Vector2i(4, 5): true})
	var walk_a := Search.new()
	var walk_b := Search.new()
	var walk_changed := Search.new()
	var walk_radius := Search.new()
	walk_a.configure(frozen_context_a,Vector2i(1,1),goals,.35,Callable())
	walk_b.configure(frozen_context_b,Vector2i(2,1),goals,.35,Callable())
	walk_changed.configure(frozen_context_changed,Vector2i(2,1),goals,.35,Callable())
	walk_radius.configure(frozen_context_a,Vector2i(2,1),goals,.76,Callable())
	check(is_same(walk_a.walkable_cache,walk_b.walkable_cache),"A-walkable-exact-share","Exact immutable map snapshot and footprint share static cells")
	check(not is_same(walk_a.walkable_cache,walk_changed.walkable_cache),"A-walkable-context-isolated","Changed authored cells never reuse static walkability")
	check(not is_same(walk_a.walkable_cache,walk_radius.walkable_cache),"A-walkable-radius-isolated","Different actor footprints never reuse static walkability")
	# HC per-tick static caches partition map/revision/projection and actor-local
	# safe-zone contexts. These negative keys prevent cross-authority reuse.
	var provider := RevisionProvider.new()
	add_child(provider)
	var cache_a := EnemyActor.new()
	var cache_b := EnemyActor.new()
	cache_a.monster_id=64
	cache_b.monster_id=64
	add_child(cache_a)
	add_child(cache_b)
	for actor:EnemyActor in [cache_a,cache_b]:
		actor.environment_blocker=provider
		actor.configure_runtime_map_projection(1,Callable(self,"_ground_to_screen"),Callable(self,"_screen_to_ground"))
		actor.set_meta("zone_generation",7)
	var scope_a:Array=cache_a._hc_static_query_scope(false)
	var scope_lookup:Dictionary={scope_a:true}
	check(scope_lookup.has(cache_b._hc_static_query_scope(false)),"A-cache-exact-share","Equal projection authority shares the exact scope key")
	provider.revision=1
	var scope_revision:Array=cache_a._hc_static_query_scope(false)
	check(scope_a!=scope_revision,"A-cache-revision","WORLD cache rejects same-tick revision replacement")
	provider.revision=0
	cache_b.runtime_map_id=2
	check(scope_a!=cache_b._hc_static_query_scope(false),"A-cache-map","WORLD cache rejects same-tick map replacement")
	cache_b.runtime_map_id=1
	cache_b.runtime_ground_gu_to_screen_position_px=Callable(self,"_alternate_ground_to_screen")
	check(scope_a!=cache_b._hc_static_query_scope(false),"A-cache-projection","WORLD cache rejects same-tick projection replacement")
	cache_b.runtime_ground_gu_to_screen_position_px=Callable(self,"_ground_to_screen")
	var goal_target:=Node2D.new()
	goal_target.global_position=_ground_to_screen(Vector2(8.5,8.5))
	add_child(goal_target)
	var exact_goal_context:=readonly_context()
	for actor:EnemyActor in [cache_a,cache_b]:
		actor.target=goal_target
		actor.combat_radius_gu=.35
		actor.configure_terrain_navigation_context(exact_goal_context)
	var goal_cache_key_a:Array=cache_a._hc_goal_cache_key(Vector2(8.5,8.5),true)
	check(goal_cache_key_a==cache_b._hc_goal_cache_key(Vector2(8.5,8.5),true),"A-goal-cache-exact-share","Exact immutable context, scope, anchor and footprint share goal authority")
	check(goal_cache_key_a!=cache_b._hc_goal_cache_key(Vector2(9.5,8.5),true),"A-goal-cache-anchor","Changed last-known anchor invalidates shared goals")
	cache_b.combat_radius_gu=.76
	check(goal_cache_key_a!=cache_b._hc_goal_cache_key(Vector2(8.5,8.5),true),"A-goal-cache-radius","Changed monster footprint invalidates shared goals")
	cache_b.combat_radius_gu=.35
	provider.revision=1
	check(goal_cache_key_a!=cache_b._hc_goal_cache_key(Vector2(8.5,8.5),true),"A-goal-cache-revision","Changed WORLD revision invalidates shared goals")
	provider.revision=0
	cache_a.set_meta("safe_zone_context",{"valid":true,"revision":1,"zones":[{"id":"a"}]})
	cache_b.set_meta("safe_zone_context",{"valid":true,"revision":1,"zones":[{"id":"b"}]})
	check(cache_a._hc_static_query_scope(true)!=cache_b._hc_static_query_scope(true),"A-cache-private-safe","Private safe-zone contexts never share cache scope")
	var private_scope_revision_one:Array=cache_a._hc_static_query_scope(true)
	cache_a.set_meta("safe_zone_context",{"valid":true,"revision":2,"zones":[{"id":"changed"}]})
	check(private_scope_revision_one!=cache_a._hc_static_query_scope(true),"A-cache-private-safe-revision","Same owner's changed private context requires and consumes a new revision")
	cache_a.queue_free()
	cache_b.queue_free()
	goal_target.queue_free()
	provider.queue_free()
	# Fairness is tested with actual shared Engine physics-frame budget, not reset per owner.
	var scheduler := Scheduler.for_tree(get_tree())
	scheduler.set_physics_process(false)
	var owners: Array[JobOwner] = []
	Terrain.reset_diagnostics()
	for index in range(30):
		var owner := JobOwner.new()
		add_child(owner)
		owners.append(owner)
		var job := Search.new()
		job.configure(context(),Vector2i(1,1),{Vector2i(1,1):Vector2(1.5,1.5)},.35,Callable())
		scheduler.submit(owner,1,job)
	for frame in range(15):
		await get_tree().physics_frame
		var previous := scheduler.service_count
		scheduler.pump(0) # deterministic quota test; production keeps the soft clock budget
		check(scheduler.service_count-previous<=2,"A17-budget-%d"%frame,"At most two services per physics frame")
	for index in range(owners.size()):
		check(owners[index].completed and owners[index].status=="FOUND" and owners[index].callback_count==1,"A17-owner-%d"%index,"Every fixed request is serviced exactly once within 15 service frames")
		owners[index].queue_free()
	check(scheduler.jobs.is_empty(),"A18","No duplicate or abandoned completed jobs")
	# Mix immediate, real-detour and terminal-no-route work in the same global
	# production queue. Waiting owners are not misreported as no-route and a
	# hard graph cannot starve the following cheap request.
	var mixed_owners:Array[JobOwner]=[]
	var detour_blocked:Dictionary={}
	var closed_blocked:Dictionary={}
	for y in range(11):detour_blocked[Vector2i(4,y)]=true
	for y in range(16):closed_blocked[Vector2i(4,y)]=true
	for index in range(18):
		var owner:=JobOwner.new()
		add_child(owner)
		mixed_owners.append(owner)
		var job:=Search.new()
		match index%3:
			0:job.configure(context(),Vector2i(1,1),{Vector2i(1,1):Vector2(1.5,1.5)},.35,Callable())
			1:job.configure(context(detour_blocked),Vector2i(2,2),{Vector2i(7,2):Vector2(7.5,2.5)},.35,Callable())
			2:job.configure(context(closed_blocked),Vector2i(2,2),{Vector2i(7,2):Vector2(7.5,2.5)},.35,Callable())
		scheduler.submit(owner,1,job)
	# Exercise the pre-V3 synchronous navigation lane through a real EnemyActor
	# that is excluded from HC melee by its named special delivery. It and the
	# HC queue must claim the same Terrain per-physics-frame budget.
	var legacy_special:=EnemyActor.new()
	legacy_special.monster_id=150
	legacy_special.attack_delivery_rule={"kind":"physical_projectile"}
	legacy_special.combat_radius_gu=.35
	legacy_special.global_position=_ground_to_screen(Vector2(1.5,1.5))
	add_child(legacy_special)
	legacy_special.configure_runtime_map_projection(1,Callable(self,"_ground_to_screen"),Callable(self,"_screen_to_ground"))
	var legacy_blocked:Dictionary={Vector2i(2,1):true}
	legacy_special.configure_terrain_navigation_context(context(legacy_blocked))
	var legacy_target:=Node2D.new()
	legacy_target.global_position=_ground_to_screen(Vector2(8.5,1.5))
	add_child(legacy_target)
	var saw_waiting_owner:=false
	var legacy_accepted_frames:=0
	for frame in range(180):
		await get_tree().physics_frame
		legacy_special._reset_terrain_navigation_state()
		var legacy_step:=legacy_special._terrain_neighbor_for_pursuit(Vector2(1.5,1.5),legacy_target,Vector2i(1,0))
		if legacy_step!=Vector2i.ZERO:
			legacy_accepted_frames+=1
		var previous:=scheduler.service_count
		scheduler.pump()
		check(scheduler.service_count-previous<=1,"C06-budget-%d"%frame,"Legacy special navigation and HC queue share the two-query frame budget")
		saw_waiting_owner=saw_waiting_owner or mixed_owners.any(func(candidate:JobOwner)->bool:return not candidate.completed)
		if mixed_owners.all(func(candidate:JobOwner)->bool:return candidate.completed):break
	check(legacy_accepted_frames>0,"C06-legacy-special","Named-delivery actor exercised the existing synchronous detour lane")
	check(saw_waiting_owner,"C06-wait","A queued owner remains WAITING before its bounded service turn")
	check(scheduler.maximum_wait_frames<=180,"C06-wait-bound","Mixed resumable queue remains within its explicit fairness bound")
	for index in range(mixed_owners.size()):
		var expected_status:="NO_ROUTE_FOR_CURRENT_GRAPH" if index%3==2 else "FOUND"
		check(mixed_owners[index].completed and mixed_owners[index].status==expected_status and mixed_owners[index].callback_count==1,"C06-owner-%d"%index,"Mixed owner completes once with its exact terminal status")
		mixed_owners[index].queue_free()
	legacy_special.queue_free()
	legacy_target.queue_free()
	check(scheduler.jobs.is_empty(),"C06-drain","Mixed global queue drains without duplicate or abandoned jobs")
	finish("path")

func _ground_to_screen(value:Vector2)->Vector2:
	return GU.ground_delta_gu_to_screen_delta_px(value)

func _screen_to_ground(value:Vector2)->Vector2:
	return GU.screen_delta_px_to_ground_delta_gu(value)

func _alternate_ground_to_screen(value:Vector2)->Vector2:
	return GU.ground_delta_gu_to_screen_delta_px(value)+Vector2(1.0,0.0)
