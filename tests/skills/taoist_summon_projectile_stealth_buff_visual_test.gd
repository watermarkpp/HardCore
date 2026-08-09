extends Node

const SummonVisualRegistryScript := preload("res://scripts/summon_visual_registry.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var owner := PlayerCharacter.new()
	owner.current_hp = 100
	## Use the formal synchronous profile activation entrypoint; this populates
	## the same registry cache consumed by SummonActor.setup().
	assert(not SummonVisualRegistryScript.profile("skeleton").is_empty())
	assert(not SummonVisualRegistryScript.profile("divine_beast").is_empty())

	var summon := _spawn(owner, "taoist.summon_skeleton")
	summon.apply_stealth(5.0, "buff.taoist.mass_invisibility")
	summon.apply_ac_buff(7, 12.0, "buff.taoist.blessed_armour_ac")
	summon.apply_mac_buff(4, 8.0, "buff.taoist.soul_shield_mac")
	summon._process(0.0)
	assert(summon.is_stealthed())
	assert(
		summon._sprite.self_modulate.a < 0.5,
		"stealth must make the summon body clearly transparent"
	)
	assert(
		summon._sprite.self_modulate.a > 0.1,
		"stealth body must stay readable, not disappear"
	)
	var hints := summon._buff_hint_lines()
	assert(hints.has("AC+7 12s"), "AC hint must stay readable while stealthed")
	assert(hints.has("MAC+4 8s"), "MAC hint must stay readable while stealthed")

	## Stealth expiry restores full body opacity.
	summon._process(5.1)
	assert(not summon.is_stealthed())
	assert(summon._sprite.self_modulate.a == 1.0)

	## Buff hints consume the snapshot and refresh/expire with it.
	summon._process(2.9)
	hints = summon._buff_hint_lines()
	assert(hints.has("AC+7 4s"), "AC hint must refresh remaining seconds")
	assert(not hints.has("MAC+4 8s"), "expired MAC hint must disappear")
	summon._process(4.1)
	assert(summon._buff_hint_lines().is_empty(), "expired AC hint must disappear")

	## Divine beast fire layer follows the same stealth fade/restore.
	var beast := _spawn(owner, "taoist.summon_divine_beast")
	beast.apply_stealth(3.0, "buff.taoist.mass_invisibility")
	beast._process(0.0)
	assert(beast._sprite.self_modulate.a < 0.5)
	assert(
		beast._fire_sprite != null and beast._fire_sprite.self_modulate.a < 0.5,
		"divine beast fire layer must fade with stealth"
	)
	beast._process(3.1)
	assert(beast._sprite.self_modulate.a == 1.0)
	assert(beast._fire_sprite.self_modulate.a == 1.0)

	owner.free()
	print(
		"TAOIST_SUMMON_PROJECTILE_STEALTH_BUFF_VISUAL_PASS: stealth fades "
		+ "body/fire only and restores on expiry; AC/MAC hints render under the "
		+ "health bar, refresh from buff_state_snapshot and disappear on expiry"
	)
	get_tree().quit(0)


func _spawn(owner: PlayerCharacter, skill_id: String) -> SummonActor:
	var summon := SummonActor.new()
	summon.setup(owner, "stealth buff fixture", 1, 0, skill_id, 19, 1)
	add_child(summon)
	summon.set_process(false)
	assert(
		not summon._animation_resources.is_empty(),
		"warm-cache fixture must install visuals immediately"
	)
	return summon
