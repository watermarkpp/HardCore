extends Node

const GroundUnit := preload("res://scripts/ground_unit_space.gd")
const RAW_DAMAGE := 20
const MAP_ID := 910001
const ORIGIN_GU := Vector2(38.5, 13.5)

var _owner: PlayerCharacter
var _targets: Dictionary = {}
var _summons: Array[SummonActor] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var previous_test_mode := PlayerState.test_mode
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	PlayerState.profession = "道士"
	PlayerState.level = 40
	_owner = PlayerCharacter.new()
	add_child(_owner)
	_owner.set_physics_process(false)
	_owner.current_hp = _owner.max_hp
	_owner.global_position = _ground_to_screen(ORIGIN_GU)

	# Each actor is initialized from its exact canonical ID. No fake name/stats
	# payload, shadow take_damage implementation, or mutated defense cache.
	for monster_id: int in [38, 39, 57, 135]:
		_targets[monster_id] = _new_target(monster_id)
	assert((_targets[38] as EnemyActor).defense == 0)
	assert((_targets[38] as EnemyActor).magic_defense == 0)
	assert((_targets[39] as EnemyActor).defense == 100)
	assert((_targets[39] as EnemyActor).magic_defense == 0)
	assert((_targets[57] as EnemyActor).defense == 0)
	assert((_targets[57] as EnemyActor).magic_defense == 100)
	for monster_id: int in [38, 39, 57, 135]:
		var target := _targets[monster_id] as EnemyActor
		var magic_stats: Dictionary = {}
		assert(target.direct_spell_runtime_stats_into(magic_stats))
		assert(
			int(magic_stats.get("anti_magic_points", -1)) == 0,
			"fixture anti-magic must be zero; resistance cannot prove MAC absorption",
		)
		assert(int(magic_stats.magic_defense_min) == target.magic_defense)
		assert(int(magic_stats.magic_defense_max) == target.magic_defense)

	var skeleton := _new_summon("taoist.summon_skeleton")
	var divine := _new_summon("taoist.summon_divine_beast")
	assert(skeleton.attack_type == "physical" and divine.attack_type == "fire")
	var observations: Dictionary = {}
	for summon: SummonActor in [skeleton, divine]:
		var rows: Dictionary = {}
		for monster_id: int in [38, 39, 57]:
			rows[monster_id] = _release(summon, _targets[monster_id], 0)
		observations[summon.summon_id] = rows

	var physical: Dictionary = observations.skeleton
	var fire: Dictionary = observations.divine_beast
	assert(int(physical[38]) == RAW_DAMAGE, "zero AC skeleton hit must deliver raw DC")
	assert(
		int(physical[39]) == 1,
		"skeleton release bypassed canonical AC100 (physical floor1): %s" % str(physical),
	)
	assert(int(physical[57]) == RAW_DAMAGE, "skeleton incorrectly consumed MAC100")
	assert(int(fire[38]) == RAW_DAMAGE, "zero MAC divine hit must deliver raw DC")
	assert(int(fire[39]) == RAW_DAMAGE, "divine fire incorrectly consumed AC100")
	assert(
		int(fire[57]) == 0,
		"divine release bypassed MAC100 or used the physical floor1: %s" % str(fire),
	)
	assert(divine.synchronize_skill_rank(4))
	assert(_release(divine, _targets[38], 0) == 22, "rank4 divine More must apply before MAC")
	assert(_release(divine, _targets[57], 0) == 0, "rank4 divine must still honor MAC100")
	assert(divine.synchronize_skill_rank(5))
	assert(_release(divine, _targets[38], 0) == 24, "rank5 divine More must apply once")
	assert(skeleton.synchronize_skill_rank(5))
	assert(_release(skeleton, _targets[38], 0) == RAW_DAMAGE, "extra summon rank must not boost a skeleton's individual damage")
	for summon: SummonActor in [skeleton, divine]:
		_verify_miss_boundary(summon, _targets[135])
		_verify_moved_target_rejects_release(summon, _targets[38])
	for summon: SummonActor in _summons:
		summon.queue_free()
	for target: EnemyActor in _targets.values():
		target.queue_free()
	_owner.queue_free()
	await get_tree().process_frame
	PlayerState.test_mode = previous_test_mode
	print("SUMMON_OUTGOING_DEFENSE_PRODUCTION_PASS: actual release AC/MAC, hit/miss, frozen geometry and single commit")
	get_tree().quit(0)


func _new_target(monster_id: int) -> EnemyActor:
	var target := EnemyActor.new()
	target.setup(GameData.get_monster_by_id(monster_id), _owner, false)
	assert(target.monster_id == monster_id and not target.get_meta("canonical_rejected", false))
	target.configure_runtime_map_projection(
		MAP_ID, Callable(self, "_ground_to_screen"), Callable(self, "_screen_to_ground"),
	)
	target.global_position = _ground_to_screen(ORIGIN_GU + Vector2(1.0, 0.0))
	add_child(target)
	target.set_physics_process(false)
	target.set_process(false)
	assert(target.can_receive_damage() and target.max_hp > RAW_DAMAGE)
	return target


func _new_summon(skill_id: String) -> SummonActor:
	var summon := SummonActor.new()
	summon.setup(_owner, ProfessionRules.skill_display_name(skill_id), 1, 3, skill_id, 40, 7)
	summon.configure_runtime_map_projection(
		MAP_ID, Callable(self, "_ground_to_screen"), Callable(self, "_screen_to_ground"),
	)
	summon.global_position = _ground_to_screen(ORIGIN_GU)
	add_child(summon)
	summon.set_physics_process(false)
	summon.set_process(false)
	# 20 is within both rank3 canonical attack ranges. Fix only the damage
	# roll; keep each pet's canonical accuracy and every target's AC/MAC/agility.
	assert(summon.attack_min <= RAW_DAMAGE and summon.attack_max >= RAW_DAMAGE)
	summon.attack_min = RAW_DAMAGE
	summon.attack_max = RAW_DAMAGE
	_summons.append(summon)
	return summon


func _prepare_attack(summon: SummonActor, target: EnemyActor) -> void:
	target.current_hp = target.max_hp
	target.set_combat_position(
		_ground_to_screen(ORIGIN_GU + Vector2(1.0, 0.0)), &"summon_outgoing_fixture",
	)
	summon.global_position = _ground_to_screen(ORIGIN_GU)
	summon._begin_attack(target)
	assert(summon._pending_attack_target == target)
	assert(summon.attack_release_snapshot_intersects_target(summon._pending_attack_snapshot, target))
	assert(target.current_hp == target.max_hp, "attack acceptance dealt damage before release")


func _release(summon: SummonActor, target: EnemyActor, exact_hit_roll: int) -> int:
	_prepare_attack(summon, target)
	summon._rng.seed = _seed_for_exact_roll(target.agility, exact_hit_roll)
	var previous_test_mode := PlayerState.test_mode
	PlayerState.test_mode = false
	summon._release_pending_attack()
	PlayerState.test_mode = previous_test_mode
	var damage := target.max_hp - target.current_hp
	assert(summon._pending_attack_target == null, "released attack retained its target")
	var hp_after_first_release := target.current_hp
	summon._release_pending_attack()
	assert(target.current_hp == hp_after_first_release, "one accepted attack dealt damage twice")
	return damage


func _verify_miss_boundary(summon: SummonActor, target: EnemyActor) -> void:
	# Primary TElfWarriorMonster inherits TSpitSpider.SpitAttack: agility roll
	# precedes MAC (ObjMon.pas:698-701). Fire is not an always-hit player spell.
	assert(target.agility > summon.accuracy)
	var hit := _release(summon, target, summon.accuracy - 1)
	var miss := _release(summon, target, summon.accuracy)
	assert(hit > 0, "%s lower hit boundary did not reach real damage" % summon.summon_id)
	assert(
		miss == 0,
		"%s must miss at roll==accuracy before any damage/defense commit" % summon.summon_id,
	)


func _verify_moved_target_rejects_release(summon: SummonActor, target: EnemyActor) -> void:
	_prepare_attack(summon, target)
	target.set_combat_position(
		_ground_to_screen(ORIGIN_GU + Vector2(0.0, 10.0)), &"summon_outgoing_leave_snapshot",
	)
	assert(not summon.attack_release_snapshot_intersects_target(summon._pending_attack_snapshot, target))
	var hp_before := target.current_hp
	summon._release_pending_attack()
	assert(target.current_hp == hp_before, "release ignored its frozen geometry rejection")
	assert(summon._pending_attack_target == null)


func _seed_for_exact_roll(agility: int, exact_roll: int) -> int:
	var probe := RandomNumberGenerator.new()
	for candidate: int in range(1, 4097):
		probe.seed = candidate
		if probe.randi_range(0, agility - 1) == exact_roll:
			return candidate
	assert(false, "could not find summon hit boundary seed")
	return 0


func _ground_to_screen(value: Vector2) -> Vector2:
	return GroundUnit.ground_delta_gu_to_screen_delta_px(value)


func _screen_to_ground(value: Vector2) -> Vector2:
	return GroundUnit.screen_delta_px_to_ground_delta_gu(value)
