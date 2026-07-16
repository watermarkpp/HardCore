# MSE-V3.4.5 施工决策与人机协作规范

本规范以 `MSE-V3.4.5_玛法通用内置场景编辑器施工档案_Codex交付确认版.docx` 为需求基线，并记录用户已批准的工程补强。原文与本规范冲突时，以本规范的工程决策为准；其余内容严格遵循原文。

## 核心定位

MSE 是用户与 Codex 共用的地图生产工具：

- 用户通过 Godot 桌面可视化界面创建、粉刷、摆放和校准地图；
- Codex 通过同一 Schema、确定性构建服务和自动测试批量修改与验证；
- 双方只维护一套 `editor.json` 可编辑源和一套可重建的运行时产物；
- 编辑器仅在 Windows 开发端运行，不进入正式 Android APK；Android 只读取 Build Runtime 产物。

## 已批准的补强决策

1. 正式地图使用字符串 `map_id`，同时登记唯一整数 `runtime_map_id`，兼容现有数值地图索引。
2. 编辑器使用文档规定的左上正坐标 `ground_px`；游戏继续使用中心世界原点。构建时通过统一适配器转换，不替换现有 `MapCoordinateMapper`。
3. Schema v4 是新地图正式标准。现有 `assets/maps` 与旧 `AuthoredMapLoader` 暂不删除，由 Legacy Adapter 逐图迁移。
4. 700×700 等大地图不得实体化全部空白文件。空白 Chunk 使用共享/虚拟底图，编辑后才物化工作 Chunk。
5. Mask 从第一版起按 Chunk 存储，避免完整超大 L8 图常驻内存。
6. 工作 Chunk、图层源和历史放入 `map_editor_workspace/`，该目录带 `.gdignore`，避免 Godot 导入风暴。最终 Bake 结果才写入 `assets/art/maps/{map_id}/chunks/`。
7. JSON、Manifest、状态和报告使用临时文件加原子替换；构建输出必须可由相同输入、素材版本和随机种子确定性复现。
8. Vanilla Core 地图默认只读。用户编辑默认写入 Expansion Layer；修改原版必须先克隆为扩展地图。
9. 场景对象允许 `rotation_deg`、`scale`、`flip_x/y`；地面基础块、NPC、门点和刷新点使用受限变换。预设碰撞随对象变换重算，手工多边形碰撞独立保存并在失配时警告。
10. 素材必须具有稳定 ID、来源、校验值、region、pivot、footprint、碰撞和版本。未经校准的素材不得进入正式 Palette。
11. 先用 64×64 沙盒地图贯通 Stage 0–8，再迁移 700×700 比奇；沙盒不改变最终地图目标。

## 文件权威关系

- 可编辑权威：`assets/data/maps/editor/{map_id}.editor.json` 与 `map_editor_workspace/{map_id}/`。
- Dirty 唯一权威：`ground_paint_state.dirty_chunks`。
- 运行时权威：`runtime.json`、`walk.json`、`scene_intent.json`、`ground_chunks.json` 与最终 Chunk PNG。
- 游戏运行时禁止读取 editor.json、paint_ops、工作图层和历史。

## 阶段门禁

严格执行 Stage 0–8。每一阶段的定向测试通过后才进入下一阶段；Stage 9 Road Brush、Stage 10 Transition Brush 和 Stage 11 高级填充不得提前阻塞 MVP。

