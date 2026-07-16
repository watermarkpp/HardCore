# MSE Stage 6 地图玩法语义验收报告

任务：`MSE-STAGE-6`  
结论：通过，允许进入 Stage 7。

## 本阶段交付

所有玩法对象均不再混入装饰物层，而是按 Schema v4 的独立图层保存：

- `npc_points`：NPC ID、服务角色、朝向与安全标记。
- `monster_spawn`：怪物 ID、数量、刷新秒数、刷新半径与环境刷怪规则。
- `boss_spawn`：Boss ID、数量、刷新秒数、刷新半径与 Boss 规则。
- `door_points`：门点 ID、目标地图 ID、目标 Tile 和单向标记；未填目标地图将拒绝保存。
- `safe_area`：安全区范围、禁止 PVP / 怪物伤害、回城锚点标记。
- `light`：范围、颜色、强度和闪烁标记。
- `region_trigger`：范围、进入触发方式、动作与一次性标记。

编辑器新增“Gameplay Semantics”画布模式：选择类型并填写内容 ID（门点填写目标地图 ID）后直接点击等距地图放置。预览颜色固定为 NPC 蓝、普通怪红、Boss 橙、门点紫、安全区绿、光源黄、区域触发青；范围对象显示圆形轮廓。

## 数据边界

- 所有数据以 `personal_expansion` 编辑层保存，供后续扩展包和私人修改使用。
- 仅写编辑器文档/工作区；没有写入 `assets/data/maps/runtime/`，没有修改游戏运行时读取，也没有导出 APK。
- Stage 7 才负责 Build Runtime：把通过校验的门点、刷怪与区域语义编译成运行时消费的数据，同时阻止未审核地图进入试玩版本。

## 验收

关键回归 8/8 通过：

- `mse_stage6_gameplay_semantics_test`
- `mse_stage5_collision_walkable_test`
- `mse_stage4_instance_semantics_test`
- `mse_stage3_calibration_ghost_test`
- `mse_stage2_paint_bake_test`
- `mse_stage1_ground_test`
- `mse_r1_gate_test`
- `map_editor_stage0_test`

素材目录保持通过：161 项可放置素材，`errors=0`，`warnings=0`。

## 下一阶段

`MSE-STAGE-7：地图语义校验、Build Runtime 与运行时导出门禁`

目标：构建可审计的编辑器到运行时导出管线，输出地面、实例、碰撞/可走区和地图玩法语义的独立运行时快照；编辑器工作区、草稿和校验失败数据不得进入 Android 试玩内容。
