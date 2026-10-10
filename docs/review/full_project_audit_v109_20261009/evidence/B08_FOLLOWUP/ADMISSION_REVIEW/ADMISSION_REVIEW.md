# B08 profile admission — 只读源码审查

审查工作区：`C:/Users/Administrator/Documents/HardCore`。固定审查提交为 `dbb1bd0878ab24a4e5bd6a1877d32f304f5623e5`，实际工作区 HEAD 为 `215f0b2f651a51e6855ee813ddd99221690311a1` / `codex/integration`。当前未提交 B08 生产候选与固定审查提交分开记录。

本专项只读生产和已有测试，仅新建本目录的审查文档/证据。没有修改生产、既有测试、runner 或 Git index，没有执行 Godot 原生测试。源码审查不能替代原生验收；本专项原生状态为 `NOT_RUN`。

## 结论与精确输入

admission 主链修复为 **NO_BUG（静态范围）**：checkpoint 前置、复用正式原子 writer、保留备份清理水位、失败选择 B 后恢复 A、技能候选提前验证并一次采用、plural pet 路径统一恢复 quest。首次在 `166f79…` 找到 **BUG：非空 writer identity override 缺少 generation 键时，可以借空 generation 兼容规则接受未知第二键**；主控随后已修复，`a95fe0…` 的最小 delta 复核为 `PASS`（静态），该反例证据仍保留。当前指定范围未见未修复的新生产 BUG。结论不扩大到整个加载链的任意故障、任意重入或所有晚期动作。

实际核验的关键源：

| 文件 | 当前 SHA256 |
| --- | --- |
| `scripts/player_state.gd` 首次主审查 / Native63 freeze | `166f791b306289c9b3c717cec59a757bbb60e7184848d001bc0ee2159e7eeebb` |
| `scripts/player_state.gd` 当前主控 guard 修复 / 最小 delta 复核 | `a95fe0b6875196b92e60a1e429f2915bfcdea9db772399ffe6fd18f18da90185` |
| `scripts/game_data.gd` | `dd452fdb61e07c60b7d187b1a3e48bfd98d2fe03fdc36b39345d214a06c9d7f3` |
| `scripts/equipment_rules.gd` | `5c3676412d0c490fdab0d78e7b8b63a5dbc88117193d3a8bde3b63d9a2cf21f8` |

附带源码指纹、固定提交 blob、Native63 原始证据指纹和只读诊断结果见 `SOURCE_REVIEW_RECEIPT.json`。除下面明确标注的修复复核外，正文行号绑定首次 `166f79…` 版本；最新 `a95fe0…` 从 writer guard 后行号偏移 +4，语义相同。整文件最小 diff 证明确仅这段 guard 改变，见 `IDENTITY_GUARD_MINIMAL_DELTA.diff`；其他源码变化后不能直接复用本结论。

## 固定审查提交到本地候选的映射

| 审查点 | 固定 dbb1bd 行为 / 行号 | 当前行为 / 行号 | 静态结论 |
| --- | --- | --- | --- |
| checkpoint 失败不能发布 B | `load_save` 从 7090 起发布 level 等；7230 最后 checkpoint，失败时 B 字段已发布 | 7139–7156 构造加载候选并 checkpoint；7157–7163 content commit；7173 才首次发布 level | NO_BUG：checkpoint 拒绝在角色发布和 content commit 之前 |
| 同一 writer | 5546 `_checkpoint_world_clock` 内直接调用 `_write_json_atomic` | 5552 live wrapper 与 7148 admission 都调用 5572 helper；5596 调用正式 `_write_json_atomic` | NO_BUG：没有增加第二套持久化权威 |
| 备份水位 | checkpoint 根据本次 `_last_json_promotion` 求旧备份 sequence | 5601 在本次 writer 返回后立即求水位；7235–7237 采用 helper 结果 | NO_BUG：不以 latest sequence 覆盖旧备份水位 |
| B 失败恢复 A | `select_character` 9966 将 active ID 置空 | 10011–10024 记录 A ID/block，B 失败恢复 A，并恢复原已阻止的 A block | NO_BUG：A 保持当前角色，原 A save block 不被失败 B 解锁 |
| 技能晚期拒绝 | 7123 在 level/inventory/equipment 等发布后向 live service 加载，并可 `invalid_skill_identity` 早退 | 7067–7075 私有新 service 校验；7200 只采用已成功的同一对象 | NO_BUG：不再重复执行可失败的技能导入 |
| plural pet 的 quest 恢复 | 7158 `quest_states` 缩进在 singular compatibility `else` 内 | 7227 位于 plural/singular 分支之外 | NO_BUG：两种存档均采用 replay/parsed quest |

比较命令使用 `git diff --ignore-space-at-eol dbb1bd -- scripts/player_state.gd`；普通 diff 会将 CRLF/LF 差异扩展为大段无关替换。忽略行尾差异的 PlayerState diff 为 147 增 / 90 删。

## checkpoint、原子 writer 身份与水位

`_checkpoint_world_clock()`（5552–5569）先 drain 已接受的 world writer receipt，之后才把 live state 与 live watermarks 传给 helper；成功后才采用结果。`_checkpoint_world_clock_snapshot()`（5572–5607）用其参数构造 document，既不读取 A 的 respawn state 作为 B 的输入，也不提前写 live watermarks。失败结果带回原参数水位和 dirty；调用方直接 block/return。

正式写入链是 helper → `_write_json_atomic()`（5860–5896）→ `_world_json_persistence.submit/finish` → `JsonPersistenceService` → `JsonPersistenceJob`。ItemExtensionCodec 的正式编码/校验、路径业务验证、临时文件写入与 readback、原主档/备份字节检查、rename promotion 和 receipt 均复用，没有 fixture loader 或新的写档实现。

显式 `world_clock_identity` 的精确边界（5874–5883）：

- 空字典保留既有调用行为，以当前 active profile/generation 构造请求身份。
- 非空字典必须 size 为 2；源代码使用 `get("profile_id", "")` 与 `get("generation", "")`，**没有显式检查 generation 键存在**。缺 profile ID 被拒绝；缺 generation + 未知第二键的 legacy 路径反例可以通过，不能描述为精确两个键集合已受约束。
- profile ID 经 `str()` 后必须非空、无 `/` 或 `\`，且不是 `.` / `..`（6042–6048）。此为既有 storage ID 合同，并非新增 UUID-only 限制。
- generation 经 `str()` 后必须满足 `valid_generation()`：空字符串代表旧 namespace，或精确 32 个小写十六进制字符（clock ledger 80–90）。
- `path` 必须精确等于 `_world_clock_path(target_id, target_generation)`；只具有同一 prefix、另一个 profile/generation、profile 主档路径均被拒绝。
- 这是合法字符串表示与精确路径约束；**不是原始 Dictionary value 的严格 String 类型约束**，因为源代码明确先 `str()`。helper 的正式调用来自 String 参数，不产生非 String 值。

路径验证独立于上述请求 metadata：`_json_validator_for_path()`（5311–5314 / 5319–5320）从真实目标路径绑定 profile ID/generation；`_validate_world_clock_document_status()`（5342–5352）再调用 `valid_snapshot()`（ledger 93–104）验证 document 的身份、generation、非负整值 sequence 和 world state。错误 document 身份不能仅靠合法 override 通过。coordinator 在 candidate 与 previous/backup 的验证处都使用同一绑定 validator（service 203–205 / 227–240），promotion 前还检查两份原文件字节（job 194–199）。

### BUG — generation 缺键被空 namespace 接受

精确源码反例（未执行原生）：在测试自己拥有的隔离 profile root 中，`path = _world_clock_path("A", "")`；document 为正式 `WorldMonsterClockLedger.snapshot_document("A", 0, empty_snapshot(), "")`；调用 `_write_json_atomic(path, document, false, {"profile_id": "A", "extra": true})`。

按 5876–5880 的实际条件：size=2；target ID=A 合法；不存在的 generation 经 `get` 得到空字符串；`valid_generation("")` 在 ledger 83–84 明确返回 true；path 精确相等。其后 document/path validator 也接受合法 A/空 generation snapshot。因此这份错误键集合不会在 writer 的身份 guard 被拒绝，若 IO 正常可落盘。它没有跨 profile/错误 document 写入漏洞，但违背非空 override 精确两键的拒绝合同。不能在原生未跑时称运行已证明，此处是完整条件链静态证据。

建议主控最小修复：非空 override 在 size=2 之外，显式要求 `has("profile_id")` 和 `has("generation")`，再沿用现有合法值/精确路径/正式 validator。保留合法 `generation: ""` 的旧 namespace；不要将合法空 gen 与缺键等同。修复风险低，仅 malformed override 拒绝分支变化。必要负例为 `{profile_id:A, extra:true}` 对合法 legacy clock，真实 writer 必须返回 false 且无 clock/temp/backup 字节变更；正例保留显式空 gen 与 32hex gen。生产文件由主控处理，本专项没有编辑。

### 主控修复后的最小 delta 复核

主控当前 SHA `a95fe0b6875196b92e60a1e429f2915bfcdea9db772399ffe6fd18f18da90185`，只读复核 5875–5887：非空 override 必须 size=2、显式 has 两个键、两值是 String，才读取其值；其后仍用原 profile ID/generation/精确路径 guard，并复用原 writer。Native63 freeze JSON 的原始文件 entry SHA 精确为 `166f79…`；同次 private index 只读取出的 Git blob 为 `980cd7bc4c13e0c0aa15820a4ab3ab193ce520ae`，其标准化行尾 bytes SHA 是 `7c8d84…`，不能与工作区原始文件字节 SHA 混称。用该冻结 blob 与当前整文件 `--ignore-space-at-eol` diff 仅这一处 hunk，不修改 private index。

旧反例现在在缺 generation 检查处返回 false；unknown extra、missing profile、非 String 值也拒绝。合法显式空 generation 的 String 类型、合法 32hex generation 与默认空 override 保持接受路径。正式 helper 参数为 String 且构造完整两键，新增严格类型检查不改变这个生产调用。没有发现该 delta 新增 BUSY/watermark/validator 行为或另一 writer。**源码修复复核 PASS；Native65 / 真实拒绝与合法 IO 正例本专项 NOT_RUN**，由主控和新 fixture 代理执行，不能以静态关闭原生验收。

水位链：job 的成功 receipt 精确报告实际 `backup_rotated` / `backup_exists` / `backup_valid` 和 previous/backup document（252–264）；owner 的主线程 callback 保存该 receipt（PlayerState 5914–5939）；helper 立即调用 `_backup_sequence_after_promotion()`（5942–5967）。没有备份时取 current sequence；真实旋转时取 previous sequence；保留已验证旧备份时取该旧备份 sequence；未知/无效备份保持 -1。计算 `field="sequence"` 不依赖 A 的 live generation。profile 的 saved/backup 水位仍来自 B 的 replay（7232–7234），world 两个水位采用本次 helper 结果。

清理门槛继续是 profile saved/profile backup/world snapshot/world backup 的最小值（5615 起），本修复没有提升门槛或跳过日志。helper 在任何后续 profile/archive 写入覆盖 `_last_json_promotion` 前已得到自己的水位。没有发现 receipt 被另一个 profile promotion 偷换的同步路径。

## A 恢复与玩家发布边界

`select_character()` 在改 active ID 之前执行正式 transaction drain、durability save 与仓库就绪检查（9994–10004），然后保存原 A 的 ID/block。B 的 `load_save()` 在上述修复所涉及的拒绝路径上，不发布 level、角色身份、gold、inventory、equipment、技能权威或 world live watermarks；失败选择恢复 A ID。若 A 原本 blocked，原 ID/reason 同时恢复；若 A 原本可保存，B block 的 ID 与恢复的 A 不同，A 不会被错误阻止。正式保存仍在 6528 检查 active ID 与 blocked ID。

保留 B 的失败 `last_load_result` 是合理行为：其中 path/reason 仍指向失败的 B，不能改成 A 成功。失败 B 的重试必须重新加载/验证；成功入场仅在 7164–7166 清除匹配的 B block。第一次没有 A 的选择失败仍恢复空 ID。

此结论不是整个文件系统的无写入事务：备份恢复、已验证 world-clock migration、gold archive 和 account shared warehouse recovery 有自己的正式持久化权威。它们可能在后续拒绝前完成；本次变更保证 B 的玩家 hydration 不在 checkpoint/content admission 失败前发布。`_initialize_shared_warehouse` 可以采用独立的 account 仓库投影，不能把它描述为 B 的角色背包采用。legacy isolated fixture 的私人 warehouse 赋值已推迟到 admission 成功之后（7168–7172）。

## 技能对象生命周期与消费者

新 `prepared_progression` 是 RefCounted 私有候选。`SkillProgressionService.load_snapshot()`（119–186）将候选进度建在局部 Dictionary，仅全部身份/等级输入成功才赋值该实例的 `_progress`（179–180）；没有信号、PlayerState 写入或存档写入。失败时已存在的 live service 没有收到这次导入；成功后 7200 采用这个已校验对象，7201 生成只读 learned IDs 投影。

生产 `scripts/**/*.gd` 全部 `_skill_progression` 命中都在 PlayerState 自身；没有生产消费者直接缓存/获得旧 service 引用，也没有返回 service 的 public getter。PlayerState 方法在调用时读当前成员。公开 `skill_progression_snapshot()` 返回 service 的 snapshot；snapshot 中 skills 是 `duplicate(true)`（service 189–193）。公开 `learned_skills` 是重新生成并 `make_read_only()` 的 ID→rank 投影（4109–4116），不是 service。player/game_root/skill_panel 消费这个投影；已有 accepted action lease 持有其动作快照是原合同，不是旧 skill service 悬挂引用。

技能 ID 解析使用登记的 EntityRegistry/固定 SkillDataLoader 真源。SkillDataLoader 57–76 / 133–161 没有本次 mode 可变条件，因此提前校验不需要先发布目标 mode。world-clock import 只转换 world-clock/奖励字段；其后 ItemExtensionCodec 是物品导入，没有再次把技能候选替换为另一个 payload。未发现新候选验证旧 mode、采用新 mode 后又技能拒绝的路径。

## Native63 数字表示失败的处置

本审查读取了原始 driver 与 runner：

- `outputs/wake_drop_v108_review_followup_20261009/B08_NATIVE63_DRIVER.txt`
- `outputs/test_logs/v109_direct63_mode_transaction/logs/runner_results_adhoc_20261010_111816_985_13792.json`
- invocation `e4206557-5f7d-4c76-9a40-eb0eca18261d`，framework run `a9f5302d-4dc1-482a-b4fb-bc1a09d83637`。

原始结果仍为 **FAIL**：60 checks 中唯一 CHECK53 失败，59 PASS；自然退出 code 1，timeout false，engine errors 0。不是原生 PASS。driver 215–216 显示 inventory/equipment 的整值 JSON 数字 int→float：`920001`/`920001.0`、count、item_id、weapon_luck/curse；列表顺序、所有键、字符串 instance ID 与数值大小相同。只读递归验证结果见 receipt；没有删字段或使用容差。

该分类合理：真正穿过 JSON 持久化边界的成功恢复比较应以同一 wire 表示比较完整结构。两侧都 JSON roundtrip、再比较全部结构，可去掉 Godot 原生 int/float 深字典严格类型差异，同时仍检查每个字段、字符串身份、列表长度/顺序和数值。正式 profile validator 用 `_is_integral_json_number()` 接受 int 和整值 float；它没有将类型严格一致作为保存后恢复合同。

测试修正只能落在成功序列化恢复比较。失败候选 `_unchanged` 的 live state 严格 `==` 与 owned bytes 比较必须继续保留，因为那里没有合法 wire roundtrip，int→float 就是实际 live 变更。不能增加全工程 numeric normalize，不能把非整值、字符串数字、bool 或近似值吞掉。Native63 原始 FAIL/receipt/日志/输入 freeze 保留；修改后的测试需要新一次固定输入原生运行，旧证据不能改称 PASS。

## 未扩大结论的风险与必要回归

晚期 `_commit_save(true,true)`（7278）与 `recalculate_stats()`（7284）的返回值仍被忽略；固定 dbb1bd 的相应代码在 7224 / checkpoint 后也忽略这些返回值。本轮消除了晚期 skill import 和 checkpoint 的明确失败出口，**没有将所有可能失败的晚期动作改为候选式发布**。`recalculate_stats` 在 feature loadout/stat 失败时确实可返回 false（3763–3772）。未据此无证据宣布本轮新增回归；若验收目标包含“任意 load stats/migration save 失败均不采用玩家”，还需要独立合同与真实触发证据。这两项不应被本专项 NO_BUG 隐藏。

必要原生回归按相关输入变化执行，不全套重复：

| 场景 | 必须保留的观察 | 当前本专项状态 |
| --- | --- | --- |
| 模式 profile failure/recovery | 真实 empty-maps candidate 拒绝；完整 live GameData / player / owned bytes 不变；block 保存；恢复同一完整 profile，恰一次 database 发布 | NOT_RUN；已有 profile wrapper，Native63 FAIL 原样保留，成功 wire 断言修正后需新原生 |
| checkpoint 真实 IO 拒绝 | 有有效 B clock 与待 replay event；只在隔离 B writer 临时目标建立真实写入冲突；拒绝 reason checkpoint_failed；A 与 B 玩家 hydration 均不误采用；原 profile/clock/backup bytes 保全 | NOT_RUN；本只读专项不新增 fixture/test |
| A→B 失败 | A 可保存与 A 已 blocked 两种；B 内容失败/无效技能/checkpoint失败；A 的 ID、mode/later、level/inventory/equipment/技能/水位保持，last_load_result 仍为 B failure | NOT_RUN；现有 profile wrapper只直接同 ID load，不等价覆盖 select_character rollback |
| checkpoint 水位 | B primary sequence n、backup m<n、replay latest k>n；成功后 world primary k / backup n，live watermarks k/n；日志清理≤四水位最小值；另测保留有效旧备份与 first baseline | NOT_RUN；复用 world_monster_clock_persistence / world_generation_persistence 相关覆盖及明确缺口 |
| writer identity负例 | extra/missing key、wrong ID/gen、wrong document identity、non-world target；拒绝无落盘；合法旧空gen和32hexgen保持正式兼容 | NOT_RUN；必须真实 writer/validator，不 mock submit/finish |
| 技能与 pet/quest | 合法技能成功采用；不合法技能在候选阶段不改A；公开snapshot不持旧service；plural和singular两条路径均加载B的独立quest | NOT_RUN；复用 profile_business_validation_recovery / multi_character_save 相关部分，补足未覆盖断言 |

上述建议保持 30s、完整正式 catalog、唯一 runner userdata 与 receipts。临时路径或 fault 仅由测试创建的独立 userdata owner 清理，不触碰真实存档、formal assets 或其他 run。

## 验证记录

只读源码定位、固定提交 focused diff、writer/validator/receipt 调用链以及引用搜索：`PASS`（静态范围）。直接 native：`NOT_RUN`。本目录外生产/测试写入：无。

普通 `git diff --check` 报告 equipment_rules/game_mode_service 新增 CRLF 行为 trailing whitespace，不能把这个原始输出称 clean PASS。以 `git -c core.whitespace=cr-at-eol diff --check -- <相关生产文件>` 检查真实行尾空白，exit 0 / `PASS`；没有为修格式修改生产文件。新文档以 LF 写入。

交付前再次核验所审查的生产 SHA，最终 receipt 对最新 `a95fe0…` 为 PASS；`SOURCE_REVIEW_RECEIPT_source_changed.json` 另保留 parent guard 改动发生后，旧 `166f79…` 绑定检测失败的现场，不将其伪装为同源复验。指纹及脚本采集输出是本地静态审查证据；新原生由主控冻结并执行。
