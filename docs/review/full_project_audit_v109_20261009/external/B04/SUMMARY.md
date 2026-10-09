# HardCore 109 · B04 第一批精细审查（死亡奖励、掉落、拾取、装备与库存）

## 固定审计依据与状态

- 固定审计源码：`172125ae99e3c4adf19af82da2720934a52f9537`；仓库：`watermarkpp/HardCore`；分支：`codex/v108-runtime-bug-review-20261009`。本报告所引用的生产代码与规则均来自该SHA；最终报告提交的父节点可能不同，不允许用新父提交的源码替换本审计来源。
- `AGENTS.md`、`PROJECT_CORE_CONTRACTS.md`、标准提示词、BATCH_04.md、SCOPE及完整AUDIT_SCOPE_MANIFEST已从固定Git对象读取。manifest GitHub文本接口对大文件返回空正文，实际使用授权设备上的`git show <exactSHA>:path`与`git ls-tree -rlz <exactSHA>`只读取得。
- B04指定的176条文件路径全部在固定树存在，并已逐一读过Git blob字节/JSON结构；其中**19项源核心函数语义审查**、**11项正式数据权威绑定语义审查**，其他根据真实深度分别保留为历史资料角色审查、装备美术/编译源部分、地图跨批、B04局部函数等类别。**字节读取并不等于176文件全量语义审查**，请见COVERAGE.json。大文件`GameRoot`/`PlayerState`仅追B04职责，其他留B08等。
- 本次GitHub仅新增报告文件，不改生产/测试/素材/人工作者资料、场景与配置；不运行Godot/native，不构建APK，不声称Android验收。**当前裁决：`B04_REVIEWED_WITH_CONDITIONAL_FINDINGS_AND_COVERAGE_GAPS`，非发布PASS。**

## 正式奖励与交易链（已核对）

1. **唯一死亡提交**：`EnemyActor.died` → `GameRoot._on_enemy_died`创建受地图/代际约束的唯一death-key → `_pump_enemy_death_work_queue`接受`QUEUED` → `PlayerState.prepare_enemy_death_settlement/finish_prepared_enemy_death_settlement`和`JsonPersistenceService`回执 → 成功`PERSISTING→SETTLING` → `LootRuntimeService.begin/advance_monster_drop_roll_job`继续按预算执行正式Sheet每槽RNG → `PLANNED/MATERIALIZING`同地图代际确认 → 地面`LootPickup`建立和`LootPickupRuntimeManager.register_pickup` → 终态`COMMITTED`。已经修复的PERSISTING锁死、探测项链来源计数问题**不重报**。死亡中异步失败、重入和退出屏障保留，未发现足以直接声称本SHA会重复写经验或奖励的充分证据。
2. **拾取持久化**：`LootPickupRuntimeManager`按Ground GU0.75半径与静态可达性查询 → `LootPickup.manager_evaluate_collection`设置一次`collection_pending`，发出item/gold提交 → `GameRoot._queue_loot_collection/_flush_loot_collections`冻结map/zone与角色存档身份 → `PlayerState.prepare_loot_save/finish_prepared_loot_save`后台JSON耐久提交 → 成功才`confirm_collect()`删除地面实体；失败`reject_collection`恢复拾取机会并在UI显示。Gold绕过背包重量，装备进背包依赖唯一ItemTransaction/PlayerState写入。可见通知由`LootFeedbackLayer`单一FIFO逐条排队展示，不可误用为存档成功的替代证据。
3. **装备物品事务与兼容**：`ItemTransactionPort.quote_new/quote/commit/_complete`对旧状态重新定价、校验同一profile/journal、异步文件成功回执后只更新相关槽位；`ItemTransactionJournal`单一序号、epoch、重复与退役回执拒绝；`ItemExtensionCodec`严格解析多层镶嵌实例、保留未知opaque数据并拒绝无法安全释放的物品，防止销售/转移破坏未知扩展。完整经济/商店全分支仍留B08，不将Port的专项审查等同整份PlayerState完成。
4. **资料唯一权威**：UserLootSheetProvider接入`assets/data/drop/dpv2_user_loot_sheet_authority_v1.json`，证据为126种怪、6083有效槽位；Sheet E为进入RNG前最终独立成功率，D为最终金币数，不叠加SPB/V5/v80/v81、全局乘数或“金币×5”。`tools/loot_sheet_compiler/compile_authority.ps1`从既有归档Sheet + 人工已批准指令生成运行文件，精确移除ID251探测项链的一条来源槽，不删除已拥有的实例；ID250技巧项链仍有两条现行掉落槽。Boss矿石token940000在成功后随机均匀落入纯度10–20的稳定ID，碎片ID950001独立进入catalog；白6/精英9/Boss12由GameData在发布时强检，保护priority保持。历史直连、21CQ、SPB和V5封存资料仅作证据，不可恢复为当前概率。
5. **人物死亡与特殊装备**：复活戒指在`PlayerCharacter`当前HP致命提交点检测`EquipmentRules.revival_cooldown_ms=300000`，触发后恢复HP、扣该装备耐久并仍计本次受击耐久；不触发GameRoot正式普通死亡扣经验。未触发时`GameRoot._on_player_death_requested`执行一次10%经验惩罚、锁定输入后UI最近城镇复活。麻痹普通5s/精英Boss2.5s；虹魔以输入伤害为吸血基准（用户已定）；隐身戒指须真实脱战恢复（既有合同）；技巧项链ID250在实例创建时从允许技能中**均匀选一个+1**，不赋予未学技能；神秘IDs218/219/220在掉落创建时按固定drop digest随机属性与相应穿戴要求，未生成新诅咒。
6. **价格与几率**：`equipment_price_candidates_v1.json`显式补全黑铁纯度ID940010..020主数据库价180000、碎片950001价200000、成品圣物徽章价400000、祖玛头像920032价2000000；`GameData._build_price_index`在独立候选来源收录，头像还走唯一稳定ID的覆盖规则；`PricingService.quote_sell`默认主库半价，得用户要求90000/100000/200000/1000000（不是把配置180000误当出售价）。`EquipmentRules.BLESSING_SUCCESS_RATE_MULTIPLIER=5`并用联合样本空间保留1~2幸运阶段准确五倍成功率；沃玛及以上小极品仅对生效随机属性结果采用3倍外门概率，作者文件`item_drop_affix_wooma_jp_policy.source.json`，运行生成使用V4稳定seed。上述为**静态合同核对**，不是本轮新native PASS。

## B04新增发现（详细触发、归因与最小验证参阅FINDINGS.json/csv）

- **B04-001（P2，条件性源表覆盖）**：固定正式怪物目录有152个`runtime_allowed && editor_placement.allowed`身份，而用户Sheet有126个profile；26个缺失，其中ID75等原来源曾有非空掉落行。正式缺profile返回空/未配置，不自动旧表回退。是否当前可刷/有意零奖励尚待发布地图和用户掉落合同核对；禁止直接补概率。
- **B04-002（P2，UI服务延迟风险）**：拾取成功反馈FIFO当前每条默认2.4秒，积压新事件无上限，一次100条可能使最后提示等待约4分钟。实现有意保证不丢提示，不能未经授权裁剪队列；先诊断真实输入吞吐和用户可接受的聚合。
- **B04-003（P3，资料激活状态表述漂移）**：编译器和运行Sheet仍写`status=PENDING_ACTIVATION`，但正式LootRuntimeService已用它作唯一奖励权威。属于机器元数据漂移，未证明影响玩家实际奖励；只能通过正式authoring在确认后对齐，不能因此关掉Sheet并回退旧表。

## 门禁与未覆盖

本批**未运行任何Godot测试**、没有手机掉帧/奖励分布或APK验收。Source binding中176个路径精确Git blob SHA，COVERAGE明确划分已审函数与未完整审查。其余38项装备视觉/编译资料与68项“名字含death”但实质是地图编辑器/发布源，只读校验身份，B05/B06/B07才审其真实功能；大文件其他职责留B08。31类跨模块消费者只追B04投影，不冒充全源审完。**主控可将B04作为发现项与必要补审输入，但不以此直接封装109。**
