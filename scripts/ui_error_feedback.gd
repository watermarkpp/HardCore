class_name UIErrorFeedback
extends RefCounted

## Player-facing error text boundary. Machine reasons/codes live in results,
## logs and diagnostics; the player UI only ever receives Chinese prose from
## this module. Internal reasons stay available to push_warning/push_error,
## diagnostic JSON and test assertions -- they must never be concatenated or
## interpolated into a player-visible string anywhere.

const GENERIC_FALLBACK := "操作失败，请稍后重试。"

## Bounded mapping for machine reasons that have no authoritative Chinese
## message of their own. This is intentionally small: gameplay authorities
## already return player-readable Chinese messages, which take precedence.
const REASON_MESSAGES := {
	"stale_instance": "所选物品状态已经变化，请重新选择。",
	"save_failed": "操作未能保存，内容没有发生改变。",
	"inventory_full": "背包已满，无法完成操作。",
	"overweight": "负重不足，无法完成操作。",
	"safe_logout_home_resolution_failed": "安全退出失败，无法确定安全返回位置。",
	"safe_logout_failed": "安全退出失败，请稍后重试。",
	"home_resolution_failed": "无法确定安全返回位置。",
	"no_injured_friendly_target_in_range": "附近没有可治疗的友方。",
}

## Explicit machine tokens that must never reach the player UI, even wrapped
## in prose. This is a denylist of internal reason namespaces, not a generic
## English-letter stripper: legitimate proper nouns (NPC 名、装备正式名称、
## 技术专有名词) keep working.
const MACHINE_REASON_TOKENS := [
	"safe_logout_",
	"home_resolution_",
	"invalid_",
	"unknown_",
	"save_failed",
	"stale_instance",
	"inventory_full",
	"overweight",
	"_failed",
	"failed:",
	"reason=",
]


## Resolve the player message for a failure result Dictionary.
## 1. result.user_message wins when present.
## 2. result.message is used only when it is explicit player-readable Chinese.
## 3. result.reason is looked up in REASON_MESSAGES.
## 4. Otherwise the caller-provided Chinese fallback is used.
## The raw reason is never returned.
static func from_result(result: Dictionary, fallback: String) -> String:
	var user_message := str(result.get("user_message", ""))
	if not user_message.is_empty():
		return user_message
	var message := str(result.get("message", ""))
	if is_player_message(message):
		return message
	return from_reason(str(result.get("reason", "")), fallback)


## Resolve the player message for a bare machine reason. Empty or unmapped
## reasons return the caller-provided Chinese fallback; the reason itself is
## never returned.
static func from_reason(reason: String, fallback: String) -> String:
	if reason.is_empty():
		return fallback
	var mapped_text := str(REASON_MESSAGES.get(reason, ""))
	if not mapped_text.is_empty():
		return mapped_text
	return fallback


## Last-line guard for text entering the error channel. Player-readable prose
## passes through unchanged; a bare machine reason token (or prose that
## embedded one) is replaced by the generic Chinese fallback.
static func user_message(message: String) -> String:
	if is_machine_reason(message):
		return GENERIC_FALLBACK
	return message


## A message is player-readable when it is non-empty and does not carry
## machine-reason content. Authorities own their Chinese prose; this check
## only refuses machine leakage.
static func is_player_message(message: String) -> bool:
	var trimmed := message.strip_edges()
	if trimmed.is_empty():
		return false
	return not is_machine_reason(trimmed)


## Detect machine reason content. Two bounded rules:
## 1. a whole-string machine token (snake_case identifier), or
## 2. a known internal reason namespace appearing inside the text.
## Chinese prose, item names and proper nouns never match either rule.
static func is_machine_reason(text: String) -> bool:
	var trimmed := text.strip_edges()
	if trimmed.is_empty():
		return false
	if REASON_MESSAGES.has(trimmed):
		# The reason key itself was passed instead of its mapped message.
		return true
	if _is_snake_case_identifier(trimmed):
		return true
	for token: String in MACHINE_REASON_TOKENS:
		if trimmed.contains(token):
			return true
	return false


static func _is_snake_case_identifier(text: String) -> bool:
	if text.is_empty():
		return false
	var has_lowercase := false
	for character: String in text:
		var code := character.unicode_at(0)
		var is_lowercase_ascii := code >= 97 and code <= 122
		var is_digit := code >= 48 and code <= 57
		var is_underscore := character == "_"
		if is_lowercase_ascii or is_underscore or is_digit:
			has_lowercase = has_lowercase or is_lowercase_ascii
		else:
			return false
	# Bare lowercase tokens ("max", "unknown", "save_failed") are machine
	# identifiers; no legitimate player prose is pure lowercase ASCII.
	return has_lowercase
