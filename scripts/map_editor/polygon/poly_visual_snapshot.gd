extends RefCounted
## Build-time catalog geometry snapshot. Images are referenced, not copied here.
## Every field read by the pinned v6 visual geometry service is included.
const CONTRACT := "hc.published_material_geometry.v1"
const PRECISION_CONTRACT := "hc.map_precision.r2"
const FIELDS := ["asset_id", "asset_type", "image", "image_size", "image_size_px",
	"anchor_px", "footprint_tiles", "selection_bounds_px", "occlusion",
	"occlusion_segments", "occlusion_base_image", "render_parts", "category",
	"object_class", "semantic_role", "sort_baseline_tile_offset", "sort_baseline_offset_px"]

static func capture(instances: Array) -> Dictionary:
	var assets: Dictionary = {}
	var errors: Array[String] = []
	for instance: Dictionary in instances:
		var id := str(instance.get("asset_id", ""))
		if assets.has(id):
			continue
		var asset := MapAssetCatalogService.find_asset(id)
		if id.is_empty() or asset.is_empty():
			errors.append("visual_snapshot_asset_missing:%s" % id)
			continue
		var saved: Dictionary = {}
		for field: String in FIELDS:
			if asset.has(field):
				saved[field] = asset[field]
		saved["asset_id"] = id
		assets[id] = saved.duplicate(true)
	var normalized: Variant = JSON.parse_string(MapEditorJsonCodec.encode(assets))
	if not normalized is Dictionary:
		return {"ok": false, "errors": ["visual_snapshot_normalization_failed"]}
	assets = normalized
	return {"ok": errors.is_empty(), "errors": errors, "snapshot": {
		"contract_id": CONTRACT, "assets": assets,
		"sha256": MapEditorJsonCodec.encode(assets).sha256_text()}}

static func validate(runtime: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var required := runtime.has("precision_contract_id")
	if required and str(runtime.precision_contract_id) != PRECISION_CONTRACT:
		errors.append("precision_contract_invalid")
	if not runtime.has("visual_asset_snapshot"):
		if required:
			errors.append("visual_snapshot_required")
		return errors
	var value: Variant = runtime.visual_asset_snapshot
	if not value is Dictionary or str(value.get("contract_id", "")) != CONTRACT:
		errors.append("visual_snapshot_contract_invalid")
		return errors
	var assets: Variant = value.get("assets", null)
	if not assets is Dictionary:
		errors.append("visual_snapshot_assets_invalid")
		return errors
	if str(value.get("sha256", "")) != MapEditorJsonCodec.encode(assets).sha256_text():
		errors.append("visual_snapshot_hash_mismatch")
	for raw: Variant in runtime.get("instances", []):
		if not raw is Dictionary:
			errors.append("visual_snapshot_instance_invalid")
			continue
		var id := str(raw.get("asset_id", ""))
		if not assets.get(id) is Dictionary or str(assets[id].get("asset_id", "")) != id:
			errors.append("visual_snapshot_asset_missing:%s" % id)
	return errors

static func resolve_asset(asset_id: String, snapshot: Dictionary) -> Dictionary:
	# Empty means an OLD published map. A malformed/new snapshot never falls
	# back to today's catalog and silently creates a mixed-version scene.
	if snapshot.is_empty():
		return MapAssetCatalogService.find_asset(asset_id)
	if str(snapshot.get("contract_id", "")) != CONTRACT:
		push_error("Published material snapshot contract invalid")
		return {}
	var value: Variant = snapshot.get("assets", {}).get(asset_id, null)
	if not value is Dictionary:
		push_error("Published material snapshot missing asset: %s" % asset_id)
		return {}
	return value
