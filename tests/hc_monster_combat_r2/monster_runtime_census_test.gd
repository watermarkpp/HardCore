extends Node

## HC-MONSTER-COMBAT-R2 T1 (R2-05) runtime census: every runtime-allowed
## canonical monster identity must survive a REAL setup + _ready cycle with
## its identity-bound body profile accepted, combat enabled, a fighting
## footsole present and a successful attack presentation start. This is the
## production census the review demanded: not a mock, not a data-only check.

const MonsterIdentityScript := preload("res://scripts/monster_identity.gd")

const RUNTIME_ALLOWED_FLOOR := 150


func _ready() -> void:
	var counts: Dictionary = GameData.canonical_monster_counts()
	assert(
		int(counts.get("catalog_runtime_allowed_count", 0)) >= RUNTIME_ALLOWED_FLOOR,
		"fixture: the canonical catalog must expose its runtime-allowed set"
	)

	var player := PlayerCharacter.new()
	add_child(player)
	player.set_physics_process(false)

	var census := []
	var body_rejected: Array = []
	var no_footsole: Array = []
	var no_attack_start: Array = []
	var contract_disabled: Array = []
	var spawned := 0
	for raw_id: Variant in GameData._monsters_by_id.keys():
		var monster_id := int(raw_id)
		var entry_value: Variant = GameData._monsters_by_id.get(raw_id)
		if not entry_value is Dictionary:
			continue
		var entry: Dictionary = entry_value
		if not bool(entry.get("runtime_allowed", false)):
			continue
		var enemy := EnemyActor.new()
		enemy.setup(GameData.get_monster_by_id(monster_id), player, false)
		enemy.global_position = Vector2(64.0 * spawned, 0.0)
		enemy.set_meta("spawn_position", enemy.global_position)
		enemy.set_meta("safe_zones", [])
		add_child(enemy)
		enemy.set_physics_process(false)
		spawned += 1

		# Two very different disabled states must not be conflated:
		# - a body-policy REJECTION is a fail-closed identity defect;
		# - a fixed_noncombat contract (e.g. the treasure chests 226-234,
		#   HUMAN_FROZEN combatEnabled=false authority) legitimately keeps
		#   combat off while its body profile is still fully accepted.
		if enemy.has_meta("body_policy_rejected"):
			body_rejected.append(monster_id)
			continue
		var footsole: Node = enemy.get_node_or_null("CollisionShape2D")
		if footsole == null or not (footsole as CollisionShape2D).shape:
			no_footsole.append(monster_id)
			continue
		var identity_entry: Dictionary = MonsterIdentityScript.catalog_entry(monster_id)
		var behavior: Variant = (identity_entry.get("combat", {}) as Dictionary).get(
			"behavior_profile", {}
		)
		var combat_enabled_contract: bool = bool(
			(behavior as Dictionary).get("combatEnabled", true)
		)
		if not combat_enabled_contract:
			contract_disabled.append(monster_id)
			continue
		if not enemy.combat_enabled:
			body_rejected.append(monster_id)
			continue
		enemy._play_attack_animation(0.46)
		if enemy.visual == null or enemy.visual._attack_remaining <= 0.0:
			no_attack_start.append(monster_id)
			continue
		census.append(monster_id)

	assert(
		spawned == int(counts.get("catalog_runtime_allowed_count", -1)),
		"the census must cover every runtime-allowed identity"
	)
	assert(
		body_rejected.is_empty(),
		"no runtime-allowed identity may be body-rejected in production (got %s)"
			% str(body_rejected)
	)
	assert(
		no_footsole.is_empty(),
		"every accepted identity must own a fighting footsole (missing %s)"
			% str(no_footsole)
	)
	assert(
		no_attack_start.is_empty(),
		"every combat identity must start an attack presentation (missing %s)"
			% str(no_attack_start)
	)
	assert(
		contract_disabled.size() == 9,
		"the fixed_noncombat chest family is the only contract-disabled set (got %s)"
			% str(contract_disabled)
	)
	assert(
		census.size() + contract_disabled.size() == spawned,
		"the census must account for every spawned identity"
	)

	for child in get_children():
		if child is EnemyActor:
			child.queue_free()
	player.queue_free()
	print("HC_MCR2_MONSTER_RUNTIME_CENSUS_PASS ids=%d" % census.size())
	get_tree().quit()
