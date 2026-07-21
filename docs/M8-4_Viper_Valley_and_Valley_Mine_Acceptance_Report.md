# M8-4 毒蛇山谷与山谷矿区验收报告

## 结论

338、457、458已使用客户端2、D421、D422原始MAP及WIL资源重建。毒蛇山谷采用干燥山地/林地场景，山谷矿区采用区别于比奇矿区的潮湿岩洞、绿色冷光和腐蚀感物件。

## 原图数据

| 项目ID | 地图 | 客户端MAP | 尺寸 | 阻挡率 | 灯光单元 |
|---:|---|---|---:|---:|---:|
| 338 | 毒蛇山谷 | 2 | 600×600 | 58.50% | 7 |
| 457 | 山谷矿区一层 | D421 | 400×400 | 87.24% | 61 |
| 458 | 山谷矿区二层 | D422 | 400×400 | 82.51% | 9 |

- 服务端结构依据：`research/MIR2/GameOfMir/M2Server/Envir.pas`。
- 客户端地图：`research/mir2_client_raw/Map/2.map`、`D421.map`、`D422.map`。
- 客户端资源：`Tiles.wil/.WIX`、`Objects.wil/.WIX`、`Objects2.wil/.WIX`。
- 完整统计、索引和可行走掩码：`assets/data/snake_valley_source_profiles.json`与`assets/art/maps/snake_valley/source_masks`。

## 完成内容

- 毒蛇山谷专用地面和8格物件：山岩、枯树、碎碑、藤门、灌木、裂隙、路标和洞口。
- 山谷矿区专用地面和8格物件：湿岩柱、洞壁、木支架、石笋、苔藓、深潭洞口、冷光矿灯和腐蚀图腾。
- 三张地图分别建立独立路线枢纽、物件密度、碰撞和灯光。
- 保持比奇—毒蛇山谷—山谷矿区—盟重的往返链以及红蛇、虎蛇、僵尸阵容和掉落正常。

## 验收

- `snake_valley_refinement_test`通过。
- `environment_batch_test`通过，40次跨主题切换无残留，静态内存变化约692KB。
- `wooma_region_refinement_test`通过。
- `mine_environment_refinement_test`通过。
- 修复两处验收脚本字段/类型错误；游戏运行代码无对应崩溃。
- 本阶段未导出APK。

