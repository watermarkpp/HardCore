extends Node

const PatchBootstrap := preload("res://scripts/device_lab_patch_bootstrap.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	assert(PatchBootstrap._safe_token("skill_flash_fix_v1"), "valid patch token rejected")
	assert(PatchBootstrap._safe_token("patch-1.2"), "digits/dash/dot patch token rejected")
	assert(not PatchBootstrap._safe_token("../escape"), "traversal patch token accepted")
	assert(not PatchBootstrap._safe_token("bad name"), "space in patch token accepted")
	assert(PatchBootstrap._safe_pack_name("skill_fix_v1.pck"), "valid PCK name rejected")
	assert(not PatchBootstrap._safe_pack_name("skill_fix_v1.zip"), "non-PCK name accepted")
	assert(PatchBootstrap._is_sha256("A".repeat(64)), "valid SHA-256 rejected")
	assert(not PatchBootstrap._is_sha256("G".repeat(64)), "non-hex SHA-256 accepted")
	assert(not PatchBootstrap._is_sha256("A".repeat(63)), "short SHA-256 accepted")
	assert(ProjectSettings.get_setting("autoload/DeviceLabPatch", "") == "*res://scripts/device_lab_patch_bootstrap.gd", "early Device Lab patch autoload missing")
	var bootstrap_source := FileAccess.get_file_as_string("res://scripts/device_lab_patch_bootstrap.gd")
	assert(bootstrap_source.contains("func _init() -> void:"), "resource patch must mount in the first autoload _init")
	assert(not bootstrap_source.contains("func _enter_tree() -> void:"), "resource patch mount must not wait until _enter_tree")
	assert(not bootstrap_source.contains("func _ready() -> void:"), "resource patch mount must not wait until _ready")
	var content_layers := str(ProjectSettings.get_setting("autoload/ContentLayers", ""))
	var autoload_section := FileAccess.get_file_as_string("res://project.godot").get_slice("[autoload]", 1).get_slice("[", 0)
	assert(autoload_section.find("DeviceLabPatch=") < autoload_section.find("ContentLayers="), "patch loader must run before gameplay autoloads: %s" % content_layers)
	print("DEVICE_LAB_PATCH_BOOTSTRAP_PASS strict_manifest init_mount early_autoload")
	get_tree().quit(0)
