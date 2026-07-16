# MSE Stage 7 Build Runtime 与运行时导出门禁验收报告

任务：`MSE-STAGE-7`  
结论：通过，允许进入 Stage 8。

## 交付

- 新增显式运行时批准：未批准的编辑器文档无法构建快照。
- 构建前强制执行 Schema、语义唯一 ID、门点目标、可走格数量、实例导出标记校验。
- 地面存在 Dirty Chunk 时构建被拒绝；只有完成 Chunk Bake 后才允许导出。
- 输出至 `assets/data/runtime/map_editor/{map_id}.runtime.json`，采用临时文件校验后原子提升。
- 快照只包含设计尺寸、地面覆盖、可导出实例、阻挡 Tile 和玩法语义；不包含 `map_editor_workspace` 或 `.editor.json` 引用。
- 编辑器增加“批准并构建 Runtime 快照”按钮；失败会显示具体门禁原因。

## 验收

`mse_stage7_build_runtime_test` 验证未批准拒绝、批准后构建、地貌阻挡编译、NPC/门点语义输出、工作区引用隔离、Dirty Chunk 拒绝及烘焙后的重新构建。

## 下一阶段

`MSE-STAGE-8：运行时快照读取契约与最终验收`。
