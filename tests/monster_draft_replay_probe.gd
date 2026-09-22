extends Node

const LabScript := preload(
	"res://tools/visual_acceptance_lab/visual_acceptance_lab.gd"
)
const PROBE_IDS := [18, 28]


func _ready() -> void:
	PlayerState.test_mode = true
	var lab := LabScript.new()
	add_child(lab)
	await get_tree().process_frame
	if not lab._is_monster_mode():
		lab._mode_option.select(1)
		lab._on_mode_changed(1)
		await get_tree().process_frame
	for monster_id: int in PROBE_IDS:
		var option_index := -1
		for index in lab._monster_rows.size():
			if int(lab._monster_rows[index].get("monster_id", -1)) == monster_id:
				option_index = index
				break
		assert(option_index >= 0)
		lab._monster_option.select(option_index)
		lab._rebuild_monster_actor(true)
		lab._apply_preview_frame()
		await get_tree().process_frame
		var visual: MonsterVisual = lab._monster.visual
		var sprite: Sprite2D = visual.sprite
		var draft := lab.MonsterDraftScript.load_draft(monster_id)
		print(
			"MONSTER_DRAFT_REPLAY_PROBE ",
			JSON.stringify({
				"monsterId": monster_id,
				"monsterName": str(lab._monster.display_name),
				"draftSavedAt": str(draft.get("savedAt", "")),
				"draftSelection": draft.get("selection", {}),
				"runtimeVisualOrigin": draft.get("runtimeVisualOrigin", []),
				"visualOffset": draft.get("visualOffset", []),
				"pickedVisualFootOffset": draft.get(
					"pickedVisualFootOffset", []
				),
				"visualPosition": [
					visual.position.x, visual.position.y,
				],
				"actorPosition": [
					lab._monster.position.x, lab._monster.position.y,
				],
				"playerPosition": [
					lab._player.position.x, lab._player.position.y,
				],
				"spritePosition": [
					sprite.position.x, sprite.position.y,
				],
				"frameSize": [visual.frame_size.x, visual.frame_size.y],
				"footAnchor": [visual.foot_anchor.x, visual.foot_anchor.y],
				"actorGroundOffset": [
					visual.actor_ground_offset.x,
					visual.actor_ground_offset.y,
				],
				"state": visual.current_state,
				"direction": visual.current_direction,
				"frame": visual.current_frame,
				"region": [
					sprite.region_rect.position.x,
					sprite.region_rect.position.y,
					sprite.region_rect.size.x,
					sprite.region_rect.size.y,
				],
				"texturePath": (
					sprite.texture.resource_path
					if sprite.texture != null
					else ""
				),
				"visualFootOrigin": [
					lab._visual_foot_origin().x,
					lab._visual_foot_origin().y,
				],
			}),
		)
	lab.queue_free()
	await get_tree().process_frame
	print("MONSTER_DRAFT_REPLAY_PROBE_PASS")
	get_tree().quit(0)
