extends RefCounted

## R33-P1: optional description text only. Not a final-body English filter.
## No gameplay data writes, resource loads, timers, frame polling or layout rules.
## Known provenance tokens are removed; ordinary English, numbers, BBCode and
## player-facing restrictions remain. Unknown technical text is for audit.
const AUDIT_SOURCES := [
	"project.hardcore.equipment_attribute_master.v2",
	"project.hardcore.equipment_attribute_master.v1",
	"equipment.attribute.master.v2",
	"equipment.attribute.master.v1",
	"server.crystal.cjlaaa",
	"source.minipizza_mir2.server",
]
const SOURCE_LABELS := ["source:", "source：", "来源:", "来源：", "数据来源:", "数据来源："]
const INTERNAL_LABELS := [
	"internal note:", "internal note：", "debug note:", "debug note：",
	"implementation note:", "authoring note:", "debug:", "internal:",
	"todo:", "fixme:", "//", "/*", "*/",
	"内部程序备注：", "内部程序备注:", "内部注释：", "内部注释:", "调试备注：", "调试备注:",
]

static func description(value: Variant) -> String:
	if not (value is String or value is StringName):
		# Never stringify a source/review Dictionary into player-facing prose.
		return ""
	var original := str(value)
	if original.is_empty():
		return original
	var result: Array[String] = []
	var changed := false
	for source_line: String in original.replace("\r\n", "\n").replace("\r", "\n").split("\n", true):
		var line := source_line
		var check_text := _unwrap_complete_styles(line.strip_edges())
		var lower := check_text.to_lower()
		var internal := false
		for prefix: String in INTERNAL_LABELS:
			if lower.begins_with(prefix):
				internal = true
				break
		if internal or _audit_payload(check_text):
			changed = true
			continue
		line = _remove_audit_parentheses(line)
		if line != source_line:
			changed = true
			if _unwrap_complete_styles(line.strip_edges()).is_empty():
				continue
		result.append(line)
	if not changed:
		return original # No byte/whitespace changes to unaffected descriptions.
	return "\n".join(result).strip_edges()

static func _audit_payload(value: String) -> bool:
	var text := value.strip_edges()
	var lower := text.to_lower()
	for label: String in SOURCE_LABELS:
		if lower.begins_with(label):
			text = text.substr(label.length()).strip_edges()
			break
	# The audited legacy requirement string is distribution/confidence.
	for source: String in AUDIT_SOURCES:
		if text == source:
			return true
		for grade: String in ["A", "B", "C", "D", "?"]:
			if text == source + "/" + grade:
				return true
	return false

static func _remove_audit_parentheses(value: String) -> String:
	var result := value
	var starts := ["（", "("]
	var ends := ["）", ")"]
	for kind in range(2):
		var cursor := 0
		while cursor < result.length():
			var begin := result.find(starts[kind], cursor)
			if begin < 0:
				break
			var end := result.find(ends[kind], begin + 1)
			if end < 0:
				break
			var payload := result.substr(begin + 1, end - begin - 1)
			if _audit_payload(payload):
				result = result.substr(0, begin) + result.substr(end + 1)
				cursor = begin
			else:
				cursor = end + 1
	return result

static func _unwrap_complete_styles(value: String) -> String:
	# Classification only; returned player text is never rebuilt from this.
	# Only balanced, whole-line wrappers are accepted. Cross-line markup is
	# deliberately left alone rather than risking destruction of useful text.
	var result := value
	for _pass in range(8):
		if not result.begins_with("["):
			break
		var close := result.find("]")
		if close < 0:
			break
		var tag := result.substr(1, close - 1).get_slice("=", 0)
		if tag not in ["color", "font_size", "b", "i", "u"]:
			break
		var ending := "[/" + tag + "]"
		if not result.ends_with(ending):
			break
		result = result.substr(close + 1, result.length() - close - 1 - ending.length()).strip_edges()
	return result
