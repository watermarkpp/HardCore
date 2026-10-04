extends "res://tests/framework/fixtures/lease_probe_root.gd"

var forged_child_rejected := true
var forged_child_quiet := true
var tested_child_callbacks := 0

func _execute_feature_child_action(request: Dictionary, ticket: RefCounted, bindings: Array,
	source: Node2D, resources: RefCounted) -> Dictionary:
	var command: Dictionary=request.child_action_lease.command().duplicate(true)
	command.parent_fact_id=command.parent_release_id+":hp:999"
	command.radius_gu=0.1
	var forged:=SkillRuntimeRouterScript.create_child_request(command,_world_context,ticket.branch())
	var hp_before:=_enemy_hp_sum()
	var mp_before: int=player.current_mp; var rng_before: int=_rng.state
	var wrong: Dictionary=super._execute_feature_child_action(forged.request,ticket,bindings,source,resources)
	forged_child_rejected=forged_child_rejected and not wrong.success
	forged_child_quiet=forged_child_quiet and hp_before==_enemy_hp_sum() and mp_before==player.current_mp and rng_before==_rng.state
	tested_child_callbacks+=1
	return super._execute_feature_child_action(request,ticket,bindings,source,resources)

func _enemy_hp_sum() -> int:
	var total:=0
	for enemy: Node in get_tree().get_nodes_in_group("enemies"):
		if enemy is EnemyActor: total+=int(enemy.current_hp)
	return total
