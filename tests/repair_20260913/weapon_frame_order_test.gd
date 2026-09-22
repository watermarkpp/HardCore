extends Node
const Visual := preload("res://scripts/player_visual.gd")

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	assert(GameData.ensure_loaded())
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	PlayerState.gender = "男"
	var player := PlayerCharacter.new()
	add_child(player)
	await get_tree().process_frame
	player.set_process(false)
	player.set_physics_process(false)
	var visual := player.visual as Visual
	visual.set_process(false)
	var master: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/equipment_attribute_master.json"))
	# Direct primary WORDER rows 128..191. Zero means behind the actor body.
	var run_rows := ["000000", "111111", "111111", "111111", "001111", "001110", "000000", "000000"]
	var weapons := 0
	var wand_seen := false
	var checked := 0
	for gender: String in ["男", "女"]:
		PlayerState.gender = gender
		for record: Dictionary in master.records:
			if str(record.category) != "武器": continue
			weapons += 1
			var catalog := GameData.get_item_record({"item_id": int(record.itemId)})
			wand_seen = wand_seen or str(catalog.name) == "魔杖"
			PlayerState.equipment["武器"] = PlayerState._make_item_instance(str(catalog.name), catalog, 800000 + int(record.itemId))
			visual._refresh_equipment_visuals()
			for row in range(8):
				for frame in range(6):
					visual.current_state = "run"
					visual.current_direction = row
					visual.current_frame = frame
					visual._update_equipment_layers()
					var expected := str(run_rows[row]).substr(frame, 1) == "0"
					assert(EquipmentRules.weapon_draws_behind_actor(row, "run", frame, gender) == expected)
					assert((visual.worn_weapon_sprite.get_index() < visual.sprite.get_index()) == expected,
						"weapon id=%d direction=%d frame=%d" % [record.itemId, row, frame])
					assert(visual.worn_weapon_sprite.z_index == 0 and visual.sprite.z_index == 0)
					assert(not visual.y_sort_enabled)
					checked += 1
			visual.current_direction = 4
			visual.current_frame = 2
			visual.current_state = "run"
			visual._update_equipment_layers()
			assert(visual.worn_weapon_sprite.get_index() > visual.sprite.get_index())
			visual.current_state = "idle"
			visual._update_equipment_layers()
			assert(visual.worn_weapon_sprite.get_index() < visual.sprite.get_index(), "same-direction action transition")
	assert(weapons == 74 and wand_seen)
	print("WEAPON_FRAME_ORDER_TEST_PASS weapon_gender_pairs=%d poses=%d primary_run_rows=8 frame_transitions=verified" % [weapons, checked])
	get_tree().quit(0)
