extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Root := preload("res://scripts/game_root.gd")
const HUD := preload("res://scripts/hud.gd")
var proof := Proof.new()
var failures: Array[String] = []
var expired: Array[String] = []

func check(value: bool, label: String) -> void:
	proof.record(value, label)
	if not value: failures.append(label)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	PlayerState.set_process(false)
	PlayerState.profile_directory = "user://temporary_item_identity_%d" % Time.get_ticks_usec()
	PlayerState.temporary_item_buff_expired.connect(func(entity_id: String) -> void: expired.append(entity_id))
	var water := GameData.get_entity_record("hc.item.910001")
	var baseline: Dictionary = PlayerState.computed_stats.duplicate(true)
	check(not water.is_empty(), "fixture uses the existing primary registered water")
	var result: Dictionary = PlayerState.apply_temporary_item_buff("hc.item.910001", water.effectProfile)
	check(result.get("ok", false), "formal item identity admits the actual primary effect")
	check(PlayerState.temporary_item_buffs.has("hc.item.910001")
		and not PlayerState.temporary_item_buffs.has(str(water.name)), "the temporary effect has one formal owner and no name alias")
	var buff: Dictionary = PlayerState.temporary_item_buffs.get("hc.item.910001", {})
	check(buff.get("entity_id") == "hc.item.910001" and buff.get("item_name") == water.name,
		"display metadata is separate from the formal owner")
	check(int(PlayerState.computed_stats.max_hp) == int(baseline.max_hp) + 50,
		"the ID change preserves the real primary max-health bonus")
	var original_started := int(buff.get("started_at_usec", -1))
	PlayerState.advance_temporary_item_buffs(119.99)
	check(not PlayerState.temporary_item_buffs.is_empty() and expired.is_empty(), "actual duration does not expire early")
	result = PlayerState.apply_temporary_item_buff("hc.item.910001", water.effectProfile)
	buff = PlayerState.temporary_item_buffs.get("hc.item.910001", {})
	check(result.get("ok", false) and int(buff.get("started_at_usec", -2)) == original_started
		and is_equal_approx(float(buff.get("remaining", -1)), 120.0), "refresh preserves original order and resets the actual duration")
	var alternate := GameData.get_entity_record("hc.item.910008")
	check(alternate.get("useEffect") == "temporary_stat_buff" and alternate.get("effectProfile", {}).get("buffGroup") == "max_hp",
		"the other same-group fixture comes from actual primary data")
	if not alternate.is_empty() and alternate.has("effectProfile"):
		result = PlayerState.apply_temporary_item_buff("hc.item.910008", alternate.effectProfile)
		buff = PlayerState.temporary_item_buffs.get("hc.item.910008", {})
		check(result.get("ok", false) and PlayerState.temporary_item_buffs.size() == 1
			and not PlayerState.temporary_item_buffs.has("hc.item.910001"), "same group replaces the actual ID without a second owner")
		check(int(buff.get("started_at_usec", -2)) == original_started
			and int(PlayerState.computed_stats.max_hp) == int(baseline.max_hp) + int(alternate.effectProfile.modifiers.max_hp),
			"same-group replacement retains start order and never stacks the old health bonus")
	var before: Dictionary = PlayerState.temporary_item_buffs.duplicate(true)
	var revision := PlayerState.temporary_item_buff_revision
	var stats: Dictionary = PlayerState.computed_stats.duplicate(true)
	for invalid: String in [str(water.name), "测试药水", "hc.item.910001.5", "hc.item.999999", "hc.skill.wizard.fireball", "hc.slot.weapon"]:
		result = PlayerState.apply_temporary_item_buff(invalid, water.effectProfile)
		check(not result.get("ok", false) and PlayerState.temporary_item_buffs == before
			and PlayerState.temporary_item_buff_revision == revision and PlayerState.computed_stats == stats,
			"invalid or presentation-only identity cannot mutate the actual effect: " + invalid)
	var speed := GameData.get_entity_record("hc.item.910003")
	result = PlayerState.apply_temporary_item_buff("hc.item.910003", speed.effectProfile)
	check(result.get("ok", false) and PlayerState.temporary_item_buffs.size() == 2, "different formal groups retain independent real effects")
	PlayerState.advance_temporary_item_buffs(10000)
	check(PlayerState.temporary_item_buffs.is_empty() and PlayerState.computed_stats == baseline,
		"expiry removes every real modifier")
	check(expired.size() == 2 and expired.has("hc.item.910008") and expired.has("hc.item.910003"),
		"expiry publishes each current formal item exactly once")
	PlayerState.advance_temporary_item_buffs(10000)
	check(expired.size() == 2, "repeated expiry cannot repeat the formal completion")
	PlayerState.inventory = [{"item_id": 910001, "name": "展示文字已经改变", "count": 1}]
	result = PlayerState.use_inventory_index_result(0)
	check(result.get("success", false) and PlayerState.item_count("hc.item.910001") == 0
		and PlayerState.temporary_item_buffs.has("hc.item.910001"), "actual use consumes and owns the formal water despite changed display")
	before = PlayerState.temporary_item_buffs.duplicate(true)
	revision = PlayerState.temporary_item_buff_revision
	PlayerState.inventory = [{"item_id": 910003, "name": "另一个显示名称", "count": 1}]
	var inventory_before: Array = PlayerState.inventory.duplicate(true)
	PlayerState._test_force_atomic_write_failure = true
	result = PlayerState.use_inventory_index_result(0)
	PlayerState._test_force_atomic_write_failure = false
	check(not result.get("success", false) and result.get("reason") == "save_failed"
		and PlayerState.inventory == inventory_before and PlayerState.temporary_item_buffs == before
		and PlayerState.temporary_item_buff_revision == revision, "real writer failure restores both typed ownership and the original inventory")
	var game := Root.new()
	game.player = PlayerCharacter.new()
	game.hud = HUD.new()
	add_child(game.hud)
	for _index in range(3): await get_tree().process_frame
	var entries: Array = game._status_buff_entries()
	check(entries.size() == 1 and entries[0].get("entity_id") == "hc.item.910001", "actual status projection carries the formal item owner")
	game.hud.update_status_buffs(entries)
	var icon: TextureRect = game.hud._status_buff_icons.get("item:max_hp")
	check(icon != null and icon.visible and icon.texture != null
		and str(icon.get_meta("item_entity_id", "")) == "hc.item.910001"
		and icon.texture.resource_path == GameData.get_item_art_path("hc.item.910001"), "the real HUD resolves the original art through the formal identity")
	game.hud.update_status_buffs([{"id": "item:service_probe", "entity_id": "hc.service_item.000123", "remaining": 10.0, "started_at": 1}])
	icon = game.hud._status_buff_icons.get("item:service_probe")
	check(icon != null and icon.texture != null and icon.get_meta("item_entity_id", "") == "hc.service_item.000123"
		and icon.texture.resource_path == GameData.get_item_art_path("hc.service_item.000123"), "a registered service-only item icon requires no invented numeric item identity")
	game._on_temporary_item_buff_expired("hc.item.910001")
	check(game.hud.notice_presenter.current_notice().get("message") == str(water.name) + "效果结束",
		"the actual end notice projects the existing Chinese display from the ID")
	game.player.free()
	game.hud.queue_free()
	game.free()
	await get_tree().process_frame
	proof.write_receipt("temporary_item_buff_identity_test", proof.records.size(), failures.size())
	print("TEMPORARY_ITEM_BUFF_IDENTITY_%s checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL", proof.records.size(), str(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)
