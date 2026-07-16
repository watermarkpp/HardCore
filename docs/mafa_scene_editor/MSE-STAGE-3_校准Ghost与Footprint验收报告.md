# MSE Stage 3 素材校准、Ghost 预览与 Footprint 放置校验报告

任务：`MSE-STAGE-3`  
结论：通过，允许进入 Stage 4。

## 已完成

- 素材面板显示153张正式地面缩略图；缩略图直接引用同一正式输出，不存在独立缩略图错配。
- 选中素材后，编辑器显示其有效锚点、占地、碰撞策略和遮挡设置。
- 校准数据写入 `personal_expansion_001/map_asset_overrides.json`，基础Catalog保持可重建。
- 校准覆盖会即时成为编辑器、Ghost和放置校验读取的有效素材数据。
- Ghost随鼠标悬停显示逻辑footprint：绿色可放置，黄色带警告，红色拒绝。
- 放置校验已覆盖素材存在性、placeable状态、footprint完整性、地图边界、图层建议和Vanilla只读提醒。
- 地面素材尝试改为多格footprint时被拒绝，要求先生成匹配的新归一化图像，避免图片与占地脱节。

## 覆盖字段

```text
anchor_px
anchor_tile
anchor_mode
footprint_tiles
collision_policy
navigation_policy
occlusion
placeable
calibration_status
```

## 验收

- 右下角1×1地砖有效；地图边界外拒绝。
- 缺失素材拒绝。
- Ghost输出4点等距footprint外轮廓。
- 有效草地校准可保存为Expansion覆盖。
- 1×1草地错误改为2×1会得到明确校验错误。
- Stage 3、2、1、R1、0回归共5/5通过。
- 未构建APK；未改动游戏运行时地图、人物方向或战斗系统。

## 下一阶段

`MSE-STAGE-4：装饰物、障碍物与建筑实例语义`

目标：从只有地面笔刷升级为可放置的通用场景实例；实例必须携带 object_role、scene_intent、gameplay_role、碰撞与导航策略，并支持选择、移动、删除、复制、批量修改和保存重开。
