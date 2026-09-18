extends Node

## WALL-P1R R10 final gate (P1-3 rewrite).
## Evidence-driven: no stage result may be hard-coded. Every stage is
## checked against the Git-committed evidence under
## docs/wall_render_rollout/<date>/ (P1-4) plus live re-verification of
## the rollout authority classification. Blocked rules:
##   - R5 review_required > 0 or rows != 67
##   - R8 manual review not closed (verdict != closed for any map)
##   - R6/R7 strict evidence missing or FAIL
##   - R9 A/B pair incomplete (missing row, id/mode/adapter/viewport
##     mismatch, non-positive draw reduction)
##   - R11 not closed (debug-build gate evidence missing)
##   - source manifest missing or candidate HEAD mismatch
## c11_ready requires blocked.is_empty() AND R8 closed AND R11 closed
## AND the integration candidate validated.
## Usage: godot --headless --path . res://tools/wall_render_r10_gate.tscn

const AUTHORITY := preload("res://tools/wall_rollout_authority.gd")
const EVIDENCE_DIR := "res://docs/wall_render_rollout/2026-09-18"


func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func _read_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)


func _ready() -> void:
	var blocked: Array = []
	# --- Source manifest (replaces the old hard-coded branch SHAs) ---
	var manifest := _load_json("%s/source_manifest.json" % EVIDENCE_DIR)
	if manifest.is_empty():
		blocked.append("source_manifest.json missing under %s" % EVIDENCE_DIR)
	var candidate_head := str(manifest.get("candidate_head", ""))
	var rollout_head := str(manifest.get("rollout_head", ""))
	var integration_base := str(manifest.get("integration_base", ""))
	if candidate_head.is_empty() or rollout_head.is_empty() or integration_base.is_empty():
		blocked.append("source_manifest.json incomplete: %s" % str(manifest.keys()))
	# --- R0/R1: live authority classification (never a stored string) ---
	var authority := AUTHORITY.classify()
	if authority["error"] != "":
		blocked.append("authority classify error: %s" % str(authority["error"]))
	else:
		var counts := {"A": 0, "B": 0, "C": 0}
		for row: Dictionary in authority["rows"]:
			counts[str(row.get("class", "?"))] = counts.get(
				str(row.get("class", "?")), 0
			) + 1
		if not (counts["A"] == 60 and counts["B"] == 7 and counts["C"] == 0):
			blocked.append("authority classification %s != 60/7/0" % str(counts))
	# --- R5 memory evidence ---
	var r5 := _load_json("%s/R5_MEMORY_SUMMARY.json" % EVIDENCE_DIR)
	var r5_rows := int(r5.get("rows", 0))
	var r5_review := int(r5.get("review_required", -1))
	if r5_rows != 67:
		blocked.append("R5 rows=%d != 67" % r5_rows)
	if r5_review != 0:
		blocked.append("R5 review_required=%d != 0" % r5_review)
	# --- R6 strict evidence ---
	var r6 := _load_json("%s/R6_STRICT_SUMMARY.json" % EVIDENCE_DIR)
	if r6.is_empty():
		blocked.append("R6_STRICT_SUMMARY.json missing")
	else:
		if str(r6.get("verdict", "")) != "PASS":
			blocked.append("R6 strict verdict=%s (%s)" % [
				str(r6.get("verdict", "?")),
				str(r6.get("failed_maps", [])),
			])
		if int(r6.get("maps", 0)) != 67:
			blocked.append("R6 strict maps=%d != 67" % int(r6.get("maps", 0)))
	# --- R7 strict evidence ---
	var r7 := _load_json("%s/R7_STRICT_SUMMARY.json" % EVIDENCE_DIR)
	if str(r7.get("verdict", "")) != "PASS":
		blocked.append("R7 strict verdict=%s" % str(r7.get("verdict", "missing")))
	if int(r7.get("hops", 0)) != 16:
		blocked.append("R7 strict hops=%d != 16" % int(r7.get("hops", 0)))
	# --- R8 visual review closure ---
	var r8 := _load_json("%s/R8_VISUAL_REVIEW.json" % EVIDENCE_DIR)
	var r8_open: Array = []
	for map_key: String in r8.keys():
		var entry: Dictionary = r8[map_key]
		if entry is Dictionary and str(entry.get("verdict", "")) != "PASS":
			r8_open.append(map_key)
	if r8.get("mengzhong_stone_coffin_room", {}) == {}:
		blocked.append("R8 review missing mengzhong_stone_coffin_room")
	if r8.get("mengzhong_dark_area", {}) == {}:
		blocked.append("R8 review missing mengzhong_dark_area")
	if not r8_open.is_empty():
		blocked.append("R8 manual review open for %s" % str(r8_open))
	if str(r8.get("review_status", "")) != "closed":
		blocked.append("R8 review_status=%s != closed" % str(
			r8.get("review_status", "missing")
		))
	# --- R9 formal A/B pair evidence ---
	var r9 := _load_json("%s/R9_PERF_SUMMARY.json" % EVIDENCE_DIR)
	var pairs: Array = r9.get("pairs", [])
	if pairs.size() != 5:
		blocked.append("R9 pairs=%d != 5" % pairs.size())
	var r9_worst := -1.0
	for pair: Dictionary in pairs:
		var key := str(pair.get("map_key", "?"))
		if int(pair.get("requested_map_id", -1)) != int(pair.get("actual_map_id_opt", -2)):
			blocked.append("R9 %s: requested id != actual (opt)" % key)
			continue
		if int(pair.get("requested_map_id", -1)) != int(pair.get("actual_map_id_legacy", -2)):
			blocked.append("R9 %s: requested id != actual (legacy)" % key)
			continue
		if str(pair.get("mode_opt", "")) != "OPTIMIZED" or str(pair.get("mode_legacy", "")) != "LEGACY":
			blocked.append("R9 %s: mode pair %s/%s" % [
				key, str(pair.get("mode_opt", "?")), str(pair.get("mode_legacy", "?")),
			])
		if str(pair.get("video_adapter", "")) == "":
			blocked.append("R9 %s: video_adapter missing" % key)
		if int(pair.get("viewport_opt", [0])[0]) != int(pair.get("viewport_legacy", [1])[0]):
			blocked.append("R9 %s: viewport mismatch" % key)
		var reduction := float(pair.get("draw_reduction_pct", -1.0))
		if reduction <= 0.0:
			blocked.append("R9 %s: draw reduction %.1f%% <= 0" % [key, reduction])
		if r9_worst < 0.0 or reduction < r9_worst:
			r9_worst = reduction
	# --- R11 closure evidence ---
	var r11 := _load_json("%s/R11_FORCE_LEGACY_SUMMARY.json" % EVIDENCE_DIR)
	if str(r11.get("verdict", "")) != "PASS":
		blocked.append("R11 verdict=%s (debug-build gate not closed)" % str(
			r11.get("verdict", "missing")
		))
	# --- Integration candidate validation ---
	var integration := _load_json("%s/INTEGRATION_CANDIDATE.json" % EVIDENCE_DIR)
	if str(integration.get("validated", "")) != "true":
		blocked.append("integration candidate not validated")
	var manifest_head := str(integration.get("candidate_head", ""))
	if not candidate_head.is_empty() and manifest_head != candidate_head:
		blocked.append("candidate_head mismatch: manifest=%s candidate=%s" % [
			manifest_head, candidate_head,
		])
	# --- Decision ---
	var r8_closed := str(r8.get("review_status", "")) == "closed" and r8_open.is_empty()
	var r11_closed := str(r11.get("verdict", "")) == "PASS"
	var integration_validated := str(integration.get("validated", "")) == "true"
	var c11_ready: bool = blocked.is_empty() and r8_closed and r11_closed and integration_validated
	var report := {
		"contract_id": "hardcore.wall_render_r10_gate_report.v2",
		"evidence_dir": EVIDENCE_DIR,
		"source_manifest": manifest,
		"stages": {
			"R0_R1_authority": {"rows": int(authority["rows"].size()), "counts": str(counts) if authority["error"] == "" else "error"},
			"R5_memory": {"rows": r5_rows, "review_required": r5_review},
			"R6_strict": {"verdict": str(r6.get("verdict", "missing")), "maps": int(r6.get("maps", 0)), "failed_maps": str(r6.get("failed_maps", []))},
			"R7_strict": {"verdict": str(r7.get("verdict", "missing")), "hops": int(r7.get("hops", 0)), "checks": int(r7.get("checks", 0))},
			"R8_visual_review": {"status": str(r8.get("review_status", "missing")), "open": str(r8_open)},
			"R9_perf_pair": {"pairs": pairs.size(), "worst_reduction_pct": r9_worst},
			"R11_force_legacy_gate": {"verdict": str(r11.get("verdict", "missing"))},
			"integration_candidate": {"validated": str(integration.get("validated", "missing"))},
		},
		"blocked": blocked,
		"c11_ready": c11_ready,
	}
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path("res://outputs/wall_perf")
	)
	var rf := FileAccess.open(
		"res://outputs/wall_perf/wall_render_r10_gate_report.json",
		FileAccess.WRITE
	)
	rf.store_string(JSON.stringify(report, "\t"))
	rf.close()
	if c11_ready:
		print("WALL_RENDER_R10_GATE_PASS blocked=0 c11_ready=true")
		get_tree().quit(0)
	else:
		print("WALL_RENDER_R10_GATE_BLOCKED blocked=%s c11_ready=false" % str(blocked))
		get_tree().quit(1)
