extends RefCounted
## Generated exact original UI->Profile call and read contract.
const ARITIES: Dictionary = {
  "_repair_plan": [
    1
  ],
  "accept_quest": [
    1
  ],
  "available_skill_ids": [
    0
  ],
  "claim_quest": [
    1
  ],
  "commit_workbench_immediate": [
    2
  ],
  "create_character": [
    3
  ],
  "current_bich_quest_id": [
    0
  ],
  "delete_character_profile": [
    1
  ],
  "destroy_inventory_indices": [
    2
  ],
  "device_lab_active_save_document": [
    0
  ],
  "device_lab_apply_save_document": [
    1
  ],
  "effective_skill_level": [
    1
  ],
  "ensure_chiyue_test_roster": [
    0
  ],
  "equip_inventory_index_result": [
    4
  ],
  "experience_to_next_level": [
    0
  ],
  "feature_publication_context": [
    0
  ],
  "finish_startup_save_upgrade": [
    0
  ],
  "has_item": [
    1
  ],
  "inventory_occupied_count": [
    0
  ],
  "inventory_weight": [
    0
  ],
  "is_skill_available": [
    1
  ],
  "is_skill_learned": [
    1
  ],
  "item_count_by_entity_id": [
    1
  ],
  "list_characters": [
    0
  ],
  "max_inventory_weight": [
    0
  ],
  "migrate_equipment_slots": [
    1
  ],
  "quest_objective_lines": [
    1
  ],
  "quest_reward_label": [
    1
  ],
  "quote_forge_tray": [
    0
  ],
  "quote_relic_synthesis": [
    3
  ],
  "repair_all_equipment": [
    1
  ],
  "repair_cost": [
    1
  ],
  "save_game": [
    0
  ],
  "save_safe_logout": [
    2
  ],
  "select_character": [
    1
  ],
  "set_later_content_enabled": [
    1
  ],
  "shared_gold_view_snapshot": [
    0
  ],
  "skill_button_assignments_snapshot": [
    0
  ],
  "skill_name_for_slot": [
    2
  ],
  "sort_inventory_deterministic": [
    0
  ],
  "transfer_shared_gold_prepared": [
    3
  ],
  "transfer_warehouse_prepared": [
    4
  ],
  "transfer_workbench_immediate": [
    3,
    4
  ],
  "unequip_to_inventory_slot": [
    4
  ],
  "use_inventory_index_result": [
    3
  ],
  "workbench_tray": [
    1
  ]
}
const READ_FIELDS: Array[String] = [
  "active_profile_id",
  "character_name",
  "computed_stats",
  "equipment",
  "experience",
  "forge_tray",
  "game_mode_id",
  "gold",
  "inventory",
  "later_content_enabled",
  "learned_skills",
  "level",
  "profession",
  "profession_id",
  "profile_directory",
  "quest_states",
  "quick_slots",
  "startup_save_upgrade_result",
  "synthesis_tray",
  "test_mode",
  "warehouse_inventory"
]
const SOURCE_METHOD_SHA256: Dictionary = {
  "_repair_plan": "4b00dec9ee2040653b42ec68d56add1b760115a9188234cf23e0bdd8ff504fa6",
  "accept_quest": "32b5e9e589ab3b3498595307135127940d1b5359ca471c155cd03f15ff95d0bb",
  "available_skill_ids": "cf819f935f5564fbebdca1f61e3f67f5d7e0f376a8ab00a9efaedea7b77e4bbe",
  "claim_quest": "ad18c4132d1ad06231c290b790cced4a7187bc2988f5b72f43a0f8b081d385fa",
  "commit_workbench_immediate": "1efec5412bef35fe9ca0799b52f6d58a31f9f2d755e5748e4ec6021d45f5c0bd",
  "create_character": "7e3098ac9fb50cba628b3c6ddfc63f6b874fd1a5e4955c92c56c8dd5facab451",
  "current_bich_quest_id": "7338610c9fa5b70ab4243ab374024fda86e99edb32eaf84709b5f5fc50fba5d6",
  "delete_character_profile": "4acbd8918833f85d380428563f4be093d4ecd5d45ce4f3e41e8480ef23ba0581",
  "destroy_inventory_indices": "2c441aee234168e7492e0aa27fae13fe21aa99facb97b18c3ffc7ffdbbbf5b54",
  "device_lab_active_save_document": "7cdc89f14116f1ae55e779f30ba8c83dca238ea6abf2a7b24858722e25eea9ea",
  "device_lab_apply_save_document": "f23d881d2b833f49c7206ccaeb7f1df0b24d29da87d6aa25a4c7d120e9d788a6",
  "effective_skill_level": "d2aebeca33b043a4b84075b3f162c566195bd58269f7dc129bd3fe52b0dc1c58",
  "ensure_chiyue_test_roster": "b0a92da160c530e6ef55df7e3140074262be13a4546fedaeb6c980667fa013a3",
  "equip_inventory_index_result": "02dc2315ec708eef9833af88f66619d879f3d4292d8897b90564bfc6ef08b2a3",
  "experience_to_next_level": "bddf5aaffeb994fdcde9bd146ee2e3f86d32ee1eae7eccf1d73105932e8808a1",
  "feature_publication_context": "ebd87350b8763e46b1af0647b2fefaa515f63726ef5c5176744b9e1e97ca1778",
  "finish_startup_save_upgrade": "c678d8de6fbed70f01974df53f0b3948d26c6d313a99fe198d808342af356485",
  "has_item": "c13efb4ec9c372c51cce9b323a46c7c7a2c71ea86fa9eb41f1a5e9ba558261bb",
  "inventory_occupied_count": "70b13e3f3a62c21bc9467a169a4441783e94a820708e418066343d33fafb8a58",
  "inventory_weight": "7dbd2a2e07c76e6459949cc0bf940cc7c654cfc5f1757ae508aab2f02b24ea2a",
  "is_skill_available": "a24f563ae7ebb4b4ad1862366801cbb259e0eb0a0d7268786e4eb4a9d0441e0a",
  "is_skill_learned": "7330e501da49bd9d3bc2796e8868206c1e390e296108bf2717fe1f2d732393f7",
  "item_count_by_entity_id": "6a8158958e5f5ef8e30e1bf676fcd6812b6ece26cca0fc1506ec1a4269204219",
  "list_characters": "0b6786ab39a8c0df69aef277bb24c314169db9a052e56ec98f47fbae7a86a440",
  "max_inventory_weight": "bda6fe39d60d3aa616e47cb713a79edd0c8011cb7a588d5259f1f719d9183891",
  "migrate_equipment_slots": "2e1ada30ce0437738c054a7fb9b4c4131e303cdb09d3db57968837d0b7b6fb00",
  "quest_objective_lines": "1d4c90880cfdf879d1c6f5d4464fea2d75629206229a263be4fe73532a36f7d7",
  "quest_reward_label": "db1dd2d1e725165e7000fa39b65ddec3387f44f0444c6c669e871206048e45fa",
  "quote_forge_tray": "0432227e665ea16e57dd9ed9ccb17bdd7682440d310a62d50fab02b48c7c2a33",
  "quote_relic_synthesis": "d721049f93e71c5c49d9cc5d2af46fe7fbaca132e715ba3b9c8173fadb87db31",
  "repair_all_equipment": "d7d893c2169eb8c828d4601b6e20e2a15f69b6378cc0b741f981efeb59e4445d",
  "repair_cost": "f8df3db0c7c037706387f864587f36d17f336a2f8f0ae416902a951fd2ff7c78",
  "save_game": "9f878bbd3b8b3be71732c111abaaa0835abe5d626735facb88edab1a37dea059",
  "save_safe_logout": "ad4dab6cebea9c88074ef41df5916d20121da2130b4b3704b1f8af0ee036bf01",
  "select_character": "5c60fa99de028fa608b04507bf23e092f6517bb6e501759493e6f0106e19e6cd",
  "set_later_content_enabled": "7af32fbb3787305199404df175f807adef17a89f0e3dde398d28974f64eb42b3",
  "shared_gold_view_snapshot": "cb6c0d2387a4aff3099847892d77d2d98230ee51d2299537b5c62f6984385cbc",
  "skill_button_assignments_snapshot": "b4f81160152b51df06adfa7c2fbc7bff628d75d66faaadf1aed8e75a1fbfaffc",
  "skill_name_for_slot": "b3e26674a82995a337f680d38b1c4ae4db05b52b28611bcf8256d9770e18ecd8",
  "sort_inventory_deterministic": "b38bb984df6b609c48cf3cfc78bad30e1b63184cc79253968377843b155b3e12",
  "transfer_shared_gold_prepared": "535ef73a609cbe3c32a281fab52a1972c1d78be938587eaa8fb0bd1ecddeaaa1",
  "transfer_warehouse_prepared": "cd03402062d1ba03f1c93c90f0e44a29637a97105cdfcba943e15e49f29f2bf7",
  "transfer_workbench_immediate": "c0dfa2602b2ca531a234fafcea9f9fa32572a58509806bfa8e288898efbb7cec",
  "unequip_to_inventory_slot": "719d4c02e910b71682a483a1a70ef893c47408f668accded7c9680b9763b4a07",
  "use_inventory_index_result": "2cd38984229facdb3e22a9b55ddf7c72fa1d7390b533f99fdc10bbf71155484e",
  "workbench_tray": "2cd72d64327adaadbf8ce34c458ad42a176da96f3681d29826279a65a5adf1dc"
}
static func accepts(method: String,size: int)->bool:
	return ARITIES.has(method) and size in ARITIES[method]
