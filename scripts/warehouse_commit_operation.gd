extends RefCounted

## Domain-thread transaction owner. Files are promoted by the same ordered
## character writer; no worker accesses gameplay state. Completion applies the
## entire live transfer before another transaction can consume this receipt.
var _service: RefCounted
var _prepared: RefCounted
var _previous: Dictionary
var _validators: Dictionary
var _record_receipt: Callable
var _complete: Callable
var _faults: Dictionary
var _identity: Dictionary
var _journal_written := false
var _rollback_ok := true


func start(service: RefCounted, prepared: RefCounted, previous: Dictionary,
	validators: Dictionary, record_receipt: Callable, on_complete: Callable, faults: Dictionary, identity: Dictionary) -> void:
	if service == null or not service.assert_owner():
		return
	assert(identity.get("profile_id") is String and identity.get("world_clock_generation") is String)
	assert(str(identity.profile_id) == str(prepared.documents.journal.profile_id))
	_identity = identity.duplicate(true)
	_identity.make_read_only()
	_service = service
	_prepared = prepared
	_previous = previous
	_validators = validators
	_record_receipt = record_receipt
	_complete = on_complete
	_faults = faults
	_promote("journal")


func _request_identity(key: String, stage: String) -> Dictionary:
	if _service == null or not _service.assert_owner():
		return {}
	var identity := _identity.duplicate(true)
	identity["path"] = str(_prepared.paths[key])
	identity["domain"] = "warehouse"
	identity["stage"] = stage + ":" + key
	return identity


static func _matches_approved(document: Dictionary, approved: Dictionary) -> Dictionary:
	# All four normalized documents and their cross-file relation have already
	# passed domain validation. Only those EXACT bytes/documents may be committed.
	return {"valid": document == approved, "terminal": false}


func _promote(key: String) -> void:
	if _service == null or not _service.assert_owner():
		return
	if bool(_faults.get(key, false)):
		_failed()
		return
	var document_key := "journal" if key == "journal" else "after_" + key
	var request: RefCounted = _service.submit(
		str(_prepared.paths[key]), _request_identity(key, "promote"),
		{}, _matches_approved.bind(_prepared.documents[document_key]), Callable(), key == "journal",
		_previous.get(key), _promoted.bind(key), false, _prepared.bytes[key],
		str(_prepared.temporary_paths[key]), key != "journal")
	if request == null:
		_failed()


func _promoted(receipt: Dictionary, key: String) -> void:
	if _service == null or not _service.assert_owner():
		return
	if not bool(receipt.get("success", false)):
		_failed()
		return
	_record_receipt.call(receipt)
	match key:
		"journal":
			_journal_written = true
			_promote("shared")
		"shared":
			_promote("profile")
		"profile":
			_finish(true, true)


func _failed() -> void:
	if _service == null or not _service.assert_owner():
		return
	if not _journal_written:
		_finish(false, false)
	elif bool(_faults.get("rollback", false)):
		_finish(false, false)
	else:
		_restore("shared")


func _restore(key: String) -> void:
	if _service == null or not _service.assert_owner():
		return
	var request: RefCounted = _service.submit(str(_prepared.paths[key]),
		_request_identity(key, "restore"),
		_prepared.documents["before_" + key], _validators[key], Callable(), false, null,
		_restored.bind(key))
	if request == null:
		_restored({"success": false}, key)


func _restored(receipt: Dictionary, key: String) -> void:
	if _service == null or not _service.assert_owner():
		return
	if bool(receipt.get("success", false)):
		_record_receipt.call(receipt)
	else:
		_rollback_ok = false
	if key == "shared":
		_restore("profile")
	else:
		_finish(false, _rollback_ok)


func _finish(success: bool, can_remove_journal: bool) -> void:
	if _service == null or not _service.assert_owner():
		return
	# Release references before callbacks can start another warehouse action.
	var callback := _complete
	_complete = Callable()
	callback.call(success, can_remove_journal, _journal_written)
