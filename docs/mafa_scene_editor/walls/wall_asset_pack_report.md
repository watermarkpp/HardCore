# MSE-V3.5 墙体素材包 V1

本包依据 MSE-V3.5-WALL 规格生成，提供两个完整墙体家族：

- `cave_granite_u0`：天然洞穴花岗岩壁；
- `orc_tomb_rough_stone_u0`：兽人古墓粗砌旧石墙。

## 内容

每个家族包含 **42 个逻辑素材**：

- L4 直墙：2 轴 × 3 变体；
- L3 直墙：2 轴 × 3 变体；
- L2 修补墙：2 轴；
- L1 修补墙：2 轴；
- 内角 4、外角 4、端头 4；
- 门洞适配 4（X/Y × open/closed）；
- 破损缺口 4；
- 接缝盖片 6。

全包共 **84 个逻辑素材**。

## 工程约束

- 固定 `64×32`、2:1 等距视角；
- `iso_x / iso_y` 为独立素材；
- 禁止运行时旋转、镜像和缩放；
- 直墙 L1/L2/L3/L4 使用精确画布与锚点；
- 每个长墙内部按 tile 输出 `part_*_base/front/shadow.png`；
- 背景透明，PNG 为 RGBA；
- 碰撞来自 `collision_cells`，不来自画布矩形；
- Socket 稳定带为 16 px，端点轮廓由同一数学母版生成。

## 使用方式

1. 将 `assets/` 目录合并到项目同名目录。
2. 读取 `assets/data/assets/wall_family_catalog.json`。
3. 读取 `assets/data/assets/wall_module_catalog.json`。
4. 导入时把每个包含 `meta.json` 的目录视为一个逻辑素材包。
5. 素材面板只显示 `preview.png`，不要暴露内部 part 文件。
6. 运行时按 `render_parts.sort_tile_offset` 分片排序。

## 美术说明

这是可直接验证编辑器、拼接、遮挡、碰撞和路径工具的程序化首版美术。接口、尺寸、锚点和分片已经稳定；后续可在不改 Socket 区、画布、锚点和碰撞的前提下，对中央 60% 区域进行人工精修或 AI 重绘。

## 自动校验

- 素材数：84
- 家族计数：`{"cave_granite_u0": 42, "orc_tomb_rough_stone_u0": 42}`
- 结构校验：PASS
- 问题数：0
