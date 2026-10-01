extends Node

const Gem := preload("res://scripts/items/socket_gem_rules.gd")
const Codec := preload("res://scripts/items/item_extension_codec.gd")
const Drop := preload("res://scripts/item_drop_instance_rules.gd")
const Registry := preload("res://scripts/identity/entity_registry.gd")
const Relics := preload("res://scripts/layers/rules/relic_synthesis_rules.gd")
const Detail := preload("res://scripts/item_detail_presenter.gd")
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
var proof := Proof.new()
var checks := 0
var failures: Array[String] = []

func check(value: bool, label: String) -> void:
	proof.record(value, label)
	checks += 1
	if not value: failures.append(label)

func _ready() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	check(Gem.ensure_loaded(), "new gem source is a hash-bound primary authoring lane")
	check(Registry.resolve(Gem.ENTITY_ID, "item").legacy_id == Gem.ITEM_ID,
		"new item identity is formally registered with its exact numeric authority")
	check(GameData.get_entity_record(Gem.ENTITY_ID).kind == "socket_gem", "typed production catalog delegates to the new primary source")
	check(GameData.get_item_record("测试宝石").is_empty(), "new gem never acquires a name-based business lookup")
	check(Gem.create_instance("gem:fixture:1").is_empty(), "registered identity alone cannot activate the default-off fixture")
	var gem := Gem.create_instance("gem:fixture:1", true)
	check(Gem.valid_instance(gem), "explicit fixture admission creates a valid uniquely identified gem")
	var renamed := gem.duplicate(true)
	renamed.name = "显示名称发生变化"
	check(Gem.valid_instance(renamed) and GameData.item_entity_id(renamed) == Gem.ENTITY_ID,
		"changing display metadata preserves the gem identity and rules")
	for field: String in ["item_id", "count", "instance_id", "gem_instance_contract_id"]:
		var bad := gem.duplicate(true)
		bad[field] = "invalid numeric" if field in ["item_id", "count"] else 123
		check(Codec.decode_wire(bad).status == Codec.INVALID, "malformed gem identity rejects without a fallback " + field)
	var base := Drop.create_instance(GameData.get_item_record({"item_id": 80}), "gem:socket-owner")
	var extension := {"hc.socketing": {"schema_version": 1,
		"sockets": [{"socket_id": Codec.SOCKET_ID, "item": gem}]}}
	var created := Codec.with_extensions(base, extension)
	check(created.status == Codec.KNOWN_VALID, "registered gem is a supported populated socket payload")
	if created.status == Codec.KNOWN_VALID:
		var wire := Codec.encode_runtime(created.item)
		check(wire.status == Codec.KNOWN_VALID and wire.item.extensions == extension,
			"embedded gem is persisted once with its original stable identity")
		check(Codec.ownership_ids(created.item) == [base.instance_id, gem.instance_id],
			"ownership enumerates the gear and its embedded unique gem")
		check(Codec.ownership_ids(wire.item) == Codec.ownership_ids(created.item),
			"wire and runtime ownership enumerate exactly the same original identities")
		check(PlayerState._validate_extended_item_ownership({"inventory": [wire.item]}),
			"one embedded gem has one valid aggregate owner")
		check(not PlayerState._validate_extended_item_ownership({"inventory": [wire.item, gem]}),
			"an embedded gem cannot also be a usable inventory item")
		check(not PlayerState._validate_extended_item_ownership({"inventory": [gem, gem.duplicate(true)]}),
			"standalone formal gems cannot duplicate their instance identity")
		var future := gem.duplicate(true)
		future.gem_instance_contract_id = "hc.socketing.fixture.gem.v2"
		check(Codec.decode_document({"inventory": [future]}).status == Codec.OPAQUE_UNSUPPORTED,
			"future standalone gem is opaque and cannot be downgraded")
		var future_owner: Dictionary = wire.item.duplicate(true)
		future_owner.extensions[Codec.SOCKET_NAMESPACE].sockets[0].item = future
		check(Codec.decode_document({"inventory": [future_owner]}).status == Codec.OPAQUE_UNSUPPORTED,
			"future embedded gem blocks the complete owner aggregate")
		var relic_catalog := Relics.record_for_id(950101)
		var relic_rng := RandomNumberGenerator.new()
		relic_rng.seed = 950101
		PlayerState.configure_relic_roll_rng(relic_rng)
		var relic: Dictionary = PlayerState._make_item_instance(str(relic_catalog.name), relic_catalog, 123, true)
		check(Relics.valid_instance(relic, 950101), "relic detail fixture uses a fully generated valid primary instance")
		var extended_relic := Codec.with_extensions(relic, extension)
		check(extended_relic.status == Codec.KNOWN_VALID and Detail.format_item(relic_catalog, extended_relic.item).contains("镶嵌：测试宝石"),
			"the dedicated relic detail branch displays the same registered embedded ownership")
	if not proof.write_receipt("socket_gem_identity_test", checks, failures.size()): failures.append("receipt")
	print("FRAMEWORK_SOCKET_GEM_IDENTITY_%s checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL", checks, str(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)
