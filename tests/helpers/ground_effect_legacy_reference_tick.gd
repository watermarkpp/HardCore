class_name GroundEffectLegacyReferenceTick
extends RefCounted

## Q2-B: test-only legacy reference for the pre-manager GroundSkillEffect hot
## path. It replicates the old per-effect _physics_process enemy loop:
##
##   for enemy in scene-order array:
##       skip invalid / queued-for-deletion
##       exact runtime_target_is_inside(enemy)
##       if damage_enabled and not claim_runtime_tick(enemy): skip
##       apply adapter damage
##
## The caller passes the explicit enemy array in the old stable order and any
## pre-existing claim state on the shared GroundSkillEffect claim table.
## Production code must never call this helper.


static func legacy_tick(
	effect: GroundSkillEffect,
	enemies: Array,
	damage_enabled := true,
	damage_applier := Callable()
) -> Dictionary:
	var candidate_ids: Array[int] = []
	var exact_hit_ids: Array[int] = []
	var damage_order: Array[int] = []
	var claim_results: Dictionary = {}
	for raw_enemy: Variant in enemies:
		if not raw_enemy is EnemyActor:
			continue
		var enemy := raw_enemy as EnemyActor
		if not is_instance_valid(enemy) or enemy.is_queued_for_deletion():
			continue
		candidate_ids.append(enemy.get_instance_id())
		if not effect.runtime_target_is_inside(enemy):
			continue
		exact_hit_ids.append(enemy.get_instance_id())
		var claim_ok := true
		if damage_enabled:
			claim_ok = effect.claim_runtime_tick(enemy)
		claim_results[enemy.get_instance_id()] = claim_ok
		if not claim_ok:
			continue
		if damage_applier.is_valid():
			damage_applier.call(enemy, effect.damage)
		elif effect.runtime_tick_adapter.is_valid():
			effect.runtime_tick_adapter.call(enemy, effect.damage)
		else:
			enemy.take_damage(effect.damage, effect.source_actor)
		damage_order.append(enemy.get_instance_id())
	return {
		"candidate_ids": candidate_ids,
		"exact_hit_ids": exact_hit_ids,
		"damage_order": damage_order,
		"claim_results": claim_results,
		"damage_count": damage_order.size(),
	}
