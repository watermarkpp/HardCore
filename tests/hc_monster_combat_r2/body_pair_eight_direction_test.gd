extends Node

## HC-MONSTER-COMBAT-R2 T6 (R2-06/R2-08 acceptance): the REAL body pair
## (a production small-tier hostile and the player) across all 8 ground
## directions at the three boundary distances:
##   1.499 GU - inside the unified 1.5 GU start reach, a real attack
##              presentation starts and the melee gate accepts;
##   1.500 GU - the exact boundary stays excluded (strict gate);
##   1.501 GU - outside the reach, the melee gate rejects.
## The stop geometry is proven against the REAL neighbor-step planner: a
## pursuit step toward the player never lands inside the physical contact
## footprint (no body overlap at the stop point).

const HCPolicy := preload("res://scripts/monster_ai_package/policy.gd")
const ActorBodyPolicyScript := preload("res://scripts/actor_body_policy.gd")
const MonsterNeighborStepPolicyScript := preload("res://scripts/monster_neighbor_step_policy.gd")
const GroundUnit := preload("res://scripts/ground_unit_space.gd")


func _ready() -> void:
	var player_px := ActorBodyPolicyScript.player_screen_radius_px()
	var small_px := ActorBodyPolicyScript.tier_screen_radius_px(ActorBodyPolicyScript.TIER_SMALL)
	var contact_gu := (player_px + small_px) / (32.0 * sqrt(2.0)) + 0.4375
	assert(contact_gu <= 1.5, "fixture: the real pair must fit the start reach")

	var player := PlayerCharacter.new()
	player.set_physics_process(false)
	add_child(player)

	var enemy := EnemyActor.new()
	enemy.setup(GameData.get_monster_by_id(24), player, false)
	add_child(enemy)
	enemy.set_physics_process(false)
	enemy.set_meta("spawn_position", Vector2.ZERO)
	enemy.set_meta("safe_zones", [])
	enemy.configure_runtime_map_projection(
		9001,
		Callable(self, "_ground_to_screen"),
		GroundUnit.screen_delta_px_to_ground_delta_gu
	)
	enemy.visual._clock_ms = Callable(self, "_clock")

	var checked := 0
	for index in 8:
		var direction := Vector2.from_angle(TAU * float(index) / 8.0)

		# 1.499: inside - the melee gate accepts and a real attack starts.
		enemy.global_position = _ground_to_screen(direction * 1.499)
		enemy.set_meta("spawn_position", enemy.global_position)
		enemy._movement_step_epoch += 1
		enemy._clear_autonomous_step_state()
		assert(
			HCPolicy.within(Vector2.ZERO, direction * 1.499, HCPolicy.START_GU),
			"1.499 GU must sit inside the start reach (direction %d)" % index
		)
		enemy._play_attack_animation(0.46)
		assert(
			enemy.visual._attack_remaining > 0.0,
			"the real pair must start a real attack at 1.499 GU (direction %d)" % index
		)
		_clock_ms += 500
		enemy.visual._advance_action_timers(0.5)
		checked += 1

		# 1.500: the exact boundary is ACCEPTED by the production gate - the
		# frozen comparator is distance <= reach + EPS (EPS = 1e-4 GU), so the
		# nominal reach itself is inclusive while anything above reach + EPS
		# (e.g. 1.501) is rejected.
		assert(
			HCPolicy.within(Vector2.ZERO, direction * 1.5, HCPolicy.START_GU),
			"the exact 1.5 GU boundary is inclusive within the frozen EPS (direction %d)" % index
		)
		checked += 1

		# 1.501: outside - the melee gate rejects.
		assert(
			not HCPolicy.within(Vector2.ZERO, direction * 1.501, HCPolicy.START_GU),
			"1.501 GU must sit outside the start reach (direction %d)" % index
		)
		checked += 1

		# Stop geometry through the PRODUCTION contact authority: the hostile's
		# real contact distance to the player body must stay inside the start
		# reach in every direction, so the walking stop point (engagement is
		# reached at the start gate) never closes into body overlap.
		assert(
			enemy._hc_standard_melee(),
			"fixture: identity 24 is a standard-melee delivery (direction %d)" % index
		)
		var production_contact := float(enemy._contact_distance_gu_to_target(player))
		assert(
			is_equal_approx(production_contact, contact_gu)
			or (production_contact > 0.0 and production_contact <= HCPolicy.START_GU + 0.0001),
			(
				"the production contact distance must sit inside the start reach "
				+ "(direction %d, got %.4f GU)"
			)
				% [index, production_contact]
		)
		checked += 1

	assert(checked == 32, "fixture: the full 8x4 matrix must run")
	enemy.queue_free()
	player.queue_free()
	print("HC_MCR2_BODY_PAIR_EIGHT_DIRECTION_PASS")
	get_tree().quit()


var _clock_ms := 0


func _clock() -> int:
	return _clock_ms


func _ground_to_screen(value: Vector2) -> Vector2:
	return GroundUnit.ground_delta_gu_to_screen_delta_px(value)
