extends Node

## Q3-C migration: the legacy Taoist profession package (resolve + execute_cast
## runtime) was removed. This test keeps the frozen Taoist coverage through the
## formal canonical surface:
##  - Taoist skill data contract (13 skills, 4 levels, visual profiles);
##  - Q1-B.1: the formal Taoist defense production entry emits a schema V2
##    runtime-map-absolute cell-union snapshot with a typed int map id and an
##    explicit projection origin.

const DataLoader := preload("res://scripts/skills/skill_data_loader.gd")
const VisualRegistry := preload("res://scripts/caster_skill_visual_registry.gd")
const Snapshot := preload("res://scripts/skills/skill_footprint_snapshot.gd")

const TAOIST_SKILL_IDS := [
	"taoist.spiritual_warfare",
	"taoist.soul_fire_talisman",
	"taoist.healing",
	"taoist.poison",
	"taoist.invisibility",
	"taoist.revelation",
	"taoist.mass_invisibility",
	"taoist.entrapment",
	"taoist.defense",
	"taoist.magic_defense",
	"taoist.mass_healing",
	"taoist.summon_skeleton",
	"taoist.summon_divine_beast",
]


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_check_skill_data_contract()
	await _check_formal_defense_snapshot()
	await get_tree().process_frame
	print("TAOIST_PROFESSION_CANONICAL_PASS skills=%d" % TAOIST_SKILL_IDS.size())
	get_tree().quit(0)


func _check_skill_data_contract() -> void:
	assert(DataLoader.reload_data().valid)
	var skill_ids := DataLoader.skill_ids()
	assert(
		TAOIST_SKILL_IDS.size() == 13,
		"taoist skill count must stay 13"
	)
	for skill_id: String in TAOIST_SKILL_IDS:
		var definition := DataLoader.skill(skill_id)
		assert(not definition.is_empty(), "%s must exist" % skill_id)
		assert(
			(definition.get("ranks", []) as Array).size() == 4,
			"%s must have 4 levels" % skill_id
		)
		assert(
			str(definition.get("class", "")) == "taoist",
			"%s class" % skill_id
		)
		if skill_id == "taoist.spiritual_warfare":
			assert(
				VisualRegistry.visual_type(skill_id).is_empty(),
				"spiritual warfare must stay visual-less"
			)
		else:
			assert(
				VisualRegistry.is_runtime_ready(skill_id),
				"%s must be runtime ready" % skill_id
			)
			assert(
				str(VisualRegistry.profile(skill_id).get("status", ""))
					== "formal_primary_client_animation",
				"%s visual status" % skill_id
			)


func _check_formal_defense_snapshot() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	PlayerState.level = 50
	PlayerState.profession = "道士"
	PlayerState.learned_skills = {"神圣战甲术": 3}
	PlayerState.inventory = [{"name": "护身符", "count": 5}]
	PlayerState.recalculate_stats()
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	game.player.current_mp = 500
	var result: Dictionary = game._execute_canonical_skill(
		"神圣战甲术",
		game.player.global_position,
		Vector2.DOWN,
		0
	)
	assert(bool(result.get("accepted", false)), "formal taoist defense rejected")
	var plan: Dictionary = result.get("canonical_plan", {})
	var snapshot: Dictionary = plan.get("canonical_snapshot", {})
	assert(
		str(snapshot.get("shape_contract_id", ""))
			== Snapshot.CELL_UNION_CONTRACT_ID,
		"taoist defense must emit a cell-union snapshot"
	)
	assert(
		snapshot.get("runtime_map_id") is int,
		"runtime_map_id must be a typed int"
	)
	assert(
		Vector2(snapshot.get("projection_origin_ground_gu", Vector2.INF))
			!= Vector2.INF,
		"projection origin must be explicit"
	)
	assert(
		bool(Snapshot.validate_for_consumer(
			snapshot,
			game._canonical_snapshot_validation_context(
				game._canonical_screen_px_to_ground_gu(
					game.player.global_position
				)
			),
			Snapshot.VALIDATION_STRICT_V2
		).get("valid", false)),
		"formal defense snapshot must pass STRICT_V2"
	)


func _make_enemy(game: Node, caster: PlayerCharacter, position: Vector2) -> EnemyActor:
	var enemy := EnemyActor.new()
	enemy.setup({
		"name": "taoist_canonical_target",
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
