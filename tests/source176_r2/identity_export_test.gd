extends Node2D

## R2/R07 identity export: runs inside the normal test harness so the
## GameData autoload is live, then writes the full monster identity
## admission list to outputs/r2_monster_identity_export.json.

func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var rows: Array = []
	var identity_script := load("res://scripts/monster_identity.gd")
	var monsters: Variant = GameData.get("monsters")
	if monsters == null:
		monsters = []
	for monster in monsters:
		if monster == null:
			continue
		var mid := int(monster.get("id", 0))
		var appearance: Dictionary = identity_script.appearance_profile(mid)
		var behavior: Dictionary = identity_script.behavior_profile(monster)
		var attack_rule: Dictionary = behavior.get("attackDelivery", {})
		var movement: Dictionary = behavior.get("movement", {})
		rows.append({
			"monster_id": mid,
			"name": str(monster.get("name", "")),
			"race": int(monster.get("race", -1)),
			"source_class": ("ordinary_melee" if str(attack_rule.get("kind", "")) == "" else str(attack_rule.get("kind", ""))),
			"gate": "source_decision_tick_v1",
			"ordinary_shape": "linf_box_half_1.0",
			"delivery": str(attack_rule.get("kind", "melee")),
			"appearance_frames": int(appearance.get("actions", {}).get("attack", {}).get("framesPerDirection", 0)),
			"appearance_body": str(appearance.get("body", "")),
			"body_stationary": bool(movement.get("stationary", false)),
			"attack_range_gu": float(monster.get("attack_range", 0.0)),
			"move_speed_gu_per_sec": float(monster.get("walk_speed", 0.0)),
			"walk_interval_ms": int(monster.get("walk_interval", 0)),
			"evidence_status": "exported_offline_identity",
		})
	var file := FileAccess.open("res://outputs/r2_monster_identity_export.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({
		"contract": "monster.source176.r2_identity_export.v1",
		"monster_count": rows.size(),
		"rows": rows,
	}, "  "))
	file.close()
	if rows.size() < 150:
		print("R2_IDENTITY_EXPORT_FAIL monsters=%d" % rows.size())
		get_tree().quit(1)
		return
	print("R2_IDENTITY_EXPORT_OK monsters=%d" % rows.size())
	get_tree().quit(0)
