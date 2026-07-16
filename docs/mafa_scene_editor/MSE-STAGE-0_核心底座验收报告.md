# MSE Stage 0 核心底座验收报告

任务：`MSE-STAGE-0-CLOSE`  
日期：2026-07-10  
结论：通过，允许进入 Stage 1。

## 已完成

- 独立桌面入口 `scenes/tools/mafa_scene_editor.tscn`，不替换游戏主场景，不进入 Android APK。
- Schema v4 新建、校验、确定性 JSON、原子保存、备份和重新读取。
- 字符串 `map_id` 与整数 `runtime_map_id` 双 ID。
- `godot_iso_64x32` 等距坐标、网格预览、像素/格坐标往返。
- 命令栈撤销/重做，默认历史上限 50。
- 单机地图设计目录接入：64×64 沙盒、比奇 256×256、盟重 280×280。
- 工作文件路径在界面明确显示，默认保存为 `map_editor_workspace/{map_id}/{map_id}.editor.json`。
- 最小素材目录 15 项：1 项内置空白草地可用；14 项现有图集标为 `needs_slicing`，不得冒充可摆放素材。
- 每项素材具备稳定 ID、来源状态、SHA-256、region、pivot、footprint、碰撞、版本、校准状态和 Palette 开关。

## 验证

- `tools/map_editor/build_asset_catalog.py`：15 项、缺失 0、正式 Palette 1 项。
- `tools/map_design/validate_map_design_catalog.py`：21 张地图错误 0；7 个未确认原图映射保持警告。
- `tests/map_editor_stage0_test.tscn`：通过。
- Godot 4.7 桌面工程扫描和全局类注册：通过。

## 保护边界

- v34 人物方向与攻击里程碑未修改。
- 未构建 APK，未连接手机。
- Vanilla Core 仍只读，新建地图写 Expansion 工作区。
- 工作文件是编辑权威；运行时不得读取工作目录。后续 Build Runtime 只发布确定性生成结果。

## 下一阶段

`MSE-STAGE-1：空白地面与虚拟 Chunk`

目标：在 64×64 沙盒创建可见旧草地底图；空白 Chunk 共享且不落盘，第一次编辑时才物化；生成 ground manifest、chunk 边界和 dirty 状态，并验证重开一致。
