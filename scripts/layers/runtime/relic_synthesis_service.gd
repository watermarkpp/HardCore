class_name RelicSynthesisService
extends RefCounted

const Rules := preload("res://scripts/layers/rules/relic_synthesis_rules.gd")

var _player: Node
var _rng := RandomNumberGenerator.new()
var _session_id := ""
var _serial := 0
var _issued: Dictionary = {}
var _busy := false


func _init(player: Node) -> void:
	_player = player
	_rng.randomize()
	_session_id = "%d:%d" % [Time.get_ticks_usec(), _rng.randi()]


func configure_rng(rng: RandomNumberGenerator) -> void:
	_rng = rng


func reset() -> void:
	_issued.clear()
	_busy = false


func quote_synthesis(item_id: int, material_indices: Array[int]) -> Dictionary:
	var quote := _build_quote(item_id, material_indices)
	if not bool(quote.get("valid", false)):
		return quote
	_serial += 1
	quote["quote_id"] = "relic:%s:%d" % [_session_id, _serial]
	if _issued.size() >= 128:
		_issued.clear()
	_issued[quote.quote_id] = quote.duplicate(true)
	return quote


func commit_synthesis(quote: Dictionary) -> Dictionary:
	var quote_id := str(quote.get("quote_id", ""))
	if _busy:
		return _failure("合成正在进行，请稍候。")
	if quote_id.is_empty() or not _issued.has(quote_id) or _issued[quote_id] != quote:
		return _failure("合成报价已失效，请重新选择材料。")
	var indices: Array[int] = []
	for raw: Variant in quote.get("material_indices", []):
		indices.append(int(raw))
	var refreshed := _build_quote(int(quote.get("item_id", -1)), indices)
	if not bool(refreshed.get("valid", false)):
		return refreshed
	var expected := quote.duplicate(true)
	expected.erase("quote_id")
	if refreshed != expected:
		return _failure("合成材料已变化，请重新选择。")
	_busy = true
	_issued.erase(quote_id)
	var tray_before: Array = _player.synthesis_tray.duplicate(true)
	var gold_before: int = _player.gold
	var next_tray: Array = tray_before.duplicate(true)
	for index: int in indices:
		next_tray[index] = {}
	var catalog := Rules.record_for_id(int(quote.item_id))
	var output: Dictionary = _player.call("_make_item_instance", str(catalog.name), catalog, -1, false)
	var rolled := Rules.roll_instance(int(quote.item_id), str(_player.profession), _rng)
	if rolled.is_empty():
		_busy = false
		return _failure("圣物属性生成失败，材料未消耗。")
	output.merge(rolled, true)
	if not Rules.valid_instance(output, int(quote.item_id)):
		_busy = false
		return _failure("圣物属性校验失败，材料未消耗。")
	next_tray[0] = output
	_player.synthesis_tray = next_tray
	_player.gold = gold_before - Rules.GOLD_COST
	if not bool(_player.call("_commit_save")):
		_player.synthesis_tray = tray_before
		_player.gold = gold_before
		_busy = false
		return _failure("合成存档失败，碎片和金币均未改变。")
	_busy = false
	_player.emit_signal("inventory_changed")
	_player.emit_signal("profile_changed")
	return {"valid": true, "committed": true, "item_id": int(quote.item_id), "output": output.duplicate(true), "message": "合成成功：%s" % str(catalog.name)}


func _build_quote(item_id: int, material_indices: Array[int]) -> Dictionary:
	var catalog := Rules.record_for_id(item_id)
	if catalog.is_empty() or material_indices.size() != Rules.FRAGMENT_COUNT:
		return _failure("请选择圣物配方并放入4个远古圣物碎片。")
	if not _player.synthesis_tray[0].is_empty():
		return _failure("请先取走合成格里的圣物。")
	var seen := {}
	for index: int in material_indices:
		if index < 1 or index >= _player.synthesis_tray.size() or seen.has(index):
			return _failure("每个材料格必须放入不同的远古圣物碎片。")
		seen[index] = true
		var raw: Variant = _player.synthesis_tray[index]
		if not raw is Dictionary or (raw as Dictionary).is_empty():
			return _failure("合成材料已变化，请重新选择。")
		var record := GameData.get_item_record(raw)
		if int(record.get("itemId", -1)) != Rules.FRAGMENT_ID or int(raw.get("count", 1)) != 1:
			return _failure("只能放入远古圣物碎片。")
	if int(_player.gold) < Rules.GOLD_COST:
		return _failure("金币不足，无法合成。")
	return {
		"valid": true,
		"profile_id": str(_player.active_profile_id),
		"item_id": item_id,
		"material_indices": material_indices.duplicate(),
		"gold_cost": Rules.GOLD_COST,
		"success_percent": 100,
		"tray_snapshot_digest": JSON.stringify(_player.synthesis_tray).sha256_text(),
		"equipment_snapshot_digest": JSON.stringify(_player.equipment).sha256_text(),
	}


func _failure(message: String) -> Dictionary:
	return {"valid": false, "committed": false, "message": message}
