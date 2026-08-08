extends Node

## Q3-B: the formal GameRoot production entry reproduces the Q3-A frozen
## profession matrix (accepted / reason / MP / cooldown) with zero
## differences, and records release/snapshot/node parity per skill.

const Fixtures := preload(
	"res://tests/helpers/skill_execution_plan_test_fixtures.gd"
)
const GroundUnit := preload("res://scripts/ground_unit_space.gd")
const Plan := preload("res://scripts/skills/skill_execution_plan.gd")
const Router := preload("res://scripts/skills/skill_runtime_router.gd")
const DataLoader := preload("res://scripts/skills/skill_data_loader.gd")

const MATRIX := [
	{
		"skill": "warrior.basic_swordsmanship",
		"display": "基本剑术",
		"profession": "战士",
		"learned": {"基本剑术": 3},
		"melee": false,
		"target": false,
		"expect_mp": 0,
		"spatial": false,
	},
	{
		"skill": "warrior.thrusting",
		"display": "刺杀剑术",
		"profession": "战士",
		"learned": {"基本剑术": 3, "刺杀剑术": 3},
		"melee": true,
		"target": false,
		"expect_mp": 0,
		"spatial": true,
	},
	{
		"skill": "wizard.lightning",
		"display": "雷电术",
		"profession": "法师",
		"learned": {"雷电术": 3},
		"melee": false,
		"target": true,
		"expect_mp": 15,
		"spatial": true,
	},
	{
		"skill": "wizard.laser",
		"display": "疾光电影",
		"profession": "法师",
		"learned": {"疾光电影": 3},
		"melee": false,
		"target": false,
		"expect_mp": 59,
		"spatial": true,
	},
	{
		"skill": "wizard.fire_wall",
		"display": "火墙",
		"profession": "法师",
		"learned": {"火墙": 3},
		"melee": false,
		"target": true,
		"expect_mp": 45,
		"spatial": true,
	},
	{
		"skill": "wizard.fireball",
		"display": "火球术",
		"profession": "法师",
		"learned": {"火球术": 3},
		"melee": false,
		"target": true,
		"expect_mp": 9,
		"spatial": true,
	},
	{
		"skill": "wizard.ice_storm",
		"display": "冰咆哮",
		"profession": "法师",
		"learned": {"冰咆哮": 3},
		"melee": false,
		"target": false,
		"expect_mp": 42,
		"spatial": true,
	},
	{
		"skill": "taoist.defense",
		"display": "神圣战甲术",
		"profession": "道士",
		"learned": {"神圣战甲术": 3},
		"melee": false,
		"target": false,
		"expect_mp": 8,
		"spatial": false,
	},
	{
		"skill": "taoist.poison",
		"display": "施毒术",
		"profession": "道士",
		"learned": {"施毒术": 3},
		"melee": false,
		"target": true,
		"expect_mp": 10,
		"spatial": true,
	},
	{
		"skill": "taoist.summon_skeleton",
		"display": "召唤骷髅",
		"profession": "道士",
		"learned": {"召唤骷髅": 3},
		"melee": false,
		"target": false,
		"expect_mp": 24,
		"spatial": true,
		"summon": true,
	},
]

var _differences: Array = []
var _rows: Array[String] = []
var _game: Node
var _caster: PlayerCharacter
var _target: EnemyActor


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	PlayerState.level = 50
	PlayerState.recalculate_stats()
	_game = load("res://scenes/main.tscn").instantiate()
	add_child(_game)
	await get_tree().process_frame
	await get_tree().process_frame
	_caster = _game.player
	_target = _make_enemy(_game, _caster, _caster.global_position + Vector2(40, 0))
	await get_tree().process_frame
	for row: Dictionary in MATRIX:
		await _matrix_case(row)
	assert(
		_differences.is_empty(),
		"profession matrix parity differences: %s" % "; ".join(_differences)
	)
	for row_line: String in _rows:
		print("SKILL_PRODUCTION_MATRIX_ROW %s" % row_line)
	await get_tree().process_frame
	print(
		"SKILL_PRODUCTION_PROFESSION_MATRIX_PASS skills=%d differences=0"
		% MATRIX.size()
	)
	get_tree().quit(0)


func _matrix_case(row: Dictionary) -> void:
	var skill_id := str(row.get("skill", ""))
	var display_name := str(row.get("display", ""))
	var profession := str(row.get("profession", ""))
	var learned: Dictionary = row.get("learned", {})
	var needs_target := bool(row.get("target", false))
	var melee := bool(row.get("melee", false))
	var amulet := bool(row.get("amulet", false))
	var poison := bool(row.get("poison", false))
	PlayerState.select_profession(profession)
	PlayerState.learned_skills = learned.duplicate()
	PlayerState.inventory = []
	if amulet:
		PlayerState.inventory.append({"name": "护身符", "count": 5})
	if poison:
		PlayerState.inventory.append({"name": "灰色药粉", "count": 5})
	PlayerState.recalculate_stats()
	_caster.current_mp = 500
	_target.current_hp = _target.max_hp
	_target.global_position = _caster.global_position + Vector2(40, 0)
	_target.control_time = 60.0
	_target.apply_control(60.0)
	_target.set_physics_process(false)
	_game._skill_cast_target = _target if needs_target else null
	if needs_target:
		_game._set_magic_locked_target(_target, true)
	var extra := {}
	if melee:
		var snapshot: Dictionary = _game._create_melee_release_footprint_snapshot(
			_caster.global_position,
			Vector2.RIGHT,
			"thrust",
			{}
		)
		extra = {
			"has_target": true,
			"line_of_sight": true,
			"valid_melee_swing": true,
			"eligible_target_count": 1,
			"charge_consumed": false,
			"direct_toggle_release": false,
			"skill_footprint_snapshot": snapshot,
			"release_id": str(snapshot.get("release_id", "")),
		}
	var mp_before := _caster.current_mp
	var result: Dictionary = _game._execute_canonical_skill(
		display_name,
		_caster.global_position,
		Vector2.RIGHT,
		12,
		extra,
		true
	)
	var plan: Dictionary = result.get("canonical_plan", {})
	var exec: Dictionary = result.get("execution_result", {})
	var mp_change := mp_before - _caster.current_mp
	var expected_mp := int(row.get("expect_mp", 0))
	Fixtures.compare_field(
		"%s.mp_change" % skill_id,
		expected_mp,
		mp_change,
		_differences
	)
	var definition := DataLoader.skill(skill_id)
	var expected_rank_mp := int(
		(definition.get("mp_cost_by_rank", [0, 0, 0, 0]) as Array)[3]
	)
	if skill_id == "taoist.poison":
		expected_rank_mp *= 2
	Fixtures.compare_field(
		"%s.mp_vs_definition" % skill_id,
		expected_rank_mp,
		mp_change,
		_differences
	)
	_compare_shadow(row, result, plan)
	var snapshot_id := str(plan.get("snapshot_id", ""))
	if bool(row.get("spatial", false)):
		assert(not snapshot_id.is_empty(), "%s must carry a snapshot id" % skill_id)
	assert(bool(result.get("accepted", false)), "%s must be accepted" % skill_id)
	var projectile_count := (exec.get("spawned_projectile_ids", []) as Array).size()
	var ground_count := (exec.get("spawned_ground_effect_ids", []) as Array).size()
	var summon_count := (exec.get("spawned_summon_ids", []) as Array).size()
	var visual_count := (exec.get("created_visual_ids", []) as Array).size()
	if skill_id == "wizard.fire_wall":
		var field_count := 0
		for child: Node in _game.get_children():
			if child is FireWallFieldController:
				field_count += 1
		assert(field_count == 1, "fire wall controller count")
		assert(
			(_game.get_children().filter(
				func(node: Node) -> bool: return node is FireWallFieldController
			) as Array).size() == 1,
			"fire wall single controller"
		)
	if skill_id == "wizard.fireball":
		assert(projectile_count == 1, "fireball projectile count")
	if bool(row.get("summon", false)):
		assert(_game._canonical_main_pet() != null, "summon pet must exist")
	_rows.append(
		"%s accepted=%s reason=%s mp=%d release=%s snapshot=%s nodes=%d/%d/%d/%d"
		% [
			skill_id,
			str(result.get("accepted", false)),
			str(result.get("reason", "accepted")),
			mp_change,
			str(plan.get("release_id", "")),
			snapshot_id,
			projectile_count,
			ground_count,
			summon_count,
			visual_count,
		]
	)


func _compare_shadow(
	row: Dictionary,
	result: Dictionary,
	plan: Dictionary
) -> void:
	var skill_id := str(row.get("skill", ""))
	var amulet := bool(row.get("amulet", false))
	var poison := bool(row.get("poison", false))
	var resource_context := Fixtures.default_resource_context(500)
	if poison:
		resource_context = Fixtures.poison_resource_context(500)
	elif amulet:
		resource_context = Fixtures.amulet_resource_context(500)
	var request := Fixtures.make_request(
		skill_id,
		3,
		50,
		Vector2i.ZERO,
		Vector2i.DOWN,
		Fixtures.default_target_context(true),
		resource_context
	)
	var snapshot := Fixtures.circle_snapshot(
		self,
		skill_id,
		"q3b:matrix:%s" % skill_id,
		1,
		Vector2(0, 0),
		2.0
	)
	# Q3-C: legacy Plan.build_plan (shadow oracle) was removed with the legacy
	# planner; the reference plan is the canonical planner output for the same
	# frozen inputs (which the Q3-A golden parity test pins to fixtures).
	var shadow: Dictionary = Router.build_canonical_plan(
		request,
		Fixtures.canonical_context(
			1,
			"q3b:matrix:%s" % skill_id,
			0,
			0,
			snapshot
		)
	)
	Fixtures.compare_field(
		"%s.accepted" % skill_id,
		bool(result.get("accepted", false)),
		bool(shadow.get("rejection", {}).get("accepted", false)),
		_differences
	)
	Fixtures.compare_field(
		"%s.reason" % skill_id,
		Plan.normalize_reason(str(result.get("reason", ""))),
		str(shadow.get("rejection", {}).get("reason", "")),
		_differences
	)
	Fixtures.compare_field(
		"%s.mp" % skill_id,
		int(plan.get("resource_cost", {}).get("mp_cost", 0)),
		int(shadow.get("resource_cost", {}).get("mp_cost", 0)),
		_differences
	)
	Fixtures.compare_field(
		"%s.cooldown" % skill_id,
		int(plan.get("cooldown_contract", {}).get("cooldown_ms", 0)),
		int(shadow.get("cooldown_contract", {}).get("cooldown_ms", 0)),
		_differences
	)


func _make_enemy(game: Node, caster: PlayerCharacter, position: Vector2) -> EnemyActor:
	var enemy := EnemyActor.new()
	enemy.setup({
		"name": "profession_matrix_target",
		"hp": 9999,
		"attackMin": 1,
		"attackMax": 1,
		"level": 1,
		"anti_magic_points": 0,
		"magic_defense_min": 0,
		"magic_defense_max": 0,
	}, caster, false)
	enemy.global_position = position
	enemy.control_time = 60.0
	game.add_child(enemy)
	return enemy


func _ground_to_screen(value: Vector2) -> Vector2:
	return GroundUnit.ground_delta_gu_to_screen_delta_px(value)
