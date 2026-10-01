extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Identity := preload("res://scripts/identity/item_identity_codec.gd")
var proof := Proof.new()
var checks := 0
var errors: Array[String] = []

func check(value: bool, label: String) -> void:
	proof.record(value, label)
	checks += 1
	if not value: errors.append(label)

func put(path: String, document: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	check(file != null, "owned legacy source file opens")
	if file != null:
		file.store_string(JSON.stringify(document))
		file.close()

func _ready() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	PlayerState.set_process(false)
	var root := "user://legacy_item_transaction_identity_%d" % Time.get_ticks_usec()
	PlayerState.profile_directory = root.path_join("characters")
	PlayerState.profile_index_path = root.path_join("profiles.json")
	PlayerState.shared_warehouse_path = root.path_join("shared.json")
	PlayerState.shared_warehouse_transaction_log_path = root.path_join("shared.transaction.json")
	PlayerState.active_profile_id = "legacy-item-transaction"
	PlayerState._shared_warehouse_initialized = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PlayerState.profile_directory))
	var path: String = PlayerState._profile_path(PlayerState.active_profile_id)
	var item := {"name": "太阳水", "count": 1, "instance_id": "legacy:owned:1"}
	var profile := {"profile_id": PlayerState.active_profile_id, "gold": 300000, "inventory": [item]}
	var shared := {"schema_version": PlayerState.SHARED_WAREHOUSE_SCHEMA_VERSION,
		"contract_id": PlayerState.SHARED_WAREHOUSE_CONTRACT_ID, "revision": 1, "warehouse_inventory": [],
		"legacy_migration": {"completed": true, "contract_id": PlayerState.SHARED_WAREHOUSE_MIGRATION_CONTRACT_ID, "sources": {}}}
	PlayerState.inventory = [item.duplicate(true)]
	PlayerState.gold = 300000
	put(path, profile)
	put(PlayerState.shared_warehouse_path, shared)
	check(bool(PlayerState._validate_profile_document_status(profile, PlayerState.active_profile_id, false).valid),
		"supported exact old name-only profile is a valid transaction source")
	var result: Dictionary = PlayerState.transfer_shared_gold(true, "legacy:bank:1", 1)
	check(bool(result.success) and PlayerState.gold == 200000 and PlayerState.shared_gold_balance() == 100000,
		"actual gold-only transaction can upgrade an old identity lane without changing ownership")
	if not bool(result.success):
		_finish()
		return
	var written: Dictionary = PlayerState._read_json(path)
	check(int(written.inventory[0].item_id) == 920014 and int(written.inventory[0].count) == 1 \
		and written.inventory[0].instance_id == item.instance_id and written.has(Identity.FIELD),
		"successful actual writer changes only the declared identity representation and gold")
	# The second file is promoted before the injected profile failure. Rollback
	# must restore the validated old wire shape, not migrate the before-image.
	PlayerState.gold = 300000
	PlayerState.inventory = [item.duplicate(true)]
	PlayerState._shared_warehouse_initialized = true
	put(path, profile)
	put(PlayerState.shared_warehouse_path, shared)
	var before_profile := PlayerState._shared_digest(profile)
	var before_shared := PlayerState._shared_digest(shared)
	PlayerState._test_fail_profile_write = true
	result = PlayerState.transfer_shared_gold(true, "legacy:bank:rollback", 1)
	PlayerState._test_fail_profile_write = false
	check(not bool(result.success) and PlayerState.gold == 300000 and PlayerState.inventory == [item],
		"failed legacy migration transaction preserves all live ownership and currency")
	check(PlayerState._shared_digest(PlayerState._read_json(path)) == before_profile \
		and PlayerState._shared_digest(PlayerState._read_json(PlayerState.shared_warehouse_path)) == before_shared,
		"actual two-file failure restores both original legacy before-image shapes")
	check(not PlayerState._warehouse_transaction_locked and not FileAccess.file_exists(PlayerState.shared_warehouse_transaction_log_path),
		"successful legacy rollback releases the verified journal instead of leaving false recovery debt")
	_finish()

func _finish() -> void:
	PlayerState.set_process(true)
	if not proof.write_receipt("legacy_item_transaction_identity_test", checks, errors.size()): errors.append("receipt")
	print("LEGACY_ITEM_TRANSACTION_IDENTITY_%s checks=%d errors=%s" % ["PASS" if errors.is_empty() else "FAIL", checks, str(errors)])
	get_tree().quit(0 if errors.is_empty() else 1)
