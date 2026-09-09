extends "res://tests/hc_monster_ai/test_support.gd"
const Identity := preload("res://scripts/monster_identity.gd")

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var catalog:=Identity._catalog()
	var entries: Dictionary=catalog.get("entries_by_id",{})
	check(not entries.is_empty(),"inventory-source","Read the real canonical ID catalog")
	var player:=PlayerCharacter.new()
	var rows: Array[Dictionary]=[]
	var ids: Array[int]=[]
	for key: String in entries:
		if bool(entries[key].get("runtime_allowed",false)):
			ids.append(int(key))
	ids.sort()
	for id: int in ids:
		var actor:=EnemyActor.new()
		# setup() derives classification from the catalog, not the caller flag.
		actor.setup({"monster_id":id},player,false)
		check(actor.monster_id==id,"inventory-id-%d"%id,"Every enabled identity survives production setup")
		var row:=actor.hc_package_policy_snapshot()
		row["canonical_name"]=actor.display_name
		row["is_boss"]=actor.is_boss
		row["attack_interval_seconds"]=actor._attack_interval
		row["move_speed_gu_per_sec"]=actor.move_speed_gu_per_sec
		row["focus_timeout_ms"]=actor._target_focus_timeout_ms
		row["attack_hit_delay_seconds"]=actor._attack_hit_delay
		rows.append(row)
		actor.free()
	player.free()
	var dir:="res://outputs/hc_monster_ai_package"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var file:=FileAccess.open(dir+"/effective_attack_policy.json",FileAccess.WRITE)
	check(file!=null,"inventory-output","Write the actual per-channel inventory")
	if file!=null:
		file.store_string(JSON.stringify({"runtime_allowed_count":ids.size(),"rows":rows},"\t"))
		file.close()
	finish("inventory")
