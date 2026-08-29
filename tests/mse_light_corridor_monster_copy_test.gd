extends Node


const SOURCE_MAP_ID := "gmhl_1"
const SOURCE_IDENTITY := "fengmo_light_corridor"
const SOURCE_DOCUMENT_SHA256 := "eec90dec56ba75a0af8ed2bcb4aae18748a27bc89bff2490c6798b5efa2d1a62"
const SOURCE_SPECIES := [112, 126, 129, 132]
const SPECS := [
	{"map_id": "gmhl_thunder_road", "identity": "fengmo_thunder_road", "source_line": 198, "extra_ids": [], "expected_count": 35, "boss_ids": [135]},
	{"map_id": "gmhl_bazhe_hall", "identity": "fengmo_bazhe_hall", "source_line": 202, "extra_ids": [128, 138], "expected_count": 37, "boss_ids": [135, 188]},
	{"map_id": "gmhl_zonghengdao", "identity": "fengmo_zonghengdao", "source_line": 206, "extra_ids": [128, 138], "expected_count": 37, "boss_ids": [135, 141]},
	{"map_id": "gmhl_mohun_dian", "identity": "fengmo_mohun_hall", "source_line": 210, "extra_ids": [128, 138], "expected_count": 37, "boss_ids": [135, 141, 191]},
	{"map_id": "gmhl_purgatory_corridor", "identity": "fengmo_purgatory_corridor", "source_line": 214, "extra_ids": [128, 138, 148, 150, 153, 156], "expected_count": 41, "boss_ids": [152, 155, 135, 141, 158]},
]

const EXPECTED_BOSSES := {
	"gmhl_thunder_road": [
  {
    "authority_ref": {
      "map_id": "fengmo_thunder_road",
      "source_category_role": "elite",
      "source_line": 199,
      "source_token_index": 1
    },
    "auto_placement_status": "AUTO_POSITIONED_BOSS",
    "classification": "elite",
    "content_layer": "personal_expansion",
    "count": 1,
    "display_name": "白野猪",
    "kind": "boss_spawn",
    "max_alive": 1,
    "monster_id": 135,
    "occupancy_footprint_tiles": [
      1,
      1
    ],
    "placement_evidence": {
      "component_id": 0,
      "current_monster_library_only": true,
      "planner_contract_id": "hardcore.map_monster_auto_placement_plan.v2",
      "selection_score": [
        1,
        45,
        1,
        1,
        2536,
        -46,
        -37
      ]
    },
    "radius_gu": 0.0,
    "runtime_export": true,
    "semantic_id": "boss_spawn.auto.v2.fengmo_thunder_road.000135",
    "spawn_group_id": "auto:v2:fengmo_thunder_road:elite:000135",
    "spawn_rule": "single_anchor_user_copy_template",
    "tile": [
      37,
      46
    ]
  }
],
	"gmhl_bazhe_hall": [
  {
    "authority_ref": {
      "map_id": "fengmo_bazhe_hall",
      "source_category_role": "elite",
      "source_line": 203,
      "source_token_index": 1
    },
    "auto_placement_status": "AUTO_POSITIONED_BOSS",
    "classification": "elite",
    "content_layer": "personal_expansion",
    "count": 1,
    "display_name": "白野猪",
    "kind": "boss_spawn",
    "max_alive": 1,
    "monster_id": 135,
    "occupancy_footprint_tiles": [
      1,
      1
    ],
    "placement_evidence": {
      "component_id": 0,
      "current_monster_library_only": true,
      "planner_contract_id": "hardcore.map_monster_auto_placement_plan.v2",
      "selection_score": [
        1,
        45,
        1,
        1,
        2536,
        -46,
        -37
      ]
    },
    "radius_gu": 0.0,
    "runtime_export": true,
    "semantic_id": "boss_spawn.auto.v2.fengmo_bazhe_hall.000135",
    "spawn_group_id": "auto:v2:fengmo_bazhe_hall:elite:000135",
    "spawn_rule": "single_anchor_user_copy_template",
    "tile": [
      37,
      46
    ]
  },
  {
    "authority_ref": {
      "map_id": "fengmo_bazhe_hall",
      "source_category_role": "elite",
      "source_line": 203,
      "source_token_index": 2
    },
    "auto_placement_status": "AUTO_POSITIONED_BOSS",
    "classification": "elite",
    "content_layer": "personal_expansion",
    "count": 1,
    "display_name": "虹魔猪卫",
    "kind": "boss_spawn",
    "max_alive": 1,
    "monster_id": 188,
    "occupancy_footprint_tiles": [
      1,
      1
    ],
    "placement_evidence": {
      "component_id": 0,
      "current_monster_library_only": true,
      "planner_contract_id": "hardcore.map_monster_auto_placement_plan.v2",
      "selection_score": [
        0,
        78,
        33,
        1,
        2536,
        -1,
        -4
      ]
    },
    "radius_gu": 0.0,
    "runtime_export": true,
    "semantic_id": "boss_spawn.auto.v2.fengmo_bazhe_hall.000188",
    "spawn_group_id": "auto:v2:fengmo_bazhe_hall:elite:000188",
    "spawn_rule": "single_anchor_user_copy_template",
    "tile": [
      4,
      1
    ]
  }
],
	"gmhl_zonghengdao": [
  {
    "authority_ref": {
      "map_id": "fengmo_zonghengdao",
      "source_category_role": "elite",
      "source_line": 207,
      "source_token_index": 1
    },
    "auto_placement_status": "AUTO_POSITIONED_BOSS",
    "classification": "elite",
    "content_layer": "personal_expansion",
    "count": 1,
    "display_name": "白野猪",
    "kind": "boss_spawn",
    "max_alive": 1,
    "monster_id": 135,
    "occupancy_footprint_tiles": [
      1,
      1
    ],
    "placement_evidence": {
      "component_id": 0,
      "current_monster_library_only": true,
      "planner_contract_id": "hardcore.map_monster_auto_placement_plan.v2",
      "selection_score": [
        1,
        45,
        1,
        1,
        2506,
        -46,
        -37
      ]
    },
    "radius_gu": 0.0,
    "runtime_export": true,
    "semantic_id": "boss_spawn.auto.v2.fengmo_zonghengdao.000135",
    "spawn_group_id": "auto:v2:fengmo_zonghengdao:elite:000135",
    "spawn_rule": "single_anchor_user_copy_template",
    "tile": [
      37,
      46
    ]
  },
  {
    "authority_ref": {
      "map_id": "fengmo_zonghengdao",
      "source_category_role": "elite",
      "source_line": 207,
      "source_token_index": 2
    },
    "auto_placement_status": "AUTO_POSITIONED_BOSS",
    "classification": "elite",
    "content_layer": "personal_expansion",
    "count": 1,
    "display_name": "邪恶毒蛇",
    "kind": "boss_spawn",
    "max_alive": 1,
    "monster_id": 141,
    "occupancy_footprint_tiles": [
      1,
      1
    ],
    "placement_evidence": {
      "component_id": 0,
      "current_monster_library_only": true,
      "planner_contract_id": "hardcore.map_monster_auto_placement_plan.v2",
      "selection_score": [
        0,
        78,
        8,
        1,
        2506,
        -1,
        -4
      ]
    },
    "radius_gu": 0.0,
    "runtime_export": true,
    "semantic_id": "boss_spawn.auto.v2.fengmo_zonghengdao.000141",
    "spawn_group_id": "auto:v2:fengmo_zonghengdao:elite:000141",
    "spawn_rule": "single_anchor_user_copy_template",
    "tile": [
      4,
      1
    ]
  }
],
	"gmhl_mohun_dian": [
  {
    "authority_ref": {
      "map_id": "fengmo_mohun_hall",
      "source_category_role": "elite",
      "source_line": 211,
      "source_token_index": 1
    },
    "auto_placement_status": "AUTO_POSITIONED_BOSS",
    "classification": "elite",
    "content_layer": "personal_expansion",
    "count": 1,
    "display_name": "白野猪",
    "kind": "boss_spawn",
    "max_alive": 1,
    "monster_id": 135,
    "occupancy_footprint_tiles": [
      1,
      1
    ],
    "placement_evidence": {
      "component_id": 0,
      "current_monster_library_only": true,
      "planner_contract_id": "hardcore.map_monster_auto_placement_plan.v2",
      "selection_score": [
        1,
        45,
        1,
        1,
        2536,
        -46,
        -37
      ]
    },
    "radius_gu": 0.0,
    "runtime_export": true,
    "semantic_id": "boss_spawn.auto.v2.fengmo_mohun_hall.000135",
    "spawn_group_id": "auto:v2:fengmo_mohun_hall:elite:000135",
    "spawn_rule": "single_anchor_user_copy_template",
    "tile": [
      37,
      46
    ]
  },
  {
    "authority_ref": {
      "map_id": "fengmo_mohun_hall",
      "source_category_role": "elite",
      "source_line": 211,
      "source_token_index": 2
    },
    "auto_placement_status": "AUTO_POSITIONED_BOSS",
    "classification": "elite",
    "content_layer": "personal_expansion",
    "count": 1,
    "display_name": "邪恶毒蛇",
    "kind": "boss_spawn",
    "max_alive": 1,
    "monster_id": 141,
    "occupancy_footprint_tiles": [
      1,
      1
    ],
    "placement_evidence": {
      "component_id": 0,
      "current_monster_library_only": true,
      "planner_contract_id": "hardcore.map_monster_auto_placement_plan.v2",
      "selection_score": [
        0,
        78,
        33,
        1,
        2536,
        -1,
        -4
      ]
    },
    "radius_gu": 0.0,
    "runtime_export": true,
    "semantic_id": "boss_spawn.auto.v2.fengmo_mohun_hall.000141",
    "spawn_group_id": "auto:v2:fengmo_mohun_hall:elite:000141",
    "spawn_rule": "single_anchor_user_copy_template",
    "tile": [
      4,
      1
    ]
  },
  {
    "authority_ref": {
      "map_id": "fengmo_mohun_hall",
      "source_category_role": "elite",
      "source_line": 211,
      "source_token_index": 3
    },
    "auto_placement_status": "AUTO_POSITIONED_BOSS",
    "classification": "elite",
    "content_layer": "personal_expansion",
    "count": 1,
    "display_name": "虹魔蝎卫",
    "kind": "boss_spawn",
    "max_alive": 1,
    "monster_id": 191,
    "occupancy_footprint_tiles": [
      1,
      1
    ],
    "placement_evidence": {
      "component_id": 0,
      "current_monster_library_only": true,
      "planner_contract_id": "hardcore.map_monster_auto_placement_plan.v2",
      "selection_score": [
        0,
        64,
        19,
        1,
        2536,
        -7,
        -62
      ]
    },
    "radius_gu": 0.0,
    "runtime_export": true,
    "semantic_id": "boss_spawn.auto.v2.fengmo_mohun_hall.000191",
    "spawn_group_id": "auto:v2:fengmo_mohun_hall:elite:000191",
    "spawn_rule": "single_anchor_user_copy_template",
    "tile": [
      62,
      7
    ]
  }
],
	"gmhl_purgatory_corridor": [
  {
    "authority_ref": {
      "map_id": "fengmo_purgatory_corridor",
      "source_category_role": "elite",
      "source_line": 215.0,
      "source_token_index": 3.0
    },
    "auto_placement_status": "AUTO_POSITIONED_BOSS",
    "classification": "elite",
    "content_layer": "personal_expansion",
    "count": 1.0,
    "display_name": "祖玛弓箭手3",
    "kind": "boss_spawn",
    "max_alive": 1.0,
    "monster_id": 152.0,
    "occupancy_footprint_tiles": [
      1.0,
      1.0
    ],
    "placement_evidence": {
      "component_id": 0.0,
      "planner_contract_id": "hardcore.map_monster_auto_placement_plan.v1",
      "selection_score": [
        1.0,
        45.0,
        1.0,
        1.0,
        2536.0,
        -46.0,
        -37.0
      ]
    },
    "radius_gu": 0.0,
    "runtime_export": true,
    "semantic_id": "boss_spawn.auto.v1.fengmo_purgatory_corridor.000152",
    "spawn_group_id": "auto:v1:fengmo_purgatory_corridor:elite:000152",
    "spawn_rule": "single_anchor_user_copy_template",
    "tile": [
      37.0,
      46.0
    ]
  },
  {
    "authority_ref": {
      "map_id": "fengmo_purgatory_corridor",
      "source_category_role": "elite",
      "source_line": 215.0,
      "source_token_index": 4.0
    },
    "auto_placement_status": "AUTO_POSITIONED_BOSS",
    "classification": "elite",
    "content_layer": "personal_expansion",
    "count": 1.0,
    "display_name": "祖玛雕像3",
    "kind": "boss_spawn",
    "max_alive": 1.0,
    "monster_id": 155.0,
    "occupancy_footprint_tiles": [
      1.0,
      1.0
    ],
    "placement_evidence": {
      "component_id": 0.0,
      "planner_contract_id": "hardcore.map_monster_auto_placement_plan.v1",
      "selection_score": [
        0.0,
        78.0,
        33.0,
        1.0,
        2536.0,
        -1.0,
        -4.0
      ]
    },
    "radius_gu": 0.0,
    "runtime_export": true,
    "semantic_id": "boss_spawn.auto.v1.fengmo_purgatory_corridor.000155",
    "spawn_group_id": "auto:v1:fengmo_purgatory_corridor:elite:000155",
    "spawn_rule": "single_anchor_user_copy_template",
    "tile": [
      4.0,
      1.0
    ]
  },
  {
    "authority_ref": {
      "map_id": "fengmo_purgatory_corridor",
      "source_category_role": "elite",
      "source_line": 215.0,
      "source_token_index": 1.0
    },
    "auto_placement_status": "USER_LIST_POSITIONED_BOSS",
    "classification": "elite",
    "content_layer": "personal_expansion",
    "count": 1.0,
    "display_name": "白野猪",
    "kind": "boss_spawn",
    "max_alive": 1.0,
    "monster_id": 135.0,
    "occupancy_footprint_tiles": [
      1.0,
      1.0
    ],
    "placement_evidence": {
      "authorization": "user_list_strict_execution",
      "component_id": 0.0,
      "planner_contract_id": "hardcore.map_monster_auto_placement_plan.v1",
      "selection_score": [
        0.0,
        19.0,
        22.0,
        1.0,
        2536.0,
        -1.0,
        -23.0
      ]
    },
    "radius_gu": 0.0,
    "runtime_export": true,
    "semantic_id": "boss_spawn.auto.v1.fengmo_purgatory_corridor.000135",
    "spawn_group_id": "auto:v1:fengmo_purgatory_corridor:elite:000135",
    "spawn_rule": "single_anchor_user_copy_template",
    "tile": [
      23.0,
      1.0
    ]
  },
  {
    "authority_ref": {
      "map_id": "fengmo_purgatory_corridor",
      "source_category_role": "elite",
      "source_line": 215.0,
      "source_token_index": 2.0
    },
    "auto_placement_status": "USER_LIST_POSITIONED_BOSS",
    "classification": "elite",
    "content_layer": "personal_expansion",
    "count": 1.0,
    "display_name": "邪恶毒蛇",
    "kind": "boss_spawn",
    "max_alive": 1.0,
    "monster_id": 141.0,
    "occupancy_footprint_tiles": [
      1.0,
      1.0
    ],
    "placement_evidence": {
      "authorization": "user_list_strict_execution",
      "component_id": 0.0,
      "planner_contract_id": "hardcore.map_monster_auto_placement_plan.v1",
      "selection_score": [
        0.0,
        18.0,
        26.0,
        18.0,
        2536.0,
        -29.0,
        -35.0
      ]
    },
    "radius_gu": 0.0,
    "runtime_export": true,
    "semantic_id": "boss_spawn.auto.v1.fengmo_purgatory_corridor.000141",
    "spawn_group_id": "auto:v1:fengmo_purgatory_corridor:elite:000141",
    "spawn_rule": "single_anchor_user_copy_template",
    "tile": [
      35.0,
      29.0
    ]
  },
  {
    "authority_ref": {
      "map_id": "fengmo_purgatory_corridor",
      "source_category_role": "elite",
      "source_line": 215.0,
      "source_token_index": 5.0
    },
    "auto_placement_status": "USER_LIST_POSITIONED_BOSS",
    "classification": "elite",
    "content_layer": "personal_expansion",
    "count": 1.0,
    "display_name": "祖玛卫士3",
    "kind": "boss_spawn",
    "max_alive": 1.0,
    "monster_id": 158.0,
    "occupancy_footprint_tiles": [
      1.0,
      1.0
    ],
    "placement_evidence": {
      "authorization": "user_list_strict_execution",
      "component_id": 0.0,
      "planner_contract_id": "hardcore.map_monster_auto_placement_plan.v1",
      "selected_from_variant_group": [
        157.0,
        158.0,
        159.0
      ],
      "selection_score": [
        0.0,
        18.0,
        14.0,
        10.0,
        2536.0,
        -10.0,
        -14.0
      ]
    },
    "radius_gu": 0.0,
    "runtime_export": true,
    "semantic_id": "boss_spawn.auto.v1.fengmo_purgatory_corridor.000158",
    "spawn_group_id": "auto:v1:fengmo_purgatory_corridor:elite:000158",
    "spawn_rule": "single_anchor_user_copy_template",
    "tile": [
      14.0,
      10.0
    ]
  }
]
}

const EXPECTED_EXTRAS := {
	"gmhl_thunder_road": [],
	"gmhl_bazhe_hall": [
  {
    "authority_ref": {
      "map_id": "fengmo_bazhe_hall",
      "source_category_role": "ordinary",
      "source_line": 202,
      "source_token_index": 5
    },
    "auto_placement_status": "AUTO_POSITIONED",
    "classification": "ordinary",
    "content_layer": "personal_expansion",
    "count": 1,
    "display_name": "楔蛾",
    "kind": "monster_spawn",
    "max_alive": 1,
    "monster_id": 128,
    "occupancy_footprint_tiles": [
      1,
      1
    ],
    "placement_evidence": {
      "component_id": 0,
      "current_monster_library_only": true,
      "planner_contract_id": "hardcore.map_monster_auto_placement_plan.v2",
      "selection_score": [
        0,
        39,
        16,
        14,
        2536,
        -14,
        -30
      ]
    },
    "radius_gu": 0.0,
    "respawn_policy_id": "normal_cave",
    "runtime_export": true,
    "semantic_id": "monster_spawn.auto.v2.fengmo_bazhe_hall.000128",
    "spawn_group_id": "auto:v2:fengmo_bazhe_hall:ordinary:000128",
    "spawn_rule": "single_anchor_user_copy_template",
    "tile": [
      30,
      14
    ]
  },
  {
    "authority_ref": {
      "map_id": "fengmo_bazhe_hall",
      "source_category_role": "ordinary",
      "source_line": 202,
      "source_token_index": 4
    },
    "auto_placement_status": "AUTO_POSITIONED",
    "classification": "ordinary",
    "content_layer": "personal_expansion",
    "count": 1,
    "display_name": "蝎蛇",
    "kind": "monster_spawn",
    "max_alive": 1,
    "monster_id": 138,
    "occupancy_footprint_tiles": [
      1,
      1
    ],
    "placement_evidence": {
      "component_id": 0,
      "current_monster_library_only": true,
      "planner_contract_id": "hardcore.map_monster_auto_placement_plan.v2",
      "selection_score": [
        0,
        27,
        18,
        13,
        2536,
        -34,
        -22
      ]
    },
    "radius_gu": 0.0,
    "respawn_policy_id": "normal_cave",
    "runtime_export": true,
    "semantic_id": "monster_spawn.auto.v2.fengmo_bazhe_hall.000138",
    "spawn_group_id": "auto:v2:fengmo_bazhe_hall:ordinary:000138",
    "spawn_rule": "single_anchor_user_copy_template",
    "tile": [
      22,
      34
    ]
  }
],
	"gmhl_zonghengdao": [
  {
    "authority_ref": {
      "map_id": "fengmo_zonghengdao",
      "source_category_role": "ordinary",
      "source_line": 206,
      "source_token_index": 5
    },
    "auto_placement_status": "AUTO_POSITIONED",
    "classification": "ordinary",
    "content_layer": "personal_expansion",
    "count": 1,
    "display_name": "楔蛾",
    "kind": "monster_spawn",
    "max_alive": 1,
    "monster_id": 128,
    "occupancy_footprint_tiles": [
      1,
      1
    ],
    "placement_evidence": {
      "component_id": 0,
      "current_monster_library_only": true,
      "planner_contract_id": "hardcore.map_monster_auto_placement_plan.v2",
      "selection_score": [
        0,
        39,
        16,
        14,
        2506,
        -14,
        -30
      ]
    },
    "radius_gu": 0.0,
    "respawn_policy_id": "normal_cave",
    "runtime_export": true,
    "semantic_id": "monster_spawn.auto.v2.fengmo_zonghengdao.000128",
    "spawn_group_id": "auto:v2:fengmo_zonghengdao:ordinary:000128",
    "spawn_rule": "single_anchor_user_copy_template",
    "tile": [
      30,
      14
    ]
  },
  {
    "authority_ref": {
      "map_id": "fengmo_zonghengdao",
      "source_category_role": "ordinary",
      "source_line": 206,
      "source_token_index": 4
    },
    "auto_placement_status": "AUTO_POSITIONED",
    "classification": "ordinary",
    "content_layer": "personal_expansion",
    "count": 1,
    "display_name": "蝎蛇",
    "kind": "monster_spawn",
    "max_alive": 1,
    "monster_id": 138,
    "occupancy_footprint_tiles": [
      1,
      1
    ],
    "placement_evidence": {
      "component_id": 0,
      "current_monster_library_only": true,
      "planner_contract_id": "hardcore.map_monster_auto_placement_plan.v2",
      "selection_score": [
        0,
        27,
        18,
        13,
        2506,
        -34,
        -22
      ]
    },
    "radius_gu": 0.0,
    "respawn_policy_id": "normal_cave",
    "runtime_export": true,
    "semantic_id": "monster_spawn.auto.v2.fengmo_zonghengdao.000138",
    "spawn_group_id": "auto:v2:fengmo_zonghengdao:ordinary:000138",
    "spawn_rule": "single_anchor_user_copy_template",
    "tile": [
      22,
      34
    ]
  }
],
	"gmhl_mohun_dian": [
  {
    "authority_ref": {
      "map_id": "fengmo_mohun_hall",
      "source_category_role": "ordinary",
      "source_line": 210,
      "source_token_index": 5
    },
    "auto_placement_status": "AUTO_POSITIONED",
    "classification": "ordinary",
    "content_layer": "personal_expansion",
    "count": 1,
    "display_name": "楔蛾",
    "kind": "monster_spawn",
    "max_alive": 1,
    "monster_id": 128,
    "occupancy_footprint_tiles": [
      1,
      1
    ],
    "placement_evidence": {
      "component_id": 0,
      "current_monster_library_only": true,
      "planner_contract_id": "hardcore.map_monster_auto_placement_plan.v2",
      "selection_score": [
        0,
        32,
        19,
        1,
        2536,
        -39,
        -62
      ]
    },
    "radius_gu": 0.0,
    "respawn_policy_id": "normal_cave",
    "runtime_export": true,
    "semantic_id": "monster_spawn.auto.v2.fengmo_mohun_hall.000128",
    "spawn_group_id": "auto:v2:fengmo_mohun_hall:ordinary:000128",
    "spawn_rule": "single_anchor_user_copy_template",
    "tile": [
      62,
      39
    ]
  },
  {
    "authority_ref": {
      "map_id": "fengmo_mohun_hall",
      "source_category_role": "ordinary",
      "source_line": 210,
      "source_token_index": 4
    },
    "auto_placement_status": "AUTO_POSITIONED",
    "classification": "ordinary",
    "content_layer": "personal_expansion",
    "count": 1,
    "display_name": "蝎蛇",
    "kind": "monster_spawn",
    "max_alive": 1,
    "monster_id": 138,
    "occupancy_footprint_tiles": [
      1,
      1
    ],
    "placement_evidence": {
      "component_id": 0,
      "current_monster_library_only": true,
      "planner_contract_id": "hardcore.map_monster_auto_placement_plan.v2",
      "selection_score": [
        0,
        25,
        39,
        1,
        2536,
        -1,
        -42
      ]
    },
    "radius_gu": 0.0,
    "respawn_policy_id": "normal_cave",
    "runtime_export": true,
    "semantic_id": "monster_spawn.auto.v2.fengmo_mohun_hall.000138",
    "spawn_group_id": "auto:v2:fengmo_mohun_hall:ordinary:000138",
    "spawn_rule": "single_anchor_user_copy_template",
    "tile": [
      42,
      1
    ]
  }
],
	"gmhl_purgatory_corridor": [
  {
    "authority_ref": {
      "map_id": "fengmo_purgatory_corridor",
      "source_category_role": "ordinary",
      "source_line": 214.0,
      "source_token_index": 5.0
    },
    "auto_placement_status": "AUTO_POSITIONED",
    "classification": "ordinary",
    "content_layer": "personal_expansion",
    "count": 1.0,
    "display_name": "楔蛾",
    "kind": "monster_spawn",
    "max_alive": 1.0,
    "monster_id": 128.0,
    "occupancy_footprint_tiles": [
      1.0,
      1.0
    ],
    "placement_evidence": {
      "component_id": 0.0,
      "planner_contract_id": "hardcore.map_monster_auto_placement_plan.v1",
      "selection_score": [
        0.0,
        42.0,
        39.0,
        1.0,
        2536.0,
        -40.0,
        -1.0
      ]
    },
    "radius_gu": 0.0,
    "respawn_policy_id": "normal_cave",
    "runtime_export": true,
    "semantic_id": "monster_spawn.auto.v1.fengmo_purgatory_corridor.000128",
    "spawn_group_id": "auto:v1:fengmo_purgatory_corridor:ordinary:000128",
    "spawn_rule": "single_anchor_user_copy_template",
    "tile": [
      1.0,
      40.0
    ]
  },
  {
    "authority_ref": {
      "map_id": "fengmo_purgatory_corridor",
      "source_category_role": "ordinary",
      "source_line": 214.0,
      "source_token_index": 4.0
    },
    "auto_placement_status": "AUTO_POSITIONED",
    "classification": "ordinary",
    "content_layer": "personal_expansion",
    "count": 1.0,
    "display_name": "蝎蛇",
    "kind": "monster_spawn",
    "max_alive": 1.0,
    "monster_id": 138.0,
    "occupancy_footprint_tiles": [
      1.0,
      1.0
    ],
    "placement_evidence": {
      "component_id": 0.0,
      "planner_contract_id": "hardcore.map_monster_auto_placement_plan.v1",
      "selection_score": [
        0.0,
        28.0,
        12.0,
        15.0,
        2536.0,
        -24.0,
        -48.0
      ]
    },
    "radius_gu": 0.0,
    "respawn_policy_id": "normal_cave",
    "runtime_export": true,
    "semantic_id": "monster_spawn.auto.v1.fengmo_purgatory_corridor.000138",
    "spawn_group_id": "auto:v1:fengmo_purgatory_corridor:ordinary:000138",
    "spawn_rule": "single_anchor_user_copy_template",
    "tile": [
      48.0,
      24.0
    ]
  },
  {
    "authority_ref": {
      "map_id": "fengmo_purgatory_corridor",
      "source_category_role": "ordinary",
      "source_line": 214.0,
      "source_token_index": 7.0
    },
    "auto_placement_status": "AUTO_POSITIONED",
    "classification": "ordinary",
    "content_layer": "personal_expansion",
    "count": 1.0,
    "display_name": "大老鼠",
    "kind": "monster_spawn",
    "max_alive": 1.0,
    "monster_id": 148.0,
    "occupancy_footprint_tiles": [
      1.0,
      1.0
    ],
    "placement_evidence": {
      "component_id": 0.0,
      "planner_contract_id": "hardcore.map_monster_auto_placement_plan.v1",
      "selection_score": [
        0.0,
        27.0,
        18.0,
        13.0,
        2536.0,
        -34.0,
        -22.0
      ]
    },
    "radius_gu": 0.0,
    "respawn_policy_id": "normal_cave",
    "runtime_export": true,
    "semantic_id": "monster_spawn.auto.v1.fengmo_purgatory_corridor.000148",
    "spawn_group_id": "auto:v1:fengmo_purgatory_corridor:ordinary:000148",
    "spawn_rule": "single_anchor_user_copy_template",
    "tile": [
      22.0,
      34.0
    ]
  },
  {
    "authority_ref": {
      "map_id": "fengmo_purgatory_corridor",
      "source_category_role": "ordinary",
      "source_line": 214.0,
      "source_token_index": 8.0
    },
    "auto_placement_status": "AUTO_POSITIONED",
    "classification": "ordinary",
    "content_layer": "personal_expansion",
    "count": 1.0,
    "display_name": "祖玛弓箭手",
    "kind": "monster_spawn",
    "max_alive": 1.0,
    "monster_id": 150.0,
    "occupancy_footprint_tiles": [
      1.0,
      1.0
    ],
    "placement_evidence": {
      "component_id": 0.0,
      "planner_contract_id": "hardcore.map_monster_auto_placement_plan.v1",
      "selection_score": [
        0.0,
        25.0,
        39.0,
        1.0,
        2536.0,
        -1.0,
        -42.0
      ]
    },
    "radius_gu": 0.0,
    "respawn_policy_id": "normal_cave",
    "runtime_export": true,
    "semantic_id": "monster_spawn.auto.v1.fengmo_purgatory_corridor.000150",
    "spawn_group_id": "auto:v1:fengmo_purgatory_corridor:ordinary:000150",
    "spawn_rule": "single_anchor_user_copy_template",
    "tile": [
      42.0,
      1.0
    ]
  },
  {
    "authority_ref": {
      "map_id": "fengmo_purgatory_corridor",
      "source_category_role": "ordinary",
      "source_line": 214.0,
      "source_token_index": 9.0
    },
    "auto_placement_status": "AUTO_POSITIONED",
    "classification": "ordinary",
    "content_layer": "personal_expansion",
    "count": 1.0,
    "display_name": "祖玛雕像",
    "kind": "monster_spawn",
    "max_alive": 1.0,
    "monster_id": 153.0,
    "occupancy_footprint_tiles": [
      1.0,
      1.0
    ],
    "placement_evidence": {
      "component_id": 0.0,
      "planner_contract_id": "hardcore.map_monster_auto_placement_plan.v1",
      "selection_score": [
        0.0,
        25.0,
        14.0,
        8.0,
        2536.0,
        -22.0,
        -8.0
      ]
    },
    "radius_gu": 0.0,
    "respawn_policy_id": "normal_cave",
    "runtime_export": true,
    "semantic_id": "monster_spawn.auto.v1.fengmo_purgatory_corridor.000153",
    "spawn_group_id": "auto:v1:fengmo_purgatory_corridor:ordinary:000153",
    "spawn_rule": "single_anchor_user_copy_template",
    "tile": [
      8.0,
      22.0
    ]
  },
  {
    "authority_ref": {
      "map_id": "fengmo_purgatory_corridor",
      "source_category_role": "ordinary",
      "source_line": 214.0,
      "source_token_index": 10.0
    },
    "auto_placement_status": "AUTO_POSITIONED",
    "classification": "ordinary",
    "content_layer": "personal_expansion",
    "count": 1.0,
    "display_name": "祖玛卫士",
    "kind": "monster_spawn",
    "max_alive": 1.0,
    "monster_id": 156.0,
    "occupancy_footprint_tiles": [
      1.0,
      1.0
    ],
    "placement_evidence": {
      "component_id": 0.0,
      "planner_contract_id": "hardcore.map_monster_auto_placement_plan.v1",
      "selection_score": [
        0.0,
        19.0,
        32.0,
        1.0,
        2536.0,
        -46.0,
        -14.0
      ]
    },
    "radius_gu": 0.0,
    "respawn_policy_id": "normal_cave",
    "runtime_export": true,
    "semantic_id": "monster_spawn.auto.v1.fengmo_purgatory_corridor.000156",
    "spawn_group_id": "auto:v1:fengmo_purgatory_corridor:ordinary:000156",
    "spawn_rule": "single_anchor_user_copy_template",
    "tile": [
      14.0,
      46.0
    ]
  }
]
}



func _ready() -> void:
	var source_path := "res://map_editor_workspace/%s/%s.editor.json" % [SOURCE_MAP_ID, SOURCE_MAP_ID]
	assert(FileAccess.file_exists(source_path), source_path)
	assert(FileAccess.get_sha256(source_path) == SOURCE_DOCUMENT_SHA256, "gmhl_1 source changed")

	var source := _load_document(SOURCE_MAP_ID)
	var source_layers: Dictionary = source.get("layers", {})
	var source_monsters := _layer_array(source_layers, "monster_spawn")
	var source_bosses := _layer_array(source_layers, "boss_spawn")
	var source_special := _layer_array(source_layers, "special_monster")
	assert(source_monsters.size() == 35, "source monster count")
	assert(_species(source_monsters) == SOURCE_SPECIES, "source species set")
	assert(source_bosses.is_empty(), "source boss count")
	assert(source_special.is_empty(), "source special count")

	for spec: Dictionary in SPECS:
		var map_id := str(spec["map_id"])
		var identity := str(spec["identity"])
		var source_line := int(spec["source_line"])
		var document := _load_document(map_id)
		var layers: Dictionary = document.get("layers", {})
		var target_monsters := _layer_array(layers, "monster_spawn")
		var target_bosses := _layer_array(layers, "boss_spawn")
		var target_special := _layer_array(layers, "special_monster")

		assert(target_monsters.size() == int(spec["expected_count"]), "%s monster count" % map_id)
		assert(target_special == source_special, "%s special layer changed" % map_id)
		assert(_ids(target_bosses) == spec["boss_ids"], "%s boss order/species" % map_id)
		assert(_normalize_numbers(target_bosses) == _normalize_numbers(EXPECTED_BOSSES[map_id]), "%s boss array changed" % map_id)

		var copied: Array = []
		var extras: Array = []
		for spawn: Dictionary in target_monsters:
			if SOURCE_SPECIES.has(int(spawn.get("monster_id", -1))):
				copied.append(spawn)
			else:
				extras.append(spawn)
		assert(copied == _retarget_spawns(source_monsters, identity, source_line), "%s copied spawn deep equality" % map_id)
		assert(_ids(extras) == spec["extra_ids"], "%s extra order/species" % map_id)
		assert(_normalize_numbers(extras) == _normalize_numbers(EXPECTED_EXTRAS[map_id]), "%s extra objects changed" % map_id)
		assert(_species(target_monsters) == _expected_species(spec["extra_ids"]), "%s species set" % map_id)
		assert(not JSON.stringify(target_monsters).contains(SOURCE_IDENTITY), "%s source identity in monsters" % map_id)
		assert(not JSON.stringify(target_bosses).contains(SOURCE_IDENTITY), "%s source identity in bosses" % map_id)
		assert(not JSON.stringify(target_special).contains(SOURCE_IDENTITY), "%s source identity in special" % map_id)
		_assert_unique_semantic_ids(target_monsters + target_bosses + target_special, map_id)

		for spawn: Dictionary in copied:
			var authority_ref: Dictionary = spawn.get("authority_ref", {})
			assert(str(authority_ref.get("map_id", "")) == identity, "%s copied authority map" % map_id)
			assert(int(authority_ref.get("source_line", -1)) == source_line, "%s copied source line" % map_id)

	print("MSE_LIGHT_CORRIDOR_MONSTER_COPY_PASS targets=5 monsters=35,37,37,37,41 bosses=1,2,2,3,5")
	get_tree().quit(0)


func _load_document(map_id: String) -> Dictionary:
	var path := "res://map_editor_workspace/%s/%s.editor.json" % [map_id, map_id]
	var loaded := MapEditorLoadService.load_document(path, false)
	assert(loaded.ok, str(loaded.get("errors", [])))
	return loaded.document


func _layer_array(layers: Dictionary, key: String) -> Array:
	var value = layers.get(key, [])
	if value == null:
		return []
	return value as Array


func _retarget_spawns(source_spawns: Array, target_identity: String, target_source_line: int) -> Array:
	var result: Array = source_spawns.duplicate(true)
	for spawn: Dictionary in result:
		if spawn.has("authority_ref"):
			var authority_ref: Dictionary = spawn["authority_ref"]
			if authority_ref.has("map_id"):
				authority_ref["map_id"] = str(authority_ref["map_id"]).replace(SOURCE_IDENTITY, target_identity)
			if authority_ref.has("source_line") and int(authority_ref["source_line"]) == 195:
				if typeof(authority_ref["source_line"]) == TYPE_FLOAT:
					authority_ref["source_line"] = float(target_source_line)
				else:
					authority_ref["source_line"] = target_source_line
		if spawn.has("semantic_id"):
			spawn["semantic_id"] = str(spawn["semantic_id"]).replace(SOURCE_IDENTITY, target_identity)
		if spawn.has("spawn_group_id"):
			spawn["spawn_group_id"] = str(spawn["spawn_group_id"]).replace(SOURCE_IDENTITY, target_identity)
	return result


func _ids(spawns: Array) -> Array:
	var ids: Array = []
	for spawn: Dictionary in spawns:
		ids.append(int(spawn.get("monster_id", -1)))
	return ids


func _species(spawns: Array) -> Array:
	var species: Array = []
	for spawn: Dictionary in spawns:
		var monster_id := int(spawn.get("monster_id", -1))
		if not species.has(monster_id):
			species.append(monster_id)
	species.sort()
	return species


func _expected_species(extra_ids: Array) -> Array:
	var expected: Array = SOURCE_SPECIES.duplicate()
	for monster_id_variant in extra_ids:
		var monster_id := int(monster_id_variant)
		if not expected.has(monster_id):
			expected.append(monster_id)
	expected.sort()
	return expected


func _assert_unique_semantic_ids(spawns: Array, map_id: String) -> void:
	var seen: Dictionary = {}
	for spawn: Dictionary in spawns:
		var semantic_id := str(spawn.get("semantic_id", ""))
		assert(not semantic_id.is_empty(), "%s empty semantic id" % map_id)
		assert(not seen.has(semantic_id), "%s duplicate semantic id %s" % [map_id, semantic_id])
		seen[semantic_id] = true


func _normalize_numbers(value: Variant) -> Variant:
	if typeof(value) == TYPE_DICTIONARY:
		var normalized_dictionary: Dictionary = {}
		var dictionary: Dictionary = value
		for key in dictionary:
			normalized_dictionary[key] = _normalize_numbers(dictionary[key])
		return normalized_dictionary
	if typeof(value) == TYPE_ARRAY:
		var normalized_array: Array = []
		var array: Array = value
		for item in array:
			normalized_array.append(_normalize_numbers(item))
		return normalized_array
	if typeof(value) == TYPE_INT:
		return float(value)
	return value
