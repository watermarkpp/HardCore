class_name SkillProjectile
extends Node2D

const CombatResolutionRules := preload("res://scripts/combat_resolution_rules.gd")
const AnimationPlayerScript := preload("res://scripts/caster_skill_animation_player.gd")

const VISUAL_PATHS := {
	"wizard.fireball": "res://assets/art/characters/wizard/effects/arcane_projectile.png",
	"wizard.great_fireball": "res://assets/art/characters/wizard/effects/great_fireball.png",
	"taoist.soul_fire_talisman": "res://assets/art/characters/taoist/effects/soul_fire_talisman.png",
}

var direction := Vector2.RIGHT
var speed := 520.0
var remaining_range := 360.0
var damage := 1
var effect := "damage"
var effect_strength := 0
var effect_duration := 0.0
var projectile_color := Color(0.35, 0.7, 1.0)
var hit_radius := 24.0
var skill_id := ""
var resolution_skill_id := ""
var source_actor: Node2D
var magic_defense_adapter := Callable()
var anti_magic_roll_override := -1
var anti_poison_roll_override := -1
var last_resolution: Dictionary = {}
var _sprite: Sprite2D


func setup(start: Vector2, cast_direction: Vector2, value: int, travel_range: float, color: Color, status_effect := "damage", status_strength := 0, status_duration := 0.0, source_skill_id := "") -> void:
	global_position = start
	direction = cast_direction.normalized() if cast_direction.length() > 0.0 else Vector2.RIGHT
	damage = maxi(0, value)
	remaining_range = maxf(40.0, travel_range)
	projectile_color = color
	effect = status_effect
	effect_strength = status_strength
	effect_duration = status_duration
	resolution_skill_id = ProfessionRules.skill_id(source_skill_id) if not source_skill_id.is_empty() else ""
	skill_id = resolution_skill_id
	if skill_id.is_empty() and PlayerState != null:
		if PlayerState.profession == "法师":
			skill_id = "wizard.fireball"
		elif PlayerState.profession == "道士":
			skill_id = "taoist.soul_fire_talisman"


func configure_runtime_resolution(
	caster: Node2D = null,
	defense_adapter := Callable(),
	anti_magic_roll := -1,
	anti_poison_roll := -1
) -> void:
	source_actor = caster
	magic_defense_adapter = defense_adapter if defense_adapter is Callable else Callable()
	anti_magic_roll_override = anti_magic_roll
	anti_poison_roll_override = anti_poison_roll


func _ready() -> void:
	add_to_group("zone_content")
	_install_visual()
	queue_redraw()


func _install_visual() -> void:
	var candidate := AnimationPlayerScript.new()
	if not candidate.configure(skill_id, direction, 34.0, true):
		candidate.queue_free()
		return
	_sprite = candidate
	add_child(_sprite)


func _physics_process(delta: float) -> void:
	var travel := minf(speed * delta, remaining_range)
	global_position += direction * travel
	remaining_range -= travel
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		if not node is EnemyActor or node.is_queued_for_deletion():
			continue
		if global_position.distance_to(node.global_position) > hit_radius:
			continue
		_apply_hit(node)
		queue_free()
		return
	if remaining_range <= 0.0:
		queue_free()


func _apply_hit(enemy: EnemyActor) -> void:
	if effect == "poison":
		var poison_bound := TaoistCombatMath.anti_poison_random_bound(enemy.anti_poison)
		var poison_roll := anti_poison_roll_override if anti_poison_roll_override >= 0 else randi_range(0, poison_bound - 1)
		var poison_applies := TaoistCombatMath.poison_succeeds(enemy.anti_poison, poison_roll)
		last_resolution = {
			"evasion_channel": "anti_poison",
			"anti_poison_checked": true,
			"anti_poison_random_bound": poison_bound,
			"anti_poison_roll": poison_roll,
			"poison_applies": poison_applies,
		}
		if not poison_applies:
			return
	elif effect == "damage" and CombatResolutionRules.anti_magic_eligible(resolution_skill_id):
		var anti_magic_roll := anti_magic_roll_override if anti_magic_roll_override >= 0 else randi_range(0, CombatResolutionRules.ANTI_MAGIC_ROLL_SIDES - 1)
		last_resolution = CombatResolutionRules.resolve_direct_spell_damage(
			resolution_skill_id,
			damage,
			enemy.monster_data,
			anti_magic_roll,
			magic_defense_adapter
		)
		var resolved_damage := int(last_resolution.final_damage)
		if resolved_damage <= 0:
			return
		enemy.take_damage(resolved_damage, source_actor)
	elif damage > 0:
		enemy.take_damage(damage, source_actor)
	if not is_instance_valid(enemy):
		return
	match effect:
		"poison": enemy.apply_poison(maxi(1, effect_strength), maxf(1.0, effect_duration))
		"control": enemy.apply_control(maxf(0.5, effect_duration))
		"charm": enemy.apply_charm(maxf(1.0, effect_duration))


func _draw() -> void:
	if not skill_id.is_empty():
		return
	draw_line(-direction * 30.0, Vector2.ZERO, Color(projectile_color, 0.25), 10.0)
	if _sprite == null:
		draw_circle(Vector2.ZERO, 9.0, projectile_color)
	draw_circle(Vector2.ZERO, 14.0, Color(projectile_color, 0.22), false, 4.0)
