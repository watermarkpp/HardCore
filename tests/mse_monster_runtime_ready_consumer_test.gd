extends Node

const CatalogService := preload(
	"res://scripts/map_editor/map_editor_content_catalog_service.gd"
)


func _ready() -> void:
	_assert_runtime_ready(24, "多钩猫")
	_assert_runtime_ready(38, "半兽勇士")
	_assert_runtime_ready(45, "蝎子")

	print(
		"MSE_MONSTER_RUNTIME_READY_CONSUMER_PASS "
		+ "ids=24,38,45"
	)

	get_tree().quit()


func _assert_runtime_ready(
	monster_id: int,
	expected_name: String
) -> void:

	var entry := (
		CatalogService.find_any_monster(
			monster_id
		)
	)

	assert(
		not entry.is_empty(),
		"missing monster id %d" % monster_id
	)

	assert(
		int(entry.get("monster_id", -1))
		== monster_id
	)

	assert(
		str(entry.get("display_name", ""))
		== expected_name
	)

	assert(
		bool(entry.get("authoring_allowed", false)),
		"%s should be authoring allowed"
		% expected_name
	)

	assert(
		bool(entry.get("runtime_ready", false)),
		"%s should be runtime ready: %s"
		% [
			expected_name,
			entry.get(
				"runtime_rejection_reason",
				""
			),
		]
	)
