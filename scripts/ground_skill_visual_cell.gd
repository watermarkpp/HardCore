class_name GroundSkillVisualCell
extends GroundSkillEffect


func _ready() -> void:
	super._ready()


func _physics_process(delta: float) -> void:
	# Visual cells are pure presentation objects. All damage logic,
	# enemy iteration, and tick claims live exclusively in
	# FireWallFieldController.  Bypassing the parent's combat loop
	# guarantees one enemy-group scan per tick per fire-wall field.
	duration -= delta
	if duration <= 0.0:
		queue_free()
		return
	if _sprite == null:
		queue_redraw()


func runtime_diagnostics() -> Dictionary:
	return {
		"enemy_group_queries": 0,
		"damage_ticks": 0,
	}
