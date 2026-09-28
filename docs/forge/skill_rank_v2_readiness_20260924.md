# 装备技能等级突破 V2：本地回归与性能准备

基线：`78a797973409c0ce47590b928f3d26ff067fe567`。施工树：`codex/forge-ui-20260923`。本报告只记录当前工作树的源码验证，不代表 APK 或手机实机验收。

## 回归前置条件

- `warrior` 组的 `complete_client_resource_catalog_test` 消费本地生成物 `outputs/resource_catalog/complete_client_frame_catalog/manifest.json`。锻造工作树原本缺少这套扫描结果；从同一主仓库的既有完整扫描产物复制到该工作树的独立 `outputs` 后，对三个文件逐个核对 SHA-256：manifest `602ead7af15bb8ed7f3114a6c51f24b60f911774aedfe0152a8bb7c7fd60d9f6`，SQLite `4c96ed1aae5ecb1e2660a2a58ae0007e17a87a2ce049d4b16d1925d327ea380a`，候选图 `22ae57084daad2ba115596367ee921f504375c20279544f8e86e0c515c9082b4`。这三项是本机忽略的生成物，未写入主树，也不纳入 Git。
- `player_movement_respawn_test` 原先使用共享 `user://` 角色与仓库路径，因既存测试用户目录状态导致建角失败。该测试现在使用独立角色目录、索引和共享仓库路径；生产存档路径、仓库验证与交易逻辑未改。

运行 `pwsh -NoProfile -File tools/run_godot_tests.ps1 -Suite warrior -TimeoutSeconds 30`：28/28 PASS，0 条引擎错误。结果：`outputs/test_logs/runner_results_warrior_20260924_144612_653_19896.json`。在新的本地工作树复现该组前，必须先用正式扫描工具生成上述客户端目录，或提供哈希一致的同源缓存；缺少外部客户端扫描产物时目录测试会明确 FAIL。

同一份源码上，`taoist_critical` 为 17/17 PASS，`skill_execution_plan_critical` 为 10/10 PASS，`skill_production_migration_critical` 为 11/11 PASS；锻造／合成相关专项 11/11 PASS。33 技能 Rank 0～3 的 132 行对照矩阵、多骷髅存档合同、宠物攻击结算、技能面板和词条 rollout 的最终专项复测为 7/7 PASS。上述各组引擎错误均为 0；详情见同一工作树 `outputs/test_logs/runner_results_*_20260924_*.json`。词条 rollout 专项只验证禁用状态和可注入生成规则，没有开启真实掉落。

## 多骷髅本机 CPU 对照

`tests/skeleton_multi_performance_test.tscn` 经正式 7 级召唤入口创建三只独立 `SummonActor`，在同一已载入场景内固定其他物理更新，预热 300 帧后，以 60 Hz 模拟每档 1800 帧，按 1、2、3、3、2、1 只执行相同的宠物 `_physics_process` 路径。所有敌人移至索敌范围外，以量出待机、编队和周期索敌的新增成本；测试断言索敌次数和时间没有随宠物数量出现数量级放大。

| 同时推进的骷髅 | 平均 CPU 时间／模拟帧 | 每档两次索敌次数 |
| ---: | ---: | ---: |
| 1 | 8.74 µs | 113、112 |
| 2 | 17.47 µs | 225、225 |
| 3 | 26.90 µs | 338、337 |

三只相对一只约 3.08 倍。该场景的索敌使用共享 `RuntimeCombatSpatialIndex`，没有对全场敌人或全场宠物逐帧扫描；技能 More 倍率在生成／等级变更时缓存。命令：`pwsh -NoProfile -File tools/run_godot_tests.ps1 -TestPaths tests/skeleton_multi_performance_test.tscn -TimeoutSeconds 30`。结果：1/1 PASS，0 条引擎错误，`outputs/test_logs/runner_results_adhoc_20260924_144646_192_5928.json`；原始采样在同目录的 `skeleton_multi_performance_test.stdout.log`。

该测量只覆盖本机 headless 下的多骷髅 CPU 增量，不等于 Android 帧率、GPU、密集怪物交战或发热结论。APK 与设备测试均为 `NOT_RUN`。技能等级装备词条的掉率、可出现部位和权重尚未确定，rollout 开关保持关闭。
