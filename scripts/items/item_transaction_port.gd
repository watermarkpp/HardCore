extends RefCounted

const Codec := preload("res://scripts/items/item_extension_codec.gd")
const Gem := preload("res://scripts/items/socket_gem_rules.gd")
const Journal := preload("res://scripts/items/item_transaction_journal.gd")
const Graph := preload("res://scripts/features/contracts/plain_graph.gd")
var _owner: WeakRef
var _active: Dictionary = {}
var _issued_context := ""
var _issued_epoch := ""

func _init(owner: Node) -> void:
	_owner = weakref(owner)

func quote_new(request: Dictionary) -> Dictionary:
	var player: Node = _owner.get_ref()
	if player == null or request.size() != 3 or request.has("operation_id"):
		return _failure("invalid_item_command")
	var issued := request.duplicate(true)
	var journal: Dictionary = player._item_transaction_journal
	var last := int(journal.get("last_sequence",0)) if journal.get("contract_id") == Journal.SEQUENCE_CONTRACT else 0
	if last >= Journal.MAX_SEQUENCE: return _failure("item_operation_sequence_exhausted")
	# Dot insertion on a new dictionary key can create a StringName; the plain
	# boundary deliberately accepts String keys only.
	issued["operation_id"] = Journal.sequence_id(_epoch_for(player),last+1)
	return quote(issued)

func _epoch_for(player: Node) -> String:
	if player._item_transaction_journal.get("contract_id") == Journal.SEQUENCE_CONTRACT:
		_issued_epoch = ""; _issued_context = ""
		return player._item_transaction_journal.epoch
	var context := JSON.stringify([player.active_profile_id,player._world_clock_generation])
	if _issued_context != context or _issued_epoch.is_empty():
		_issued_context = context; _issued_epoch = Crypto.new().generate_random_bytes(16).hex_encode()
	return _issued_epoch

func quote(request: Dictionary) -> Dictionary:
	var player: Node = _owner.get_ref()
	if player == null or not _request_valid(request): return _failure("invalid_item_command")
	var digest := JSON.stringify([player.active_profile_id, request.action, request.target_instance_id, request.gem_instance_id]).sha256_text()
	var recorded := Journal.lookup(player._item_transaction_journal, request.operation_id)
	if not recorded.is_empty():
		if recorded.request_digest != digest: return _failure("operation_identity_conflict")
		return {"success": true, "replay": true, "request": request.duplicate(true), "outcome": recorded}
	var epoch := _epoch_for(player) if request.operation_id.begins_with(Journal.SEQUENCE_PREFIX) else ""
	var admission := Journal.admission(player._item_transaction_journal,request.operation_id,epoch)
	if not bool(admission.success): return _failure(admission.reason)
	var config := ContentLayers.feature_configuration()
	if Gem.MODULE not in config.get("enabled_modules", []): return _failure("socket_fixture_disabled")
	if "items.transact" not in config.catalog.modules[Gem.MODULE].capabilities: return _failure("missing_item_transaction_permission")
	if not player._valid_profile_storage_id(player.active_profile_id) or player.active_profile_id == player._save_blocked_profile_id \
		or not player._can_accept_immediate_item_use() or player._world_clock_snapshot_sequence < 0:
		return _failure("item_transaction_unavailable")
	if not player._validate_extended_item_ownership({"inventory": player.inventory, "equipment": player.equipment,
		"forge_tray": player.forge_tray, "synthesis_tray": player.synthesis_tray, "warehouse_inventory": player.warehouse_inventory}):
		return _failure("invalid_item_ownership")
	var target := _find(request.target_instance_id)
	if target.is_empty(): return _failure("target_instance_missing_or_ambiguous")
	var base := Codec.base_record(target.record)
	if base.is_empty() or not base.get("count") in [1, 1.0] or GameData.get_item_record(base).get("kind") != "equipment" \
		or not base.has("item_id") or GameData.item_entity_id(base).is_empty(): return _failure("invalid_socket_target")
	var existing := Codec.extensions(target.record)
	var sockets: Array = existing.get(Codec.SOCKET_NAMESPACE, {}).get("sockets", [])
	var gem: Dictionary = {}
	if request.action == "hc.socketing.insert":
		var input := _find(request.gem_instance_id)
		if not sockets.is_empty() or input.is_empty() or input.container != "inventory" or not Gem.valid_instance(input.record):
			return _failure("socket_input_unavailable")
		gem = input.record
	else:
		if sockets.size() != 1: return _failure("socket_is_empty")
		gem = sockets[0].item
		if _free_inventory_slot() < 0: return _failure("inventory_full")
	var extension := {Codec.SOCKET_NAMESPACE: {"schema_version": 1, "sockets": (
		[{"socket_id": Codec.SOCKET_ID, "item": gem}] if request.action == "hc.socketing.insert" else [])}}
	var output := Codec.with_extensions(base, extension)
	if output.status != Codec.KNOWN_VALID: return _failure(output.reason)
	var result := {"success": true, "replay": false, "request": request.duplicate(true),
		"protocol_epoch":epoch,
		"profile_id": player.active_profile_id, "world_clock_generation": player._world_clock_generation,
		"rules_revision": config.catalog.revision, "request_digest": digest,
		"target_digest": _target_digest(target.record), "gem_digest": _item_digest(gem),
		"target_entity_id": GameData.item_entity_id(base), "gem_instance_id": gem.instance_id}
	var captured := Graph.capture(result)
	return captured.value if bool(captured.success) else _failure("non_plain_item_quote")

func commit(quoted: Dictionary) -> Dictionary:
	var player: Node = _owner.get_ref()
	if player == null or not quoted.get("success", false) or not quoted.get("request") is Dictionary:
		return _failure("invalid_item_quote")
	var request: Dictionary = quoted.request
	var refreshed := quote(request)
	if not bool(refreshed.get("success", false)): return _failure("stale_item_quote")
	if bool(refreshed.replay): return _outcome(refreshed.outcome)
	if refreshed != quoted: return _failure("stale_item_quote")
	if not _active.is_empty():
		return _pending(_active.job) if _active.quote == quoted else _failure("item_inputs_reserved")
	# No snapshot is captured ahead of another accepted character receipt.
	# UI retries once that existing ordered writer becomes available.
	if player._json_persistence.pending_count() > 0 or player._workbench_transfer_pending:
		return _failure("character_writer_busy")
	var path: String = player._profile_path(player.active_profile_id)
	var plan := {"quote": quoted.duplicate(true), "destination": _free_inventory_slot() if request.action == "hc.socketing.remove" else -1,
		"output": {}, "journal": {}, "reason": "", "job": null}
	_active = plan
	var identity := {"domain": "item_transaction", "path": path, "profile_id": quoted.profile_id,
		"world_clock_generation": quoted.world_clock_generation, "operation_id": request.operation_id}
	var job: RefCounted = player._json_persistence.submit(path, identity, {}, player._json_validator_for_path(path),
		_guard.bind(plan), false, null, _complete.bind(plan), false, null, "", false, _build_document.bind(plan))
	if job == null:
		_active = {}
		return _failure("character_writer_rejected")
	plan.job = job
	return _pending(job)

func record_reserved(record: Dictionary) -> bool:
	if _active.is_empty(): return false
	var ids := Codec.ownership_ids(record)
	return ids.has(_active.quote.request.target_instance_id) or ids.has(_active.quote.gem_instance_id)

func slot_reserved(index: int) -> bool:
	return not _active.is_empty() and int(_active.destination) >= 0 and (index < 0 or index == int(_active.destination))

func _guard(_identity: Dictionary, plan: Dictionary) -> bool:
	if not _receipt_context_matches(plan): return false
	return quote(plan.quote.request) == plan.quote

func _receipt_context_matches(plan: Dictionary) -> bool:
	var player: Node = _owner.get_ref()
	if player == null or player.active_profile_id != plan.quote.profile_id or player._world_clock_generation != plan.quote.world_clock_generation:
		return false
	var target := _find(plan.quote.request.target_instance_id)
	if target.is_empty() or _target_digest(target.record) != plan.quote.target_digest: return false
	var gem: Dictionary = {}
	if plan.quote.request.action == "hc.socketing.insert":
		gem = _find(plan.quote.gem_instance_id).get("record", {})
	else:
		var sockets: Array = Codec.extensions(target.record).get(Codec.SOCKET_NAMESPACE, {}).get("sockets", [])
		if sockets.size() != 1: return false
		gem = sockets[0].item
	if _item_digest(gem) != plan.quote.gem_digest: return false
	if int(plan.destination) >= 0 and int(plan.destination) < player.inventory.size() and not player.inventory[plan.destination].is_empty(): return false
	return true

func _build_document(previous: Dictionary, identity: Dictionary, plan: Dictionary) -> Variant:
	var player: Node = _owner.get_ref()
	if not _guard(identity, plan) or previous.is_empty(): return null
	# Disk and live journal must refer to the same accepted outcomes. An external
	# edit or late incompatible receipt requires recovery, never a second apply.
	if JSON.parse_string(JSON.stringify(previous.get(Journal.FIELD, {}))) != JSON.parse_string(JSON.stringify(player._item_transaction_journal)):
		plan.reason = "item_journal_authority_changed"
		return null
	var target := _find(plan.quote.request.target_instance_id)
	var gem: Dictionary = (_find(plan.quote.gem_instance_id).get("record", {}) if plan.quote.request.action == "hc.socketing.insert"
		else Codec.extensions(target.record)[Codec.SOCKET_NAMESPACE].sockets[0].item)
	var output := Codec.with_extensions(Codec.base_record(target.record), {Codec.SOCKET_NAMESPACE: {"schema_version": 1,
		"sockets": [{"socket_id": Codec.SOCKET_ID, "item": gem}] if plan.quote.request.action == "hc.socketing.insert" else []}})
	if output.status != Codec.KNOWN_VALID: return null
	plan.output = output.item
	plan.gem = gem.duplicate(true)
	var entry := {"operation_id": identity.operation_id, "request_digest": plan.quote.request_digest,
		"action": plan.quote.request.action, "target_instance_id": plan.quote.request.target_instance_id,
		"gem_instance_id": plan.quote.gem_instance_id, "rules_revision": plan.quote.rules_revision}
	plan.journal = Journal.appended(player._item_transaction_journal, player.active_profile_id, entry,plan.quote.protocol_epoch)
	if plan.journal.is_empty(): return null
	var document: Dictionary = player._prepare_character_save_payload(false).duplicate(true)
	if document.is_empty(): return null
	var decoded := Codec.decode_document(document)
	if decoded.status != Codec.KNOWN_VALID: return null
	document = decoded.document
	_apply_item_delta(document.inventory, document.equipment, target, plan)
	document[Journal.FIELD] = plan.journal
	var encoded := Codec.encode_document(document)
	return encoded.document if encoded.status == Codec.KNOWN_VALID else null

func _complete(receipt: Dictionary, plan: Dictionary) -> void:
	# A retained asynchronous callback loses publication rights with its job.
	# It must not restore an old journal/frontier after a later operation finishes.
	if _active.is_empty() or _active.get("job") != plan.get("job"): return
	var player: Node = _owner.get_ref()
	if bool(receipt.get("success", false)):
		# Receipt consumption precedes pumping any next character save. Publish
		# related ownership first; never assign the captured full profile/inventory.
		if player == null or not _receipt_context_matches(plan):
			if player != null:
				player._save_blocked_profile_id = plan.quote.profile_id
				player._save_blocked_reason = "item_transaction_recovery_required"
			receipt["success"] = false
			receipt["reason"] = "item_transaction_recovery_required"
			plan.job.response["success"] = false
			plan.job.response["reason"] = "item_transaction_recovery_required"
		else:
			var target := _find(plan.quote.request.target_instance_id)
			_apply_item_delta(player.inventory, player.equipment, target, plan)
			player._item_transaction_journal = plan.journal.duplicate(true)
			# A completed provisional epoch belongs only to its durable document.
			# If supported recovery later restores a pre-sequence backup, this port
			# must issue a fresh epoch instead of reopening the lost old stream.
			if plan.journal.get("contract_id") == Journal.SEQUENCE_CONTRACT:
				_issued_epoch = ""; _issued_context = ""
			player._record_background_json_receipt(receipt)
			var sequence := int(receipt.document.death_event_sequence)
			player._profile_backup_death_event_sequence = player._backup_sequence_after_promotion(
				str(receipt.identity.path), player._profile_saved_death_event_sequence, sequence, "death_event_sequence")
			player._profile_saved_death_event_sequence = sequence
			player._active_profile_legacy_warehouse_pending = false
			_active = {}
			player._queue_character_snapshot_save()
			player.recalculate_stats(false)
			player.inventory_changed.emit()
			if target.container == "equipment": player.equipment_changed.emit()
			player.profile_changed.emit()
			return
	_active = {}

func _apply_item_delta(inventory: Array, equipment: Dictionary, target: Dictionary, plan: Dictionary) -> void:
	# The economic operation owns only the extension. Current durability remains
	# owned by combat, including changes after irreversible file promotion.
	var current: Dictionary = (inventory[target.index] if target.container == "inventory" else equipment[target.slot]).duplicate(true)
	current[Codec.RUNTIME_EXTENSION] = plan.output[Codec.RUNTIME_EXTENSION].duplicate(true)
	if target.container == "inventory": inventory[target.index] = current
	else: equipment[target.slot] = current
	if plan.quote.request.action == "hc.socketing.insert":
		var gem_index: int = _find(plan.quote.gem_instance_id).get("index", -1)
		assert(gem_index >= 0)
		inventory[gem_index] = {}
	else:
		while inventory.size() <= int(plan.destination): inventory.append({})
		inventory[plan.destination] = plan.gem.duplicate(true)

func _find(instance_id: String) -> Dictionary:
	var player: Node = _owner.get_ref()
	var found := {}
	for index in player.inventory.size():
		var record: Variant = player.inventory[index]
		if record is Dictionary and record.get("instance_id") == instance_id:
			if not found.is_empty(): return {}
			found = {"container": "inventory", "index": index, "record": record}
	for slot: String in player.equipment:
		var record: Variant = player.equipment[slot]
		if record is Dictionary and record.get("instance_id") == instance_id:
			if not found.is_empty(): return {}
			found = {"container": "equipment", "slot": slot, "record": record}
	return found

func _free_inventory_slot() -> int:
	var player: Node = _owner.get_ref()
	for index in player.inventory.size():
		if player.inventory[index] is Dictionary and player.inventory[index].is_empty(): return index
	return player.inventory.size() if player.inventory.size() < player.INVENTORY_CAPACITY else -1

static func _item_digest(record: Dictionary) -> String:
	var encoded := Codec.encode_runtime(record)
	return JSON.stringify(encoded.item).sha256_text() if encoded.status == Codec.KNOWN_VALID else ""

static func _target_digest(record: Dictionary) -> String:
	var normalized := Codec.normalize_runtime(record)
	if normalized.status != Codec.KNOWN_VALID: return ""
	var economic_view: Dictionary = normalized.item.duplicate(true)
	# Only current combat wear is independent of socket eligibility. Maximum
	# durability, affixes, enhancement and all ownership/schema fields still
	# participate in the relevant version check.
	economic_view.erase("durability")
	economic_view.erase("durability_raw")
	# Hash the already validated view; do not ask the strict base validator to
	# accept a projected record with its mandatory durability fields removed.
	return JSON.stringify(economic_view).sha256_text()

static func _request_valid(request: Dictionary) -> bool:
	if request.size() != 4: return false
	for field: String in ["operation_id", "action", "target_instance_id", "gem_instance_id"]:
		if not request.get(field) is String: return false
	return request.action in Journal.ACTIONS and Journal.identity_valid(request.operation_id) \
		and Journal.identity_valid(request.target_instance_id) and (
			Journal.identity_valid(request.gem_instance_id) if request.action == "hc.socketing.insert" else request.gem_instance_id.is_empty())

static func _outcome(entry: Dictionary) -> Dictionary:
	return {"success": true, "pending": false, "durable": true, "applied_in_memory": true, "outcome": entry.duplicate(true)}

static func _pending(job: RefCounted) -> Dictionary:
	return {"success": true, "pending": true, "durable": false, "applied_in_memory": false, "job": job}

static func _failure(reason: String) -> Dictionary:
	return {"success": false, "pending": false, "durable": false, "applied_in_memory": false, "reason": reason}
