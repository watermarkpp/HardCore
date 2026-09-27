extends Node

## HC-MONSTER-COMBAT-R3 W3 (R3-04): a body-policy-rejected actor never joins
## the world as a combat participant. It is visible for diagnosis only - not
## an "enemies" member, not damageable, and its reserved CollisionShape2D is
## freed instead of leaking as an orphan node. A normal identity keeps the
## full world admission path.

var _failures: Array[String] = []


func _expect(value: bool, message: String) -> void:
	if not value:
		_failures.append(message)
		printerr("R3_BODY_ISOLATION: ", message)


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var player := PlayerCharacter.new()
	add_child(player)
	player.set_physics_process(false)

	# --- Control: a normal identity keeps the full admission path ---
	var healthy := EnemyActor.new()
	healthy.setup(GameData.get_monster_by_id(24), player, false)
	add_child(healthy)
	healthy.set_physics_process(false)
	_expect(
		healthy.is_in_group("enemies"),
		"the healthy identity must be an enemies member",
	)
	_expect(
		healthy.get_node_or_null("CollisionShape2D") != null,
		"the healthy identity must own its fighting footsole",
	)
	_expect(
		healthy.combat_enabled and not healthy.has_meta("body_policy_rejected"),
		"the healthy identity must stay combat enabled",
	)

	# --- Rejected: a tampered body profile resolves to nothing ---
	var rejected := EnemyActor.new()
	rejected.setup(GameData.get_monster_by_id(24), player, false)
	rejected.combat_body_profile = {}
	add_child(rejected)
	rejected.set_physics_process(false)
	_expect(
		rejected.has_meta("body_policy_rejected"),
		"the tampered profile must be body-policy rejected",
	)
	_expect(
		not rejected.is_in_group("enemies"),
		"a rejected actor must never join the enemies group",
	)
	_expect(
		rejected.is_in_group("enemies_body_rejected"),
		"a rejected actor joins only the diagnostic group",
	)
	_expect(
		not rejected.combat_enabled,
		"a rejected actor must stay combat disabled",
	)
	_expect(
		rejected.get_node_or_null("CollisionShape2D") == null,
		"a rejected actor must not leak an orphan CollisionShape2D",
	)
	var hp_before: int = rejected.current_hp
	rejected.take_damage(50, player)
	_expect(
		rejected.current_hp == hp_before,
		"a rejected actor must take no damage",
	)
	_expect(
		rejected._threat_table.is_empty(),
		"a rejected actor must build no threat",
	)
	_expect(
		not rejected._dying and not rejected._death_pending,
		"a rejected actor can never die in combat",
	)

	healthy.queue_free()
	rejected.queue_free()
	player.queue_free()
	if _failures.is_empty():
		print("R3_BODY_ISOLATION_PASS")
	get_tree().quit(0 if _failures.is_empty() else 1)
