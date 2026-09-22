extends Node
const Space := preload("res://scripts/ground_unit_space.gd")
class Probe extends PlayerCharacter:
	var commits := 0
	var poisons := 0
	var controls := 0
	func _apply_resolved_damage(amount: int, causes_struck: bool, damage_type := "physical", durability_context := {}, force_struck_reaction := false) -> void:
		commits += 1
		super._apply_resolved_damage(amount,causes_struck,damage_type,durability_context,force_struck_reaction)
	func apply_poison(_damage: int, _duration: float) -> void: poisons += 1
	func apply_control(_duration: float) -> void: controls += 1
	func is_in_safe_zone() -> bool: return false

func _ready() -> void: _run.call_deferred()
func is_environment_point_blocked(_point: Vector2) -> bool: return false
func _ground_to_screen(point: Vector2) -> Vector2: return Space.ground_delta_gu_to_screen_delta_px(point)
func _screen_to_ground(point: Vector2) -> Vector2: return Space.screen_delta_px_to_ground_delta_gu(point)

func _run() -> void:
	assert(GameData.ensure_loaded())
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	PlayerState.level = 60
	PlayerState.recalculate_stats(false)
	var player := Probe.new()
	player.set_meta("runtime_map_id",1)
	add_child(player)
	player.set_physics_process(false)
	player.max_hp = 100000
	player.current_hp = 100000
	player.defense_min = 0
	player.defense_max = 0
	PlayerState.computed_stats.magic_defense_min = 0
	PlayerState.computed_stats.magic_defense_max = 0
	PlayerState.computed_stats.anti_magic_points = 10
	# Every harmful spell family, empty-ID monster magic and mixed release.
	for id: String in ["", "wizard.fireball", "wizard.lightning", "wizard.fire_wall", "wizard.ice_storm", "wizard.hell_thunder", "taoist.soul_fire_talisman"]:
		var state := player._rng.state
		var result := player.take_direct_spell_damage(id,100,0)
		assert(result.magic_evaded and result.applied_damage==0 and not result.magic_defense_checked,id)
		assert(player._rng.state == state,"forced evasion miss must not roll MAC/durability")
	var reference := RandomNumberGenerator.new()
	player._rng.seed = 9183
	reference.seed = 9183
	reference.randi_range(0,9)
	var mixed := player.take_monster_mixed_damage(100,100,{"release_id":"one-mixed-event"})
	assert(mixed.magic_evaded and mixed.applied_damage==0)
	assert(player._rng.state==reference.state,"mixed release must use exactly one evasion roll")
	assert(player.commits==0 and player.current_hp==100000)
	var attacker := EnemyActor.new()
	attacker.setup({"monster_id":150},null,false)
	attacker.environment_blocker = self
	attacker.configure_runtime_map_projection(1,_ground_to_screen,_screen_to_ground)
	add_child(attacker)
	attacker.set_physics_process(false)
	attacker.accuracy = 999
	attacker.control_on_hit_seconds = 2.0
	attacker.control_chance_denominator_base = 1
	attacker.behavior_profile = {"onHit":{"poisonDamage":4,"poisonSeconds":5}}
	attacker.max_hp = 100
	attacker.current_hp = 50
	# Real frozen projectile release path, including adjacent ranged shots.
	assert(attacker._launch_physical_projectile(player,100))
	attacker._settle_physical_projectile_release(attacker._pending_attack_release_record)
	assert(player.commits==0 and player.controls==0 and player.poisons==0 and attacker.current_hp==50)
	var physical_delivery := attacker.attack_delivery_rule.duplicate(true)
	attacker.attack_delivery_rule = {"status":{"statusChance":1.0,"poisonWeight":1,"controlWeight":0,"poisonDamage":4,"poisonSeconds":8}}
	attacker._deal_area_magic_damage(player,100)
	assert(player.commits==0 and player.poisons==0 and attacker.last_magic_attack_resolution.magic_evaded)
	assert(not attacker._apply_monster_special_magic_damage(player,100,"line_magic"))
	# A physical melee attack remains governed by accuracy/agility only.
	attacker._apply_attack_damage(player,100,false)
	assert(player.commits==1 and player.current_hp==99900 and player.poisons==1 and player.controls==1, "melee: %s" % [ [player.commits,player.current_hp,player.poisons,player.controls] ])
	PlayerState.computed_stats.anti_magic_points = 0
	attacker.attack_delivery_rule = physical_delivery
	assert(attacker._launch_physical_projectile(player,100))
	attacker._settle_physical_projectile_release(attacker._pending_attack_release_record)
	assert(player.commits==2 and player.current_hp==99800 and player.poisons==2)
	# All ten deterministic thresholds; real incoming HP changes, not just JSON.
	PlayerState.computed_stats.anti_magic_points = 3
	for roll in range(10):
		var hp := player.current_hp
		var result := player.take_ranged_damage(10,false,false,roll)
		assert(bool(result.magic_evaded)==(roll<3))
		assert(player.current_hp==hp-(0 if roll<3 else 10))
	# Monster-target original spell susceptibility remains its own contract.
	assert(not CombatResolutionRules.resolve_magic_damage("wizard.ice_storm",10,10,0).magic_evaded)
	player.free()
	attacker.free()
	print("RANGED_MAGIC_EVASION_PASS projectile adjacent melee AoE mixed single-roll side-effects ten-thresholds")
	get_tree().quit()
