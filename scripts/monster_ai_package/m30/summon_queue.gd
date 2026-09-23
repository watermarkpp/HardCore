class_name HCM30SummonQueue
extends Node

## One queue per GameRoot; main-thread SceneTree writes only.
## A soft time budget cannot preempt one EnemyActor.setup()/add_child().
const PROBES_PER_TICK := 8
const MATERIALIZATIONS_PER_TICK := 1
const MAX_ATTEMPTS_PER_CHILD := 96
const MAX_PENDING_BATCHES := 256
const SOFT_BUDGET_USEC := 1000
const MONSTER_SUMMON_HARD_CAP := 5

var _host_ref: WeakRef
var _map_id: int = -1
var _generation: int = -1
var _jobs: Array[Dictionary] = []
var _children: Dictionary = {} # stable owner spawn-slot -> {instance_id: WeakRef}
var _reserved: Dictionary = {} # stable owner spawn-slot -> queued births
var _cursor: int = 0
var _last_pump_tick: int = -1
var _queue_epoch: int = 0
var _pump_active: bool = false
var _materializing_job: Dictionary = {}
var _materializing_epoch: int = -1
var _stats: Dictionary = {
	"reentrant_pump_rejected": 0, "stale_callback_rejections": 0,
	"max_resolve_call_usec": 0, "max_probe_call_usec": 0,
	"cancel_during_materialize": 0, "requests": 0, "admitted_children": 0, "spawned": 0,
	"candidate_probes": 0, "materialization_attempts": 0,
	"landing_exhausted": 0, "spawn_failed": 0,
	"cancelled_children": 0, "duplicate_release": 0,
	"capacity_rejected": 0, "max_tick_usec": 0,
	"max_probes_in_tick": 0, "max_materializations_in_tick": 0,
	"max_pending_batches": 0, "max_queue_age_ticks": 0,
	"max_spawn_call_usec": 0, "last_probes_in_tick": 0,
	"last_materializations_in_tick": 0,
}

func configure(host: Node) -> void:
	_host_ref = weakref(host)
	name = "M30SummonQueue"
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_sync_world(host)

func _ready() -> void:
	set_physics_process(not _jobs.is_empty())

func _host() -> Node:
	return _host_ref.get_ref() as Node if _host_ref != null else null

func _sync_world(host: Node) -> void:
	var map_id: int = int(host.get("current_map_id"))
	var generation: int = int(host.get("_zone_generation"))
	if map_id == _map_id and generation == _generation:
		return
	cancel_all()
	# An old world's in-flight birth cannot occupy a slot in the new world.
	_reserved.clear()
	_materializing_epoch = -1
	_children.clear()
	_map_id = map_id
	_generation = generation
	# Once per map/manager activation, not once per probe or summon request.
	var existing: Dictionary = host.get("_active_enemy_cache")
	for value: Variant in existing.values():
		if is_instance_valid(value) and value is EnemyActor:
			track_child(value as EnemyActor)

func track_child(child: EnemyActor) -> void:
	if not is_instance_valid(child):
		return
	if child.runtime_map_id != _map_id:
		return
	if int(child.get_meta("zone_generation", -1)) != _generation:
		return
	var slot: String = str(child.get_meta("summoner_spawn_slot", ""))
	if slot.is_empty():
		return
	var members: Dictionary = _children.get(slot, {})
	if members.has(child.get_instance_id()):
		return
	# Transfer the in-flight reservation to a live child atomically, including
	# the factory's synchronous track_child callback. Never count that birth
	# as both live and reserved, nor free its slot before it is registered.
	if (
		_materializing_epoch == _queue_epoch
		and str(_materializing_job.get("slot", "")) == slot
		and not bool(_materializing_job.get("birth_tracked", false))
	):
		_release_reservation(slot, 1)
		_materializing_job["birth_tracked"] = true
	members[child.get_instance_id()] = weakref(child)
	child.tree_exiting.connect(_child_exiting.bind(child.get_instance_id(), slot), CONNECT_ONE_SHOT)
	child.died.connect(_child_died.bind(child.get_instance_id(), slot), CONNECT_ONE_SHOT)
	_children[slot] = members

func _child_exiting(instance_id: int, slot: String) -> void:
	var members: Dictionary = _children.get(slot, {})
	members.erase(instance_id)
	if members.is_empty():
		_children.erase(slot)

func _child_died(_child: EnemyActor, _data: Dictionary, instance_id: int, slot: String) -> void:
	_child_exiting(instance_id, slot)

func _active(slot: String) -> int:
	var members: Dictionary = _children.get(slot, {})
	for id: Variant in members.keys():
		var child_ref: WeakRef = members[id]
		var child: EnemyActor = child_ref.get_ref() as EnemyActor
		if not is_instance_valid(child):
			members.erase(id)
		elif child.is_queued_for_deletion() or child.current_hp <= 0 or child._death_pending or child._dying:
			members.erase(id)
		elif child.runtime_map_id != _map_id or int(child.get_meta("zone_generation", -1)) != _generation:
			members.erase(id)
	if members.is_empty():
		_children.erase(slot)
	return members.size()

func _source_valid(source: EnemyActor, host: Node) -> bool:
	# The existing producer/receiver authorizes the signal. Do not require an
	# ordinary summon_rule here: a source-locked boss may use another producer.
	return (
		is_instance_valid(source) and source.is_inside_tree()
		and not source.is_queued_for_deletion()
		and source.get_parent() == host
		and source.runtime_map_id == _map_id
		and int(source.get_meta("zone_generation", -1)) == _generation
		and source.current_hp > 0 and not source._death_pending and not source._dying
		and source.combat_enabled and source.control_time <= 0.0
		and source.charm_time <= 0.0 and not source.dormant and not source._burrowed
	)

func enqueue(source: EnemyActor, monster_ids: Array, count: int, max_active: int) -> void:
	var host: Node = _host()
	if not is_instance_valid(host):
		return
	_sync_world(host)
	_stats["requests"] = int(_stats["requests"]) + 1
	if bool(host.get("_map_transition_in_progress")) or bool(host.get("_world_bootstrap_in_progress")):
		return
	if not _source_valid(source, host) or monster_ids.is_empty() or count <= 0 or max_active <= 0:
		return
	# is_boss is compiled by EnemyActor.setup from the canonical ID classification.
	# Bosses retain their authored cap; ordinary and elite summoners share cap 5.
	var effective_max_active := max_active if source.is_boss else mini(max_active, MONSTER_SUMMON_HARD_CAP)
	var slot: String = str(source.get_meta("spawn_slot_id", ""))
	if slot.is_empty():
		return
	_stats["last_source_monster_id"] = source.monster_id
	_stats["last_source_instance_id"] = source.get_instance_id()
	_stats["last_source_slot"] = slot
	_stats["last_requested_count"] = count
	_stats["last_max_active"] = max_active
	_stats["last_effective_max_active"] = effective_max_active
	_stats["last_child_ids"] = monster_ids.duplicate()
	# The producer reserves its serial BEFORE emitting the synchronous signal.
	var serial: int = int(source.get_meta("m30_summon_release_serial", 0))
	var life: int = int(source.get_meta("hc_combat_life_epoch", 0))
	var accepted: Vector2i = source.get_meta("m30_last_queued_release", Vector2i(-1, -1))
	if serial > 0 and accepted == Vector2i(life, serial):
		_stats["duplicate_release"] = int(_stats["duplicate_release"]) + 1
		return
	if serial > 0:
		source.set_meta("m30_last_queued_release", Vector2i(life, serial))
	if _jobs.size() >= MAX_PENDING_BATCHES:
		_stats["capacity_rejected"] = int(_stats["capacity_rejected"]) + 1
		return
	# Keep the existing cap PER SPAWN SLOT, including previous-life survivors.
	var allowed: int = mini(count, maxi(0, effective_max_active - _active(slot) - int(_reserved.get(slot, 0))))
	if allowed <= 0:
		return
	_reserved[slot] = int(_reserved.get(slot, 0)) + allowed
	_jobs.append({
		"source": weakref(source), "life": life, "slot": slot,
		"ids": monster_ids.duplicate(), "limit": effective_max_active,
		"remaining": allowed, "index": 0, "attempts": 0,
		"enqueued_tick": Engine.get_physics_frames(), "serial": serial,
		"monster": {},
	})
	set_physics_process(true)
	_stats["admitted_children"] = int(_stats["admitted_children"]) + allowed
	_stats["max_pending_batches"] = maxi(int(_stats["max_pending_batches"]), _jobs.size())

func _job_source(job: Dictionary, host: Node) -> EnemyActor:
	var source_ref: WeakRef = job["source"]
	var source: EnemyActor = source_ref.get_ref() as EnemyActor
	if not _source_valid(source, host):
		return null
	if str(source.get_meta("spawn_slot_id", "")) != str(job["slot"]):
		return null
	if int(source.get_meta("hc_combat_life_epoch", 0)) != int(job["life"]):
		return null
	return source

func _release_reservation(slot: String, amount: int) -> void:
	var remaining: int = maxi(0, int(_reserved.get(slot, 0)) - amount)
	if remaining == 0:
		_reserved.erase(slot)
	else:
		_reserved[slot] = remaining

func _finish_child(job: Dictionary) -> void:
	if not bool(job.get("birth_tracked", false)):
		_release_reservation(str(job["slot"]), 1)
	job["birth_tracked"] = false
	job["remaining"] = int(job["remaining"]) - 1
	job["index"] = int(job["index"]) + 1
	job["attempts"] = 0
	job["monster"] = {}

func _remove_job(index: int, cancelled: bool) -> void:
	var job: Dictionary = _jobs[index]
	var remaining: int = int(job["remaining"])
	_release_reservation(str(job["slot"]), remaining)
	if cancelled:
		_stats["cancelled_children"] = int(_stats["cancelled_children"]) + remaining
	_jobs.remove_at(index)
	if _cursor >= _jobs.size():
		_cursor = 0

func cancel_all() -> void:
	var in_flight_slot := ""
	if _materializing_epoch == _queue_epoch and not bool(_materializing_job.get("birth_tracked", false)):
		in_flight_slot = str(_materializing_job.get("slot", ""))
	_queue_epoch += 1
	for job: Dictionary in _jobs:
		_stats["cancelled_children"] = int(_stats["cancelled_children"]) + int(job["remaining"])
	_jobs.clear()
	set_physics_process(false)
	_reserved.clear()
	# A synchronous factory callback can cancel and enqueue before registering
	# its newborn. Keep that one admission occupied until the factory returns.
	if not in_flight_slot.is_empty():
		_reserved[in_flight_slot] = 1
		_materializing_epoch = _queue_epoch
	_cursor = 0

func _physics_process(_delta: float) -> void:
	pump()

func pump() -> void:
	# A host callback may pump/cancel/enqueue synchronously. Never run two cursors.
	if _pump_active:
		_stats["reentrant_pump_rejected"] = int(_stats["reentrant_pump_rejected"]) + 1
		return
	var tick: int = Engine.get_physics_frames()
	if _last_pump_tick == tick:
		return
	_last_pump_tick = tick
	_pump_active = true
	_pump_body(tick)
	_pump_active = false

func _callback_world_current(host: Node, epoch: int) -> bool:
	if not is_instance_valid(host) or not host.is_inside_tree() or host.is_queued_for_deletion():
		cancel_all()
		return false
	_sync_world(host)
	if bool(host.get("_map_transition_in_progress")) or bool(host.get("_world_bootstrap_in_progress")):
		cancel_all()
		return false
	# Do NOT clear a new generation's queue because an old callback returned.
	return epoch == _queue_epoch

func _pump_body(tick: int) -> void:
	_stats["last_probes_in_tick"] = 0
	_stats["last_materializations_in_tick"] = 0
	var host: Node = _host()
	if not is_instance_valid(host) or not host.is_inside_tree() or host.is_queued_for_deletion():
		cancel_all()
		return
	_sync_world(host)
	if bool(host.get("_map_transition_in_progress")) or bool(host.get("_world_bootstrap_in_progress")):
		cancel_all()
		return
	var started: int = Time.get_ticks_usec()
	var probes: int = 0
	var materializations: int = 0
	var visits: int = 0
	while not _jobs.is_empty() and probes < PROBES_PER_TICK and materializations < MATERIALIZATIONS_PER_TICK:
		if visits > 0 and Time.get_ticks_usec() - started >= SOFT_BUDGET_USEC:
			break
		if visits >= MAX_PENDING_BATCHES + PROBES_PER_TICK:
			break
		visits += 1
		_cursor %= _jobs.size()
		var job: Dictionary = _jobs[_cursor]
		var epoch: int = _queue_epoch
		var source: EnemyActor = _job_source(job, host)
		if source == null:
			_remove_job(_cursor, true)
			continue
		_stats["max_queue_age_ticks"] = maxi(int(_stats["max_queue_age_ticks"]), tick - int(job["enqueued_tick"]))
		var slot: String = str(job["slot"])
		if _active(slot) >= int(job["limit"]):
			_remove_job(_cursor, true)
			continue
		var monster: Dictionary = job["monster"]
		if monster.is_empty():
			var ids: Array = job["ids"]
			var resolve_started: int = Time.get_ticks_usec()
			monster = host.call("_hc_m30_resolve_monster", ids[int(job["index"]) % ids.size()]) as Dictionary
			_stats["max_resolve_call_usec"] = maxi(int(_stats["max_resolve_call_usec"]), Time.get_ticks_usec() - resolve_started)
			if not _callback_world_current(host, epoch):
				_stats["stale_callback_rejections"] = int(_stats["stale_callback_rejections"]) + 1
				break
			source = _job_source(job, host)
			if source == null:
				_remove_job(_cursor, true)
				continue
			job["monster"] = monster
		if monster.is_empty():
			_finish_child(job)
		else:
			probes += 1
			job["attempts"] = int(job["attempts"]) + 1
			var probe_started: int = Time.get_ticks_usec()
			var candidate: Vector2 = host.call("_hc_m30_probe_landing", source.global_position)
			_stats["max_probe_call_usec"] = maxi(int(_stats["max_probe_call_usec"]), Time.get_ticks_usec() - probe_started)
			if not _callback_world_current(host, epoch):
				_stats["stale_callback_rejections"] = int(_stats["stale_callback_rejections"]) + 1
				break
			source = _job_source(job, host)
			if source == null or _active(slot) >= int(job["limit"]):
				_remove_job(_cursor, true)
				continue
			if candidate.is_finite():
				materializations += 1
				var spawn_started: int = Time.get_ticks_usec()
				_materializing_job = job
				_materializing_epoch = epoch
				var child: EnemyActor = host.call("_hc_m30_materialize", monster, candidate, {
					"spawn_group_id": "%s:summons" % slot,
					"respawn_enabled": false,
					"summoner_spawn_slot": slot,
					"summon_monster_id": int(monster.get("monster_id", -1)),
					"m30_source_instance_id": source.get_instance_id(),
					"m30_source_life": int(job["life"]),
				}) as EnemyActor
				_stats["max_spawn_call_usec"] = maxi(int(_stats["max_spawn_call_usec"]), Time.get_ticks_usec() - spawn_started)
				# Birth already returned from the formal factory. Source death during
				# a child-ready callback does not retrospectively kill a live child.
				if is_instance_valid(child):
					_stats["spawned"] = int(_stats["spawned"]) + 1
				else:
					_stats["spawn_failed"] = int(_stats["spawn_failed"]) + 1
				if not _callback_world_current(host, epoch):
					_stats["cancel_during_materialize"] = int(_stats["cancel_during_materialize"]) + 1
					if is_instance_valid(child):
						track_child(child) # map/generation filter; never own an old child
					elif _materializing_epoch == _queue_epoch and not bool(job.get("birth_tracked", false)):
						_release_reservation(slot, 1)
					_materializing_job = {}
					_materializing_epoch = -1
					break
				if is_instance_valid(child):
					track_child(child)
				_materializing_job = {}
				_materializing_epoch = -1
				_finish_child(job)
			elif int(job["attempts"]) >= MAX_ATTEMPTS_PER_CHILD:
				_stats["landing_exhausted"] = int(_stats["landing_exhausted"]) + 1
				_finish_child(job)
		if int(job["remaining"]) <= 0:
			_remove_job(_cursor, false)
		else:
			_cursor = (_cursor + 1) % _jobs.size()
	_stats["candidate_probes"] = int(_stats["candidate_probes"]) + probes
	_stats["materialization_attempts"] = int(_stats["materialization_attempts"]) + materializations
	_stats["last_probes_in_tick"] = probes
	_stats["last_materializations_in_tick"] = materializations
	_stats["max_probes_in_tick"] = maxi(int(_stats["max_probes_in_tick"]), probes)
	_stats["max_materializations_in_tick"] = maxi(int(_stats["max_materializations_in_tick"]), materializations)
	_stats["max_tick_usec"] = maxi(int(_stats["max_tick_usec"]), Time.get_ticks_usec() - started)
	if _jobs.is_empty():
		set_physics_process(false)

func snapshot() -> Dictionary:
	var result: Dictionary = _stats.duplicate()
	result["last_pump_tick"] = _last_pump_tick
	result["queue_epoch"] = _queue_epoch
	result["map_id"] = _map_id
	result["generation"] = _generation
	result["pending_batches"] = _jobs.size()
	result["reserved_by_slot"] = _reserved.duplicate()
	result["tracked_slots"] = _children.size()
	return result
