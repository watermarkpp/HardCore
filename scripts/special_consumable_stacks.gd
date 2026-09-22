extends RefCounted
## Lossless legacy migration. Existing items never change slots or cross a page.
const EFFECTS := ["temporary_stat_buff", "blessing_oil", "repair_oil", "war_god_oil"]

static func split_available(records: Array, capacity: int, page_size: int) -> Array:
	var result := records
	var copied := false
	for page_start in range(0, capacity, page_size):
		var page_end := mini(page_start + page_size, capacity)
		var free: Array[int] = []
		var candidates: Array[int] = []
		for index in range(page_start, page_end):
			if index >= records.size() or (records[index] is Dictionary and records[index].is_empty()):
				free.append(index)
			elif records[index] is Dictionary and int(records[index].get("count", 1)) > 1:
				var record: Dictionary = records[index]
				if record.has("instance_id"):
					continue
				var item := GameData.get_item_record(record)
				if str(item.get("useEffect", "")) in EFFECTS and not bool(item.get("stackable", true)):
					candidates.append(index)
		var cursor := 0
		for index: int in candidates:
			var available := mini(int(records[index].count) - 1, free.size() - cursor)
			if available <= 0:
				break
			if not copied:
				result = records.duplicate()
				copied = true
			var source: Dictionary = records[index].duplicate(true)
			source["count"] = int(source.count) - available
			result[index] = source
			for _i in available:
				var target := free[cursor]
				cursor += 1
				while result.size() <= target:
					result.append({})
				var single := source.duplicate(true)
				single["count"] = 1
				result[target] = single
	return result
