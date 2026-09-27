# 额度刷新后从这里继续

用户于 2026-09-26 批准 SOL6_AUDIT.md 的修复方案，并要求额度耗尽前尽量推进、保存完整进度。不是取消任务。恢复后不要重新询问方案许可。

## 基线与现场

- 主树：C:/Users/Administrator/Documents/HardCore，codex/integration，起点 f5d6308f53162509bffd30f6981987cbfe80fa68。
- 用户既有 AGENTS.md dirty 与大量 untracked 资产、工具、uid、chatgpt_share 目录必须保留；不能全量 add、restore 或 clean。
- 审计覆盖 78a79797..f5d6308f 的 13 条提交记录。正式测试 6 PASS/1 FAIL；w6_visual_contract_test 两条 add_child/move_child 引擎错误源于本轮368a16e6，不是无关历史基线。
- 用户已验收原版技能画面及火墙混合效果，冻结素材、尺寸、时序、锚点、遮挡与玩法；不得为了性能降低怪物数量或删碰撞。
- 名称最新要求（2026-09-27 再次明确）：物品落地后保持自己的位置，名称固定在自身图标正上方；允许长名称重叠，取消名称避让和整片重排。F04 已落实，见本目录 F04_IMPLEMENTATION.md。
- 用户旧角色和朋友老存档必须保留；F02 的代际隔离、旧版写回与故障恢复本地修复已通过，见 F02_IMPLEMENTATION.md。实际新→v93→新 APK 往返仍 NOT_RUN；不能把本地测试当作手机降级验收。
- 用户此前安排自己另开 GLM 临时树处理怪物寻路/包围，要求主控审计后再合入一起打包。当前没有审查或合入那棵树。锻造树排除。

## 已批准顺序与待办

1. F01：修原子保存成功后备份序号推定错误，防清理误删恢复日志。本轮先处理；下面进度会更新。
2. F02：已实现代际隔离与导入恢复，本地回归 PASS；实际 APK 往返待验收。不能简单忽略 death_event_gap 或只提升 SAVE_VERSION。
3. F06：建角失败恢复旧角色时完整恢复世界账本运行态（含世界数据、序号和脏标志）；审计方法链已复现。
4. F03：死亡日志只写必要变化；统一串行后台持久化执行器，保持提交/失败/恢复语义。现在死亡仍全量 world_state、主线程 JSON/flush/回读；拾取准备仍先同步 checkpoint。
5. F04/F05：简化名称锚点、分离结算与显示队列，保持一件/两帧的表现选择和碰撞落点规则。现有测试 test_mode 绕过生产节奏，需补真生产路径。
6. F07：修雷电背景节点初始化顺序；推广火墙局部 Screen 混合只作为候选，需要同背景、叠加、遮挡视觉验收。
7. 审计怪物工作树，验证后整合。最后统一回归与 APK；不打包已知失败源码。

## 证据

- 本目录 SOL6_AUDIT.md、audit_probe_results.json、audit_recovery_results.json 保留审计快照。
- 可复现探针与日志：outputs/test_logs/sol6_audit_20260926/；隔离数据 .godot/runtime_appdata/sol6_audit_20260926。
- 初始 runner：outputs/test_logs/runner_results_adhoc_20260926_084917_263_7440.json（3 PASS/1 FAIL），runner_results_adhoc_20260926_085509_435_23152.json（3 PASS）。
- APK/DEVICE TEST：NOT_RUN；本轮没有接触真实手机存档。

## 本轮施工进度

已完成五项局部修复，尚未 commit/push：

- F01：`player_state.gd` 的 `_promote_verified_json` 输出实际轮换结果，`_backup_sequence_after_promotion` 统一计算备份序号；保留旧备份的异常路径读取并校验实际备份，不能核验时阻止清理推进。正常已验证字节路径沿用已知主档序号，不额外反复解析大存档。人物同步保存、世界检查点与拾取提交三处接入。
- F06：建角事务运行态快照/回滚补上 world_monster_respawn_state、死亡/主档/备份/世界快照各序号与 dirty 标志。测试直接执行生产 snapshot→reset→restore，再继续死亡提交、保存、重载；完整 create_character 磁盘故障注入仍 NOT_RUN。
- `tests/world_monster_clock_persistence_test.gd` 新增 profile/world/pickup 三种损坏主档→保存→清理→再次恢复场景，以及创建失败回滚方法链。全部使用隔离存档、test_mode=false。
- F07：`caster_skill_animation_player.gd` 将 BackBufferCopy 改为动画节点自有子节点，show_behind_parent=true、相同相对 Z 层；避免子节点 _ready 时修改尚在初始化的父节点。首次绘制前同步挂载，随特效自动释放，重新配置时立即隐藏待释放的旧拷贝。保留现有 shader、全屏拷贝模式、资源、时间与锚点。此项修复节点生命周期，未完成像素/手机验收，也未消除其他技能的全屏拷贝成本。
- F04：`loot_name_layout.gd` 取消排序、邻居避让和名称重排，正式注册只定位新物品。管理器移除新增/拾取/消失/筛选/位置更新触发的全地图名称扫描；名称按自身宽度居中在图标上方。地形碰撞、落点规则、物品身份、拾取与过滤行为保持。`ground_names_test.gd` 改用用户最新固定位置合同，覆盖 150 件逐批出现、金币、超长名称允许重叠、移除一半、筛选及物品移动。F04 最新证据见 F04_IMPLEMENTATION.md。
- F02：`player_state.gd`、`world_monster_clock_ledger.gd` 新增世界账本代际隔离；旧版回存导入新代，人物最新数据与旧版世界数据保持，原文件归档。世界基线、带标记主档和匹配备份全部成功后才可进入游戏；失败可续接。旧版初次拆分留下的未标记主档通过精确原归档识别并保留已提交奖励。清理、备份恢复、建角回滚和删除角色均接入代际；已补快速保存缓存的未知/空代际区别，避免误清事件。完整架构、失败分类、测试与 v93 世界时钟限制见 F02_IMPLEMENTATION.md。

TDD 与回归证据：

1. F01 先失败：`runner_results_adhoc_20260926_090740_560_21500.json`，三个保存路径均出现实际备份1/记账2断言失败。
2. F01 修复后 5/5 PASS、0 引擎错误：`runner_results_adhoc_20260926_090855_855_6004.json`。场景：world_monster_clock_persistence、ledger、legacy_migration、profile_business_validation_recovery、repair_20260913/loot_async_durability。
3. F06 先失败：`runner_results_adhoc_20260926_090927_401_9088.json`，回滚后世界状态断言失败。
4. F06 修复后最终源码 3/3 PASS、0 引擎错误：`runner_results_adhoc_20260926_091019_347_640.json`。场景：world_monster_clock_persistence（含全部新场景）、multi_character_save、character_delete_transaction。
5. F07 先失败：`runner_results_adhoc_20260926_091349_396_9544.json`，两条 add_child/move_child 引擎错误加一条节点归属断言失败。
6. F07 修复后第一组：`runner_results_adhoc_20260926_091455_232_364.json`，w6、skill_visual_cold_lifecycle、fire_wall_animation_batch PASS；caster_skill_visual FAIL，因为旧断言写死前一个兄弟节点。将它更新为新的自有子节点、同 Z、show_behind_parent 断言，没有删去 Screen 混合检查。
7. 更新测试后 `runner_results_adhoc_20260926_091536_995_22500.json`：w6（另补释放时无孤儿拷贝断言）、caster_skill_visual 均 PASS，0 引擎错误。冷加载/火墙已在同一生产代码上通过，未重复运行。两份 F07 结果也保存于本目录，注意第一份包含已分类/已修的旧测试失败，不可称第一组全通过。

8. F04 首次专项两项 PASS：`runner_results_adhoc_20260926_191029_373_1392.json`；后续三项回归 PASS：`runner_results_adhoc_20260926_191133_322_15032.json`。前次会话的进程句柄已经失效，但落盘结果完整，已于 2026-09-27 核对全部进程退出码与引擎错误数。收尾增加金币/超长名称后重新执行五项回归，最终结果见 F04_IMPLEMENTATION.md。

9. F02：`runner_results_adhoc_20260927_080352_505_8000.json` 7/7 PASS；`runner_results_adhoc_20260927_080605_391_15112.json` 8/8 PASS；补快速保存缓存恢复断言、复现并修正后，`runner_results_adhoc_20260927_080734_669_12548.json` 最终复验 3/3 PASS。全部零引擎错误；两组回归共 14 个不同场景，最后三项为有针对性的重复，不宣称全套都在最后重跑。

以上 JSON 都位于 outputs/test_logs/，关键结果也复制到本目录。HEAD 仍为 f5d6308f，五项修复保存在主树工作区；用户既有 AGENTS.md 未改动。生产改动：player_state.gd、world_monster_clock_ledger.gd、caster_skill_animation_player.gd、loot_name_layout.gd、loot_pickup_runtime_manager.gd、loot_pickup.gd；测试改动：world_monster_clock_persistence_test.gd、world_monster_clock_legacy_migration_test.gd、world_monster_clock_ledger_test.gd、character_delete_transaction_test.gd、w6_visual_contract_test.gd、caster_skill_visual_test.gd、loot_ui_20260914/ground_names_test.gd。另有本目录报告、补丁/哈希与 PROJECT_CURRENT_STATUS.md 续接入口。

### 下一步直接执行

先重新核对当前 Git（其他任务可能继续写入），保留本轮差异。F04 固定名称已经落地，无需再设计拥挤避让；F02 本地修复已落地，不要重做代际方案。下一项直接处理 F03 主线程持久化，再处理 F05 结算与显示队列分离；继续执行已批准方案，无需再问常规内部选择。F07 节点生命周期功能测试已通过，后续仍需与已验收画面进行同背景/叠加/遮挡的真实渲染对照。最后合并审计怪物树、统一回归与 APK；不要打包已知失败源码。不要推送整个 dirty 工作区，不包含 AGENTS.md、锻造树或无关资产。

F03 接口约束：后台请求必须冻结 profile_id、world_clock_generation、sequence 和不可变 payload，不能在任务完成时再从活动角色推导写入目标。F02 的旧档导入属于加载边界上的一次性事务，不能移成未完成就允许开始游戏。现有按字节校验的保存快路没有解析 previous_generation 时收据返回 null；null 不能当作空代际，否则会重复引入误清日志缺陷。
