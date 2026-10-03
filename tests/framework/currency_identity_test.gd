extends Node

const Registry := preload("res://scripts/identity/entity_registry.gd")
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
var proof := Proof.new()
var checks := 0
var failures: Array[String] = []

func check(value: bool, label: String) -> void:
	proof.record(value, label)
	checks += 1
	if not value: failures.append(label)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	PlayerState.test_mode = true
	check(GameData.ensure_loaded(), "real catalog loads")
	check(not Registry.resolve("hc.currency.gold", "currency").is_empty(), "gold already has one registered stable identity")
	# Explicit legacy-authoring observation distinguishes a missing consumer
	# from a missing underlying currency record in the RED execution.
	var legacy: Dictionary = GameData.get_item_record("金币")
	check(legacy.get("kind") == "currency" and int(legacy.get("currencyAmount", 0)) > 0, "existing exact legacy currency source remains available")
	var currency: Dictionary = GameData.get_entity_record("hc.currency.gold")
	check(not currency.is_empty() and currency.get("kind") == "currency", "registered currency resolves through the real entity consumer")
	check(GameData.get_item_record("hc.currency.gold") == currency and not currency.is_empty(), "the item consumer resolves the same catalog currency")
	check(GameData.item_entity_id("hc.currency.gold") == "hc.currency.gold", "stable currency round-trips its identity")
	if currency.is_empty():
		_finish()
		return
	check(currency.get("currency_id") == "hc.currency.gold", "constructed catalog record owns its explicit currency ID")
	# Explicit compatibility observation only; production queries below use IDs.
	check(legacy == currency and GameData.item_entity_id(legacy) == "hc.currency.gold", "exact legacy source import retains the same amount and gains the registered identity")
	var unit := int(currency.get("currencyAmount", 0))
	check(unit == int(legacy.get("currencyAmount", -1)) and unit > 0, "authoritative existing currency amount is unchanged")
	check(GameData.get_item_record({"currency_id": "hc.currency.gold"}) == currency, "typed currency reference resolves without a display name")
	for invalid: Dictionary in [
		{"currency_id": "hc.currency.missing", "name": "金币"},
		{"currency_id": 1, "name": "金币"},
		{"currency_id": "hc.currency.gold", "item_id": 80, "name": "金币"},
		{"currency_id": "hc.currency.gold", "service_index": 123, "name": "金币"},
	]:
		check(GameData.get_item_record(invalid).is_empty(), "malformed/unknown/conflicting currency reference cannot fall back to its display name: " + JSON.stringify(invalid))
	check(GameData.get_entity_record("hc.currency.missing").is_empty(), "unknown registered-namespace query is rejected")
	var detached: Dictionary = GameData.get_item_record("hc.currency.gold")
	detached["currencyAmount"] = unit + 100
	check(int(GameData.get_item_record("hc.currency.gold").currencyAmount) == unit, "caller edits cannot alter the catalog owner")
	PlayerState.reset_progress(false)
	PlayerState.gold = 0
	var inventory_before: Array = PlayerState.inventory.duplicate(true)
	var single: Dictionary = PlayerState._build_receive_batch_result([{"entity_id": "hc.currency.gold", "count": 1}], inventory_before)
	check(bool(single.get("success", false)) and int(single.get("gold_delta", -1)) == unit and single.get("inventory") == inventory_before, "formal ID-only reward credits its exact catalog amount without an item stack")
	var double: Dictionary = PlayerState._build_receive_batch_result([{"entity_id": "hc.currency.gold", "count": 2}], inventory_before)
	check(bool(double.get("success", false)) and int(double.get("gold_delta", -1)) == 2 * unit, "quantity still multiplies the existing currency amount")
	PlayerState.gold = PlayerState.PLAYER_GOLD_CAP - unit + 1
	var capped: Dictionary = PlayerState._build_receive_batch_result([{"entity_id": "hc.currency.gold", "count": 1}], inventory_before)
	check(not bool(capped.get("success", false)) and capped.get("reason") == "gold_cap", "canonical currency cannot bypass the existing gold cap")
	var balance_before := PlayerState.gold
	var pending_before := PlayerState._json_persistence.pending_count()
	var invalid_reward: Dictionary = PlayerState._build_receive_batch_result([{"entity_id": "hc.currency.missing", "name": "金币", "count": 1}], inventory_before)
	check(not bool(invalid_reward.get("success", false)) and invalid_reward.get("reason") == "unknown_item", "explicit unknown reward ID does not fall back to a matching Chinese label")
	check(PlayerState.gold == balance_before and PlayerState.inventory == inventory_before and PlayerState._json_persistence.pending_count() == pending_before, "pure admission/rejection checks create no resource, ownership or writer changes")
	_finish()

func _finish() -> void:
	if not proof.write_receipt("currency_identity_test", checks, failures.size()):
		failures.append("receipt")
	print("CURRENCY_IDENTITY_%s checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL", checks, str(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)
