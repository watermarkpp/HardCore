extends Node


const MANIFEST_PATH := "res://assets/data/equipment_paper_doll_presentation_modes.json"


func _ready() -> void:
	_run.call_deferred()


func _load_json(path: String) -> Dictionary:
	assert(FileAccess.file_exists(path), "missing JSON contract: %s" % path)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert(parsed is Dictionary, "contract must parse as Dictionary: %s" % path)
	return parsed


func _assert_transparent_corners(path: String, label: String) -> Image:
	assert(ResourceLoader.exists(path), "%s resource missing: %s" % [label, path])
	var texture := load(path) as Texture2D
	assert(texture != null, "%s texture failed to load" % label)
	var image := texture.get_image()
	assert(image != null and not image.is_empty(), "%s image is empty" % label)
	var corners := [
		image.get_pixel(0, 0).a,
		image.get_pixel(image.get_width() - 1, 0).a,
		image.get_pixel(0, image.get_height() - 1).a,
		image.get_pixel(image.get_width() - 1, image.get_height() - 1).a,
	]
	for alpha: float in corners:
		assert(alpha <= 0.001, "%s has an opaque outer corner" % label)
	return image


func _assert_alpha_layer(path: String, label: String) -> void:
	assert(ResourceLoader.exists(path), "%s resource missing: %s" % [label, path])
	var texture := load(path) as Texture2D
	assert(texture != null, "%s texture failed to load" % label)
	var image := texture.get_image()
	var has_transparent := false
	var has_opaque := false
	for y: int in image.get_height():
		for x: int in image.get_width():
			var alpha := image.get_pixel(x, y).a
			has_transparent = has_transparent or alpha <= 0.001
			has_opaque = has_opaque or alpha >= 0.999
	assert(has_transparent and has_opaque, "%s must retain transparent color-key pixels" % label)


func _assert_slot_rect_empty(image: Image, rect_values: Array) -> void:
	assert(rect_values.size() == 4)
	var rect := Rect2i(
		int(rect_values[0]),
		int(rect_values[1]),
		int(rect_values[2]),
		int(rect_values[3])
	)
	for y: int in range(rect.position.y, rect.end.y):
		for x: int in range(rect.position.x, rect.end.x):
			assert(
				image.get_pixel(x, y).a <= 0.001,
				"avatar-only base retained slot/background pixel at %d,%d" % [x, y]
			)


func _run() -> void:
	var manifest := _load_json(MANIFEST_PATH)
	assert(manifest.get("contractId", "") == "equipment.paper_doll.presentation_modes.v1")
	assert(manifest.get("defaultMode", "") == "world_avatar")
	assert(manifest.get("sex", "") == "male")

	var modes: Dictionary = manifest.get("modes", {})
	var world: Dictionary = modes.get("world_avatar", {})
	var classic_mode: Dictionary = modes.get("classic_avatar", {})
	var avatar: Dictionary = classic_mode.get("avatarOnly", {})
	assert(world.get("contractId", "") == "equipment.paper_doll.world_avatar.v1")
	assert(avatar.get("contractId", "") == "equipment.paper_doll.avatar_only.v1")
	assert(bool(world.get("transparentOnly", false)))
	assert(bool(classic_mode.get("transparentOnly", false)))
	assert(world.get("drawOrder", []) == ["base", "dress", "weapon", "helmet"])
	assert(avatar.get("drawOrder", []) == ["base", "hair", "dress", "weapon", "helmet"])

	var legacy: Dictionary = manifest.get("legacyFullPanel", {})
	assert(bool(legacy.get("forbiddenForPlayerUI", false)))
	assert(bool(legacy.get("containsBackground", false)))
	assert(bool(legacy.get("containsEquipmentSlotFrames", false)))

	var base: Dictionary = avatar.get("base", {})
	var base_image := _assert_transparent_corners(str(base.get("path", "")), "classic avatar base")
	for rect_values: Variant in avatar.get("slotExclusionRects", []):
		assert(rect_values is Array)
		_assert_slot_rect_empty(base_image, rect_values)
	var hair: Dictionary = avatar.get("hair", {})
	_assert_alpha_layer(str(hair.get("path", "")), "classic avatar hair")

	var validation: Dictionary = manifest.get("validation", {})
	assert(validation.get("professionIds", []).size() == 3)
	assert(validation.get("tierIds", []).size() == 3)
	assert(validation.get("loadoutContractIds", []).size() == 9)
	assert(int(validation.get("femaleAssetsGenerated", -1)) == 0)

	print(
		"EQUIPMENT_PAPER_DOLL_PRESENTATION_MODES_GODOT_TEST_PASS "
		+ "modes=2 loadouts=9 legacy_forbidden=true"
	)
	get_tree().quit(0)
