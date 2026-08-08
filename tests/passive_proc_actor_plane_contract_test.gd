extends Node

const EquipmentRulesScript := preload("res://scripts/equipment_rules.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	var player := PlayerCharacter.new()
	add_child(player)
	await get_tree().process_frame
	var visual: Node2D = player.visual
	# The actor visual composite is a single world actor plane: z=0,
	# z_as_relative, not internally y-sorted, not top-level.
	assert(visual.z_index == 0)
	assert(visual.z_as_relative)
	assert(not visual.y_sort_enabled)
	assert(not visual.is_set_as_top_level())
	assert(
		str(visual.get_meta("actor_render_domain", "")) == "actor_y_sort"
	)
	assert(
		str(visual.get_meta("actor_composite_sort_contract", ""))
		== EquipmentRulesScript.ACTOR_VISUAL_SORT_CONTRACT_ID
	)
	# PassiveProcSkillEffect belongs to the actor composite plane.
	var proc := visual.get_node("PassiveProcSkillEffect") as Sprite2D
	assert(proc != null, "PassiveProcSkillEffect node must exist")
	assert(proc.get_parent() == visual, "proc effect must be a child of the actor composite")
	assert(proc.z_index == 0, "proc effect must sit on the formal actor plane z=0")
	assert(proc.z_as_relative, "proc effect must inherit the composite plane")
	assert(not proc.y_sort_enabled)
	assert(not proc.is_set_as_top_level())
	# Effective z through the parent chain must equal the formal plane.
	var effective_z := visual.z_index + proc.z_index
	assert(effective_z == 0, "effective proc effect z must be 0 (single world actor plane)")
	# Playing the proc effect must not change its plane or hide it.
	visual.play_passive_proc_effect("actor_composite_plane_probe")
	await get_tree().process_frame
	await get_tree().process_frame
	assert(proc.z_index == 0, "proc effect plane must not change while playing")
	assert(not proc.is_set_as_top_level())
	assert(proc.get_parent() == visual)
	player.queue_free()
	await get_tree().process_frame
	print("PASSIVE_PROC_ACTOR_PLANE_CONTRACT_PASS")
	get_tree().quit(0)
