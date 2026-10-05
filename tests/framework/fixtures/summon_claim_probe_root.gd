extends "res://tests/framework/fixtures/published_birth_probe_root.gd"

var claim_observations: Array[Dictionary] = []
var claim_probe_mode := "normal"
var _current_claim_context: Dictionary = {}
var _current_claim_monster: Dictionary = {}
var _current_claim_position := Vector2.INF

func enable_claim_probe() -> void:
	child_entered_tree.connect(_probe_entered)

func _hc_m30_materialize(monster: Dictionary, candidate: Vector2, context: Dictionary) -> EnemyActor:
	var serial := _runtime_spawn_serial
	var copied := context.duplicate(false)
	copied["_m30_job"] = context["_m30_job"].duplicate(true)
	var rejected_copy := super._hc_m30_materialize(monster, candidate, copied)
	var copy_unchanged := _runtime_spawn_serial == serial
	_current_claim_context = context
	_current_claim_monster = monster
	_current_claim_position = candidate
	var observation := {"copied_rejected": rejected_copy == null, "copy_unchanged": copy_unchanged,
		"reentrant_rejected": false, "reentrant_unchanged": false, "mode": claim_probe_mode}
	claim_observations.append(observation)
	var child := super._hc_m30_materialize(monster, candidate, context)
	serial = _runtime_spawn_serial
	var replay := super._hc_m30_materialize(monster, candidate, context)
	observation["replay_rejected"] = replay == null
	observation["replay_unchanged"] = _runtime_spawn_serial == serial
	observation["child_valid"] = is_instance_valid(child)
	observation["job_not_in_actor"] = child != null and not (child.get_meta("spawn_context") as Dictionary).has("_m30_job")
	if child != null: child.set_physics_process(false)
	_current_claim_context = {}; _current_claim_monster = {}; _current_claim_position = Vector2.INF
	return child

func _probe_entered(node: Node) -> void:
	if _current_claim_context.is_empty() or not node is EnemyActor: return
	var observation: Dictionary = claim_observations[-1]
	var serial := _runtime_spawn_serial
	var rejected := super._hc_m30_materialize(_current_claim_monster, _current_claim_position, _current_claim_context)
	observation["reentrant_rejected"] = rejected == null
	observation["reentrant_unchanged"] = _runtime_spawn_serial == serial
	if claim_probe_mode == "death_and_cancel":
		var source_ref: WeakRef = _current_claim_context["_m30_job"].source
		var source: EnemyActor = source_ref.get_ref()
		source.take_damage(source.current_hp * 10, player, {"source_class": "direct", "damage_channel": "magic_defense"})
		_hc_m30_summon_queue.cancel_all()
		observation["source_fatal"] = source.current_hp == 0
		observation["inflight_reserved"] = int(_hc_m30_summon_queue._reserved.get(str(_current_claim_context.summoner_spawn_slot), 0)) == 1
