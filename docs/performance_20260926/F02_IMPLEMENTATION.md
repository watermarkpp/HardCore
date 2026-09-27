# F02：旧版回存与世界账本代际隔离

日期：2026-09-27。基线：`codex/integration` / `f5d6308f53162509bffd30f6981987cbfe80fa68`。本项在现有 F01/F04/F06/F07 工作区改动之上继续，未提交、推送或构建。

## 根因和边界

v93 源码 `672811a135ddf0f4d8048a6a0eb11e92dee48dc4` 的人物保存只序列化自己认识的字段，包括内嵌的 `world_monster_respawn_state`，不保存新增的 `death_event_sequence`。新版再次读取旧版写回文件时，人物序号为 0，独立世界快照可能已经到 N，旧事件已被合法清理，导致 `death_event_gap`。直接忽略 gap 可能回退奖励或覆盖旧版最新的人物进度。

同时，早期时钟拆分代码在首次旧档加载后只写归档和世界快照，人物主档仍保持旧格式直到下一次保存。这个状态可能已经有新版提交的死亡奖励，不能把所有无序号文件一律当成全新导入而丢掉它们。

## 实现

生产文件：`scripts/player_state.gd`、`scripts/world_monster_clock_ledger.gd`。

1. 新增持久化字段 `world_clock_generation`，为空表示原有账本命名空间；旧档导入使用独立的 32 位小写十六进制随机标识。人物、快照和事件必须匹配角色 ID 与代际。使用 Crypto，不消耗玩法随机数。
2. 旧版回存导入后，人物进度沿用该文件；世界初始状态来自该文件的旧版世界记录。新空间为 `world_clocks/<profile>/<generation>.json` 和 `death_events/<profile>/<generation>/<sequence>.json`。旧代文件保留，后续事件不会串到旧代中。
3. 导入顺序为：完整旧档归档 → 新代世界初始快照 → 带新代标记的人物主档 → 同代恢复备份。进入游戏前必须全部成功。导入中的 `world_clock_import_source` 是旧档语义摘要，用于精确核验并续完备份转换；正常人物保存后不再携带这个临时字段。
4. 导入失败禁止后续运行态覆盖原人物；主档临时文件写失败时原主档字节不变，备份转换失败时原备份保留。下一次加载可完成导入。原档语义归档保存在 `clock_import_backups`，原子备份转换还保留原备份字节。
5. 对早期未给人物标记的正向迁移，只在 `clock_migration_backups/<profile>-<digest>.json` 确实匹配当前源文件时继续读取原事件流。该流的缺口、损坏仍拒绝加载；不忽略错误。新导入采用不同归档目录，失败重试不会伪造旧迁移证据。
6. 清理请求捕获角色 ID、代际和安全序号。建角失败运行态回滚包含代际。删除角色时按精确 ID 处理各代快照、事件和导入备份临时文件，保留其他角色数据。
7. 自审补住 F01 与新代际交叉处：字节校验快速路径不解析前一代际，收据使用 null 表示未知；未知时沿用已知的旧主档序号，不把未知当成空代际从而过早清理事件。没有为此增加每次保存的 JSON 解析。

SAVE_VERSION 仍为 10；未修改游戏稳定 ID、包名、版本号、地图、怪物、技能、美术或掉落合同。代际是存档内部身份字段，不是新增玩法 ID。

## 本地验证

存档专项使用 `test_mode=false` 和工作树隔离用户目录，运行真实文件写入、备份、恢复、后台事件清理。未读写真实手机存档。

| 场景 | 结果 |
| --- | --- |
| 新版事件已清理后，按 v93 相关字段语义回存，再升回新版；重复两轮 | PASS |
| 等级、经验、金币、背包数量、装备实例及旧版世界截止时间保留 | PASS |
| 新死亡尚未人物检查点保存时，主档损坏，从同代备份恢复事件 | PASS |
| 主档/世界检查点进度不同，快速保存后再损坏，保留备份所需事件 | PASS |
| 导入主档临时文件失败、备份临时文件失败，拒绝覆盖并可续接 | PASS |
| 早期未标记的正向迁移已有死亡事件，导入后保留奖励 | PASS |
| 不同代事件拒绝串用，代际初始快照缺失拒绝加载 | PASS |
| 清理不动其他代日志；删除不动其他角色文件 | PASS |
| 创建失败快照/回滚后继续在正确代际提交死亡事件 | PASS |

正式命令均为 `./tools/run_godot_tests.ps1 -TestPaths @(...) -TimeoutSeconds 30`，具体 TestPaths 完整列在对应 runner JSON 中：

- `F02_regression_results.json`：7/7 PASS、0 引擎错误，原始 `runner_results_adhoc_20260927_080352_505_8000.json`。world_monster_clock_ledger、legacy_migration、persistence、character_delete_transaction、multi_character_save、profile_business_validation_recovery、loot_async_durability。
- `F02_related_regression_results.json`：8/8 PASS、0 引擎错误，原始 `runner_results_adhoc_20260927_080605_391_15112.json`。legacy_migration、shared_warehouse_migration、shared_warehouse_transaction、warehouse_prepared_transaction、bank_prepared_transaction、safe_logout_save_failure、loot_stable_identity_save、enemy_mass_death_batch_pipeline。
- `F02_final_retest_results.json`：快速保存收据修正后的 3/3 PASS、0 引擎错误，原始 `runner_results_adhoc_20260927_080734_669_12548.json`。legacy_migration、persistence、loot_async_durability。上两组共 14 个不同场景，不宣称所有场景都在这最后三项中重跑。

先失败证据与分类：

- `075525_371_8528`：新增旧版回存测试复现 `death_event_gap`，生产缺陷。
- `075844_965_22892`、`075918_479_5372`：迁移已完成，但测试直接比较未经过 JSON 读回的内存值/字符串与读回文档；改为比较相同反序列化层级的完整语义摘要，并保留字段断言。属于测试表示层差异。
- `080226_008_22052`：新增零序号缺失基线和删除新代文件两项失败，补齐生产守卫与文件生命周期后通过。
- `080651_689_23128`：新增不重置缓存的真实快速保存恢复测试失败；null/空代际混淆，生产缺陷，最终三项复验已通过。

## 未做的验收与后续约束

- APK BUILD：NOT_RUN；实际 v93 APK → 新版 APK 安装和存档往返：NOT_RUN。当前测试根据核对过的 v93 字段写回行为构造文件，不冒充执行过旧 APK。
- v93 本身不会读取新版独立世界时钟。降级期间世界刷新按 v93 自己加载/保存的状态运行；本修复不能让已经发布的 v93 自动理解新代目录。人物进度兼容与跨版本完全相同的世界刷新状态是不同的验收项目。
- 导入归档及旧代记录保留作恢复依据；本项没有新增自动批量清理旧代策略。不能为了省空间删除仍可能被旧人物备份引用的记录。
- 这是存档安全修复，不是帧耗时优化结论。F03 主线程同步 I/O 与全量世界事件、F05 结算/显示队列仍待施工。
- F03 的后台任务必须冻结 `profile_id + generation + sequence + payload`，完成回调不能依据当时的全局活动角色重新选择写入目录。此身份合同也适用于拾取准备、检查点与清理请求。
