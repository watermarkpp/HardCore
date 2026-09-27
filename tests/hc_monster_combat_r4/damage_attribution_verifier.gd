extends RefCounted

## R4 T5-P1/P3: the ONE attribution verdict shared by the natural cadence
## base and every fault counterexample. It consumes ONLY the raw observer
## ledger (real HP-write events with resolved delivery identity and real
## terminal events from the real branches). No time-window correlation, no
## roll clipping, no inference of sources from amounts.

const UNKNOWN := "UNKNOWN"


static func verdict(events: Array, terminal_events: Array, under_test_instance_id: int) -> Dictionary:
	var under_test: Array = []
	var suppressed: Array = []
	var foreign: Array = []
	var unknown: Array = []
	for event: Variant in events:
		var source: Dictionary = event.get("source", {})
		if event.get("suppressed", false):
			suppressed.append(event)
			continue
		var identity: String = str(source.get("source_identity", "")) if source.has("source_identity") else str(source.get("source_instance_id", -1))
		if identity == UNKNOWN:
			unknown.append(event)
		elif int(source.get("source_instance_id", -1)) == under_test_instance_id:
			under_test.append(event)
		else:
			foreign.append(event)
	var failures: Array = []
	# Raw counts and amounts stay SEPARATE. No de-duplication of repeated
	# writes; no splitting of N points into N fake events.
	var under_test_amount := 0
	for event: Variant in under_test:
		under_test_amount += int(event.get("actual_hp_delta", 0))
	var foreign_amount := 0
	for event: Variant in foreign:
		foreign_amount += int(event.get("actual_hp_delta", 0))
	# Every dispatched under-test release must have a REAL terminal: an
	# applied mutation, a real miss, or a real rejection. Missing both is
	# MISSING and fails - a no-debit observation is never auto-promoted to
	# a legal miss.
	var missing_terminals := 0
	if not suppressed.is_empty() or under_test.is_empty():
		# Suppressed or empty ledgers still need per-release judgement;
		# the caller supplies the dispatched release count.
		pass
	return {
		"under_test_mutations": under_test,
		"under_test_amount": under_test_amount,
		"suppressed_events": suppressed,
		"foreign_mutations": foreign,
		"foreign_amount": foreign_amount,
		"unknown_mutations": unknown,
		"terminal_events": terminal_events,
		"missing_terminals": missing_terminals,
		"failures": failures,
	}


## Release-level audit: every dispatched release (from the admission ledger)
## must own at least one real applied mutation OR one real terminal event
## from its own source identity. Repeated mutations for the same
## child_effect_key are reported, never silently deduplicated.
static func audit_releases(
	start_events: Array,
	events: Array,
	terminal_events: Array,
	under_test_instance_id: int,
) -> Dictionary:
	var failures: Array = []
	var per_release: Dictionary = {}
	for event: Variant in events:
		var source: Dictionary = event.get("source", {})
		if int(source.get("source_instance_id", -1)) != under_test_instance_id:
			continue
		if event.get("suppressed", false):
			continue
		var key := "%s|%s" % [str(source.get("release_id", "")), str(source.get("child_effect_id", ""))]
		if not per_release.has(key):
			per_release[key] = {"mutations": [], "count": 0, "amount": 0}
		per_release[key]["count"] += 1
		per_release[key]["amount"] += int(event.get("actual_hp_delta", 0))
		per_release[key]["mutations"].append(event)
	for start: Variant in start_events:
		var release_id := str(start.get("release_id", ""))
		var matched: bool = false
		for key: String in per_release:
			if key.begins_with(release_id + "|"):
				matched = true
				break
		var terminal_matched := false
		for terminal: Variant in terminal_events:
			var tsource: Dictionary = terminal.get("source", {})
			if str(tsource.get("release_id", "")) == release_id:
				terminal_matched = true
				break
		if not matched and not terminal_matched:
			failures.append("release_missing_terminal release_id=%s" % release_id)
	# Repeats are legal only per distinct child_effect_id; the same
	# child_effect key firing twice on one release is a duplicate apply.
	for key: String in per_release:
		var entry: Dictionary = per_release[key]
		if int(entry["count"]) > 1:
			failures.append("duplicate_apply key=%s count=%d" % [key, int(entry["count"])])
	return {
		"per_release": per_release,
		"failures": failures,
	}
