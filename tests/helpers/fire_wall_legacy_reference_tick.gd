class_name FireWallLegacyReferenceTick
extends RefCounted

## Q2-C: test-only legacy reference for the pre-refactor FireWall hot path. It
## replicates the old FireWallFieldController._apply_field_tick loop:
##
##   per enemy (old stable order):
##       per visual cell (old order) until first hit:
##           cell exact test
##       claim via the first-hit cell
##       damage once per enemy per tick
##
## Production code must never call this helper.


static func legacy_tick(
	cell_exact_testers: Array[Callable],
	claim_cells: Array,
	enemies: Array,
	damage_applier: Callable,
	damage_enabled := true,
	tick_callback_valid := true
) -> Dictionary:
	var exact_test_count := 0
	var damage_order: Array[int] = []
	var claim_results: Dictionary = {}
	for raw_enemy: Variant in enemies:
		if not raw_enemy is EnemyActor:
			continue
		var enemy := raw_enemy as EnemyActor
		if not is_instance_valid(enemy) or enemy.is_queued_for_deletion():
			continue
		var hit_cell_index := -1
		for cell_index: int in range(cell_exact_testers.size()):
			var tester: Callable = cell_exact_testers[cell_index]
			if not tester.is_valid():
				continue
			exact_test_count += 1
			if not bool(tester.call(enemy)):
				continue
			hit_cell_index = cell_index
			break
		if hit_cell_index < 0:
			continue
		if not tick_callback_valid:
			continue
		var claim_ok := true
		if damage_enabled:
			claim_ok = (claim_cells[hit_cell_index] as GroundSkillVisualCell).claim_runtime_tick(
				enemy
			)
		claim_results[enemy.get_instance_id()] = claim_ok
		if not claim_ok:
			continue
		if damage_applier.is_valid():
			damage_applier.call(enemy, 0)
		damage_order.append(enemy.get_instance_id())
	return {
		"exact_test_count": exact_test_count,
		"damage_order": damage_order,
		"damage_count": damage_order.size(),
		"claim_results": claim_results,
	}
