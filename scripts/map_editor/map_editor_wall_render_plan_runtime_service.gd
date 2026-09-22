class_name MapEditorWallRenderPlanRuntimeService
extends RefCounted
## WALL-P1R Consumer R1 C1: load -> validate -> return candidate.
##
## Pure logic; creates no nodes and performs no synchronous texture loads.
## Runtime validation is structural + ResourceLoader-based only (advisor
## Consumer R1 interface contract): derived/source PNG bytes are NEVER
## re-read to recompute SHAs at runtime - exported builds may not carry
## raw PNG files. Content provenance stays with the publisher/packaging
## gate (source_image_sha256 remains build-side provenance).
##
## Any validation failure yields candidate.ok == false with a precise
## reason; the caller must then render the whole map through the legacy
## path. Partial optimization is forbidden.

const COMPILER := preload(
	"res://scripts/map_editor/map_editor_wall_render_compiler.gd"
)
const GEOMETRY_SERVICE := preload(
	"res://scripts/map_editor/map_editor_runtime_visual_geometry_service.gd"
)
const COORDINATE := preload("res://scripts/map_editor/map_editor_coordinate.gd")

const STORE_DIR_PREFIX := "assets/data/runtime/map_editor/wall_render_store/"
const SUPPORTED_COMPILER_VERSION := 2


## Returns:
##   {
##     "ok": bool,
##     "reason": String (empty when ok),
##     "plan": Dictionary (the validated plan, empty when not ok),
##   }
static func load_candidate(
	plan_path: String,
	runtime_json_path: String,
	map_key: String,
	design_size: Vector2i,
	commands: Array
) -> Dictionary:
	if not FileAccess.file_exists(plan_path):
		return _reject("plan file missing: %s" % plan_path)
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(plan_path)
	)
	if parsed is not Dictionary:
		return _reject("plan unparsable")
	var plan: Dictionary = parsed
	if str(plan.get("contract_id", "")) != COMPILER.PLAN_CONTRACT_ID:
		return _reject("contract id mismatch")
	if int(plan.get("compiler_version", -1)) != SUPPORTED_COMPILER_VERSION:
		return _reject("compiler version mismatch")
	if str(plan.get("map_key", "")) != map_key:
		return _reject("map key mismatch")
	var plan_design: Array = plan.get("design_size", [])
	if (
		plan_design.size() != 2
		or int(plan_design[0]) != design_size.x
		or int(plan_design[1]) != design_size.y
	):
		return _reject("design size mismatch")
	if str(plan.get("visual_geometry_contract_id", "")) != (
		GEOMETRY_SERVICE.VISUAL_GEOMETRY_CONTRACT_ID
	):
		return _reject("geometry contract mismatch")
	if str(plan.get("ground_coordinate_contract_id", "")) != (
		COORDINATE.GROUND_COORDINATE_CONTRACT_ID
	):
		return _reject("coordinate contract mismatch")
	var runtime_sha := _sha256_file(runtime_json_path)
	if runtime_sha.is_empty() or runtime_sha != str(
		plan.get("source_runtime_json_sha256", "")
	):
		return _reject("runtime json sha mismatch")
	if str(plan.get("source_commands_sha256", "")) != (
		COMPILER.commands_digest(commands)
	):
		return _reject("commands digest mismatch")
	var accounting: Dictionary = plan.get("accounting", {})
	var total := int(accounting.get("total_commands", -1))
	if total != commands.size():
		return _reject("total command count mismatch")
	# Index sets: in-range, pairwise disjoint, exact full union.
	var seen := {}
	for bucket: String in [
		"atlas_command_indices", "shadow_chunk_command_indices",
		"legacy_command_indices",
	]:
		if not plan.has(bucket):
			return _reject("missing index set %s" % bucket)
		for value: Variant in plan[bucket]:
			var index := int(value)
			if index < 0 or index >= total:
				return _reject("index out of range %d" % index)
			if seen.has(index):
				return _reject("duplicate classification %d" % index)
			seen[index] = true
	if seen.size() != total:
		return _reject("closure mismatch %d != %d" % [seen.size(), total])
	# Atlas pages and entries (structure + bounds only; texture sizes are
	# verified by the caller after threaded prefetch completes).
	var page_heights: Array = plan.get("atlas_page_heights", [])
	var pages: Array = plan.get("atlas_pages", [])
	if pages.is_empty() or pages.size() != page_heights.size():
		return _reject("page count mismatch")
	# page_index hardening (advisor R1.1): unique and an exact 0..N-1
	# cover - no duplicate, no gap, no negative index ever reaches
	# page_heights[...] below.
	var seen_page_indices := {}
	for record: Dictionary in pages:
		var page_index := int(record.get("page_index", -1))
		if page_index < 0 or page_index >= pages.size():
			return _reject("page index out of range %d" % page_index)
		if seen_page_indices.has(page_index):
			return _reject("duplicate page index %d" % page_index)
		seen_page_indices[page_index] = true
	if seen_page_indices.size() != pages.size():
		return _reject("page index coverage mismatch")
	for record: Dictionary in pages:
		var store_error := _validate_store_record(record)
		if store_error != "":
			return _reject(store_error)
		var page_index := int(record.get("page_index", -1))
		if int(record.get("width", -1)) != COMPILER.PAGE_WIDTH:
			return _reject("page width mismatch")
		if int(record.get("height", -1)) <= 0 or int(
			record.get("height", -1)
		) > COMPILER.PAGE_MAX_HEIGHT:
			return _reject("page height out of contract %d" % int(
				record.get("height", -1)
			))
		if int(record.get("height", -1)) != int(page_heights[page_index]):
			return _reject("page height mismatch")
		if not ResourceLoader.exists(_resource_path(str(record["path"]))):
			return _reject("page resource missing: %s" % str(record["path"]))
	var seen_keys := {}
	for entry: Dictionary in plan.get("atlas_entries", []):
		var key := str(entry.get("key", ""))
		if key.is_empty() or seen_keys.has(key):
			return _reject("entry key empty or duplicated")
		seen_keys[key] = true
		var page_index := int(entry.get("page", -1))
		var region: Array = entry.get("region", [])
		if (
			entry.get("layers", []).is_empty()
			or entry.get("group_keys", []).is_empty()
			or entry.get("group_mappings", []).is_empty()
			or entry.get("command_indices", []).is_empty()
			or page_index < 0 or page_index >= pages.size()
			or region.size() != 4
		):
			return _reject("incomplete entry %s" % key)
		if (
			int(region[0]) < 0 or int(region[1]) < 0
			or int(region[0]) + int(region[2]) > COMPILER.PAGE_WIDTH
			or int(region[1]) + int(region[3]) > int(
				page_heights[page_index]
			)
		):
			return _reject("entry region out of bounds %s" % key)
	# Group mappings: global uniqueness, representative membership,
	# per-command group agreement, exact union == atlas command set.
	var mapping_groups := {}
	var mapped_commands := {}
	for entry: Dictionary in plan.get("atlas_entries", []):
		for mapping: Dictionary in entry.get("group_mappings", []):
			var group_key := str(mapping.get("group_key", ""))
			if group_key.is_empty() or mapping_groups.has(group_key):
				return _reject("group mapping empty or duplicated %s" % (
					group_key
				))
			mapping_groups[group_key] = true
			var representative := int(
				mapping.get("representative_command_index", -1)
			)
			var mapping_ints := {}
			for value: Variant in mapping.get("command_indices", []):
				var index := int(value)
				if index < 0 or index >= total:
					return _reject("mapping index out of range %d" % index)
				if mapped_commands.has(index):
					return _reject("command in two mappings %d" % index)
				mapping_ints[index] = true
				mapped_commands[index] = true
				if str(commands[index].get("actor_sort_group", "")) != (
					group_key
				):
					return _reject("mapping group key mismatch %d" % index)
			if representative < 0 or not mapping_ints.has(representative):
				return _reject("representative not in mapping %s" % group_key)
	var atlas_command_set := {}
	for value: Variant in plan.get("atlas_command_indices", []):
		atlas_command_set[int(value)] = true
	if mapped_commands.size() != atlas_command_set.size():
		return _reject("mapping union size != atlas set")
	for index: int in atlas_command_set:
		if not mapped_commands.has(index):
			return _reject("mapping missing command %d" % index)
	# Shadow chunks: structure, sha-named store discipline, ResourceLoader
	# existence, and segment references.
	var segment_count: int = plan.get("shadow_segments", []).size()
	for record: Dictionary in plan.get("shadow_chunks", []):
		var chunk_error := _validate_store_record(record)
		if chunk_error != "":
			return _reject(chunk_error)
		if int(record.get("segment_index", -1)) < 0 or int(
			record["segment_index"]
		) >= segment_count:
			return _reject("chunk segment index invalid")
		if int(record.get("insert_command_index", -1)) < 0 or int(
			record["insert_command_index"]
		) >= total:
			return _reject("chunk insert index out of range")
		if int(record.get("size_px", [0, 0])[0]) <= 0 or int(
			record["size_px"][1]
		) <= 0:
			return _reject("chunk size invalid")
		if not ResourceLoader.exists(_resource_path(str(record["path"]))):
			return _reject("chunk resource missing: %s" % str(record["path"]))
	return {"ok": true, "reason": "", "plan": plan}


static func _reject(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "plan": {}}


## Store discipline: fixed directory, sha-named file, 64 lowercase hex.
static func _validate_store_record(record: Dictionary) -> String:
	var path := str(record.get("path", ""))
	if not path.begins_with(STORE_DIR_PREFIX):
		return "store path outside contract dir: %s" % path
	var sha := str(record.get("sha256", ""))
	if sha.length() != 64 or sha != sha.to_lower():
		return "store sha not 64 lowercase hex: %s" % sha
	for character: String in sha:
		if not (
			(character >= "0" and character <= "9")
			or (character >= "a" and character <= "f")
		):
			return "store sha not hex: %s" % sha
	if path.get_file() != "%s.png" % sha:
		return "store filename does not match sha: %s" % path
	return ""


static func _resource_path(store_path: String) -> String:
	return "res://" + store_path.lstrip("/")


static func _sha256_file(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return ""
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()
