extends RefCounted

## One identity based verifier. Admission owns declared children; amounts only
## check committed HP arithmetic, never infer or replace a delivery source.
const UNKNOWN := "UNKNOWN"
const ID_FIELDS := ["source_instance_id", "source_life", "parent_action_id", "runtime_map_id", "zone_generation"]
const CHILD_FIELDS := ["release_id", "child_effect_id", "victim_instance_id", "victim_life", "victim_generation", "admission_release_id"]

static func _integer_fields(record: Dictionary, fields: Array) -> bool:
	for field: String in fields:
		if not record.has(field) or typeof(record[field]) != TYPE_INT:
			return false
	return true

static func _valid_admission(start: Dictionary) -> bool:
	return (
		str(start.get("source_identity", "")) != UNKNOWN
		and typeof(start.get("release_id")) == TYPE_STRING
		and not str(start.release_id).is_empty()
		and _integer_fields(start, ["source_instance_id", "source_life", "parent_action_id", "map_id", "generation", "target_id", "target_life", "target_generation"])
		and int(start.source_instance_id) > 0 and int(start.source_life) >= 0
		and int(start.parent_action_id) > 0
		and int(start.target_id) > 0 and int(start.target_life) >= 0
	)

static func _valid_child_identity(child: Dictionary) -> bool:
	if str(child.get("source_identity", "")) == UNKNOWN:
		return false
	if not _integer_fields(child, ID_FIELDS + ["victim_instance_id", "victim_life", "victim_generation"]):
		return false
	for field: String in ["release_id", "child_effect_id", "admission_release_id"]:
		if typeof(child.get(field)) != TYPE_STRING or str(child[field]).is_empty():
			return false
	# Explicit integer world-generation sentinels are allowed for standalone
	# fixtures, but absent fields and fractional lifecycle IDs are never proof.
	return int(child.source_instance_id) > 0 and int(child.source_life) >= 0 and int(child.parent_action_id) > 0 and int(child.victim_instance_id) > 0 and int(child.victim_life) >= 0

static func verdict(events: Array, terminal_events: Array, under_test_instance_id: int) -> Dictionary:
	var own: Array = []
	var foreign: Array = []
	var unknown: Array = []
	var own_amount := 0
	var foreign_amount := 0
	for event: Dictionary in events:
		var source: Dictionary = event.get("source", {})
		if source.is_empty() or str(source.get("source_identity", "")) == UNKNOWN:
			unknown.append(event)
		elif int(source.get("source_instance_id", -1)) == under_test_instance_id:
			own.append(event)
			own_amount += int(event.get("actual_hp_delta", 0))
		else:
			foreign.append(event)
			foreign_amount += int(event.get("actual_hp_delta", 0))
	return {"under_test_mutations": own, "under_test_amount": own_amount,
		"foreign_mutations": foreign, "foreign_amount": foreign_amount,
		"unknown_mutations": unknown, "terminal_events": terminal_events,
		"suppressed_events": [], "failures": []}

static func _parent(start: Dictionary) -> Dictionary:
	return {"source_instance_id": start.get("source_instance_id", -1),
		"source_life": start.get("source_life", -1), "parent_action_id": start.get("parent_action_id", -1),
		"runtime_map_id": start.get("map_id", -1), "zone_generation": start.get("generation", -1)}

static func _same(a: Dictionary, b: Dictionary, fields: Array) -> bool:
	for field: String in fields:
		if not a.has(field) or not b.has(field) or a[field] != b[field]:
			return false
	return true

static func _child_key(source: Dictionary) -> String:
	return "%s|%s|%s|%s" % [source.get("release_id", ""), source.get("child_effect_id", ""), source.get("victim_instance_id", -1), source.get("victim_life", -1)]

static func audit_releases(starts: Array, events: Array, terminals: Array, source_id: int, deliveries: Array = [], overflowed := false) -> Dictionary:
	var failures: Array = []
	var per_release: Dictionary = {}
	var parents: Dictionary = {}
	var expected: Dictionary = {}
	var completed: Dictionary = {}
	if overflowed:
		failures.append("observer_overflow")
	for start: Dictionary in starts:
		var rid := str(start.get("release_id", ""))
		if not _valid_admission(start) or parents.has(rid) or int(start.get("source_instance_id", -1)) != source_id:
			failures.append("invalid_admission identity=%s" % rid)
			continue
		parents[rid] = start
		per_release[rid] = {"children": [], "terminals": [], "mutations": [], "count": 0, "amount": 0}
	for child: Dictionary in deliveries:
		if int(child.get("source_instance_id", -1)) != source_id:
			continue
		if not _valid_child_identity(child):
			failures.append("invalid_delivery_identity key=%s" % _child_key(child))
			continue
		var rid := str(child.get("admission_release_id", ""))
		if not parents.has(rid) or not _same(child, _parent(parents[rid]), ID_FIELDS):
			failures.append("orphan_delivery key=%s" % _child_key(child))
			continue
		var key := _child_key(child)
		if expected.has(key) or str(child.get("child_effect_id", "")).is_empty() or int(child.get("victim_instance_id", 0)) <= 0 or int(child.get("victim_life", -1)) < 0:
			failures.append("invalid_delivery key=%s" % key)
			continue
		expected[key] = child
		per_release[rid].children.append(key)
	for event: Dictionary in events + terminals:
		var source: Dictionary = event.get("source", {})
		if int(source.get("source_instance_id", -1)) != source_id:
			continue
		if not _valid_child_identity(source):
			failures.append("invalid_result_identity key=%s" % _child_key(source))
			continue
		var rid := str(source.get("admission_release_id", source.get("release_id", "")))
		if not parents.has(rid) or not _same(source, _parent(parents[rid]), ID_FIELDS):
			failures.append("unowned_result key=%s" % _child_key(source))
			continue
		var key := _child_key(source)
		var is_write := event.has("mutation_id")
		if is_write or str(source.get("child_effect_id", "")) != "admission":
			if not expected.has(key) or not _same(source, expected[key], ID_FIELDS + CHILD_FIELDS):
				failures.append("undeclared_or_mismatched_child key=%s" % key)
				continue
		else:
			var start: Dictionary = parents[rid]
			if source.get("release_id") != rid or source.get("admission_release_id") != rid or source.get("victim_instance_id") != start.get("target_id") or source.get("victim_life") != start.get("target_life") or source.get("victim_generation") != start.get("target_generation") or not per_release[rid].children.is_empty():
				failures.append("invalid_admission_terminal key=%s" % key)
				continue
		completed[key] = int(completed.get(key, 0)) + 1
		if int(completed[key]) > 1:
			failures.append("duplicate_apply key=%s count=%d" % [key, int(completed[key])])
		var mp_before := int(event.get("mp_before", -1))
		var mp_after := int(event.get("mp_after", -1))
		if mp_before >= 0 or mp_after >= 0:
			if mp_before < 0 or mp_after < 0 or mp_after > mp_before or int(event.get("actual_mp_delta", -1)) != mp_before - mp_after:
				failures.append("invalid_mp_payment key=%s" % key)
		if is_write:
			var delta := int(event.get("actual_hp_delta", -1))
			if event.get("victim_instance_id") != source.get("victim_instance_id") or event.get("victim_life") != source.get("victim_life") or event.get("victim_generation") != source.get("victim_generation") or delta <= 0 or int(event.get("hp_before", -1)) - int(event.get("hp_after", -1)) != delta or int(event.get("hp_after", -1)) != maxi(0, int(event.get("hp_before", -1)) - int(event.get("resolved_damage", -1))):
				failures.append("invalid_hp_mutation key=%s" % key)
			per_release[rid].mutations.append(event)
			per_release[rid].count += 1
			per_release[rid].amount += delta
		else:
			if str(event.get("terminal_kind", "")) not in ["miss", "rejected", "mitigated"] or str(event.get("rejection_reason", "")).is_empty():
				failures.append("invalid_terminal key=%s" % key)
			per_release[rid].terminals.append(event)
	for rid: String in per_release:
		var entry: Dictionary = per_release[rid]
		if entry.children.is_empty() and entry.terminals.is_empty():
			failures.append("release_missing_terminal release_id=%s" % rid)
		for key: String in entry.children:
			if not completed.has(key):
				failures.append("release_missing_terminal release_id=%s child=%s" % [rid, key])
	return {"per_release": per_release, "failures": failures}
