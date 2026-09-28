extends Node


func _ready() -> void:
	var priest := EnemyActor.new()
	priest.setup(GameData.get_monster_by_id(222), null, false)
	assert(priest.monster_id == 222)
	assert(int(priest.behavior_profile.get("serviceClass", {}).get("race", -1)) == 200)
	assert(is_equal_approx(priest.life_steal_ratio, 0.2))
	priest.current_hp = 100
	priest.apply_source_magic_life_steal(4)
	assert(priest.current_hp == 100, "source integer division has no +1 floor")
	priest.apply_source_magic_life_steal(15)
	assert(priest.current_hp == 103, "source post-MAC magic heal must divide by five")
	priest.apply_source_magic_life_steal(0)
	assert(priest.current_hp == 103)
	priest.free()
	print("MONSTER_MAGIC_LIFESTEAL_PASS id222=1 integer_division=1 zero_result=1")
	get_tree().quit(0)
