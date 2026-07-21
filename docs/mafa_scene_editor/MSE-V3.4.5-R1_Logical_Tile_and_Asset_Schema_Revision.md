# MSE-V3.4.5-R1 逻辑 Tile 与正式素材 Schema 修订

依据：`地图编辑器素材规格_V3.2-R1_逻辑Tile与有效菱形覆盖修订版.txt`  
任务：`MSE-R1-GATE`  
结论：已按当前 V3.4.5 架构吸收，不降级地图 Schema。

## 修订决策

- 地图继续使用 Schema v4；素材使用独立 `asset_schema_version=2`；实例语义使用 `instance_schema_version=1`。
- `64×32` 是逻辑 1×1 Tile。高清源图允许任意真实像素，但进入正式 `base_tile` Palette 前必须归一。
- 图片尺寸只用于校验；footprint 必须由导入配置或人工校准明确声明。
- 用户本批五组素材明确登记为 1×1 base tile，不是根据尺寸猜测。
- 新素材默认 `personal_expansion`；Vanilla Core 继续只读。

## 正确的等距 footprint 几何

旧方案的 `64×footprint_x / 32×footprint_y` 对矩形 footprint 不成立。正式公式为：

```text
logical_width  = (footprint_x + footprint_y) × 32
logical_height = (footprint_x + footprint_y) × 16
```

因此：

- 1×1 = 64×32
- 2×2 = 128×64
- 3×1 = 128×64
- 4×2 = 192×96

实现权威为 `scripts/map_assets/iso_footprint_geometry.gd`。

## 高清地面素材本地处理

来源：`C:/Users/Administrator/Desktop/sucai/` 中五组透明 PNG。

| 地形 | 数量 | 原始特征 | 正式输出 |
|---|---:|---|---|
| 古旧草地 | 29 | 约 237–262×155–169 | 64×32 |
| 暗色草地 | 29 | 约 236–263×155–171 | 64×32 |
| 落叶草地 | 36 | 约 230–238×152–159 | 64×32 |
| 泥地 | 29 | 约 237–263×152–168 | 64×32 |
| 石地 | 30 | 约 233–251×156–166 | 64×32 |

处理不是矩形拉伸：读取透明轮廓，定位上、右、下、左四个菱形尖点，通过透视变换映射到标准64×32菱形，再应用标准有效区Mask。原图复制到带 `.gdignore` 的 raw import 区，正式输出进入共享 terrain 目录。

结果：153/153成功，拒绝0；有效菱形内部覆盖率100%；加上程序空白草地，正式可放置目录共154项。

## 三层素材目录

- `map_asset_source_catalog.json`：原图路径、raw import路径与来源哈希。
- `map_asset_import_catalog.json`：四尖点、归一方法、输出路径与覆盖率。
- `map_asset_catalog.json`：仅正式可放置素材；缩略图直接引用同一正式输出并绑定相同哈希，杜绝缩略图错配。
- `map_asset_problem_list.json`：拒绝或待人工处理的素材。

## 图层与兼容

16个标准层全部保留，并增加既有扩展层 `interactables`、`region_semantics`，总计18层。`ground_base` 已加入 Schema v4。旧 Schema v4 文档打开时由升级器补齐缺层，不破坏已有地图。

## 验收

- `validate_map_asset_catalog.py`：154项，错误0，警告0。
- `mse_r1_gate_test`：通过。
- `map_editor_stage0_test`：通过。
- 未构建APK，未修改v34人物方向与攻击事务。

## 后续

进入 `MSE-STAGE-1：空白地面与虚拟 Chunk`。Stage 1 必须直接使用本次生成的正式64×32素材，不再读取桌面原图或旧来源图集。
