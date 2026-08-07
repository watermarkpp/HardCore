extends Node

## Q3-C: the legacy skill-runtime production APIs are DELETED, not merely
## uncalled. This test statically scans the production scripts and fails if any
## legacy token re-enters the tree.

const BANNED_TOKENS := [
	"SkillRuntimeRouter.execute(",
	"CasterSkillRuntime.resolve(",
	"create_cast_nodes(",
	"_apply_canonical_effects(",
	"_spawn_canonical_cast_visual(",
	"visual_plan",
	"SkillCastResult",
]

const SCRIPT_PATHS := [
	"res://scripts/game_root.gd",
	"res://scripts/caster_skill_runtime.gd",
	"res://scripts/skills/skill_runtime_router.gd",
	"res://scripts/skills/skill_execution_plan.gd",
	"res://scripts/skills/skill_execution_plan_contract.gd",
]


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var violations: Array[String] = []
	for path: String in SCRIPT_PATHS:
		var file := FileAccess.open(path, FileAccess.READ)
		assert(file != null, "production script missing: %s" % path)
		var source := file.get_as_text()
		for token: String in BANNED_TOKENS:
			if source.contains(token):
				violations.append("%s contains %s" % [path, token])
	assert(
		violations.is_empty(),
		"legacy tokens found in production scripts: %s"
			% "; ".join(violations)
	)
	# The canonical entries must still exist exactly once.
	_assert_definition_count(
		"res://scripts/skills/skill_runtime_router.gd",
		"static func build_canonical_plan(",
		1
	)
	_assert_definition_count(
		"res://scripts/caster_skill_runtime.gd",
		"static func create_cast_nodes_from_canonical_plan(",
		1
	)
	print("SKILL_RUNTIME_NO_LEGACY_API_PASS")
	get_tree().quit(0)


func _assert_definition_count(
	path: String,
	needle: String,
	expected: int
) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	assert(file != null, "script missing: %s" % path)
	var source := file.get_as_text()
	var count := 0
	for line: String in source.split("\n"):
		if line.contains(needle):
			count += 1
	assert(
		count == expected,
		"%s must define %s exactly %d time(s), found %d"
			% [path, needle, expected, count]
	)
