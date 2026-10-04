extends RefCounted

const DropRules := preload("res://scripts/item_drop_instance_rules.gd")
const RelicRules := preload("res://scripts/layers/rules/relic_synthesis_rules.gd")
const PlainGraph := preload("res://scripts/features/contracts/plain_graph.gd")
const GemRules := preload("res://scripts/items/socket_gem_rules.gd")
const RuneRules := preload("res://scripts/items/rune_item_rules.gd")
const Registry := preload("res://scripts/identity/entity_registry.gd")
const Identity := preload("res://scripts/identity/item_identity_codec.gd")
const EquipmentIdentity := preload("res://scripts/identity/equipment_identity_codec.gd")
const CONTRACT := "hardcore.item.container.v2"
const VERSION := 2
const RUNTIME_EXTENSION := "_hc_item_extension"
const KNOWN_VALID := "KNOWN_VALID"
const INVALID := "INVALID"
const OPAQUE_UNSUPPORTED := "OPAQUE_UNSUPPORTED"
const ARRAY_FIELDS := ["inventory", "warehouse_inventory", "forge_tray", "synthesis_tray"]
const SOCKET_NAMESPACE := "hc.socketing"
const SOCKET_ID := "hc.socketing.primary"
const RUNE_NAMESPACE := "hc.runes"
const RUNE_ID := "hc.runes.primary"

# Wire containers have one base. Runtime keeps that same base as the existing
# flat item record; this private field owns extensions only, never attributes.
# Old records retain their exact wire shape and old strict validators.
static func decode_wire(record: Dictionary) -> Dictionary:
	var is_container := _is_wire_container(record)
	# An unsupported owner defines its own graph and field limits. Recognize
	# that shallow header before applying today's corruption/recovery rules.
	if is_container:
		if (_integer(record.get("format_version")) and record.format_version > VERSION) \
			or (record.get("contract_id") is String and record.contract_id != CONTRACT):
			return _failure(OPAQUE_UNSUPPORTED, "unsupported_item_container")
		if _integer(record.get("format_version")) and record.format_version == VERSION \
			and record.get("contract_id") is String and record.contract_id == CONTRACT \
			and record.get("extensions") is Dictionary:
			var support := _extension_support_status(record.extensions)
			if support.status != KNOWN_VALID:
				return support
	if record.has(RUNTIME_EXTENSION):
		return _failure(INVALID, "private_runtime_item_field_on_wire")
	if not is_container:
		if record.has("rune_instance_contract_id"):
			if not record.rune_instance_contract_id is String: return _failure(INVALID,"invalid_rune_instance_contract")
			if record.rune_instance_contract_id!=RuneRules.INSTANCE_CONTRACT: return _failure(OPAQUE_UNSUPPORTED,"unsupported_rune_instance_contract")
			if _integer(record.get("item_id")) and Registry.from_legacy("item",int(record.item_id)).is_empty():
				return _failure(OPAQUE_UNSUPPORTED,"unknown_rune_item_identity")
			return _success(record) if RuneRules.valid_instance(record) else _failure(INVALID,"invalid_rune_instance")
		if _integer(record.get("item_id")) and not RuneRules.record_for_id(int(record.item_id)).is_empty():
			return _failure(INVALID,"missing_rune_instance_contract")
		if record.has("gem_instance_contract_id"):
			if not record.gem_instance_contract_id is String:
				return _failure(INVALID, "invalid_gem_instance_contract")
			if record.gem_instance_contract_id != GemRules.INSTANCE_CONTRACT:
				return _failure(OPAQUE_UNSUPPORTED, "unsupported_gem_instance_contract")
			return _success(record) if GemRules.valid_instance(record) else _failure(INVALID, "invalid_gem_instance")
		if _integer(record.get("item_id")) and int(record.item_id) == GemRules.ITEM_ID:
			return _failure(INVALID, "missing_gem_instance_contract")
		return _success(record)
	var plain := PlainGraph.capture(record, 4096, 16)
	if not bool(plain.success):
		return _failure(INVALID, "item_extension_graph_capacity_or_type")
	if not _integer(record.get("format_version")) or not record.get("contract_id") is String:
		return _failure(INVALID, "invalid_item_container_version")
	if record.format_version != VERSION or not _keys(record, ["contract_id", "format_version", "entity_id", "base", "extensions"]) \
		or not record.base is Dictionary or not record.extensions is Dictionary or not record.entity_id is String:
		return _failure(INVALID, "invalid_item_container")
	var base: Dictionary = record.base
	if base.has(RUNTIME_EXTENSION) or _is_wire_container(base) or not _valid_extended_base(base, record.entity_id):
		return _failure(INVALID, "invalid_item_container_base")
	var extensions := _validate_extensions(base, record.extensions)
	if extensions.status != KNOWN_VALID:
		return extensions
	var runtime := base.duplicate(true)
	runtime[RUNTIME_EXTENSION] = {"contract_id": CONTRACT, "format_version": VERSION,
		"extensions": record.extensions.duplicate(true)}
	return _success(runtime)

static func encode_runtime(record: Dictionary) -> Dictionary:
	if _is_wire_container(record):
		return _failure(INVALID, "wire_container_in_runtime")
	if not record.has(RUNTIME_EXTENSION):
		return decode_wire(record)
	var metadata: Variant = record[RUNTIME_EXTENSION]
	if not metadata is Dictionary or not _keys(metadata, ["contract_id", "format_version", "extensions"]):
		return _failure(INVALID, "invalid_runtime_item_extension")
	var base := record.duplicate(true)
	base.erase(RUNTIME_EXTENSION)
	var wire := {"contract_id": metadata.contract_id, "format_version": metadata.format_version,
		"entity_id": GameData.item_entity_id(base), "base": base, "extensions": metadata.extensions}
	var validation := decode_wire(wire)
	if validation.status != KNOWN_VALID:
		return validation
	return _success(wire)

static func normalize_runtime(record: Dictionary) -> Dictionary:
	if _is_wire_container(record):
		return decode_wire(record)
	var validation := encode_runtime(record)
	return _success(record) if validation.status == KNOWN_VALID else validation

static func base_record(record: Dictionary) -> Dictionary:
	if _is_wire_container(record):
		var decoded := decode_wire(record)
		return base_record(decoded.item) if decoded.status == KNOWN_VALID else {}
	if not record.has(RUNTIME_EXTENSION):
		return record
	if encode_runtime(record).status != KNOWN_VALID:
		return {}
	var base := record.duplicate(true)
	base.erase(RUNTIME_EXTENSION)
	return base

static func with_extensions(base: Dictionary, extensions: Dictionary) -> Dictionary:
	var wire := {"contract_id": CONTRACT, "format_version": VERSION,
		"entity_id": GameData.item_entity_id(base), "base": base, "extensions": extensions}
	return decode_wire(wire)

static func extensions(record: Dictionary) -> Dictionary:
	if _is_wire_container(record):
		var decoded := decode_wire(record)
		return record.extensions.duplicate(true) if decoded.status == KNOWN_VALID else {}
	var encoded := encode_runtime(record)
	if encoded.status != KNOWN_VALID or not _is_wire_container(encoded.item):
		return {}
	return encoded.item.extensions.duplicate(true)

static func decode_document(document: Dictionary) -> Dictionary:
	return _map_document(document, false)

static func encode_document(document: Dictionary) -> Dictionary:
	return _map_document(document, true)

static func _map_document(document: Dictionary, encode: bool) -> Dictionary:
	var identity := Identity.support(document)
	if identity.status != KNOWN_VALID:
		return identity
	var equipment_identity := EquipmentIdentity.normalize_document(document, encode)
	if equipment_identity.status != KNOWN_VALID: return equipment_identity
	var output: Dictionary = equipment_identity.document
	document = output
	var failure: Dictionary = {}
	var owns_items := document.has("equipment")
	for field: String in ARRAY_FIELDS:
		if not document.get(field) is Array:
			continue # The existing aggregate validator owns container shape/capacity.
		owns_items = true
		var mapped: Array = document[field]
		for index in mapped.size():
			var raw: Variant = mapped[index]
			if not raw is Dictionary:
				continue
			var result := _map_document_item(raw, encode, encode or not bool(identity.formal))
			if result.status != KNOWN_VALID:
				if result.status == OPAQUE_UNSUPPORTED:
					return result
				failure = result
				continue
			if not is_same(result.item, raw):
				if is_same(mapped, document[field]): mapped = mapped.duplicate()
				mapped[index] = result.item
		if not is_same(mapped, document[field]):
			if is_same(output, document): output = output.duplicate()
			output[field] = mapped
	if document.get("equipment") is Dictionary:
		var mapped: Dictionary = document.equipment
		for slot: Variant in document.equipment:
			var raw: Variant = document.equipment[slot]
			if not raw is Dictionary:
				if encode or bool(identity.formal) or document.has(EquipmentIdentity.FIELD) or not raw is String:
					return _failure(OPAQUE_UNSUPPORTED, "non_record_formal_equipment")
				# Only the explicit old equipment import may carry a display
				# string. Validate its exact registered owner now; runtime's
				# existing importer still owns instance/durability creation.
				if not raw.is_empty() and Identity.normalize({"name": raw}, true).status != KNOWN_VALID:
					return _failure(OPAQUE_UNSUPPORTED, "unknown_legacy_equipment_identity")
				continue
			var result := _map_document_item(raw, encode, encode or not bool(identity.formal))
			if result.status != KNOWN_VALID:
				if result.status == OPAQUE_UNSUPPORTED:
					return result
				failure = result
				continue
			if not is_same(result.item, raw):
				if is_same(mapped, document.equipment): mapped = mapped.duplicate()
				mapped[slot] = result.item
		if not is_same(mapped, document.equipment):
			if is_same(output, document): output = output.duplicate()
			output.equipment = mapped
	if encode and owns_items and not document.has(Identity.FIELD):
		if is_same(output, document): output = output.duplicate()
		output[Identity.FIELD] = Identity.HEADER.duplicate()
	return failure if not failure.is_empty() else {"status": KNOWN_VALID, "document": output, "reason": ""}

static func _map_document_item(record: Dictionary, encode: bool, allow_legacy: bool) -> Dictionary:
	# A prepared journal may combine unchanged wire records and changed runtime
	# records. Validate either representation and publish only canonical wire.
	var runtime := decode_wire(record) if not encode or _is_wire_container(record) else normalize_runtime(record)
	if runtime.status != KNOWN_VALID: return runtime
	var identity := Identity.normalize(runtime.item, allow_legacy)
	if identity.status != KNOWN_VALID: return identity
	return encode_runtime(identity.item) if encode else identity

static func document_items(document: Dictionary) -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	for field: String in ARRAY_FIELDS:
		if document.get(field) is Array:
			for record: Variant in document[field]:
				if record is Dictionary: records.append(record)
	if document.get("equipment") is Dictionary:
		for record: Variant in document.equipment.values():
			if record is Dictionary: records.append(record)
	return records

static func has_extensions(record: Dictionary) -> bool:
	return record.has(RUNTIME_EXTENSION) or _is_wire_container(record) or record.has("gem_instance_contract_id") or record.has("rune_instance_contract_id")

static func can_release_ownership(record: Dictionary) -> bool:
	# Selling, destruction and material consumption cannot silently destroy an
	# independently owned embedded item. Remove it through the common port first.
	var normalized := normalize_runtime(record)
	return normalized.status == KNOWN_VALID and embedded_records(normalized.item).is_empty()

static func embedded_records(record: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	var owned:=extensions(record)
	for socket: Dictionary in owned.get(SOCKET_NAMESPACE,{}).get("sockets",[]):
		result.append({"slot_id":socket.socket_id,"namespace_id":SOCKET_NAMESPACE,"item":socket.item})
	for rune: Dictionary in owned.get(RUNE_NAMESPACE,{}).get("runes",[]):
		result.append({"slot_id":rune.rune_slot_id,"namespace_id":RUNE_NAMESPACE,"item":rune.item})
	return result

static func ownership_ids(record: Dictionary) -> Array[String]:
	var base := base_record(record)
	var result: Array[String] = []
	if base.is_empty():
		return result
	var instance: Variant = base.get("instance_id")
	if instance is String and not instance.is_empty():
		result.append(instance)
	for socket: Dictionary in embedded_records(record):
		var gem := decode_wire(socket.item)
		if gem.status == KNOWN_VALID:
			result.append(str(gem.item.instance_id))
	return result

static func _valid_extended_base(base: Dictionary, entity_id: String) -> bool:
	if entity_id.is_empty() or GameData.item_entity_id(base) != entity_id \
		or not base.get("instance_id") is String or base.instance_id.is_empty() or base.instance_id.length() > 128 \
		or not _integer(base.get("count")) or base.count != 1:
		return false
	var catalog := GameData.get_entity_record(entity_id)
	if catalog.is_empty() or catalog.get("kind") != "equipment":
		return false
	if base.has("drop_instance_contract_id"):
		return DropRules.validate_instance(base, catalog)
	var numeric_id := int(catalog.get("itemId", -1))
	if RelicRules.is_synthesis_item(numeric_id):
		return RelicRules.valid_instance(base, numeric_id)
	# Plain legacy equipment remains subject to the existing validator. The new
	# extension boundary additionally requires an exact registered item identity.
	return _integer(base.get("item_id")) and int(base.item_id) == numeric_id

static func _validate_extensions(base: Dictionary, value: Dictionary) -> Dictionary:
	if value.size() > 2:
		return _failure(INVALID, "item_extension_namespace_capacity")
	var seen: Dictionary={}; seen[base.instance_id]=true
	for namespace_id: Variant in value:
		if namespace_id==RUNE_NAMESPACE:
			var rune_status:=_validate_rune_extension(base,value[namespace_id])
			if rune_status.status!=KNOWN_VALID: return rune_status
			for rune: Dictionary in value[namespace_id].runes:
				if seen.has(rune.item.instance_id): return _failure(INVALID,"duplicate_embedded_instance_identity")
				seen[rune.item.instance_id]=true
			continue
		if namespace_id != SOCKET_NAMESPACE:
			return _failure(OPAQUE_UNSUPPORTED, "unsupported_item_extension_namespace")
		var extension: Variant = value[namespace_id]
		if not extension is Dictionary or not _integer(extension.get("schema_version")):
			return _failure(INVALID, "invalid_socket_extension_version")
		if extension.schema_version > 1:
			return _failure(OPAQUE_UNSUPPORTED, "unsupported_socket_extension_version")
		if extension.schema_version != 1 or not _keys(extension, ["schema_version", "sockets"]) \
			or not extension.sockets is Array or extension.sockets.size() > 1:
			return _failure(INVALID, "invalid_socket_extension")
		for socket: Variant in extension.sockets:
			if not socket is Dictionary or not _keys(socket, ["socket_id", "item"]) \
				or not socket.socket_id is String or socket.socket_id != SOCKET_ID or not socket.item is Dictionary:
				return _failure(INVALID, "invalid_socket_record")
			var gem := decode_wire(socket.item)
			if gem.status != KNOWN_VALID:
				return gem
			if gem.item.has(RUNTIME_EXTENSION) or not gem.item.get("instance_id") is String \
				or gem.item.instance_id.is_empty() or gem.item.instance_id == base.instance_id \
				or not _integer(gem.item.get("count")) or gem.item.count != 1 \
				or not GemRules.valid_instance(gem.item):
				return _failure(INVALID, "invalid_socket_gem")
			if seen.has(gem.item.instance_id): return _failure(INVALID,"duplicate_embedded_instance_identity")
			seen[gem.item.instance_id]=true
	return {"status": KNOWN_VALID, "reason": ""}

static func _extension_support_status(value: Dictionary) -> Dictionary:
	# Recognize unsupported ownership before judging a known base/capacity. A
	# corrupted sibling must never authorize recovery over a future extension.
	for namespace_id: Variant in value:
		if namespace_id not in [SOCKET_NAMESPACE,RUNE_NAMESPACE]:
			return _failure(OPAQUE_UNSUPPORTED, "unsupported_item_extension_namespace")
		var extension: Variant = value[namespace_id]
		if extension is Dictionary and _integer(extension.get("schema_version")) and extension.schema_version > 1:
			return _failure(OPAQUE_UNSUPPORTED, "unsupported_rune_extension_version" if namespace_id==RUNE_NAMESPACE else "unsupported_socket_extension_version")
		if extension is Dictionary:
			var entries: Variant=extension.get("runes" if namespace_id==RUNE_NAMESPACE else "sockets")
			if entries is Array:
				for entry: Variant in entries:
					if not entry is Dictionary or not entry.get("item") is Dictionary: continue
					var item: Dictionary=entry.item
					if item.get("rune_instance_contract_id") is String and item.rune_instance_contract_id!=RuneRules.INSTANCE_CONTRACT:
						return _failure(OPAQUE_UNSUPPORTED,"unsupported_rune_instance_contract")
					if item.get("rune_instance_contract_id") is String and _integer(item.get("item_id")) \
						and Registry.from_legacy("item",int(item.item_id)).is_empty():
						return _failure(OPAQUE_UNSUPPORTED,"unknown_rune_item_identity")
					if item.get("gem_instance_contract_id") is String and item.gem_instance_contract_id!=GemRules.INSTANCE_CONTRACT:
						return _failure(OPAQUE_UNSUPPORTED,"unsupported_gem_instance_contract")
					if _is_wire_container(item) and ((_integer(item.get("format_version")) and item.format_version>VERSION) \
						or (item.get("contract_id") is String and item.contract_id!=CONTRACT)):
						return _failure(OPAQUE_UNSUPPORTED,"unsupported_embedded_item_container")
	return {"status": KNOWN_VALID, "reason": ""}

static func _validate_rune_extension(base: Dictionary,value: Variant) -> Dictionary:
	if not value is Dictionary or not _keys(value,["schema_version","runes"]) or not _integer(value.schema_version) \
		or value.schema_version!=1 or not value.runes is Array or value.runes.size()>1: return _failure(INVALID,"invalid_rune_extension")
	for rune: Variant in value.runes:
		if not rune is Dictionary or not _keys(rune,["rune_slot_id","item"]) or rune.rune_slot_id!=RUNE_ID or not rune.item is Dictionary:
			return _failure(INVALID,"invalid_rune_slot")
		var item:=decode_wire(rune.item)
		if item.status!=KNOWN_VALID: return item
		if not RuneRules.valid_instance(item.item) or item.item.instance_id==base.instance_id: return _failure(INVALID,"invalid_embedded_rune")
	return {"status":KNOWN_VALID,"reason":""}

static func _is_wire_container(record: Dictionary) -> bool:
	return record.has("format_version") or record.has("base") or record.has("extensions") \
		or (record.get("contract_id") is String and record.contract_id.begins_with("hardcore.item.container."))

static func _keys(value: Dictionary, fields: Array) -> bool:
	if value.size() != fields.size():
		return false
	for field: String in fields:
		if not value.has(field):
			return false
	return true

static func _integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value))

static func _success(item: Dictionary) -> Dictionary:
	return {"status": KNOWN_VALID, "item": item, "reason": ""}

static func _failure(status: String, reason: String) -> Dictionary:
	return {"status": status, "item": {}, "document": {}, "reason": reason}
