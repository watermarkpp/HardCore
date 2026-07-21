# MSE Stage 2 地面笔刷、Paint State 与 Chunk Bake 验收报告

任务：`MSE-STAGE-2`  
结论：通过，允许进入 Stage 3。

## 已完成

- 左侧素材面板只展示153个已校准的正式地面笔刷。
- 点击素材选择笔刷；编辑器画布左键绘制，拖动连续绘制。
- 画布以等距坐标反算 tile，并在范围外拒绝绘制。
- 绘制操作记录到命中Chunk的操作数组；同一Chunk多次绘制只保留一个dirty标记。
- 命令栈已接入笔刷：撤销追加 `erase_tile` 反向操作，重做重新追加 `paint_tile`。
- 烘焙服务只读取 `dirty_chunks`，每个dirty Chunk生成一个1024×1024预览PNG。
- 烘焙完成后Chunk保持 `materialized`，待烘焙队列清空；没有dirty Chunk时不重复生成文件。

## 路径边界

```text
map_editor_workspace/{map_id}/ground/
  ground_manifest.json
  ground_state.json
  chunks/c_x_y.json
  baked_preview/c_x_y.png
  baked_preview/bake_manifest.json
```

上述均为编辑器工作产物，不属于运行时目录。`assets/data/maps/runtime/` 和 `assets/art/maps/{map_id}/chunks/` 仍由后续 Build Runtime 阶段独占。

## 验收

- 同一Chunk两次绘制：dirty数保持1。
- 擦除后该tile回退到共享默认草地。
- `c_2_1` 烘焙为1024×1024 PNG。
- 烘焙后dirty队列为空；再次烘焙返回 `no_dirty_chunks`。
- `mse_stage2_paint_bake_test`、Stage 1、R1、Stage 0回归共4/4通过。
- 未构建APK，未改动游戏运行时地图、人物方向或战斗系统。

## 下一阶段

`MSE-STAGE-3：素材校准面板、Ghost 预览与Footprint 放置校验`

目标：把当前地面笔刷延伸为通用放置交互；实现素材切片/校准入口、绿色/黄色/红色Ghost、逻辑footprint占地和可放置校验，为装饰物、障碍物和建筑工具做准备。
