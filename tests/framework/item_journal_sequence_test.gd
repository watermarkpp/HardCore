extends Node

const Journal := preload("res://scripts/items/item_transaction_journal.gd")
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
var proof := Proof.new()
var checks := 0
var failures: Array[String] = []
func check(value: bool,label: String) -> void:
	proof.record(value,label); checks += 1
	if not value: failures.append(label)
func _ready() -> void: _run.call_deferred()
func _run() -> void:
	check(PlayerState.has_method("quote_new_item_transaction"),"existing transaction owner can issue a recoverable sequence instead of stopping permanently at journal64")
	if not failures.is_empty(): _finish(); return
	var api: Variant = Journal
	var epoch := "1234567890abcdef1234567890abcdef"
	var profile := "journal-sequence-unit"
	var entry := {"operation_id":"legacy:1","request_digest":"request".sha256_text(),"action":"hc.socketing.insert",
		"target_instance_id":"sequence:gear","gem_instance_id":"sequence:gem","rules_revision":"rules".sha256_text()}
	var legacy := {}
	for index in 64:
		entry.operation_id = "legacy:"+str(index+1)
		legacy = Journal.appended(legacy,profile,entry)
	check(legacy.get("entries",[]).size() == 64 and Journal.validate_document({"profile_id":profile,Journal.FIELD:legacy}).valid,"original opaque-ID journal reaches its unchanged valid boundary")
	check(Journal.appended(legacy,profile,entry).is_empty(),"old protocol still refuses over-capacity instead of deleting historical outcomes")
	var value := legacy.duplicate(true)
	for sequence in range(1,131):
		entry.operation_id = api.sequence_id(epoch,sequence)
		value = api.appended(value,profile,entry,epoch)
		if value.is_empty(): break
	check(not value.is_empty(),"new durable sequence completes 130 operations while retaining all 64 legacy outcomes")
	if value.is_empty(): _finish(); return
	check(value.get("contract_id") == "hc.item.transactions.v2" and value.get("schema_version") == 2,"new protocol has an explicit versioned identity")
	check(value.entries.size() == 64 and value.legacy_entries == legacy.entries and int(value.retired_through) == 66 and int(value.last_sequence) == 130,"bounded recent results plus contiguous durable retirement watermark preserve legacy data")
	check(Journal.validate_document({"profile_id":profile,Journal.FIELD:value}).valid,"sole production validator accepts the complete sequenced aggregate")
	check(not Journal.lookup(value,"legacy:1").is_empty() and not Journal.lookup(value,api.sequence_id(epoch,130)).is_empty(),"legacy and retained recent retries still return exact stored outcomes")
	var retired: Dictionary = api.admission(value,api.sequence_id(epoch,1),epoch)
	check(not bool(retired.success) and retired.reason == "item_operation_retired","retired identity has a permanent explicit refusal despite removal of its detailed outcome")
	check(not bool(api.admission(value,api.sequence_id("abcdef1234567890abcdef1234567890",131),epoch).success),"another epoch cannot borrow the same next serial")
	check(not bool(api.admission(value,api.sequence_id(epoch,132),epoch).success),"future serial cannot skip a required contiguous result")
	check(bool(api.admission(value,api.sequence_id(epoch,131),epoch).success),"only the exact next operation is eligible")
	var bad := value.duplicate(true); bad.entries.remove_at(0)
	check(not Journal.validate_document({"profile_id":profile,Journal.FIELD:bad}).valid,"a gap in retained sequence outcomes invalidates the aggregate")
	bad = value.duplicate(true); bad.retired_through = 65
	check(not Journal.validate_document({"profile_id":profile,Journal.FIELD:bad}).valid,"a mismatched retirement watermark cannot silently reopen history")
	bad = value.duplicate(true); bad.entries[1].operation_id = bad.entries[0].operation_id
	check(not Journal.validate_document({"profile_id":profile,Journal.FIELD:bad}).valid,"duplicate sequenced identities invalidate the whole aggregate")
	bad = value.duplicate(true); bad.schema_version = 3; bad.entries = "malformed"
	check(Journal.validate_document({"profile_id":profile,Journal.FIELD:bad}).terminal,"future v2-container version remains terminal before known-schema structure validation")
	bad = value.duplicate(true); bad.legacy_entries[0].action = "hc.future.action"
	check(Journal.validate_document({"profile_id":profile,Journal.FIELD:bad}).terminal,"unknown preserved legacy action remains terminal in a v2 aggregate")
	check(api.sequence_id(epoch,9007199254740992).is_empty(),"operation serials outside exact JSON integer range cannot be issued")
	check(not bool(api.admission({},"hc:itemtx:malformed:1",epoch).success),"malformed reserved-prefix ID cannot fall back to the legacy protocol")
	var restored := Journal.recovered(value)
	check(restored.get("contract_id") == "hc.item.transactions.v3" and restored.get("schema_version") == 3 and restored.get("epoch") != epoch,"backup recovery has an explicit new durable epoch contract")
	check(restored.get("entries") == value.entries and restored.get("legacy_entries") == legacy.entries and restored.get("retired_through") == value.retired_through,"recovery preserves every bounded old outcome and logical watermark")
	check(Journal.validate_document({"profile_id":profile,Journal.FIELD:JSON.parse_string(JSON.stringify(restored))}).valid,"mixed-epoch recovery is valid after actual JSON numeric conversion")
	check(Journal.admission(restored,Journal.sequence_id(epoch,131)).reason == "item_operation_epoch_mismatch","an old issuer cannot claim the next recovered sequence")
	var recovery_epoch: String = restored.epoch
	for sequence in range(131,199):
		entry.operation_id = Journal.sequence_id(recovery_epoch,sequence)
		restored = Journal.appended(restored,profile,entry,recovery_epoch)
		if restored.is_empty(): break
	check(not restored.is_empty() and restored.entries.size() == 64 and restored.legacy_entries == legacy.entries and int(restored.retired_through) == 134,"68 recovered operations cross the mixed window without losing opaque history or growing results")
	if restored.is_empty(): _finish(); return
	check(Journal.admission(restored,Journal.sequence_id(recovery_epoch,131)).reason == "item_operation_retired","new recovery stream also permanently refuses its own retired detailed results")
	var again := Journal.recovered(restored)
	check(again.get("epoch") not in [epoch,recovery_epoch] and again.entries == restored.entries,"repeated v3 recovery closes its prior producer while retaining outcomes")
	check(Journal.admission(again,Journal.sequence_id(recovery_epoch,199)).reason == "item_operation_epoch_mismatch","recovery of recovery cannot reuse old next identity")
	bad = again.duplicate(true); bad.entries[0].operation_id = Journal.sequence_id(epoch,1)
	check(not Journal.validate_document({"profile_id":profile,Journal.FIELD:bad}).valid,"mixed epochs never permit sequence gaps or wrong positions")
	bad = again.duplicate(true); bad.entries[0].operation_id = "opaque:wrong"
	check(not Journal.validate_document({"profile_id":profile,Journal.FIELD:bad}).valid,"v3 recent outcomes still require canonical sequenced IDs")
	bad = again.duplicate(true); bad.schema_version = 4; bad.entries = "malformed"
	check(Journal.validate_document({"profile_id":profile,Journal.FIELD:bad}).terminal,"future recovery schema is terminal before malformed known fields")
	check(Journal.recovered(legacy).is_empty(),"recovery helper cannot reinterpret opaque history as a sequenced stream")

	_finish()
func _finish() -> void:
	if not proof.write_receipt("item_journal_sequence_test",checks,failures.size()): failures.append("receipt")
	print("ITEM_JOURNAL_SEQUENCE_%s checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL",checks,str(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)
