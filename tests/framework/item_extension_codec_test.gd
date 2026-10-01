extends Node

const Codec := preload("res://scripts/items/item_extension_codec.gd")
const DropRules := preload("res://scripts/item_drop_instance_rules.gd")
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const NameStyle := preload("res://scripts/ui_item_name_style.gd")
const LootVisual := preload("res://scripts/loot_visual_effect.gd")
var proof := Proof.new()
var checks := 0
var failures: Array[String] = []

func check(value: bool, label: String) -> void:
	proof.record(value, label)
	checks += 1
	if not value: failures.append(label)

func put(path: String, value: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	check(file != null, "owned test file can be opened " + path.get_file())
	if file != null:
		file.store_string(value)
		file.close()

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	var directory := "user://framework_item_codec_%d" % Time.get_ticks_usec()
	PlayerState.profile_directory = directory.path_join("characters")
	PlayerState.profile_index_path = directory.path_join("profiles.json")
	PlayerState.shared_warehouse_path = directory.path_join("shared.json")
	PlayerState.shared_warehouse_transaction_log_path = directory.path_join("shared.transaction.json")
	PlayerState.active_profile_id = "item-codec"
	PlayerState.character_name = "物品容器验收"
	PlayerState._shared_warehouse_initialized = false
	check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PlayerState.profile_directory)) == OK,
		"profile test owns an isolated directory")
	var catalog := GameData.get_item_record({"item_id": 80})
	var base := DropRules.create_instance(catalog, "codec:stable-v3")
	check(not base.is_empty() and DropRules.validate_instance(base, catalog), "actual registered base is a strict valid v3 drop")
	var extension := {"hc.socketing": {"schema_version": 1, "sockets": []}}
	var created := Codec.with_extensions(base, extension)
	check(created.status == Codec.KNOWN_VALID, "known socket namespace creates a formal runtime item")
	if created.status != Codec.KNOWN_VALID:
		_finish()
		return
	var runtime: Dictionary = created.item
	var encoded := Codec.encode_runtime(runtime)
	check(encoded.status == Codec.KNOWN_VALID and encoded.item.base == base \
		and encoded.item.entity_id == "hc.item.000080", "wire codec retains one exact base and registered typed identity")
	check(Codec.decode_wire(encoded.item).item == runtime, "known wire round trip preserves the entire extension payload")
	check(not DropRules.validate_instance(runtime, catalog) and not DropRules.validate_instance(encoded.item, catalog),
		"old strict v1 base validator still rejects extension fields and containers")
	check(GameData.validate_item_drop_instance(runtime), "actual production drop consumer validates the codec base")
	for version in range(3):
		var historical: Dictionary = (DropRules.create_legacy_instance(catalog, "codec:legacy") if version == 0
			else (DropRules.create_v2_instance(catalog, "codec:v2") if version == 1 else base))
		var wrapped := Codec.with_extensions(historical, extension)
		check(wrapped.status == Codec.KNOWN_VALID and Codec.encode_runtime(wrapped.item).item.base == historical,
			"original affix/rule payload is preserved without generation " + str(version))
	check(Codec.encode_runtime(base).item == base and Codec.decode_wire(base).item == base,
		"old unextended instance remains an exact identity transform")
	var invalid: Dictionary = encoded.item.duplicate(true)
	invalid.base["unknown_base_field"] = 1
	check(Codec.decode_wire(invalid).status == Codec.INVALID, "codec never relaxes the old base field whitelist")
	invalid = encoded.item.duplicate(true)
	invalid.entity_id = "hc.item.000081"
	check(Codec.decode_wire(invalid).status == Codec.INVALID, "wire identity cannot replace the base item identity")
	var unsupported: Array[Dictionary] = []
	var future: Dictionary = encoded.item.duplicate(true)
	future.format_version = 3
	unsupported.append(future)
	future = encoded.item.duplicate(true)
	future.extensions = {"hc.future": {"schema_version": 1, "opaque": "保留原数据"}}
	unsupported.append(future)
	future = encoded.item.duplicate(true)
	future.extensions["hc.socketing"].schema_version = 2
	unsupported.append(future)
	for index in unsupported.size():
		var candidate: Dictionary = unsupported[index]
		check(Codec.decode_wire(candidate).status == Codec.OPAQUE_UNSUPPORTED, "future owner is opaque rather than corrupt " + str(index))
		var aggregate := PlayerState._prepare_character_save_payload(false).duplicate(true)
		aggregate.inventory = [candidate]
		var status: Dictionary = PlayerState._validate_profile_document_status(aggregate, PlayerState.active_profile_id, false)
		check(not bool(status.valid) and bool(status.terminal), "production aggregate refuses backup recovery over unsupported item " + str(index))
	var mixed := {"inventory": [invalid, unsupported[0]]}
	check(Codec.decode_document(mixed).status == Codec.OPAQUE_UNSUPPORTED, "unsupported sibling takes precedence over invalid known item")
	PlayerState.inventory = [runtime.duplicate(true)]
	var saved: Dictionary = PlayerState._prepare_character_save_payload(false).duplicate(true)
	check(saved.inventory == [encoded.item], "actual profile writer serializes the explicit wire container")
	var shared: Dictionary = PlayerState._shared_document_for_records([runtime], PlayerState._shared_warehouse_empty_document())
	check(shared.warehouse_inventory == [encoded.item], "actual shared writer routes the same codec")
	var received: Dictionary = PlayerState._build_receive_result_for_record(runtime, [], true)
	check(bool(received.get("success", false)) and received.inventory[0] == runtime,
		"actual loot/warehouse receive path retains the complete extension")
	var received_wire: Dictionary = PlayerState._build_receive_result_for_record(encoded.item, [], true)
	check(bool(received_wire.get("success", false)) and json_equal(received_wire.inventory[0], runtime),
		"formal wire receive publishes a runtime base rather than a raw wrapper")
	var affixed: Dictionary = {}
	for index in range(1000):
		var candidate := DropRules.create_legacy_instance(catalog, "codec:affixed:%d" % index)
		if DropRules.is_affixed_instance(candidate, catalog):
			affixed = candidate
			break
	check(not affixed.is_empty(), "existing deterministic v1 source provides a real affixed sample")
	if not affixed.is_empty():
		var affixed_runtime: Dictionary = Codec.with_extensions(affixed, extension).item
		check(NameStyle.display_name(catalog, affixed).begins_with("★") \
			and NameStyle.display_name(catalog, affixed_runtime) == NameStyle.display_name(catalog, affixed),
			"actual item presentation retains the old verified affix marker")
		var identity := {"item_id": 80, "source_item_id": 80, "canonical_item_id": 80,
			"source_canonical_item_id": 80, "output_item_id": 80, "identity_status": "resolved",
			"name": "木剑", "item_name": "木剑", "canonical_name": "木剑", "source_canonical_name": "木剑",
			"output_record": catalog, "item_instance": affixed}
		check(LootVisual.affix_is_valid(identity), "existing formal loot oracle recognizes the real affix")
		identity.item_instance = affixed_runtime
		check(LootVisual.affix_is_valid(identity), "actual ground presentation preserves the extended item affix")
	# Real unknown primary with a valid backup must remain byte-identical and
	# leave the current owner untouched. A second malformed field cannot mask it.
	var old := saved.duplicate(true)
	old.inventory = [base]
	var unknown := old.duplicate(true)
	unknown.inventory = [unsupported[0]]
	unknown.level = "corrupt sibling"
	var path := PlayerState._profile_path(PlayerState.active_profile_id)
	var raw := JSON.stringify(unknown, "\t") + "\n"
	var backup := JSON.stringify(old, "  ") + "\n"
	put(path, raw)
	put(path + ".bak", backup)
	var live_items := PlayerState.inventory.duplicate(true)
	PlayerState.gold = 4321
	PlayerState.test_mode = false
	PlayerState.load_save()
	check(not bool(PlayerState.last_load_result.get("success", false)), "real loader rejects future primary rather than restoring old backup")
	check(PlayerState.gold == 4321 and PlayerState.inventory == live_items, "opaque aggregate never partially publishes or rolls back live state")
	check(FileAccess.get_file_as_string(path) == raw and FileAccess.get_file_as_string(path + ".bak") == backup,
		"primary and backup preserve all original opaque bytes")
	check(PlayerState._prepare_character_save_payload(false).is_empty(), "unsupported item locks the whole character writer")
	put(path, JSON.stringify(saved))
	PlayerState.load_save()
	check(bool(PlayerState.last_load_result.get("success", false)) and json_equal(PlayerState.inventory, [runtime]),
		"real supported load decodes to the existing runtime item authority")
	check(PlayerState.save_game(false, false, false), "real ordered writer accepts the supported container")
	var reread: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	check(reread is Dictionary and json_equal(reread.inventory, [encoded.item]), "real disk round trip does not serialize the runtime-only metadata")
	var deposited: Dictionary = PlayerState.deposit_to_warehouse(0, 0)
	check(bool(deposited.get("success", false)) and json_equal(PlayerState.warehouse_inventory[0], runtime),
		"actual warehouse deposit preserves the runtime extension record")
	var shared_disk: Variant = JSON.parse_string(FileAccess.get_file_as_string(PlayerState.shared_warehouse_path))
	check(shared_disk is Dictionary and json_equal(shared_disk.warehouse_inventory[0], encoded.item),
		"actual multi-file warehouse commit saves the formal container")
	PlayerState._shared_warehouse_initialized = false
	PlayerState.warehouse_inventory = []
	check(PlayerState._initialize_shared_warehouse() and json_equal(PlayerState.warehouse_inventory[0], runtime),
		"actual account initialization decodes wire items before publishing the warehouse")
	var withdrawn: Dictionary = PlayerState.withdraw_from_warehouse(0)
	check(bool(withdrawn.get("success", false)) and json_equal(PlayerState.inventory[0], runtime),
		"actual warehouse withdrawal preserves the exact item and affix ownership")
	var duplicate := saved.duplicate(true)
	duplicate.inventory = [encoded.item, encoded.item.duplicate(true)]
	check(not bool(PlayerState._validate_profile_document_status(duplicate, PlayerState.active_profile_id, false).valid),
		"a copied extended instance cannot create a second aggregate owner")
	var cross_shared := PlayerState._shared_document_for_records([runtime])
	check(not PlayerState._profile_and_shared_drop_instances_are_disjoint(saved, cross_shared),
		"profile and shared warehouse cannot simultaneously own an extended instance")
	for index in unsupported.size():
		var candidate := cross_shared.duplicate(true)
		candidate.warehouse_inventory = [unsupported[index]]
		candidate.schema_version = "malformed sibling"
		var status: Dictionary = PlayerState._validate_shared_warehouse_document_status(candidate)
		check(not bool(status.valid) and bool(status.terminal), "shared future payload remains terminal " + str(index))
	for input: Dictionary in [runtime, encoded.item]:
		PlayerState.inventory = []
		check(PlayerState.save_game(false, false, false), "owned empty inventory is durable before pickup " + str(input.has("base")))
		var plan: Dictionary = PlayerState.prepare_loot_save([{"item_id": 80, "item_name": "木剑", "item_instance": input}])
		var completion: Dictionary = plan.get("immediate", {})
		if plan.has("writer"):
			completion = PlayerState.finish_prepared_loot_save(plan, true)
		check(bool(completion.get("success", false)) and json_equal(PlayerState.inventory, [runtime]),
			"actual prepared pickup persists wire and applies only runtime authority " + str(input.has("base")))
	PlayerState.inventory = []
	var cross_identity: Dictionary = PlayerState.receive_loot_batch_partial([
		{"item_id": 81, "item_name": "显示名称不能改身份", "item_instance": encoded.item}], true)
	check(not bool(cross_identity.outcomes[0].success) and PlayerState.inventory.is_empty(),
		"formal pickup envelope cannot authorize another item's valid base")
	await _verify_extended_forge(extension)
	for field: String in ["format_version", "contract_id", "entity_id", "base", "extensions"]:
		var bad: Dictionary = encoded.item.duplicate(true)
		bad[field] = "invalid numeric type" if field == "format_version" else 123
		check(Codec.decode_wire(bad).status == Codec.INVALID, "malformed typed wire field is rejected without an engine error " + field)
	var before_shared_bytes := FileAccess.get_file_as_string(PlayerState.shared_warehouse_path)
	var future_shared: Dictionary = JSON.parse_string(before_shared_bytes)
	future_shared.warehouse_inventory = [unsupported[1]]
	var opaque_shared := JSON.stringify(future_shared, "\t") + "\n"
	put(PlayerState.shared_warehouse_path + ".bak", before_shared_bytes)
	put(PlayerState.shared_warehouse_path, opaque_shared)
	var warehouse_before := PlayerState.warehouse_inventory.duplicate(true)
	PlayerState._shared_warehouse_initialized = false
	check(not PlayerState._initialize_shared_warehouse() and PlayerState.warehouse_inventory == warehouse_before,
		"actual account initialization refuses unknown primary despite a known backup")
	check(not PlayerState._write_shared_warehouse([runtime]), "unknown account aggregate blocks the shared writer")
	check(FileAccess.get_file_as_string(PlayerState.shared_warehouse_path) == opaque_shared \
		and FileAccess.get_file_as_string(PlayerState.shared_warehouse_path + ".bak") == before_shared_bytes,
		"unknown shared primary and backup retain their exact bytes after attempted writes")
	PlayerState.test_mode = true
	_finish()

func _verify_extended_forge(extension: Dictionary) -> void:
	var catalog := GameData.get_item_record({"item_id": 81})
	var base := DropRules.create_instance(catalog, "codec:forge:81")
	var extended := Codec.with_extensions(base, extension)
	check(extended.status == Codec.KNOWN_VALID, "actual forge target receives the same registered extension contract")
	if extended.status != Codec.KNOWN_VALID: return
	PlayerState.forge_tray = PlayerState._empty_workbench_tray()
	PlayerState.forge_tray[4] = extended.item
	PlayerState.gold = 2000000
	for win in [true, false]:
		for entry: Array in [[1, 940013], [3, 239], [8, 239]]:
			var material := GameData.get_item_record({"item_id": entry[1]})
			PlayerState.forge_tray[entry[0]] = PlayerState._make_item_instance(str(material.name), material, -1, false)
			PlayerState.forge_tray[entry[0]]["item_id"] = entry[1]
		check(PlayerState.save_game(false, false, false), "extended forge inputs are durably serialized " + str(win))
		var quote: Dictionary = PlayerState.quote_forge_tray()
		check(bool(quote.get("valid", false)), "actual forge accepts the extended base " + str(win))
		if not bool(quote.get("valid", false)): continue
		var rng := rng_for_outcome(int(quote.final_success_bps), win)
		check(rng != null, "bounded isolated seed provides the requested forge outcome " + str(win))
		if rng == null: continue
		PlayerState._forge_service().configure_rng(rng)
		var committed: Dictionary = await PlayerState.commit_workbench_immediate("forge", quote)
		check(bool(committed.get("committed", false)) and bool(committed.get("forge_succeeded", false)) == win,
			"real extended forge commits the requested outcome " + str(win))
		PlayerState._json_persistence.drain()
		check(not PlayerState._item_save_failed, "background forge writer retains the extension " + str(win))
		var wire_document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PlayerState._profile_path(PlayerState.active_profile_id)))
		var saved: Dictionary = wire_document.forge_tray[4]
		check(saved.get("contract_id") == Codec.CONTRACT and json_equal(saved.get("extensions"), extension),
			"actual forge disk result remains an extension container " + str(win))
		var preserved := saved.get("base", {}) as Dictionary
		for field: String in ["instance_id", "drop_key_digest", "modifiers", "drop_affix"]:
			check(json_equal(preserved.get(field), base.get(field)), "forge never rerolls the accepted base " + str(win) + " " + field)
		var decoded := Codec.decode_document(wire_document)
		check(decoded.status == Codec.KNOWN_VALID, "restart routes the complete forge aggregate through the codec " + str(win))
		if decoded.status == Codec.KNOWN_VALID:
			PlayerState.forge_tray = PlayerState._load_workbench_tray(decoded.document.forge_tray)
	check(bool((await PlayerState.transfer_workbench_immediate("forge", 4, -1, 70)).get("success", false)),
		"actual workbench transfer moves the decoded extended record by its original instance")
	PlayerState._json_persistence.drain()
	check(PlayerState.inventory.size() > 70 and PlayerState.inventory[70].instance_id == base.instance_id \
		and json_equal(Codec.extensions(PlayerState.inventory[70]), extension),
		"workbench transfer preserves extension data and original instance ownership")

func rng_for_outcome(threshold: int, win: bool) -> RandomNumberGenerator:
	for candidate in range(1, 1000):
		var rng := RandomNumberGenerator.new()
		rng.seed = candidate
		if (rng.randi_range(0, 9999) < threshold) == win:
			rng.seed = candidate
			return rng
	return null

func json_equal(actual: Variant, expected: Variant) -> bool:
	# Godot JSON reads integral values as float. Compare the complete wire graph,
	# retaining every field, array order and exact value across that boundary.
	return JSON.parse_string(JSON.stringify(actual)) == JSON.parse_string(JSON.stringify(expected))

func _finish() -> void:
	if not proof.write_receipt("item_extension_codec_test", checks, failures.size()): failures.append("receipt")
	print("FRAMEWORK_ITEM_EXTENSION_CODEC_%s checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL", checks, str(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)
