extends Node
# Real production panel subclasses; the spies call the original body.
# Storage paths point exclusively to this test's isolated, empty fixture.
class BankSpy:
	extends "res://scripts/warehouse_panel.gd"
	var bank_calls := 0
	func _refresh_bank_state() -> void:
		bank_calls += 1
		super._refresh_bank_state()
class RepairSpy:
	extends "res://scripts/shop_panel.gd"
	var repair_calls := 0
	func _refresh_repair_preview() -> void:
		repair_calls += 1
		super._refresh_repair_preview()
class PreviewSpy:
	extends "res://scripts/equipment_character_preview.gd"
	var rebuild_calls := 0
	func refresh() -> void:
		rebuild_calls += 1
		super.refresh()
const Inventory := preload("res://scripts/inventory_panel.gd")
var failures: Array[String] = []
var checks := 0
func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
func _ready() -> void:
	PlayerState.test_mode = true
	_run.call_deferred()
func frames(count: int = 2) -> void:
	for i in count:
		await get_tree().process_frame
func _run() -> void:
	assert(GameData.ensure_loaded(), "GameData must load, no reduced fixture catalog")
	var fixture := "user://ui_l1_hidden_%d" % Time.get_ticks_usec()
	PlayerState.profile_directory = fixture + "/characters"
	PlayerState.profile_index_path = fixture + "/profiles.json"
	PlayerState.shared_warehouse_path = fixture + "/shared.json"
	PlayerState.shared_warehouse_transaction_log_path = fixture + "/transaction.json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PlayerState.profile_directory))
	PlayerState._shared_warehouse_initialized = false
	PlayerState._warehouse_transaction_locked = false
	assert(PlayerState._initialize_shared_warehouse(), "isolated shared store init")
	var shared_before := FileAccess.get_sha256(PlayerState.shared_warehouse_path)
	var bank := BankSpy.new()
	bank.hide()
	add_child(bank)
	await bank.wait_until_runtime_ready()
	await frames(5)
	bank.bank_calls = 0
	for i in 12:
		PlayerState.profile_changed.emit()
	await frames()
	expect(bank.bank_calls == 0, "hidden warehouse profile signals must do ZERO bank-view reads")
	bank.show()
	await frames()
	expect(bank.bank_calls == 1, "one fresh bank view on first show")
	bank.bank_calls = 0
	for i in 20:
		bank._refresh_transfer_action_states()
	expect(bank.bank_calls == 0, "item-selection action refresh must not reread unchanged bank view")
	for i in 5:
		PlayerState.profile_changed.emit()
	await frames()
	expect(bank.bank_calls == 1, "visible same-frame profile signals coalesce to one bank view")
	bank.hide()
	bank.bank_calls = 0
	PlayerState.profile_changed.emit()
	await frames()
	expect(bank.bank_calls == 0, "close-to-NPC transition must leave hidden bank dormant")
	expect(FileAccess.get_sha256(PlayerState.shared_warehouse_path) == shared_before, "view refresh must never mutate shared storage")
	bank.queue_free()
	await frames()

	var shop := RepairSpy.new()
	shop.hide()
	add_child(shop)
	await frames(5)
	shop.repair_calls = 0
	for i in 8:
		PlayerState.equipment_changed.emit()
	await frames()
	expect(shop.repair_calls == 0, "hidden shop must not calculate repair previews on equipment signals")
	shop.show()
	await frames()
	expect(shop.repair_calls == 1, "shop show flushes one dirty repair preview")
	shop.repair_calls = 0
	for i in 5:
		PlayerState.equipment_changed.emit()
	await frames()
	expect(shop.repair_calls == 1, "visible shop repair preview coalesces")
	shop.queue_free()
	await frames()

	var standalone := PreviewSpy.new()
	standalone.configure_presentation_mode("classic_avatar")
	standalone.hide()
	add_child(standalone)
	await frames()
	standalone.rebuild_calls = 0
	for i in 8:
		PlayerState.equipment_changed.emit()
	await frames()
	expect(standalone.rebuild_calls == 0, "hidden standalone avatar performs no reactive rebuild")
	standalone.show()
	await frames()
	expect(standalone.rebuild_calls == 1, "standalone avatar catches up once on show")
	standalone.queue_free()
	await frames()

	var inventory: Control = Inventory.new()
	inventory.hide()
	add_child(inventory)
	await inventory.wait_until_runtime_ready()
	await frames(5)
	inventory.show()
	await frames()
	var avatar: Control = inventory.character_preview
	var before_revision: int = avatar._render_revision
	PlayerState.equipment_changed.emit()
	inventory.refresh() # same path as a successfully completed equipment action
	await frames()
	expect(avatar._render_revision - before_revision == 1, "InventoryPanel is sole reactive owner; no duplicate avatar rebuild")
	inventory.hide()
	before_revision = avatar._render_revision
	PlayerState.equipment_changed.emit()
	await frames()
	expect(avatar._render_revision == before_revision, "hidden inventory has no reactive avatar work")
	inventory.show()
	await frames()
	expect(avatar._render_revision == before_revision + 1, "inventory reopen displays latest equipment exactly once")
	inventory.queue_free()
	await frames()
	# Leave failed test-owned fixtures for diagnosis. Never touch default user data.
	for failure: String in failures:
		push_error("UI_L1_HIDDEN " + failure)
	print("UI_L1_HIDDEN_%s checks=%d failures=%d" % ["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
