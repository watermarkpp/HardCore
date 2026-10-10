# B08-001–005 处置草稿（供 root review branch 接入）

这是现有证据整理稿，只新增本 Markdown 和对应 JSON；没有重新审生产函数体、运行测试、修改源码/已有测试/runner/index 或提交。记录截止 Native69 的实际结果：profile admission 完整52/52、自然退出0、engine0、runner PASS。本稿不授予当前同源完整 B08、全项目、APK109 或设备验收 PASS。

## 固定外部报告、接收与本地候选

外部 B08 审查源固定为 `dbb1bd0878ab24a4e5bd6a1877d32f304f5623e5`，tree `fef3e786da2a7462abdc069f48615215407f6a11`。八份正文为 SOURCE_BINDING.json、COVERAGE.json、SUMMARY.md、FINDINGS.json、FINDINGS.csv、REDUNDANCY.md、VALIDATION_GAPS.md、CROSS_BATCH_CLOSURE.json；另有 RECEIVE_RECEIPT.json。接收 commit `2d95b21cfe148b09ead5bba5ea7786dfa70e92e4`，parent `e3de5f54d0ce237c9bf0159ecc2d89c1a2c2a1de`。接收 PASS 仅证明八份报告字节接收，不是玩法通过；原文保持不变。

报告实际覆盖是 71 个固定 Git 源文件、3201 个函数声明、93 个定向函数体，长流程部分阅读。它明确保留全项目语义 MISSING，cross-batch fully_closed_by_B08=0；这些数不能当功能或性能通过数。REDUNDANCY 未证明任何可删除的生产/测试/数据/素材，既有 owner 与历史负例继续保留。

本地 `codex/integration` HEAD `215f0b2f651a51e6855ee813ddd99221690311a1` 上的八文件为 LOCAL B08 修复候选，不能写成外部固定 dbb1 已包含这些修复。最近 Native69 候选 tree `1180b2a65b445192d73704fadfc629554590f337`，真实输入2553，fingerprint `c777d9d737e8b2588deb6084d67cf2ec25e0b2afb1bfa0efe536d23f703b5611`，postverify PASS证明输入/引擎/index未变。对照68/69实际freeze条目，下列八个生产文件原始bytes/SHA均相同；69只修fixture空数组hash guard后重跑profile admission。

| Native68/69 相同生产输入 | 原始文件 SHA256 |
| --- | --- |
| `scripts/equipment_rules.gd` | `5c3676412d0c490fdab0d78e7b8b63a5dbc88117193d3a8bde3b63d9a2cf21f8` |
| `scripts/game_data.gd` | `dd452fdb61e07c60b7d187b1a3e48bfd98d2fe03fdc36b39345d214a06c9d7f3` |
| `scripts/layers/runtime/content_layer_registry.gd` | `cf3042e27a4247311d79a7453f1357697d3056975d7f50a8714f5ecbf492cdc5` |
| `scripts/layers/runtime/game_mode_service.gd` | `f7644b5358963a1a469db756bb6e3933c314b1173a3a6a766c88c669e5710d0a` |
| `scripts/layers/runtime/prepared_content_configuration.gd` | `cf9cb0b72a9fa37635caa91237492e7221c4965ff400b548b29b7396b07a725e` |
| `scripts/layers/runtime/runtime_service_facade.gd` | `72f4629cd27ffca2eb4f36c82be989dc99f2c6ca56e29496513566582f7b0c37` |
| `scripts/player_state.gd` | `a95fe0b6875196b92e60a1e429f2915bfcdea9db772399ffe6fd18f18da90185` |
| `scripts/startup_loading.gd` | `605eae695b3b1d297b43710894023e2b4a0f692b0edbbe00b2a7e70c18fc0c62` |

Git 标准化行尾 blob 与工作区原始 bytes SHA 是不同指纹，不能混用。详细 binding、八份原始报告 receipt 和每个阶段的 scene/run/invocation 见对应 JSON。

## 发现到修复/证据/剩余验收的映射

| ID / 固定源分类 | 本地修复与已验证证据 | 当前验收边界 |
| --- | --- | --- |
| B08-001 / P1 PRODUCTION_CONTROL_FLOW_BUG | 既有 ContentLayers/GameData/GameModes 唯一 owner prepare/完整正式 catalog 验证/adopt 后协调提交；READY启动边界保留。Native61 input_composed81/81 clean runner PASS；Native62 stale51/51、failure_boundary95/95 clean PASS。 | 局部组件 PASS；不能拼不同源码阶段为当前完整同源 PASS；全 UI 动态调用与 Android不在该证据内。 |
| B08-002 / P1 PRODUCTION_CONTROL_FLOW_BUG | RuntimeServices 传播失败；later setter采用正式协调内容提交与 bool 保存结果。Native62 later39/39、failure_boundary95/95 clean runner PASS；真实API无成功信号的拒绝路径有组件证据。 | facade/later API组件 PASS；仍不证明每个外部UI/dynamic caller。保持后来开关正式字段/存档权威，不建第二条reload。 |
| B08-003 / P1 PRODUCTION_CONTROL_FLOW_BUG | mode+later在migration/hydration前准备；B的必要checkpoint走同一writer先成功，再content commit/发布角色；失败block并恢复A。Native64 profile60/60 clean PASS。Native69真实TMP失败、A完整状态与水位/特征对象、B save guard、同B移除fault恢复等52/52 clean runner PASS。 | Scoped admission组件 PASS；Native68 runner FAIL engine11独立保留。仍不表示全部晚期动作已候选化或当前完整同源B08集成通过。 |
| B08-004 / P2 CONDITIONAL_PRODUCTION_STATE_RISK | candidate拒绝不污染live；直接load失败清61catalog字段、unloaded、保留error；价格/item读者禁止lazy重新加载。Native62 direct173/173业务receipt PASS；Native61证明candidate/live隔离。 | Native62 direct自然exit0，但正式empty-map负例push_error使runner FAIL；单列 EXPECTED_PRODUCTION_REJECTION。不是clean native PASS，也未覆盖每一种后期parser失败/真实视觉消费者。 |
| B08-005 / P2 CONDITIONAL_PRODUCTION_STATE_RISK | 私有SkillProgression候选提前校验，成功后采用同一对象；生产消费者没有持旧service；plural/singular恢复quest共同路径。Native69实际技能+合法非空plural pet/独立quest恢复52/52 clean runner PASS；Native68旧skill save integration自然0/engine0 runner PASS。 | Scoped skill/profile admission组件 PASS；Native68 admission runner FAIL独立保留。旧skill场景receipt/count MISSING，保留现代assignments导致legacy quick-slot migration分支覆盖限制，不能冒充完整迁移验证。 |

五项均有固定源问题到本地修复的映射；最终聚合验收仍 MISSING。外部 finding的原始native NOT_RUN与unproved文字是其固定审查时事实，保持原记录，不回写为外部已验收本地施工。

## 已保留的原生阶段

每个阶段沿用自身candidate/input/engine/scene/run/invocation，不跨阶段合计assertions制造总PASS。所有57–67阶段postverify均PASS，但那不改变业务/runner FAIL。

| Native | runner通过场景/总场景 | engine errors | framework receipt检查 | 分类与限制 |
| --- | --- | --- | --- | --- |
| 57 | 0/1 | 0 | mode_reload_transaction_20261010_test: MISSING | 30s timeout; complete receipt MISSING; original full scene retained |
| 58 | 0/1 | 0 | mode_reload_transaction_20261010_test: MISSING | 30s timeout after CHECK94; live preparation checks47/80 failed in partial stdout; complete receipt MISSING |
| 59 | 0/1 | 2 | mode_reload_transaction_input_composed_20261010_test: MISSING | test parse error: diagnostic large needs explicit bool; engine2; receipt MISSING |
| 60 | 0/1 | 0 | mode_reload_transaction_input_composed_20261010_test: 80/81 FAIL | 81 checks, one actual detached-candidate live price-counter mutation failure; later fixed with candidate-local price resolver |
| 61 | 1/1 | 0 | mode_reload_transaction_input_composed_20261010_test: 81/81 PASS | input/composed81 clean component PASS; includes publication coherence, unchanged request/input/reentry/consumed checks |
| 62 | 3/5 | 1 | mode_reload_transaction_stale_20261010_test: 51/51 PASS; mode_reload_transaction_profile_20261010_test: 59/60 FAIL; mode_reload_transaction_later_20261010_test: 39/39 PASS; mode_reload_transaction_failure_boundary_20261010_test: 95/95 PASS; mode_reload_transaction_direct_failure_20261010_test: 173/173 PASS | five separate scenes: stale51, later39, boundary95 clean PASS; profile59/60 FAIL; direct173 business PASS but expected production engine error makes runner FAIL |
| 63 | 0/1 | 0 | mode_reload_transaction_profile_20261010_test: 59/60 FAIL | profile59/60 FAIL; full differences limited to8 equal int/float wire representation changes; original FAIL retained |
| 64 | 1/1 | 0 | mode_reload_transaction_profile_20261010_test: 60/60 PASS | profile60/60 clean PASS after success-only full JSON roundtrip comparison; failure unchanged assertions remain strict |
| 65 | 0/1 | 2 | profile_load_admission_20261010_test: MISSING | admission test parse error on unchanged inference; engine2; receipt MISSING |
| 66 | 0/1 | 0 | profile_load_admission_20261010_test: 23/24 FAIL | admission23/24 FAIL CHECK22: fixture did not yet persist a legal nonempty plural pet profile; real TMP fault not reached |
| 67 | 3/3 | 0 | world_monster_clock_persistence_test: MISSING; world_monster_clock_legacy_migration_test: MISSING; profile_business_validation_recovery_test: MISSING | three legacy IO scenes runner PASS/exit0/engine0; framework receipts and assertion counts MISSING |

Native57/58完整receipt MISSING；stdout中途检查不能代替自然退出。分组仍保留原7组及新增direct负例、完整正式catalog与真实IO，每scene30秒，没有延长时限或减少断言/负载。Native60实际污染只有live价格计数，修复使用candidate自己的price_lookup，正常消费者仍沿原价格权威；其原FAIL保留。

Native62 direct 的原始ERROR是“五层内容注册表未能生成Merged Game Database”，backtrace指向GameData正式parser/direct load。173业务检查通过，runner因stderr/engine各1仍FAIL；不得删push_error、放宽runnerallowlist或写clean PASS。ContentLayers未READY的合法直接拒绝也在此组件内，不能与empty-maps正式ERROR混称。

Native62/63 profile唯一CHECK53是成功序列化恢复的int/float严格字典差异。只读完整结构验证发现8个等值数值类型差异，其他变化零；Native64仅成功恢复使用两侧JSON roundtrip后完整结构比较，失败_unchanged仍严格==、owned bytes仍严格比较，所有字段保留。原62/63 FAIL继续独立保留。

Native65是fixture的unchanged类型推断解析错误。Native66 CHECK22是fixture未形成合法非空plural pet保存数据，实际TMP故障尚未到达；不能把23/24解释为故障链已完整通过。Native68改用正式创建道士、正式学骷髅、公开合法非空pet snapshot，保持全部52项。

Native67三旧IO场景：world_monster_clock_persistence、world_monster_clock_legacy_migration、profile_business_validation_recovery，均自然退出0、runner PASS、engine0。三个framework receipt和assertion count都MISSING；JSON用null明确表示未知，不把台账缺失sentinel 0当零断言或推断通过数量。

## Native68 保留失败与 Native69 独立通过

Native68/69已收集入新的 `evidence/B08_NATIVE/NATIVE57_69_EVIDENCE_LEDGER.json`（SHA256 `41f9a25e5bb0c333ccde4a9c241593679b656e1b56c14520e1f420cabe64fc77`）；旧57–67台账及原始失败不修改。Native68 invocation `8b73d71f-8412-46d8-abc3-ddfb783d7b9d`；admission run `709a6d90-50a3-4d13-9b26-6361770a0ea9`。

- Admission完整receipt52/52 PASS，自然退出0，timeout=false。实际writer missing-generation+extra/more-than-two/non-String-generation/wrong-path四负例CHECK28–31均业务PASS；真实精确TMP目录fault、相同writer确实失败、A/state/catalog/watermark保全、B block、同B恢复与plural quest、水位一次采用均业务PASS（CHECK32–51）。
- Admission runner FAIL：fixture `_file_hashes` 对empty byte array调用HashingContext.update，产生11条len==0引擎错误。原始errors/日志/receipt保留；empty-file hash证据需要正确fixture的clean复验，不能仅凭业务receipt授予最终PASS。
- 同轮旧skill_progression_save_integration自然0、runner PASS、engine0，但frameworkreceipt/count MISSING；它保留现代skill assignments，对旧quick-slot migration分支的覆盖限制也保留。此旧场景未变，fixture hash修正不要求无依据重复该场景。
- Native69仅重跑修正hash fixture后的profile admission：runner 1/1 PASS、engine errors0、自然exit0、timeout=false、完整receipt52/52 PASS（failed0），30秒和完整正式catalog/IO、四writer负例、真实TMP故障与恢复断言全部保留。invocation `9ace50c6-f38d-402a-87f6-66059dc1cfe8`，run `e04d3793-dbff-4ada-a16d-5df22da4f212`；actual receipt与full producer trace的run/invocation/source fingerprint逐一吻合。独立userdata路径和两引擎SHA见JSON，2553-input postverify PASS、mainindex保全。这是scoped admission clean PASS，不将Native57–69不同源码阶段合为最终同源PASS。

Native69实际receipt为 `outputs/test_logs/v109_direct69_mode_transaction/raw/e04d3793-dbff-4ada-a16d-5df22da4f212/profile_load_admission_20261010_test.result.json`；其canonical full producer trace位于 `evidence/B08_NATIVE/native69/producer_traces/e04d3793-dbff-4ada-a16d-5df22da4f212_9ace50c6-f38d-402a-87f6-66059dc1cfe8/PROFILE_ADMISSION_TRACE.json`。CHECK28–31证明四identity拒绝，CHECK32–43证明真实TMP IO失败与A/bytes/水位保全及B block，CHECK44–51证明只移除own fault后同B恢复、plural quest、唯一checkpoint、唯一composed publication且不重写character/shared文件，CHECK52写出完整trace。

## 只读审查补充及没有关闭的风险

`ADMISSION_REVIEW.md` / `SOURCE_REVIEW_RECEIPT.json` 已绑定PlayerState初始166f79和主控修复a95fe0。审查发现初始非空writer identity缺generation可借合法空namespace接受未知第二键；主控最小补size2+has两键+String类型，严格路径与正式validator、空generation兼容不变，静态delta PASS。Native68四真实writer负例业务PASS保留；Native69同四正式writer负例在完整52/52中clean runner PASS，补齐该专项引擎验收。

同一checkpoint writer及本次promotion receipt即时读取、四水位清理门槛保全、select_character失败恢复A/原A block、prepared skill无晚期导入拒绝、消费者没有旧service引用、plural quest缩进均有只读代码证据。该审查没有执行原生。晚期迁移_commit_save和recalculate_stats的返回值仍被忽略，固定dbb1已有；本次并没有宣布全部加载失败都可无副作用回滚。独立account仓库恢复/迁移的正式权威不等于B角色hydrate。

## 接入与发行边界

- 当前本地修复候选的外部fixed-source审查：NOT_RUN，待B09；已接收的B08审查仍固定dbb1。
- 全项目语义审计：MISSING。B01–B07/B08已有partial/MISSING/NOT_RUN/BLOCKED剩余职责不被本稿清空；30怪同负载CPU/FPS/service fairness、Android战斗/音频/地图、crash/powerkill等仍按原各批边界保留。
- APK109：NOT_RUN。DEVICE TEST：NOT_RUN。仅本地native/静态/报告接收不构成构建、签名、覆盖安装、旧存档兼容或设备体验验收。
- ID127召唤蝙蝠掉落政策：BLOCKED，等待用户产品选择；不得猜概率或恢复fallback。quick-slot多按键产品规则与异常XP/drop断电策略也沿外部gap保留。
- Root负责决定reviewbranch提交内容、更新canonical新阶段证据、固定最终候选并验收。此稿没有commit/push/merge/index写入；接入时原始外部八份报告和全部失败证据继续保留。
