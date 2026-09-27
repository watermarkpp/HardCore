extends Node

## REVIEW FIXTURE ONLY. Godot NOT_RUN here. A refused body must not advertise
## damageability to targeting/spatial consumers while silently rejecting HP.
## The full factory/index/reservation test is ALSO required by the plan.

func _ready() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var rejected := EnemyActor.new()
	rejected.setup(GameData.get_monster_by_id(24), null, false)
	rejected.combat_body_profile = {}
	add_child(rejected)
	rejected.set_physics_process(false)
	var was_rejected := bool(rejected.get_meta("body_policy_rejected", false))
	var advertised_damageability := rejected.can_receive_damage()
	var hp_before: int = rejected.current_hp
	rejected.take_damage(50)
	var hp_changed := rejected.current_hp != hp_before
	rejected.queue_free()
	if not was_rejected or advertised_damageability or hp_changed:
		printerr("R4_BODY_QUERY: rejected=%s can_receive_damage=%s hp_changed=%s" % [was_rejected, advertised_damageability, hp_changed])
		get_tree().quit(1)
		return
	print("R4_BODY_REJECTED_QUERY_CONTRACT_PASS")
	get_tree().quit(0)
