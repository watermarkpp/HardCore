extends Node

## Skill-learning central notice acceptance (R2).
## Both production entries (bag activation and quick-slot use) must surface
## the SAME authoritative central success notice ("已学会：X" /
## "技能提升：X（当前N级）"), failures must stay on the error channel, and the
## detail presenter must never double-report a learn result.

const Common := preload("res://tests/r6_1_review/real_panel_matrix_common.gd")

var failures: Array[String] = []
var hud: GameHUD
var panel: InventoryPanel


func expect(value: bool, message: String) -> void:
	if not value:
		failures.append(message)


func settle() -> void:
	for _index in range(4):
		await get_tree().process_frame


func _first_book_index() -> int:
	# A consumed bag cell keeps an empty {} placeholder in PlayerState.inventory,
	# so activation must target the first non-empty skill-book slot.
	for index in range(PlayerState.inventory.size()):
		var record: Variant = PlayerState.inventory[index]
		if record is Dictionary and not (record as Dictionary).is_empty():
			return index
	return -1


func reset_fixture_state() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	# Level 99 clears every skill-book level requirement for the learn path;
	# the level-short case pins level 1 explicitly after this reset.
	PlayerState.level = 99
	PlayerState.profession = "战士"
	PlayerState.gender = "男"
	PlayerState.inventory = []
	PlayerState.equipment = {}
	for index in range(PlayerState.QUICK_ITEM_SLOT_COUNT):
		PlayerState.quick_item_slots[index] = ""
	PlayerState.recalculate_stats(false)
	if panel != null:
		panel._ui_dismiss_selection()


func find_warrior_skill_book() -> String:
	for value: Variant in GameData.item_catalog:
		if not value is Dictionary:
			continue
		var item: Dictionary = value
		if str(item.get("kind", "")) != "skill_book":
			continue
		var book_name := str(item.get("name", ""))
		if book_name.is_empty():
			continue
		var skill := GameData.get_skill(book_name, 0)
		var profession := str(skill.get("profession", ""))
		if profession in ["", "战士"]:
			return book_name
	return ""


func place_books(book_name: String, copies: int) -> void:
	var record := GameData.get_item(book_name)
	for _index in range(copies):
		var instance := PlayerState._make_item_instance(book_name, record)
		if not instance.is_empty():
			PlayerState.inventory.append(instance)


func _ready() -> void:
	PlayerState.test_mode = true
	_run.call_deferred()


func _run() -> void:
	if not Common.ensure_data():
		get_tree().quit(1)
		return
	var book_name := find_warrior_skill_book()
	expect(not book_name.is_empty(), "a warrior-learnable skill book exists in the catalog")
	if book_name.is_empty():
		get_tree().quit(1)
		return

	reset_fixture_state()
	hud = GameHUD.new()
	add_child(hud)
	await settle()
	hud._toggle_inventory()
	panel = hud.inventory_panel
	await settle()
	expect(panel != null and panel.visible, "inventory panel open")
	expect(hud.notice_presenter != null, "central notice presenter present")

	# --- Level-too-low failure stays on the error channel --------------------
	PlayerState.level = 1
	place_books(book_name, 1)
	panel.refresh()
	await settle()
	panel._activate_inventory_index(0)
	await settle()
	expect(not bool(hud.notice_presenter.current_notice().get("message", "x").begins_with("已学会")), "level-short learn never reports success")
	expect(hud.error_label.text.begins_with("需要人物等级"), "level-short learn surfaces the requirement error centrally")
	expect(hud.error_label.text.contains("级"), "requirement error is player-readable Chinese")

	# --- Bag entry: first learn shows the central success once ----------------
	reset_fixture_state()
	# The level-short block left a live ERROR notice on the shared layer; a
	# real player would see it expire. The test clears it to assert the learn
	# notice directly (success must queue behind a live error, not flush it).
	hud.notice_presenter.clear_for_test()
	place_books(book_name, 3)
	panel.refresh()
	await settle()
	panel._activate_inventory_index(0)
	await settle()
	var learn_notice: Dictionary = hud.notice_presenter.current_notice()
	var first_message := str(learn_notice.get("message", ""))
	expect(first_message == "已学会：%s" % book_name, "bag entry reports the authoritative learn text (got [%s])" % first_message)
	expect(str(learn_notice.get("kind", "")) == "success", "learn notice is a success notice")
	expect(hud.notice_presenter.queue_size() == 0, "learn reports exactly one notice")

	# --- Bag entry: upgrade text uses the authority wording -------------------
	panel.refresh()
	await settle()
	panel._activate_inventory_index(_first_book_index())
	await settle()
	var upgrade_message := str(hud.notice_presenter.current_notice().get("message", ""))
	expect(upgrade_message == "技能提升：%s（当前2级）" % book_name, "upgrade reports the authoritative text (got [%s])" % upgrade_message)

	# --- Quick-slot entry reports the SAME central text ------------------------
	reset_fixture_state()
	place_books(book_name, 1)
	PlayerState.quick_item_slots[0] = book_name
	var quick_result := PlayerState.use_quick_item_slot(0, book_name)
	expect(bool(quick_result.get("ok", false)), "quick-slot learn succeeds")
	expect(str(quick_result.get("kind", "")) == "skill_book", "quick-slot learn classifies as skill_book")
	var quick_message := str(quick_result.get("message", ""))
	expect(quick_message == "已学会：%s" % book_name, "quick-slot learn carries the SAME authority text as the bag entry")

	# --- Max-rank failure stays on the error channel ---------------------------
	reset_fixture_state()
	place_books(book_name, 20)
	panel.refresh()
	await settle()
	var reached_max := false
	for _attempt in range(20):
		panel._activate_inventory_index(_first_book_index())
		await settle()
		if hud.error_label.text.contains("最高等级"):
			reached_max = true
			break
		if hud.notice_presenter.current_notice().is_empty():
			break
	expect(reached_max, "exhausting the skill ranks surfaces 最高等级 on the error channel")
	expect(not hud.error_label.text.contains("已学会"), "max-rank failure never reports success on the error lane")
	expect(not hud.notice_presenter.full_text().contains("已学会"), "max-rank failure never reports success on the notice layer")

	hud.queue_free()
	await settle()
	if failures.is_empty():
		print("SKILL_LEARNING_NOTICE_REAL_INPUT_PASS: bag/quick-slot share the authority text, failures stay on the error lane")
		get_tree().quit(0)
	else:
		for failure in failures:
			printerr("SKILL_LEARNING_NOTICE_REAL_INPUT_FAIL: " + failure)
		get_tree().quit(1)
