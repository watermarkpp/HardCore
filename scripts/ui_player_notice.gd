class_name UIPlayerNotice
extends RefCounted

## Unified player-notice contract (UNIFIED-PLAYER-NOTICE R2).
##
## Business layers report WHAT happened (kind, code, message, item/skill
## references). This module owns the canonical notice shape, priority and
## dedupe semantics. Presentation decisions -- colors, geometry, item-name
## styling -- stay with the HUD presenter; item names always resolve through
## UIItemNameStyle so central notices cannot drift from the item system.

const KIND_ERROR := "error"
const KIND_WARNING := "warning"
const KIND_SUCCESS := "success"
const KIND_INFO := "info"

const PRIORITY_ERROR := 100
const PRIORITY_WARNING := 70
const PRIORITY_SUCCESS := 40
const PRIORITY_INFO := 20

const DEFAULT_DURATION := 2.0
const MAX_QUEUE := 4

## Item uses that own a central result notice (R2 user contract): skill
## books, blessing/repair oils and TIMED 神水 effects. Instant-restore
## potions (生命药水/魔力药水/太阳水 and friends) stay silent on purpose.
const REPORTED_USE_EFFECTS: Array[String] = [
	"blessing_oil",
	"repair_oil",
	"war_god_oil",
	"temporary_stat_buff",
	"temporary_buff",
]

const VALID_KINDS: Array[String] = [KIND_ERROR, KIND_WARNING, KIND_SUCCESS, KIND_INFO]


## Structured gate for item-use notices, decided from the catalog record
## only (kind/useEffect data — never message substring sniffing).
static func should_report_item_use(item: Dictionary) -> bool:
	if str(item.get("kind", "")) == "skill_book":
		return true
	return str(item.get("useEffect", "")) in REPORTED_USE_EFFECTS


static func is_valid_kind(kind: String) -> bool:
	return kind in VALID_KINDS


static func priority_for(kind: String) -> int:
	match kind:
		KIND_ERROR:
			return PRIORITY_ERROR
		KIND_WARNING:
			return PRIORITY_WARNING
		KIND_SUCCESS:
			return PRIORITY_SUCCESS
		_:
			return PRIORITY_INFO


## Normalize any caller dictionary into the canonical notice shape. Unknown
## or invalid fields are dropped here so the presenter can trust its input.
## A notice is either text-only (message) or segmented (segments carry the
## mixed-format content, e.g. "已装备 " + authoritative item name).
static func normalize(raw: Dictionary) -> Dictionary:
	var kind := str(raw.get("kind", KIND_INFO))
	if not is_valid_kind(kind):
		kind = KIND_INFO

	var message := str(raw.get("message", ""))
	var segments: Array = []
	var raw_segments: Variant = raw.get("segments", [])
	if raw_segments is Array:
		for raw_segment: Variant in raw_segments:
			if not raw_segment is Dictionary:
				continue
			var segment: Dictionary = raw_segment
			if str(segment.get("type", "text")) == "item":
				var item: Variant = segment.get("item", {})
				if item is Dictionary and not (item as Dictionary).is_empty():
					var instance: Variant = segment.get("instance", {})
					segments.append({
						"type": "item",
						"item": item,
						"instance": instance if instance is Dictionary else {},
					})
					continue
			var text := str(segment.get("text", ""))
			if not text.is_empty():
				segments.append({"type": "text", "text": text})

	# Segmented notices keep their message: the presenter renders it as the
	# leading plain text (e.g. ActionResult "锻造成功" + item name).

	var dedupe_key := str(raw.get("dedupe_key", ""))
	if dedupe_key.is_empty():
		dedupe_key = str(raw.get("code", ""))
	if dedupe_key.is_empty():
		dedupe_key = "msg:" + message

	var duration: float = DEFAULT_DURATION
	var raw_duration: Variant = raw.get("duration", DEFAULT_DURATION)
	if (raw_duration is float or raw_duration is int) and is_finite(float(raw_duration)):
		duration = maxf(0.1, float(raw_duration))

	return {
		"kind": kind,
		"code": str(raw.get("code", "")),
		"message": message,
		"segments": segments,
		"duration": duration,
		"dedupe_key": dedupe_key,
		"priority": priority_for(kind),
		"surface": str(raw.get("surface", "global")),
	}


## Build the canonical item segment. The item name and its color/outline are
## resolved by the presenter through UIItemNameStyle at render time; callers
## only carry the catalog record and the committed instance.
static func item_segment(item: Dictionary, instance: Dictionary = {}) -> Dictionary:
	return {
		"type": "item",
		"item": item,
		"instance": instance,
	}


static func text_segment(text: String) -> Dictionary:
	return {"type": "text", "text": text}


## ActionResult contract for future player-action services (forge, synth,
## reinforce...). A service returns {success, reason, message, notice_code,
## notice_kind, item_ref, ...}; the calling layer forwards it to
## HUD.present_action_result(), which normalizes it into a notice here.
## `reason` is diagnostics-only and never rendered.
static func from_action_result(result: Dictionary) -> Dictionary:
	var success := bool(result.get("success", false))
	var kind := str(result.get("notice_kind", ""))
	if not is_valid_kind(kind):
		kind = KIND_SUCCESS if success else KIND_ERROR
	# Machine-reason boundary (R2.1): a failed action whose message is itself
	# a machine token or namespaced reason never reaches the player overlay;
	# the error-feedback authority supplies the Chinese fallback. Success
	# prose is business-authored and passes through untouched.
	var message := str(result.get("message", ""))
	if not success:
		message = UIErrorFeedback.from_result(result, "操作失败，请稍后重试。")
	var notice := {
		"kind": kind,
		"code": str(result.get("notice_code", "")),
		"message": message,
		"duration": DEFAULT_DURATION,
	}
	var item_ref: Variant = result.get("item_ref", {})
	if item_ref is Dictionary and not (item_ref as Dictionary).is_empty():
		var resolved := resolve_item_ref(item_ref)
		# Contract spacing (R2.1): message + item name read as one line
		# ("锻造成功 屠龙"); the gap is explicit text, never container padding.
		if not notice["message"].is_empty() and not str(notice["message"]).ends_with(" "):
			notice["message"] = str(notice["message"]) + " "
		notice["segments"] = [
			item_segment(resolved["item"], resolved["instance"]),
		]
	return normalize(notice)


## item_ref may be: a catalog record, a committed instance, or the explicit
## {item:..., instance:...} pair. Resolve the best (catalog, instance) pair
## for UIItemNameStyle.describe().
static func resolve_item_ref(item_ref: Dictionary) -> Dictionary:
	if item_ref.has("item") and item_ref.has("instance"):
		var item: Variant = item_ref["item"]
		var instance: Variant = item_ref["instance"]
		if item is Dictionary and instance is Dictionary:
			return {"item": item, "instance": instance}
	var catalog := item_ref.duplicate()
	var instance := {}
	# A committed instance is identifiable by its own instance_id; its
	# catalog entry is then looked up through the canonical id.
	if str(item_ref.get("instance_id", "")).is_empty():
		return {"item": catalog, "instance": instance}
	var item_id := UIItemNameStyle.canonical_id(item_ref)
	if item_id > 0:
		var rules: Dictionary = GameData.get_item_rules_record({"item_id": item_id})
		if not rules.is_empty():
			catalog = rules
			instance = item_ref.duplicate()
	return {"item": catalog, "instance": instance}
