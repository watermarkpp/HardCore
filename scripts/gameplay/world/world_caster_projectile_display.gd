extends "res://scripts/skill_projectile.gd"

## Original visual installer/draw/anchor are inherited verbatim on Main.
## S WorldSkillProjectileModel remains the only motion/contact/attack owner.
func _ready() -> void:
	add_to_group("zone_content")
	_install_visual()
	queue_redraw()
	set_physics_process(false)

func _physics_process(_delta: float) -> void: pass
func _apply_hit(_enemy: EnemyActor) -> void:
	assert(false, "Main caster display cannot execute gameplay")
func _emit_projectile_audio_phase(_phase: String, _reason: String) -> void: pass
