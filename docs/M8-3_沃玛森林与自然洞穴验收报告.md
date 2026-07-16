# M8-3 沃玛森林与自然洞穴验收报告

## 结论

268、1506、1507已从通用地表/古墓模板升级为客户端原始MAP驱动的专用场景。沃玛森林使用地图1的草地、荒地、树木与遗迹素材；两张沃玛自然洞穴使用E001/E002的岩土地面和Objects洞壁素材。

## 原始地图统计

| 项目ID | 地图 | 客户端MAP | 尺寸 | 阻挡率 | 灯光单元 |
|---:|---|---|---:|---:|---:|
| 268 | 沃玛森林 | 1 | 600×600 | 55.14% | 1 |
| 1506 | 沃玛自然洞穴一 | E001 | 100×100 | 81.27% | 2 |
| 1507 | 沃玛自然洞穴二 | E002 | 100×100 | 78.91% | 6 |

- 服务端结构规则：`research/MIR2/GameOfMir/M2Server/Envir.pas`。
- 客户端地图：`research/mir2_client_raw/Map/1.map`、`E001.map`、`E002.map`。
- 客户端资源：`Tiles.wil/.WIX`、`Objects.wil/.WIX`。
- 完整统计、资源索引和可行走掩码：`assets/data/wooma_region_source_profiles.json`与`assets/art/maps/wooma_region/source_masks`。

## 完成内容

- 森林专用地面及8格物件图集：古树、倒木、遗迹柱、碎碑、藤架、洞口、灌木和路标。
- 自然洞穴专用地面及8格物件图集：岩柱、洞壁、石笋、菌簇、裂隙、骨堆、沃玛图腾和洞门。
- 268、1506、1507分别建立独立路线枢纽、碰撞、密度和洞穴灯光。
- 门点安全区保持畅通，完整连接比奇、沃玛森林、自然洞穴和沃玛寺庙入口。
- 保持怪物阵容、掉落、沃玛号角、沃玛卫士和沃玛教主正常。

## 验收

- `wooma_region_refinement_test`通过。
- `wooma_area_test`通过。
- `wooma_temple_refinement_test`通过。
- `environment_batch_test`通过，40次跨主题切换无残留。
- 本阶段未导出APK。

