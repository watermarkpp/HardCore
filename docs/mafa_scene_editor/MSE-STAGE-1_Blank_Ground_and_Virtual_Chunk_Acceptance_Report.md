# MSE Stage 1 空白地面与虚拟 Chunk 验收报告

任务：`MSE-STAGE-1`  
结论：通过，允许进入 Stage 2。

## 交付内容

- `MapEditorGroundService` 建立地面 manifest、dirty state 与Chunk工作操作。
- 新建地图直接显示正式 `ground.old_grass.001` 的虚拟底图；不生成整图PNG。
- Chunk尺寸固定为1024×1024 ground pixel，使用编辑器左上正坐标。
- 空白Chunk记录为 `virtual`，只保留共享默认地面素材ID，不产生Chunk文件。
- 第一次地面编辑将目标Chunk标为 `dirty/materialized`，并仅写入该Chunk的操作JSON。
- 所有地面工作文件仍位于 `map_editor_workspace/{map_id}/ground/`，被Godot忽略；运行时产物目录尚未写入。

## 验收数据

| 地图 | 设计尺寸 | 地面像素尺寸 | 虚拟Chunk网格 | 初始Chunk文件 |
|---|---:|---:|---:|---:|
| 64格沙盒 | 64×64 | 4096×2048 | 4×2，共8个 | 0 |
| 比奇省 | 80×80 | 5120×2560 | 5×3，共15个 | 0 |

沙盒中心格编辑后，只物化 `c_2_1`，`dirty_chunks` 从0变为1；重开后manifest、操作和dirty状态一致。

## 编辑器界面

- 新建地图后自动初始化虚拟地面。
- 64×64以下地图使用真实64×32草地预览；更大地图使用轻量地面预览，避免在编辑器缩略视图绘制数万张贴图。
- 增加“初始化虚拟地面 Chunk”和“中心格模拟首次地面编辑”两个Stage 1验证入口。后者是临时验证入口，Stage 2正式地面笔刷会取代它。

## 验证

- `mse_stage1_ground_test`：通过。
- `mse_r1_gate_test`：通过。
- `map_editor_stage0_test`：通过。
- 未构建APK；未改动运行时地图、人物方向或战斗代码。

## 下一阶段

`MSE-STAGE-2：地面笔刷、Paint State 与Chunk Bake`

目标：用户选择正式地面素材后可在网格上连续绘制；操作进入同一dirty state；只重烘焙dirty Chunk并生成可预览PNG，仍不进入运行时目录。
