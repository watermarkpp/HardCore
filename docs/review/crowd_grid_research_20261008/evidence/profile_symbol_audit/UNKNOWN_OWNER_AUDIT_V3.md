# UNKNOWN_OWNER_AUDIT_V3

- Fixed research commit: `edae6fdef6a6551a951fab1ea8c6ade43359d603`
- Unknown signatures retained: **675**
- Unique resources: **87**; validated blobs: **86**; missing source resources: **1**
- Every git validation error was captured; failed git output was never hashed.

## Source validation

Strict validation used `git rev-parse --verify <fixed_commit>^{tree}:<resource>` with a strict 40-hex result, followed by `git cat-file -t` requiring `blob`. Git rejects a literal `<commit>:<path>^{blob}` path expression, so the tree-path equivalent is recorded. Missing frozen sources are marked `MISSING_SOURCE`; no MAIN/current source was substituted.

Missing resources:

- `res://tests/crowd_engagement_scaling_20261008.gd` (MISSING_SOURCE; git return code 128)

## Resource self top 15

This is a resource aggregate inventory. `self_ms` is not caller CPU attribution; `inclusive_ms` must not be summed as independent owners.

|rank|resource|signatures|calls|self ms|inclusive ms|internal ms|
|---:|---|---:|---:|---:|---:|---:|
|1|`res://scripts/enemy.gd`|136|1263906|488.004|0.000|87.083|
|2|`res://scripts/monster_visual.gd`|36|283529|142.639|0.000|4.371|
|3|`res://scripts/game_root.gd`|57|317263|125.394|0.000|25.397|
|4|`res://scripts/runtime_combat_spatial_index.gd`|18|106810|88.236|0.000|0.000|
|5|`res://scripts/map_editor/polygon/poly_index.gd`|5|100312|64.102|0.000|0.000|
|6|`res://scripts/layers/runtime/execution/frame_budget.gd`|13|75738|54.055|0.000|1.266|
|7|`res://scripts/world_spatial_rules.gd`|6|147883|46.492|0.000|0.000|
|8|`res://scripts/ground_unit_space.gd`|5|217284|45.361|0.000|0.000|
|9|`res://scripts/layers/runtime/map_editor_runtime_bridge.gd`|6|73742|36.704|0.000|0.000|
|10|`res://scripts/monster_visual_streaming_coordinator.gd`|13|133502|34.370|0.000|155.180|
|11|`res://tests/crowd_engagement_scaling_20261008.gd`|5|1569|33.330|0.000|0.012|
|12|`res://scripts/monster_ai_package/decision_budget.gd`|10|122403|27.740|0.000|116.099|
|13|`res://scripts/player_visual.gd`|21|13002|22.898|0.000|0.149|
|14|`res://scripts/map_editor/polygon/poly_runtime.gd`|3|8084|21.337|0.000|0.000|
|15|`res://scripts/map_editor/map_editor_coordinate.gd`|2|89639|20.566|0.000|0.000|

## Group summary

|group|signatures|calls|self ms|inclusive ms|
|---|---:|---:|---:|---:|
|MISSING_SOURCE|5|1569|33.330|0.000|
|budget_admission_or_scheduler|15|70372|56.038|0.000|
|poly_index_geometry|11|123580|76.209|0.000|
|poly_nav_path_dependency|15|72|0.112|0.000|
|poly_runtime_callee|3|8084|21.337|0.000|
|script_function_exact|554|2478414|1197.321|0.000|
|shared_builtin_or_native|66|1176402|107.366|0.000|
|test_fixture|6|12679|10.955|0.000|

## Poly boundary

The core execution set is `poly_index.gd` + `poly_geometry.gd` only. `poly_runtime` actual callees and `poly_nav`/`poly_path` dependencies remain separate; folder membership is not treated as one portable boundary.

## Exact mapping failures / missing source

|resource|method|status|blob|
|---|---|---|---|
|`res://scripts/enemy.gd`|`get_meta`|builtin_or_native_line_zero|`227555f49328b84db8e8359c3a2289cad926307a`|
|`res://tests/crowd_engagement_scaling_20261008.gd`|`_physics_process`|MISSING_SOURCE|`—`|
|`res://tests/world_crowd_firewall_profile_test.gd`|`get_ticks_usec`|builtin_or_native_line_zero|`19b68d0c9cfb175b682c5dbdf16cbb01b67a3202`|
|`res://tests/crowd_engagement_scaling_20261008.gd`|`_count_scaling_targeting`|MISSING_SOURCE|`—`|
|`res://scripts/monster_visual_streaming_coordinator.gd`|`has_method`|builtin_or_native_line_zero|`53a18e3e11e18ea88e9175527554a0466c026424`|
|`res://scripts/enemy.gd`|`intersect_ray`|builtin_or_native_line_zero|`227555f49328b84db8e8359c3a2289cad926307a`|
|`res://scripts/game_root.gd`|`get_instance_id`|builtin_or_native_line_zero|`ffa623869eed27b6c1981d6289c043bf528e7c52`|
|`res://scripts/loot_pickup_runtime_manager.gd`|`is_queued_for_deletion`|builtin_or_native_line_zero|`a63fa2e72a9487a74ee0ed552a320a625cc08c33`|
|`res://scripts/device_lab_runtime.gd`|`file_exists`|builtin_or_native_line_zero|`2919c961aeba82ab6bfc3c627473efc5d69559f0`|
|`res://scripts/hud_resource_orb.gd`|`draw_multiline_string`|builtin_or_native_line_zero|`a6fc70755c7d05bf97cfbc7dd9554978e311ce22`|
|`res://scripts/monster_ai_package/decision_budget.gd`|`get_physics_frames`|builtin_or_native_line_zero|`07ce07b8b3e76170a723fcd26ebccfa4ff2e2b2e`|
|`res://scripts/loot_pickup_runtime_manager.gd`|`get_ref`|builtin_or_native_line_zero|`a63fa2e72a9487a74ee0ed552a320a625cc08c33`|
|`res://scripts/game_root.gd`|`has_method`|builtin_or_native_line_zero|`ffa623869eed27b6c1981d6289c043bf528e7c52`|
|`res://scripts/enemy.gd`|`get_script`|builtin_or_native_line_zero|`227555f49328b84db8e8359c3a2289cad926307a`|
|`res://tests/crowd_engagement_scaling_20261008.gd`|`_run`|MISSING_SOURCE|`—`|
|`res://scripts/map_coordinate_mapper.gd`|`<anonymous lambda>(lambda)`|source_present_no_exact_func_name|`fe2896d60928a85ef507fd5e715ab9cd4d671df6`|
|`res://scripts/enemy.gd`|`has_meta`|builtin_or_native_line_zero|`227555f49328b84db8e8359c3a2289cad926307a`|
|`res://scripts/monster_visual_streaming_coordinator.gd`|`get_ticks_msec`|builtin_or_native_line_zero|`53a18e3e11e18ea88e9175527554a0466c026424`|
|`res://scripts/enemy.gd`|`create`|builtin_or_native_line_zero|`227555f49328b84db8e8359c3a2289cad926307a`|
|`res://scripts/game_root.gd`|`get_process_frames`|builtin_or_native_line_zero|`ffa623869eed27b6c1981d6289c043bf528e7c52`|
|`res://scripts/audio_runtime_service.gd`|`play`|builtin_or_native_line_zero|`d270a038e5f0b9dd3ddb17535f17aea38da70a75`|
|`res://scripts/enemy.gd`|`@control_time_setter`|source_present_no_exact_func_name|`227555f49328b84db8e8359c3a2289cad926307a`|
|`res://scripts/enemy.gd`|`get_property_list`|builtin_or_native_line_zero|`227555f49328b84db8e8359c3a2289cad926307a`|
|`res://scripts/map_coordinate_mapper.gd`|`<anonymous lambda>(lambda)`|source_present_no_exact_func_name|`fe2896d60928a85ef507fd5e715ab9cd4d671df6`|
|`res://scripts/enemy.gd`|`@charm_time_setter`|source_present_no_exact_func_name|`227555f49328b84db8e8359c3a2289cad926307a`|
|`res://scripts/monster_visual.gd`|`get_global_transform_with_canvas`|builtin_or_native_line_zero|`5ff3bbb0dc060fa9d47c89b09e23a63f499d0cb6`|
|`res://scripts/monster_visual.gd`|`get_physics_frames`|builtin_or_native_line_zero|`5ff3bbb0dc060fa9d47c89b09e23a63f499d0cb6`|
|`res://scripts/enemy.gd`|`get_world_2d`|builtin_or_native_line_zero|`227555f49328b84db8e8359c3a2289cad926307a`|
|`res://tests/world_crowd_firewall_profile_test.gd`|`_physics_process`|exact_func_name_multiple_matches|`19b68d0c9cfb175b682c5dbdf16cbb01b67a3202`|
|`res://scripts/game_root.gd`|`is_action_just_pressed`|builtin_or_native_line_zero|`ffa623869eed27b6c1981d6289c043bf528e7c52`|
|`res://scripts/game_root.gd`|`force_update_scroll`|builtin_or_native_line_zero|`ffa623869eed27b6c1981d6289c043bf528e7c52`|
|`res://scripts/enemy.gd`|`get_ticks_msec`|builtin_or_native_line_zero|`227555f49328b84db8e8359c3a2289cad926307a`|
|`res://scripts/game_root.gd`|`get_visible_rect`|builtin_or_native_line_zero|`ffa623869eed27b6c1981d6289c043bf528e7c52`|
|`res://scripts/monster_ai_package/policy.gd`|`get_closest_point_to_segment`|builtin_or_native_line_zero|`9c68cdf33fc16e73dc6846904c787a33ec9db5d2`|
|`res://scripts/player_status_marker_strip.gd`|`get`|builtin_or_native_line_zero|`6632e0fc7190f098cb3065e0bd332bf58fab85cf`|
|`res://scripts/game_root.gd`|`get_nodes_in_group`|builtin_or_native_line_zero|`ffa623869eed27b6c1981d6289c043bf528e7c52`|
|`res://scripts/hud.gd`|`set_shader_parameter`|builtin_or_native_line_zero|`e686ca981330918d035013840f811cfa4b3f36c5`|
|`res://scripts/layers/runtime/execution/frame_budget.gd`|`get_thread_caller_id`|builtin_or_native_line_zero|`abae07cdae94ffb8f626fea5e0372c0709b20a81`|
|`res://scripts/game_root.gd`|`is_action_pressed`|builtin_or_native_line_zero|`ffa623869eed27b6c1981d6289c043bf528e7c52`|
|`res://scripts/hud_resource_orb.gd`|`draw_arc`|builtin_or_native_line_zero|`a6fc70755c7d05bf97cfbc7dd9554978e311ce22`|
|`res://scripts/map_editor/polygon/poly_geometry.gd`|`is_point_in_polygon`|builtin_or_native_line_zero|`7a09060a0ae311cbf69c162c870429160c1bd9a9`|
|`res://tests/world_crowd_firewall_profile_test.gd`|`get_monitor`|builtin_or_native_line_zero|`19b68d0c9cfb175b682c5dbdf16cbb01b67a3202`|
|`res://scripts/player.gd`|`get_vector`|builtin_or_native_line_zero|`0b68a4ade8552fff7af2f1e6653361ff143b9acd`|
|`res://scripts/enemy.gd`|`@target_setter`|source_present_no_exact_func_name|`227555f49328b84db8e8359c3a2289cad926307a`|
|`res://scripts/player.gd`|`has_action`|builtin_or_native_line_zero|`0b68a4ade8552fff7af2f1e6653361ff143b9acd`|
|`res://scripts/monster_crowd_attack_position_policy.gd`|`get`|builtin_or_native_line_zero|`4787b3041c1c9fcf4b9fa1a717b51248835cdacb`|
|`res://scripts/player_state.gd`|`@profession_id_getter`|generated_property_getter|`2ad1baffc398deeb02930d1d05fd85bf32391446`|
|`res://scripts/layers/runtime/execution/frame_budget.gd`|`get_main_thread_id`|builtin_or_native_line_zero|`abae07cdae94ffb8f626fea5e0372c0709b20a81`|
|`res://scripts/runtime_combat_spatial_index.gd`|`<anonymous lambda>(lambda)`|source_present_no_exact_func_name|`1f851f96d0ae5cd5aa95d7f1e817d35d389e2659`|
|`res://scripts/device_lab_runtime.gd`|`is_debug_build`|builtin_or_native_line_zero|`2919c961aeba82ab6bfc3c627473efc5d69559f0`|
|`res://scripts/hud_resource_orb.gd`|`draw_line`|builtin_or_native_line_zero|`a6fc70755c7d05bf97cfbc7dd9554978e311ce22`|
|`res://scripts/hud_resource_orb.gd`|`draw_circle`|builtin_or_native_line_zero|`a6fc70755c7d05bf97cfbc7dd9554978e311ce22`|
|`res://scripts/player.gd`|`has_meta`|builtin_or_native_line_zero|`0b68a4ade8552fff7af2f1e6653361ff143b9acd`|
|`res://scripts/player_health_bar.gd`|`draw_string`|builtin_or_native_line_zero|`5d1f85869c99bd9799129fc34c22d07d33750f91`|
|`res://scripts/game_root.gd`|`get_ticks_msec`|builtin_or_native_line_zero|`ffa623869eed27b6c1981d6289c043bf528e7c52`|
|`res://scripts/layers/runtime/execution/frame_budget.gd`|`get_main_loop`|builtin_or_native_line_zero|`abae07cdae94ffb8f626fea5e0372c0709b20a81`|
|`res://scripts/monster_ai_package/path_scheduler.gd`|`get_ticks_usec`|builtin_or_native_line_zero|`9cc6aea89b4c736873eff10f9996e451e85cdb8d`|
|`res://scripts/player_state.gd`|`@attack_skill_slots_getter`|generated_property_getter|`2ad1baffc398deeb02930d1d05fd85bf32391446`|
|`res://scripts/player.gd`|`get_ticks_msec`|builtin_or_native_line_zero|`0b68a4ade8552fff7af2f1e6653361ff143b9acd`|
|`res://scripts/quick_item_icon_layout.gd`|`get_instance_id`|builtin_or_native_line_zero|`d39e5546d7d8c453b0ead8eda89933fd676bfe05`|
|`res://scripts/enemy.gd`|`start`|builtin_or_native_line_zero|`227555f49328b84db8e8359c3a2289cad926307a`|
|`res://scripts/monster_ai_package/path_scheduler.gd`|`get_physics_frames`|builtin_or_native_line_zero|`9cc6aea89b4c736873eff10f9996e451e85cdb8d`|
|`res://scripts/monster_ai_package/path_scheduler.gd`|`new`|builtin_or_native_line_zero|`9cc6aea89b4c736873eff10f9996e451e85cdb8d`|
|`res://scripts/audio_runtime_service.gd`|`get_ticks_msec`|builtin_or_native_line_zero|`d270a038e5f0b9dd3ddb17535f17aea38da70a75`|
|`res://scripts/device_lab_runtime.gd`|`get_name`|builtin_or_native_line_zero|`2919c961aeba82ab6bfc3c627473efc5d69559f0`|
|`res://scripts/player.gd`|`randi_range`|builtin_or_native_line_zero|`0b68a4ade8552fff7af2f1e6653361ff143b9acd`|
|`res://scripts/player_health_bar.gd`|`draw_rect`|builtin_or_native_line_zero|`5d1f85869c99bd9799129fc34c22d07d33750f91`|
|`res://scripts/hud.gd`|`set_meta`|builtin_or_native_line_zero|`e686ca981330918d035013840f811cfa4b3f36c5`|
|`res://scripts/ui_selection_dismiss_guard.gd`|`is_queued_for_deletion`|builtin_or_native_line_zero|`21a8fecdb686dcc3422112478fb9c3c86983115c`|
|`res://scripts/hud_resource_orb.gd`|`queue_redraw`|builtin_or_native_line_zero|`a6fc70755c7d05bf97cfbc7dd9554978e311ce22`|
|`res://scripts/player_visual.gd`|`get_first_node_in_group`|builtin_or_native_line_zero|`c3c468bfbe673b833887512f8f20dcd3289381ba`|
|`res://scripts/game_root.gd`|`<anonymous lambda>(lambda)`|source_present_no_exact_func_name|`ffa623869eed27b6c1981d6289c043bf528e7c52`|
|`res://scripts/map_editor/polygon/poly_nav_graph.gd`|`is_point_in_polygon`|builtin_or_native_line_zero|`00eaaf6676e43b6d36109668870acddf41cc1ab7`|
|`res://tests/crowd_engagement_scaling_20261008.gd`|`get_instance_id`|MISSING_SOURCE|`—`|
|`res://scripts/map_editor/polygon/poly_path_search.gd`|`@implicit_new`|builtin_or_native_line_zero|`2c8ddd6fca461b48bfc2d6471b6efb132838db6a`|
|`res://scripts/monster_ai_package/path_scheduler.gd`|`@implicit_new`|builtin_or_native_line_zero|`9cc6aea89b4c736873eff10f9996e451e85cdb8d`|
|`res://scripts/enemy.gd`|`is_visible_in_tree`|builtin_or_native_line_zero|`227555f49328b84db8e8359c3a2289cad926307a`|
|`res://scripts/monster_ai_package/path_search.gd`|`@implicit_new`|builtin_or_native_line_zero|`c19705de63f070fa7f222459fc5d6f3bdecdebc6`|
|`res://tests/crowd_engagement_scaling_20261008.gd`|`set_physics_process`|MISSING_SOURCE|`—`|
|`res://scripts/quick_item_icon_layout.gd`|`get_size`|builtin_or_native_line_zero|`d39e5546d7d8c453b0ead8eda89933fd676bfe05`|
|`res://scripts/enemy.gd`|`get_global_transform_with_canvas`|builtin_or_native_line_zero|`227555f49328b84db8e8359c3a2289cad926307a`|

## Scope and interpretation

This is an offline ownership/source audit of the retained native profile. It does not establish caller causality, migration coverage, or a performance gain. No tests, Godot runs, or new sampling were performed.
