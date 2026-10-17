extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Ground := preload("res://scripts/ground_unit_space.gd")
var proof := Proof.new()
var errors: Array[String] = []

func check(value: bool, label: String) -> void:
	proof.record(value, label)
	if not value:
		errors.append(label)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	var owner := PlayerCharacter.new()
	add_child(owner)
	owner.set_physics_process(false)
	var summon := SummonActor.new()
	summon.setup(owner, "skeleton", 30, 3, "taoist.summon_skeleton", 35)
	var core: Object = summon.domain_state
	var full_methods := ["step_physics", "step_process", "take_damage", "take_magic_damage", "take_monster_mixed_damage", "take_direct_spell_damage", "apply_control", "apply_monster_poison", "persistence_snapshot", "restore_persistence_snapshot", "_begin_attack", "_update_pending_attack", "_nearest_enemy"]
	var owns_full_gameplay := not core is Node
	for method: String in full_methods:
		owns_full_gameplay = owns_full_gameplay and core.has_method(method)
	check(owns_full_gameplay, "the non-Node summon model owns AI motion accepted release damage control poison and persistence")
	if not owns_full_gameplay:
		summon.free()
		owner.free()
		_finish()
		return
	add_child(summon)
	summon.set_process(false)
	summon.set_physics_process(false)
	summon.configure_runtime_map_projection(9001, Ground.ground_delta_gu_to_screen_delta_px, Ground.screen_delta_px_to_ground_delta_gu)
	core.current_hp = 200
	core.ac_min = 0
	core.ac_max = 0
	core.mac_min = 0
	core.mac_max = 0
	core.take_damage(30, 0)
	check(summon.current_hp == 170 and core.current_hp == 170, "physical damage writes the same HP exposed by the legacy adapter")
	core.take_magic_damage(20, 0)
	check(summon.current_hp == 150, "magic damage keeps its original independent MAC pipeline")
	core.apply_ac_buff(5, 2.0)
	core.apply_mac_buff(7, 2.0)
	var mixed: Dictionary = core.take_monster_mixed_damage(30, 20, {})
	check(mixed.applied_damage == 38 and core.current_hp == 112, "mixed damage retains independent AC and MAC rolls before a single HP write")
	var spell: Dictionary = core.take_direct_spell_damage("wizard.fireball", 20, 9, 0)
	check(spell.applied_damage == 13 and core.current_hp == 99 and spell.physical_defense_bypassed, "direct spell reads active MAC and bypasses AC without changing the shared resolution rule")
	check(core.apply_monster_poison(10, 2.0, 0.5), "original source poison accepts on a live owner outside transition")
	core._update_monster_source_poison(0.5)
	check(core.current_hp == 89, "source poison advances on the original H prefix and applies the resolved tick")
	core._monster_source_poison.clear()
	check(core.restore_health(5) == 5 and summon.current_hp == 94, "effective healing updates the same model and presentation boundary")
	var saved: Dictionary = core.persistence_snapshot()
	saved.max_hp = 1
	check(core.restore_persistence_snapshot(saved) and core.max_hp == 392 and core.current_hp == 94, "persistence restore rederives authored stats and preserves absolute saved HP")
	owner.global_position = Vector2(400.0, 200.0)
	summon.global_position = owner.global_position
	core._target_acquire_remaining = 60.0
	var before := summon.global_position
	var lifetime_before: float = core.remaining_lifetime
	core.step_physics(1.0 / 60.0)
	check(core.remaining_lifetime < lifetime_before and not core.actual_ground_motion_gu.is_zero_approx() and core.actual_ground_motion_gu.is_equal_approx(Ground.actual_ground_motion_gu_from_screen_positions(before, summon.global_position)), "real body follow motion and lifetime are advanced by the model's original H function")
	core.apply_control(0.25)
	before = summon.global_position
	core.step_physics(0.125)
	check(summon.global_position == before and summon.velocity == Vector2.ZERO and is_equal_approx(core._monster_control_remaining, 0.125), "control clears movement and charges its first original H time slice")
	core._monster_control_remaining = 0.0
	var enemy := EnemyActor.new()
	enemy.setup(GameData.get_monster_by_id(38), owner, false)
	add_child(enemy)
	enemy.set_physics_process(false)
	enemy.set_process(false)
	enemy.max_hp = 500
	enemy.current_hp = 500
	enemy.global_position = summon.global_position + Ground.ground_delta_gu_to_screen_delta_px(Vector2(1.0, 0.0))
	summon.apply_stealth(10.0)
	summon._begin_attack(enemy)
	check(not core.is_stealthed() and summon._pending_attack_target == enemy and str(summon.last_attack_footprint_snapshot.release_id).contains(":%d:" % summon.get_instance_id()), "attack acceptance synchronously breaks stealth and freezes the positive actor release identity")
	var delay: float = summon._pending_attack_release_remaining
	var hp_before := enemy.current_hp
	enemy.global_position = summon.global_position + Ground.ground_delta_gu_to_screen_delta_px(Vector2(0.0, 3.0))
	core._update_pending_attack(delay)
	check(enemy.current_hp == hp_before and summon._pending_attack_target == null, "accepted release tests the frozen footprint against the target's current position")
	enemy.global_position = summon.global_position + Ground.ground_delta_gu_to_screen_delta_px(Vector2(1.0, 0.0))
	summon._begin_attack(enemy)
	enemy.set_meta("hc_combat_life_epoch", int(enemy.get_meta("hc_combat_life_epoch", 0)) + 1)
	check(summon._pending_attack_target == enemy, "the original pending object reference follows the same target through a life change")
	core._update_pending_attack(float(summon._pending_attack_release_remaining))
	check(enemy.current_hp < hp_before and summon._pending_attack_target == null, "legal delayed summon attack applies real enemy HP damage and retires its producer")
	summon._begin_attack(enemy)
	core.apply_control(0.1)
	check(summon._pending_attack_target == null and summon.velocity == Vector2.ZERO, "control preserves original accepted-attack cancellation behavior")
	core._monster_control_remaining = 0.0
	core.maximum_pet_level = 7
	core.pet_growth_exp = 0
	var growth_level_before: int = core.summon_exp_level
	enemy.current_hp = 1
	enemy.defense = 0
	core.attack_min = 100
	core.attack_max = 100
	var target_life_before: int = enemy.get_meta("hc_combat_life_epoch", 0)
	summon._begin_attack(enemy)
	core._update_pending_attack(float(summon._pending_attack_release_remaining))
	check(enemy.current_hp == 0 and int(enemy.get_meta("hc_combat_life_epoch", 0)) > target_life_before and (core.pet_growth_exp > 0 or core.summon_exp_level > growth_level_before), "qualified settlement reads the same killed target after its death life change and grants original kill growth")
	var orphan := SummonActor.new()
	orphan.setup(null, "skeleton", 30, 3, "taoist.summon_skeleton", 35)
	add_child(orphan)
	orphan.set_process(false)
	orphan.set_physics_process(false)
	orphan.domain_state.step_physics(1.0 / 60.0)
	check(orphan.state == SummonActor.SummonState.EXPIRED and orphan.is_queued_for_deletion(), "a missing owner retains the original expiry branch without borrowing the summon as its owner")
	core._apply_resolved_damage(999999)
	check(core.current_hp == 0 and summon.state == SummonActor.SummonState.DEAD and summon.collision_layer == 0 and summon.collision_mask == 0, "death owns HP state target retirement and physical collision removal synchronously")
	var death_duration: float = summon._death_visual_remaining
	core.step_process(death_duration * 0.5)
	check(not summon.is_queued_for_deletion(), "death does not retire before the activated numeric presentation duration")
	core.step_process(death_duration)
	check(summon.is_queued_for_deletion(), "the original P duration scan retires the dead actor")
	enemy.queue_free()
	owner.queue_free()
	await get_tree().process_frame
	_finish()

func _finish() -> void:
	proof.write_receipt("multicore_summon_full_model_20261014", proof.records.size(), errors.size())
	if errors.is_empty():
		print("MULTICORE_SUMMON_FULL_MODEL_20261014_PASS")
	else:
		for message: String in errors:
			printerr(message)
	get_tree().quit(0 if errors.is_empty() else 1)
