class_name RuntimeDiagnostics
extends RefCounted

# ── P1-D: Runtime Diagnostic Gate ──
# All heavy runtime logging is opt-in via ProjectSettings.
# Default = false for all categories so debug APK performance
# is not contaminated.

const SETTING_ENABLED := &"hardcore/debug/diagnostics/enabled"
const SETTING_COMBAT := &"hardcore/debug/diagnostics/combat"
const SETTING_SKILL_GEOMETRY := &"hardcore/debug/diagnostics/skill_geometry"
const SETTING_SKILL_VISUAL := &"hardcore/debug/diagnostics/skill_visual"
const SETTING_PROJECTILE := &"hardcore/debug/diagnostics/projectile"
const SETTING_BOOTSTRAP := &"hardcore/debug/diagnostics/bootstrap"
const SETTING_INPUT_GATE := &"hardcore/debug/diagnostics/input_gate"
const SETTING_FILE_OUTPUT := &"hardcore/debug/diagnostics/file_output"


static func is_enabled(category := &"") -> bool:
	var _global: bool = ProjectSettings.get_setting(SETTING_ENABLED, false)
	if not _global:
		return false
	if category.is_empty():
		return true
	return bool(ProjectSettings.get_setting(category, false))


static func combat_enabled() -> bool:
	return is_enabled(SETTING_COMBAT)


static func skill_geometry_enabled() -> bool:
	return is_enabled(SETTING_SKILL_GEOMETRY)


static func bootstrap_enabled() -> bool:
	return is_enabled(SETTING_BOOTSTRAP)


static func input_gate_enabled() -> bool:
	return is_enabled(SETTING_INPUT_GATE)


static func file_output_enabled() -> bool:
	return is_enabled(SETTING_FILE_OUTPUT)
