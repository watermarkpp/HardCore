extends Node

const CombatRuntimeServiceScript := preload(
	"res://scripts/layers/runtime/combat_runtime_service.gd"
)

## Real incoming-delivery coverage: the enemy physical bridge and the enemy
## direct area-magic bridge must land on SummonActor's AC/MAC consumers rather
## than treating the pet as a raw HP node.


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var previous_test_mode := PlayerState.test_mode
	PlayerState.test_mode = true
	var owner := PlayerCharacter.new()
	owner.current_hp = 100
	add_child(owner)
	var summon := SummonActor.new()
	summon.setup(owner, "骷髅", 1, 0, "taoist.summon_skeleton", 19, 1)
	add_child(summon)
	await get_tree().process_frame
	summon.set_physics_process(false)

	var enemy := EnemyActor.new()
	enemy.attack_min = 10
	enemy.attack_max = 10
	var combat_runtime := CombatRuntimeServiceScript.new()

	# Rank-0 skeleton AC is 2..4.  The shared enemy physical entry therefore
	# leaves 6..8 damage from a raw 10, never the raw 10 itself.
	summon.current_hp = 100
	var physical_before := summon.current_hp
	assert(combat_runtime.apply_enemy_physical_damage(summon, 10, enemy))
	var physical_damage := physical_before - summon.current_hp
	assert(
		physical_damage >= 6 and physical_damage <= 8,
		"enemy physical bridge bypassed summon AC: %d" % physical_damage
	)

	# Enemy area magic uses the direct-spell method and therefore consumes MAC,
	# while bypassing AC.  Rank-0 skeleton MAC is 3..6, so raw 10 becomes 4..7.
	summon.current_hp = 100
	enemy._deal_area_magic_damage(summon, 10)
	var magic_resolution: Dictionary = enemy.last_magic_attack_resolution
	var magic_damage := 100 - summon.current_hp
	assert(bool(magic_resolution.get("success", false)))
	assert(bool(magic_resolution.get("magic_defense_checked", false)))
	assert(magic_damage >= 4 and magic_damage <= 7)
	assert(bool(magic_resolution.get("physical_defense_bypassed", false)))

	combat_runtime.free()
	enemy.free()
	summon.queue_free()
	owner.queue_free()
	await get_tree().process_frame
	PlayerState.test_mode = previous_test_mode
	print(
		"SUMMON_INCOMING_DAMAGE_RUNTIME_PASS: enemy physical consumes AC; "
		+ "enemy direct area magic consumes MAC"
	)
	get_tree().quit(0)
