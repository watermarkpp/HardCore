extends Node


func roll_monster_drops(monster_id: int, monster_name: String, rng: RandomNumberGenerator, maximum := 6) -> Dictionary:
	var table := GameData.get_calibrated_drops(monster_id, monster_name)
	if table.is_empty():
		table = WorldContent.monster_drops(monster_name)
	var result: Array[String] = []
	for drop: Variant in table:
		if not drop is Dictionary:
			continue
		var denominator := maxi(1, int(drop.get("denominator", 1)))
		if rng.randi_range(1, denominator) == 1:
			result.append(str(drop.get("itemName", drop.get("name", "未知物品"))))
			if result.size() >= maximum:
				break
	return {"configured": not table.is_empty(), "items": result}
