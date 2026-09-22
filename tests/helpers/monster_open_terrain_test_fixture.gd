class_name MonsterOpenTerrainTestFixture
extends RefCounted

const TerrainPolicy := preload(
	"res://scripts/monster_terrain_navigation_policy.gd"
)

const DESIGN_SIZE := Vector2i(128, 128)
# Keep visual-backed fixtures inside the default headless viewport while
# leaving enough terrain margin for their largest 32-direction probe.
const CENTER_GROUND_GU := Vector2(16.5, 16.5)


static func build(runtime_map_id: int) -> Dictionary:
	return TerrainPolicy.build_context(
		runtime_map_id,
		{
			"build_sha256": "a".repeat(64),
			"source": {"runtime_map_id": runtime_map_id},
			"design": {
				"design_size": [DESIGN_SIZE.x, DESIGN_SIZE.y],
			},
			"collision": {"blocked_tiles": []},
		},
		TerrainPolicy.EXPECTED_GROUND_COORDINATE_CONTRACT_ID,
	)
