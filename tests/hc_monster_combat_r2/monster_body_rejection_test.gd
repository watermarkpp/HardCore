extends Node

const MonsterIdentityScript := preload("res://scripts/monster_identity.gd")
const ActorBodyPolicyScript := preload("res://scripts/actor_body_policy.gd")


## HC-MONSTER-COMBAT-R2 T2: production body rejection is fail-closed.
## A tampered or foreign body profile must never fall back to the small tier
## and keep fighting: the enemy stays visible, but combat is disabled, no
## fighting footsole shape exists, and the rejection is diagnosable on the
## instance and in the runtime counters.


func _count_footsole_shapes(actor: Node) -> int:
	var shapes: Array[Node] = actor.find_children(
		"CollisionShape2D", "CollisionShape2D", false, false
	)
	return shapes.size()


func _ready() -> void:
	# Positive control: an untampered managed identity owns exactly one
	# fighting footsole and keeps combat enabled.
	var healthy := EnemyActor.new()
	healthy.setup(GameData.get_monster_by_id(18).duplicate(true), null, true)
	add_child(healthy)
	assert(healthy.combat_enabled, "fixture: a valid profile must keep combat enabled")
	assert(
		_count_footsole_shapes(healthy) == 1,
		"fixture: a valid profile must own exactly one footsole shape"
	)
	assert(
		not healthy.has_meta("body_policy_rejected"),
		"fixture: a valid profile must not carry a rejection meta"
	)
	healthy.queue_free()

	# Rejection 1: a structurally valid profile stamped with a foreign
	# assignment rule (small-tier stamp on a boss identity, 76 沃玛教主).
	var boss_profile: Dictionary = MonsterIdentityScript.body_profile(76)
	assert(
		not boss_profile.is_empty() and str(boss_profile.get("tier")) == "large",
		"fixture: monster 76 must be a large-tier boss identity"
	)
	var foreign := boss_profile.duplicate(true)
	foreign["assignment_rule"] = "default_small"
	var foreign_enemy := EnemyActor.new()
	foreign_enemy.setup(GameData.get_monster_by_id(76).duplicate(true), null, true)
	foreign_enemy.combat_body_profile = foreign
	add_child(foreign_enemy)
	assert(
		not foreign_enemy.combat_enabled,
		"a foreign assignment rule must disable combat, not fall back"
	)
	assert(
		_count_footsole_shapes(foreign_enemy) == 0,
		"a rejected profile must not create a fighting footsole"
	)
	assert(
		foreign_enemy.has_meta("body_policy_rejected"),
		"the rejection must be diagnosable on the instance"
	)
	foreign_enemy.queue_free()

	# Rejection 2: stale policy provenance on an otherwise valid profile.
	var small_profile: Dictionary = MonsterIdentityScript.body_profile(18)
	var stale := small_profile.duplicate(true)
	stale["policy_sha256"] = "fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210"
	var stale_enemy := EnemyActor.new()
	stale_enemy.setup(GameData.get_monster_by_id(18).duplicate(true), null, true)
	stale_enemy.combat_body_profile = stale
	add_child(stale_enemy)
	assert(
		not stale_enemy.combat_enabled,
		"a stale policy hash must disable combat"
	)
	assert(
		_count_footsole_shapes(stale_enemy) == 0,
		"a stale-policy body must not create a fighting footsole"
	)
	stale_enemy.queue_free()

	# Rejection 3: an empty profile (legacy fixture without baked data) must
	# not resurrect the R1 fallback-small-keeps-fighting behavior.
	var empty_enemy := EnemyActor.new()
	empty_enemy.setup(GameData.get_monster_by_id(18).duplicate(true), null, true)
	empty_enemy.combat_body_profile = {}
	add_child(empty_enemy)
	assert(
		not empty_enemy.combat_enabled,
		"an empty profile must disable combat instead of falling back"
	)
	assert(_count_footsole_shapes(empty_enemy) == 0, "an empty profile must not create a footsole")
	empty_enemy.queue_free()

	print("HC_BODY_REJECTION_PASS")
	get_tree().quit()
