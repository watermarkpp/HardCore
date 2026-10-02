extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Codec := preload("res://scripts/items/item_extension_codec.gd")
const Gem := preload("res://scripts/items/socket_gem_rules.gd")
const Drop := preload("res://scripts/item_drop_instance_rules.gd")
var proof := Proof.new()
var checks := 0
var failures: Array[String] = []
func check(value: bool,label: String) -> void:
	proof.record(value,label); checks += 1
	if not value: failures.append(label)
func _ready() -> void: _run.call_deferred()
func _run() -> void:
	check(not PlayerState.test_mode and OS.get_environment("APPDATA").replace("\\","/").contains("/.godot/runtime_appdata/"),"real load and writer run only in the prelaunch isolated account")
	if not failures.is_empty(): _finish(); return
	PlayerState.begin_startup_save_upgrade()
	check(PlayerState.finish_startup_save_upgrade() and PlayerState.create_character("旧备份事务验证","hc.profession.warrior").is_empty(),"production startup and profile creation succeed")
	PlayerState.set_process(false)
	var base := Drop.create_instance(GameData.get_item_record({"item_id":80}),"backup:gear")
	var gem := Gem.create_instance("backup:gem",true)
	PlayerState.inventory = [base,gem]
	check(PlayerState.save_game(true,true,true),"initial unsequenced checkpoint is durable")
	var path: String = PlayerState._profile_path(PlayerState.active_profile_id)
	var original := FileAccess.get_file_as_bytes(path)
	check(ContentLayers.set_feature_module_enabled(Gem.MODULE,true),"default-off test module enabled explicitly")
	var request := {"action":"hc.socketing.insert","target_instance_id":base.instance_id,"gem_instance_id":gem.instance_id}
	var quote: Dictionary = PlayerState.quote_new_item_transaction(request)
	var pending: Dictionary = PlayerState.commit_item_transaction(quote)
	check(bool((await _wait(pending.get("job"))).get("success",false)),"first sequenced operation commits through the actual sole writer")
	PlayerState._start_item_save(); PlayerState._json_persistence.drain()
	# Simulate supported backup recovery on this newly created profile only.
	# No original user save or unrelated profile is read or overwritten.
	check(_write(path+".bak",original) and _write(path,"{broken".to_utf8_buffer()),"owned corrupt primary has the exact original unsequenced recovery checkpoint")
	PlayerState.load_save()
	check(bool(PlayerState.last_load_result.get("success",false)) and PlayerState._item_transaction_journal.is_empty(),"production loader recovers the valid older checkpoint, not the lost newer frontier")
	check(Codec.extensions(PlayerState.inventory[0]).is_empty() and PlayerState.inventory[1].instance_id == gem.instance_id,"recovered document owns its original loose gem exactly once")
	var stale: Dictionary = PlayerState.quote_item_transaction(quote.request)
	check(not bool(stale.success) and stale.get("reason") == "item_operation_epoch_mismatch","same-process old issuer cannot resurrect a completed epoch after recovery to an unsequenced checkpoint")
	var next: Dictionary = PlayerState.quote_new_item_transaction(request)
	check(bool(next.get("success",false)) and next.get("request",{}).get("operation_id") != quote.request.operation_id,"fresh recovery intent uses a different epoch instead of reusing a lost operation identity")
	if bool(next.get("success",false)):
		var continued: Dictionary = PlayerState.commit_item_transaction(next)
		check(bool((await _wait(continued.get("job"))).get("success",false)),"recovered profile remains usable through one newly issued actual transaction")
	PlayerState._start_item_save(); PlayerState._json_persistence.drain()
	var prior: Dictionary = PlayerState.quote_new_item_transaction({"action":"hc.socketing.remove","target_instance_id":base.instance_id,"gem_instance_id":""})
	check(bool(prior.get("success",false)),"an uncommitted next quote captures the current profile generation")
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	source.erase("death_event_sequence"); source.erase("world_clock_generation"); source.erase("world_clock_import_source")
	source["world_monster_respawn_state"] = PlayerState.world_monster_respawn_state.duplicate(true)
	var old_writer := JSON.stringify(source).to_utf8_buffer()
	check(_write(path,old_writer) and _write(path+".bak",old_writer),"owned legacy-clock fixture preserves the sequenced item journal and embedded gem")
	PlayerState.load_save()
	check(bool(PlayerState.last_load_result.get("success",false)) and not PlayerState._world_clock_generation.is_empty(),"actual legacy-clock import creates a new generation around the unchanged item transaction stream")
	var before: Array = PlayerState.inventory.duplicate(true)
	var stale_generation: Dictionary = PlayerState.commit_item_transaction(prior)
	check(not bool(stale_generation.success) and stale_generation.reason == "stale_item_quote" and PlayerState.inventory == before,"a previous-generation uncommitted quote cannot cross the real import boundary")
	check(bool(PlayerState.commit_item_transaction(next).get("durable",false)),"a completed persistent economic outcome remains replayable across world-clock generation changes")
	var current: Dictionary = PlayerState.quote_new_item_transaction({"action":"hc.socketing.remove","target_instance_id":base.instance_id,"gem_instance_id":""})
	var continuation: Dictionary = PlayerState.commit_item_transaction(current)
	check(bool((await _wait(continuation.get("job"))).get("success",false)),"current-generation quote continues the same durable sequence through its actual writer")
	PlayerState._start_item_save(); PlayerState._json_persistence.drain()
	var known := FileAccess.get_file_as_bytes(path)
	var future: Dictionary = JSON.parse_string(known.get_string_from_utf8())
	future.item_transactions.schema_version = 3
	future.inventory = [{"contract_id":Codec.CONTRACT,"format_version":2,"entity_id":123,"base":{},"extensions":{}}]
	var future_bytes := JSON.stringify(future).to_utf8_buffer()
	check(_write(path+".bak",known) and _write(path,future_bytes),"owned future sequenced journal is paired with a valid prior backup and a malformed known item sibling")
	var live: Array = PlayerState.inventory.duplicate(true)
	PlayerState.load_save()
	check(not bool(PlayerState.last_load_result.get("success",false)) and PlayerState.inventory == live,"future sequenced aggregate blocks known-corruption recovery before replacing live ownership")
	check(not PlayerState.save_game(false,false,false) and FileAccess.get_file_as_bytes(path) == future_bytes and FileAccess.get_file_as_bytes(path+".bak") == known,"future journal keeps exact primary and backup bytes under the existing write lock")
	_finish()
func _write(path: String,value: PackedByteArray) -> bool:
	var file := FileAccess.open(path,FileAccess.WRITE)
	if file == null: return false
	file.store_buffer(value); file.flush(); var okay := file.get_error() == OK; file.close(); return okay
func _wait(job: Variant) -> Dictionary:
	if job == null: return {"success":false}
	var deadline := Time.get_ticks_msec()+5000
	while not bool(job.response.get("finished",false)) and Time.get_ticks_msec()<deadline:
		PlayerState._json_persistence.pump(); await get_tree().process_frame
	return job.response
func _finish() -> void:
	if not proof.write_receipt("item_journal_legacy_backup_test",checks,failures.size()): failures.append("receipt")
	print("ITEM_JOURNAL_LEGACY_BACKUP_%s checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL",checks,str(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)
