# MSE Stage 5 地貌印章、手工碰撞与 Walkable 预览验收报告

任务：`MSE-STAGE-5`  
结论：通过，允许进入 Stage 6。

## 本阶段交付

- 从 `C:\Users\Administrator\Desktop\sucai\green_screen_assets_split_only` 本地处理三项透明背景地貌素材；原始文件保留在 `assets/raw_import/map_assets/terrain_sources/`，正式 PNG 写入 `assets/art/maps/_shared/terrain_stamps/`。
- 新增 `terrain.mud_decal_01`、`terrain.mud_decal_02`：2×2 逻辑格的纯视觉泥地印章，不产生碰撞。
- 新增 `terrain.palisade_wall_01`：3×1 逻辑格的地貌边界印章，使用 `terrain_stamp_generated` 策略，自动阻挡玩家与怪物。
- 编辑器新增 terrain 放置角色；地貌实例与装饰/建筑实例保持不同语义，保存后可重新载入。
- 新增矩形、椭圆、多边形三种手工碰撞。矩形/椭圆为起点和终点两次点击；多边形连续点选，按 Enter 提交，右键取消。
- 新增 Walkable 预览开关：红色格表示由地貌自动碰撞或手工碰撞共同生成的不可行走区域。

## 数据与边界

- 地貌目录：`assets/data/assets/map_terrain_asset_catalog.json`。
- 合并后的正式 `map_asset_catalog.json` 现含 161 个可放置素材。
- 手工碰撞、预览和实例编辑只写入编辑器文档及 `map_editor_workspace/`；本阶段没有生成 `walk.json`，没有触碰 `assets/data/maps/runtime/`，也没有导出 APK。
- 运行时导航烘焙、运行时碰撞和 Android 消费数据留给后续 Build Runtime 阶段，避免用尚未审核的编辑结果污染试玩版本。

## 验收

以下关键测试均通过（7/7）：

- `mse_stage5_collision_walkable_test`
- `mse_stage4_instance_semantics_test`
- `mse_stage3_calibration_ghost_test`
- `mse_stage2_paint_bake_test`
- `mse_stage1_ground_test`
- `mse_r1_gate_test`
- `map_editor_stage0_test`

素材目录校验：`assets=161 errors=0 warnings=0`。

## 下一阶段

`MSE-STAGE-6：NPC、门点、怪物刷新、安全区、光效与区域触发`

目标：将可玩的地图语义对象纳入同一编辑器工作流，并让它们与地面、地貌、碰撞和可走区域预览保持可校验的关联；仍不直接写入游戏运行时目录。
