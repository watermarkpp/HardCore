# B08 — HardCore 跨模块生产链和真实剩余职责只读审查

fixed_source_sha: dbb1bd0878ab24a4e5bd6a1877d32f304f5623e5
fixed_git_tree_sha: fef3e786da2a7462abdc069f48615215407f6a11
Audit type: fixed Git objects, static control flow; no Godot/headless/export/Android/saves/secret read or production edits.

## 已实际读取/绑定

本次核实固定提交和 Git tree，与之后的施工 HEAD 不混。读取 AGENTS、PROJECT_CORE_CONTRACTS、标准提示、BATCH_08、SCOPE、完整 manifest、CROSS_BATCH_GAPS、AUDIT_PROGRESS、模式重载消费 trace，B07A/B07B final disposition/原生台账及 B01–B07 各五份原始 SOURCE_BINDING/COVERAGE/VALIDATION_GAPS/SUMMARY/FINDINGS（共45个已有报告文件）。
按实际正式入口额外读取了 mode, GameData, PlayerState, player, enemy, GameRoot, summon, AI budget, persistent loot/save, map READY/Loading/audio, stable identity/authoring, Android Java+seal、共享测试/历史 oracle 等 71 个固定 Git 文件。它们包含 3201 个函数入口，其中 93 个做定向函数体阅读，长函数超过阅读窗口标为 STATIC_PARTIAL_BODY；全量函数语义仍 MISSING，详细未审函数列在 COVERAGE.json。源文件条目、哈希和之前各批独立基线绑定在 SOURCE_BINDING.json。目录/文件计数不是通过。

## 发现（固定源码事实与运行假设明确分离）

- B08-001 [P1/PRODUCTION_CONTROL_FLOW_BUG] Commits active_mode, each enabled package and its signal, PlayerState.game_mode_id before GameData.load_database; ignores false, returns true. 固定行 scripts/layers/runtime/game_mode_service.gd:17–29。
- B08-002 [P1/PRODUCTION_CONTROL_FLOW_BUG] Facade mutates ContentLayers first then ignores false for nonlater and returns changed=true. Later branch directly calls PlayerState.set_later_content_enabled which commits signal/save without independent reload gate. 固定行 scripts/layers/runtime/runtime_service_facade.gd:16–22。
- B08-003 [P1/PRODUCTION_CONTROL_FLOW_BUG] last_load_result is marked successful on JSON read; load_save publishes level/profession/mode, ignores apply_mode failure/fallback, mutates experience/inventory/equipment, may call migration _commit_save; select_character trusts last_load_result and returns true. 固定行 scripts/player_state.gd:6988–7236。
- B08-004 [P2/CONDITIONAL_PRODUCTION_STATE_RISK] load_database clears loaded then assigns maps/database/items/skills before all validation. Getters read current indexes without own readiness guard. Failure can leave partial or mixed cached data accessible if caller ignores readiness. 固定行 scripts/game_data.gd:236–320。
- B08-005 [P2/CONDITIONAL_PRODUCTION_STATE_RISK] Fields level, profession, mode, inventory, equipment and warehouse may mutate before load_snapshot failure; last_load_result false and select_character only resets active_profile_id. 固定行 scripts/player_state.gd:7087–7131。

根因集中在内容状态提交顺序，而不只是某个 boolean。ContentLayers 先更改 enabled_expansions/merged_database 并同步发 expansion_state_changed，GameModes 先更改 active_mode 和 PlayerState.game_mode_id 后忽略 GameData.load_database(false)；PlayerState.load_save 已标成功并恢复背包/装备，select_character 可能依据先前 success 进入场景。GameData 的重载失败 flag 已清 unloaded，但公开数组/索引和 getter 接口不能默认具有原子候选发布。不能单点补 return false 就宣布完成。

最小完整建议：以 ContentLayers/GameModes/GameData/PlayerState 现有唯一所有者建立受控的 prepare/validate/commit 边界；解析扩展与稳定 ID、技能和装备投影、GameData 全链准备成功后再发布 mode、profile_changed、expansion_state_changed、database_reloaded 与兼容 migration 存档。失败时无旧模式/旧存档副作用，保存阻塞状态明确；如果保留旧快照不可证明可恢复，则保持 unavailable 并显示失败，不允许假自动 classic fallback。尤其区别 Android autoload 未READY：project.godot 顺序 ContentLayers→GameData→PlayerState→GameModes，StartupLoading 在 intro 之后依次 ensure_loaded，原始正常启动不应因为允许延迟准备就被判为 BUG。

## 玩家攻击/魔法/HP/MP/受击 → 敌人死亡 → 掉落/拾取/存档

- PlayerCharacter.request_attack/request_skill 在动作提交记录 action_id+combat_epoch、pause-aware windup 到 _emit_attack/_emit_skill。已确认死亡/退树/地图生命周期拒绝，普通人物移动不撤销合法本次释放。GameRoot._on_player_attack 创建 canonical Ground GU snapshot/空间 query；法术 _execute_canonical_skill_plan 和 _apply_canonical_spell_damage 消费唯一 SkillRuntime 与 snapshot/AOE exact 判定，未发现可据此合法截断 AOEs 的静态证据。
- PlayerCharacter.take_damage / take_direct_spell_damage 走真实防御、MAC/抗魔、护盾 MP 与 _apply_resolved_damage 单写 HP 死亡 owner；战斗硬直由受击动画和 pause-aware 战斗时钟管理。Enemy._apply_damage_core 对实际正损血同时生成 threat、唤醒、cold-source，并区分 direct STRUCK 与 DOT；不是额外 HP 权威。Boss 必要动作路径有独立 delivery；未对所有 430 个 Enemy 函数和所有 Boss 个体做完整语义证明。
- GameRoot._on_enemy_died 固定致死瞬间 map/generation 与 monster snapshot、入唯一死亡队列；PlayerState.prepare_death_settlement 先创建持久化事件，PERSISTING 等真实保存回执，之后 _advance_enemy_death_work_slice 才规划、分帧物化和提交。普通模式每帧地面节点限制，而 _drain_enemy_death_queue_for_logout 是退出前授权的同步强制结算，失败/pending 会拒绝安全退出。不把此退出边界诬称 teardown 偷生地面物品。
- 拾取 receive_loot_batch_partial 的 inventory/gold 工作副本与 typed item/ID 校验有正式 owner，prepare_loot_save / JSON persistence / item journal 具独立状态。Power cut 在经验持久化、随机roll、地面物化和拾取存档之间的业务语义仍 BLOCKED，不把PC headless当进程终止/手机证据。6/9/12白怪/精英/Boss掉落槽与当前保护未变。

## 静态LOS激活与300ms非必要规划

- GameRoot 的玩家/非隐身召唤物 emitter 入队后按 runtime_map_id/zone_generation 建 AABB query，_service_passive_monster_wakeup_batch 不受 optional planner 的300ms门限阻塞。Enemy.request_passive_target_wakeup 实施实际6/9/12 aggro范围（分类数据）、安全区/隐身限制与静态 terrain LOS；实际正伤害由 _apply_damage_core → _wake_dormant_from_received_damage / _acquire_cold_damage_target 跳过被动范围等待。不可把怪物当 LOS 墙。
- Enemy._owner_decision_window_due / _pursuit_process_budget_begin 约束非紧急 observation/new-step 重追击，攻击资格另在 _attack_engagement_ready。没有真实当前30怪同负载 FPS、CPU service fairness、300ms backlog tail latency 的动态比较，故性能验收 NOT_RUN，资料 6083 项非任何降负载证明。

## 地图epoch/异步租约/READY/Loading/UI音频

- GameRoot._begin_map_transition 冻结 combat epoch/transition ID 并关输入；_run_map_transition 等待 Loading cover、prefetch、真实 world build，异步回来重检 transition_id；_fail_map_transition 按 pre-arrival保留世界 vs post-arrival safe-home 处理、失败时保持危险输入锁。不将B06地图编辑器headless持久化解读为断电/Android。
- WorldBootstrapCoordinator.Generation/lease、FeatureResourcePreparation FAILED/CANCELLED/ERR_BUSY、audio session/source/frontier、HUD旧世代信号回调、召唤物墙边跟随和大型场景剩余控制流仍逐函数部分/未审。保留已验收视觉金边、图标、血条、音效与正式发行合同。

## 资料身份及明确不报告为BUG的合同

- source_priority_policy 是优先总表，equipment_attribute_master 唯一装备属性主源；generator/typed stable ID→registry/capability→GameData→装备属性面板；B07A 现有原生55(64)/54(58)、equipment15、guard9、compiler126张/4876具名行和限定 I/O 正负证据按来源复用，不把历史编译器425817四项误当当下全PASS。
- ID193 虹魔教主近战吸血确认为按 pre-AC 输入30×0.33，目标只失19点仍吸9HP；tests/special_actor_lifesteal_poison_gap_test.gd:12–25 明确禁止改成实际 HP 伤害。魔法吸血另按 post-defense/applied_damage。本次明确 NO_BUG，不合并，不更改比例。ID169 legacy-only不生成；召唤蝙蝠ID127掉落仍等待用户产品选择。
- 复活戒300秒和免经验仅戒指复活、麻痹普通5秒/精英Boss2.5秒、隐身/技巧/神秘/探测项链与价格、油5×和JP3×、锁定/移动/AOE/受击间隔保持既有权威；本次未把源码函数读取数当全角色技能行为验收。

## Java Android构建与历史/共享fixture

- build_android_isolated.ps1:357–359 Enter-AndroidJavaEnvironment 且576–577 finally Restore；two_pass_export_hook 对第一包/真实seal/第二包、engine/source SHA、原包签名相同有具体控制流；verify_android_build.ps1 包身份 com.personal.mafaoffline、versionCode 递增、原证书和runtime内容门禁。只审源码，没有执行构建、安装109、验证设备旧存档，均 NOT_RUN；Java本次输入未变复用既有helper/probe native，不无意义重跑。
- formal_world_skill_fixture 已追 publish_targets 从真 READY 到真实 _begin_map_transition/unique slot、spawn/epoch/active_map 断言，5秒是fixture窗口不是生产启动性能SLA；取消/失败回滚尚无全原生覆盖。map_runtime_transaction_test_fixtures fail seams、旧 loot oracle/旧 R2 cadence、不缩怪 m30_sampling_copy75函数、墙遮挡31函数、UI calibrator45函数及 suite registration 顶层仍部分/未审，详见 COVERAGE & CROSS_BATCH_CLOSURE；历史 fixtures 只作比较不得恢复退役格子方案。

## 最终门禁和报告接收

- 旧B01–B07原生台账分阶段独立使用：B07A旧53/54失败保留；B07B初始六项ownership覆盖列表MISSING不得补造，native56 13 clean checks仅限自己的修复范围，Windows Assign失败/PID复用/Linux仍 NOT_RUN；非-framework通用PASS只作功能兼容，不能冒充正式receipt。B06 powerkill、B05 Android音频、B02/B03 Android战斗召唤及新109设备均 NOT_RUN。
- CROSS_BATCH_CLOSURE.json 对22个旧真实职责和本批追加职责逐项列出 STILL_MISSING/BLOCKED/NOT_RUN/STATIC_PARTIAL、具体函数 owner 与后续最小验证。此审计不能授予全项目、主树合入或109发布PASS；只读报告由主控复核/限定施工/必要回归。
