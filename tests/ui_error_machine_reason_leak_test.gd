extends Node

## Machine-reason leak gate (R1). Two enforcement layers:
## 1. STATIC: production scripts that feed the player-visible error channel
##    must not concatenate machine reasons into shown strings and must not
##    contain the retired reason-bearing messages.
## 2. RUNTIME: UIErrorFeedback must never return a machine reason to the UI,
##    while keeping Chinese prose and proper nouns intact.

const UIErrorFeedbackScript := preload("res://scripts/ui_error_feedback.gd")

## Production files whose consumers reach the player-visible error channel.
const SCANNED_FILES := [
	"res://scripts/ui_error_feedback.gd",
	"res://scripts/hud.gd",
	"res://scripts/inventory_panel.gd",
	"res://scripts/game_root.gd",
	"res://scripts/player_state.gd",
]

## Retired player-visible reason interpolations. None of these may return.
const FORBIDDEN_LITERALS := [
	"安全退出失败：%s",
	"目标位置解析失败：%s",
	"技能学习失败：%s",
	"操作失败：%s",
]

## Machine reason namespaces that must never appear inside a shown string.
const FORBIDDEN_REASON_TOKENS := [
	"safe_logout_",
	"home_resolution_",
	"invalid_",
	"unknown_",
	"save_failed",
	"stale_instance",
]


func _ready() -> void:
	_run.call_deferred()


func _read_script(res_path: String) -> String:
	var file := FileAccess.open(res_path, FileAccess.READ)
	assert(file != null, "cannot open %s" % res_path)
	return file.get_as_text()


func _assert_no_shown_reason_concatenation(source: String, res_path: String) -> void:
	# Any show_error_message / show_message call whose argument interpolates a
	# machine reason field is a leak. from_result/user_message wrappers are the
	# only sanctioned reason consumers.
	var lines := source.split("\n")
	for line_index in range(lines.size()):
		var line: String = lines[line_index]
		var shown := line.contains("show_error_message(") or line.contains("show_message(")
		if not shown:
			continue
		assert(
			not line.contains('.get("reason"'),
			"%s:%d interpolates a raw reason field into a shown message" % [res_path, line_index + 1]
		)
		for token: String in FORBIDDEN_REASON_TOKENS:
			assert(
				not line.contains(token),
				"%s:%d shows a raw machine reason token %s" % [res_path, line_index + 1, token]
			)


func _run() -> void:
	# --- Static layer --------------------------------------------------------
	for res_path: String in SCANNED_FILES:
		var source := _read_script(res_path)
		for literal: String in FORBIDDEN_LITERALS:
			assert(
				not source.contains(literal),
				"%s still contains retired reason interpolation %s" % [res_path, literal]
			)
		_assert_no_shown_reason_concatenation(source, res_path)

	# The dedicated error channel entry must sanitize at the boundary.
	var hud_source := _read_script("res://scripts/hud.gd")
	assert(
		hud_source.contains("UIErrorFeedbackScript.user_message(message)"),
		"hud.show_error_message must pass through the user_message guard"
	)

	# Every literal passed to show_error_message in production must already be
	# player-safe: never a bare machine reason.
	for res_path: String in SCANNED_FILES:
		var source := _read_script(res_path)
		var lines := source.split("\n")
		for line_index in range(lines.size()):
			var line: String = lines[line_index]
			if not line.contains("show_error_message("):
				continue
			var trimmed := line.strip_edges()
			var argument := trimmed.trim_prefix("show_error_message(").strip_edges()
			if argument.begins_with("\"") and argument.find("\"", 1) > 0:
				var literal := argument.substr(1, argument.find("\"", 1) - 1)
				assert(
					not UIErrorFeedbackScript.is_machine_reason(literal),
					"%s:%d passes machine reason literal into error channel: %s" % [res_path, line_index + 1, literal]
				)

	# --- Runtime layer -------------------------------------------------------
	var mapped := UIErrorFeedbackScript.from_result({"reason": "save_failed"}, "后备文本")
	assert(mapped == "操作未能保存，内容没有发生改变。", "save_failed maps to Chinese, got: %s" % mapped)
	assert(
		UIErrorFeedbackScript.from_result({"reason": "stale_instance"}, "后备文本") == "所选物品状态已经变化，请重新选择。",
		"stale_instance maps to Chinese"
	)
	assert(
		UIErrorFeedbackScript.from_result({"reason": "custom_unknown_reason"}, "后备文本") == "后备文本",
		"unmapped reason returns the fallback, never the reason"
	)
	assert(
		UIErrorFeedbackScript.from_result({"message": "所选装备已变化", "reason": "stale_instance"}, "后备文本") == "所选装备已变化",
		"authoritative Chinese message wins over reason mapping"
	)
	assert(
		UIErrorFeedbackScript.from_result({"message": "save_failed"}, "后备文本") == "后备文本",
		"a bare machine token in message is refused"
	)
	assert(UIErrorFeedbackScript.from_reason("inventory_full", "后备文本") == "背包已满，无法完成操作。", "inventory_full maps")
	assert(UIErrorFeedbackScript.from_reason("overweight", "后备文本") == "负重不足，无法完成操作。", "overweight maps")
	assert(
		UIErrorFeedbackScript.from_reason("safe_logout_home_resolution_failed", "后备文本") == "安全退出失败，无法确定安全返回位置。",
		"safe logout home resolution maps"
	)
	assert(UIErrorFeedbackScript.from_reason("safe_logout_failed", "后备文本") == "安全退出失败，请稍后重试。", "safe_logout_failed maps")
	assert(UIErrorFeedbackScript.from_reason("home_resolution_failed", "后备文本") == "无法确定安全返回位置。", "home_resolution_failed maps")
	assert(
		UIErrorFeedbackScript.from_reason("no_injured_friendly_target_in_range", "后备文本") == "附近没有可治疗的友方。",
		"heal target reason maps"
	)
	assert(UIErrorFeedbackScript.from_reason("", "后备文本") == "后备文本", "empty reason returns fallback")
	assert(UIErrorFeedbackScript.from_reason("anything_else", "装备暂无法使用。") == "装备暂无法使用。", "unmapped reason returns fallback")

	assert(UIErrorFeedbackScript.user_message("stale_instance") == UIErrorFeedbackScript.GENERIC_FALLBACK, "bare token blocked")
	assert(UIErrorFeedbackScript.user_message("some invalid_thing") == UIErrorFeedbackScript.GENERIC_FALLBACK, "invalid_ namespace blocked")
	assert(UIErrorFeedbackScript.user_message("unknown_user") == UIErrorFeedbackScript.GENERIC_FALLBACK, "unknown_ namespace blocked")
	assert(UIErrorFeedbackScript.user_message("上传 save_failed 现场") == UIErrorFeedbackScript.GENERIC_FALLBACK, "embedded token blocked")
	assert(UIErrorFeedbackScript.user_message("需要等级30") == "需要等级30", "Chinese passes")
	assert(UIErrorFeedbackScript.user_message("裁决之杖") == "裁决之杖", "equipment proper noun passes")
	assert(UIErrorFeedbackScript.user_message("麻痹戒指") == "麻痹戒指", "special equipment proper noun passes")
	assert(UIErrorFeedbackScript.user_message("无法装备该装备。") == "无法装备该装备。", "ordinary prose passes")
	assert(not UIErrorFeedbackScript.is_machine_reason("玩家"), "Chinese never classified as machine")
	assert(UIErrorFeedbackScript.is_machine_reason("stale_instance"), "snake_case token classified")
	assert(UIErrorFeedbackScript.is_machine_reason("max"), "bare lowercase identifier classified")

	print("UI_ERROR_MACHINE_REASON_LEAK_PASS: static scan clean, boundary mapping correct")
	get_tree().quit(0)
