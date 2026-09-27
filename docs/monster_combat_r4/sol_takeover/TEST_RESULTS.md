# R4 实际执行结果（持续更新）

## 观察与伤害身份闭环

执行源基于本地候选 `227a9c945f3bb21e4fbe51d38e10bbde4b0d8f9d` 加本轮未提交修复。实际源码与测试文件哈希在 `evidence/observation_final/r4_observation_final/source_identity.json`；以文件哈希识别这次执行，不将基线HEAD当作无dirty源码证明。

命令：`tools/run_godot_tests.ps1 -TestPaths @('tests/hc_monster_combat_r4/observer_integrity_test.tscn', 'tests/hc_monster_combat_r4/damage_attribution_counterexamples_test.tscn', 'tests/hc_monster_combat_r4/all_damage_lost_test.tscn', 'tests/hc_monster_combat_r4/natural_cadence_24_test.tscn', 'tests/hc_monster_combat_r4/natural_cadence_76_test.tscn', 'tests/hc_monster_combat_r4/natural_cadence_238_test.tscn', 'tests/hc_monster_combat_r4/natural_cadence_239_test.tscn', 'tests/hc_monster_combat_r4/natural_cadence_24_chase_test.tscn') -TimeoutSeconds 30`。四项20起手、全漏和反例为已声明重场景，运行器上限60秒。

结果：**PASS 8/8，timeout=0，engine_log_errors=0**。原始stdout/stderr/engine与runner在 `evidence/observation_final/r4_observation_final/runner_results_adhoc_20260927_132532_672_19136.json` 同目录。逐次原始流水在 `evidence/observation_final/r4_cadence_*.json`、`r4_counterexamples*.json`。

覆盖：正常、采样前设置的真实AC减伤、实际魔法闪避、实际离开射程拒绝、真实combat_epoch切换、真实丢伤+同帧同额外来扣血、重复HP写入、无身份嵌套、有身份外来嵌套、20次全部丢伤。故障发生在写入流程；观察器无故障开关、无HP写入权；验收器不读取故障状态。

身份验收严格检查来源实例/生命、父动作、地图/世界代际、根释放、明确声明的子释放、目标实例/生命/世界代际。UNKNOWN独立保留，不能替补受审终态；金额只核验实际HP算术。合法两目标与伪造身份使用同一验收器。实际多目标、MP护身支付和换图组合继续补真实行为，不能把单位用例当成整项R4完成。

### 旧 18/20 与退出失败裁定

初次原候选76/239的18/20附近记录缺少正确parent归属与真实miss终态，保留为FAIL。修复后的76/239，未改公式/RNG/冷却：每个根释放归属到明确child，真实 `mixed_magic_evaded` 分支给出miss终态。不能据此逆推无完整身份的旧记录全为合法miss，也没有按奇偶补记录。

上一轮24打印PASS但process超时，保留在 `evidence/natural_24_timeout`。当前明确关闭记录、释放GameRoot、等待两次真实process_frame再退出。24最终实际启动约5秒、world boot约5秒、自然采样约48秒、写证据3ms、清理29ms；完整进程自然退出在60秒内。未清冷却、未缩pending、未手调游戏钟。

### 已执行相关回归

monster_mixed_damage_atomic、ranged_magic_evasion、monster_special_delivery_runtime：PASS 3/3（`outputs/test_logs/runner_results_adhoc_20260927_130604_626_8444.json`）。接口探针补全新增可选身份参数，原断言不变。w1_special_delivery_runtime、synchronous_revive_death_token此前定向PASS。

## 快照当前断言裁定

当前执行：`evidence/snapshots_red/runner_results_adhoc_20260927_131906_652_12240.json`。

- enemy_snapshot_v2_production：**FAIL**。夹具把玩家放在2GU，要求 `_deal_melee_hit` 得到V2；真实1.5GU中心入口提前拒绝，所以snapshot空。修夹具到合法范围，保留V2/同地图/跨地图/legacy计数原断言；生产不可回退2GU。
- canonical_snapshot_identity_production：**PASS**。当前正式技能入口可传播身份。历史失败未自动定为无关；保留当前原始运行结果。
- caster_skill_visual_factory_entry：**FAIL**。SkyStrike/Beam/非SkyStrike断言全部成立，未加入树的创建结果未free，退出泄漏资源；需修资源清理。现存 `skill_visual_profiles.json` 确实声明SkyStrike，不能根据旧报告推测其应删除，也不动用户已验收的Magic素材。

## 快照修复与 D3 边界

`r4_d3_and_snapshot/runner_results_adhoc_20260927_132930_884_24216.json`：PASS 4/4，无引擎错误、正常退出。怪物快照夹具改到1.499GU，移除无效的2GU source-range覆盖；V2、严格消费者、跨地图拒绝和legacy计数断言未削弱。视觉工厂创建的两个未入树节点明确free后退出，原类型断言保持。

`r4_d3_four_ids/runner_results_adhoc_20260927_133031_891_5604.json`：PASS 1/1。24/76/238/239各八方向×1.499/1.500/1.501GU，96组真实准入检查；64组合法起手都有实际伤害或正式终态、身体父动作ID和音频动作ID绑定，32组射程外拒绝没有消耗冷却或扣血。每例新建生产Actor，不清计时、不手动播放攻击、不调用虚拟physics tick。另用真实WORLD层StaticBody验证墙体阻挡与删除后准入；碰撞修订号走既有缓存失效接口。逐案原始账本在 `evidence/d3_four_ids/r4_d3_boundary.json`。

这里的音频检查证明身份与请求阶段接线，headless没有声卡听感或GPU绘制验收。D3横移/绕圈、真实持续受击压力、身体敌对组合及暂停迟绘组合仍需执行，不把边界矩阵当作完整D3。

最终full critical、同SHA干净检出、性能配对与D3完整矩阵：**NOT_RUN**。本地候选尚未达到最终审查条件。

## MP支付与受击相关回归

MP反例先在真实Player伤害入口得到FAIL：20伤害/AC0的实际HP和MP结果均正确，原观察行没有MP前后值。`evidence/mp_red` 保存FAIL流水与runner。修复只记录实际MP支付前后值，支付公式、随机数和扣费位置保持。

`r4_mp_and_struck/runner_results_adhoc_20260927_133540_000_5220.json`：PASS 11/11，timeout=0，engine_log_errors=0。包含MP支付、观察器等价性、混合伤害原子性、怪物受击、休眠伤害唤醒、玩家/怪物受击链、玩家释放顺序、毒与受击、魔法盾换图生命周期、召唤受击、同步复活死亡通知。固定输入20伤害/50MP支付30MP而零HP损伤；10MP不足时扣完MP并扣13HP。独立期望核验，MP元数据没有用resolved伤害金额推断来源。

原始Windows日志/JSON在专项evidence目录用Git属性保留实际CRLF字节；格式检查允许CR-at-EOL，保留真实运行输出，不改原始PASS/FAIL内容。旧候选Markdown尾空格仍单列历史格式FAIL，不能与本轮源码检查混称全绿。

## 来源生成一致性闭环（攻击零值仍有阻断）

主源33/183/241移动间隔2500/500/400ms均存在；旧生成物runtime_allowed=false产生0速度。正式生成器增加精确ID更新入口，明确选中44条已审差异；另外112条及顶层来源头信息保持相同。9条过时分类修到现存canonical分类；32条profile/special元数据跟上已集成候选。逐字段差异：evidence/authority_generation/exact_target_diff.json。没有修改21CQ、地图、素材或掉落源。

精确更新四项Python反例、完整生成check、144条精确Race/12条DATA_HOLD的targeting绑定测试：PASS。Cadence禁运行测试改为显式禁用副本，而非假设如今已允许运行的33仍禁用；保留IMMOBILE/不发grant断言，runner正常退出PASS。

完整运行时审计仍为FAIL：MFC1及all_monster_loading对183/241显式0攻击间隔报缺失。原始FAIL保留evidence/authority_red。183源Race117/TExplosionSpider为一次自爆类；241候选Race120实际指TSoccerBall，与其21CQ名并不能证明飞火攻击规则。当前普通Enemy正间隔fallback仍未正确区分这两种用途，不能伪造正间隔或删断言变绿。这两项属于来源/生产语义阻断，继续核对。canonical目录PASS；移动缺失/速度fallback错误在新审计为0。

## D3运动、真实受击、身体及生命周期

`evidence/d3_motion_related/runner_results_adhoc_20260927_135806_576_10868.json`：PASS 8/8，完整退出、引擎错误0。24/76/238/239通过真实玩家touch运动横移、绕圈，接着承受真实火墙/爆裂火焰伤害；每种产生约9GU运动、10或11次受击，持续受击阶段分别2/6/4/4次新起手。所有真实admission/delivery/HP/terminal使用同一验收器；活动身体动作及音频请求父ID一致。真实暂停12个process帧冻结战斗钟；恢复后继续。关闭表现更新时攻击自然过期，恢复表现不会复活动作。另含索引桶边界、拒绝工厂/查询、死亡双代际及动作幂等回归。停止绘制和headless身份检查不构成实际GPU/听感验收。

`evidence/body_lifecycle_final/runner_results_adhoc_20260927_140936_293_7992.json`：PASS 4/4，引擎错误0。生产Enemy→实际骷髅/神兽（24/76/238）检查合法身体、形状半径和真实伤害。76实际同格玩家+骷髅得到两个明确child，各自唯一终态。238真实准入后同步死亡复活、目标切换地图代际、来源切图及目标释放，旧攻击没有伤害新生命；全部得到真实拒绝。

最初夹具错误地假设238存在伤害pending，把表现延迟当伤害延迟，并把16.2/16.8当同格（正式格子按round而非floor）。原FAIL保留body_lifecycle_red及body_lifecycle_fixture_red；第一轮逐场stdout已被后续默认同名日志覆盖，标MISSING，原runner及流水仍保存。修正后暴露实际生产错误：准入回调可释放目标，但后续仍读取global_position；原报错/timeout完整保存body_lifecycle_source_red。最小修复检查有效性，冻结record仍进TARGET_UNAVAILABLE拒绝。没有增加伤害延迟或吞事件。异步投递跨代际尚NOT_RUN，不能把本同步例称作异步验证。

## 当前历史25项复核

`evidence/historical_current_red/runner_results_adhoc_20260927_135051_727_24196.json`：18 PASS、7 FAIL。production_snapshot夹具2GU改合法1.499；warrior_skill_state_machine、live_attack_resolution、melee_lock_fallback、warrior_thrust_defense的正式世界未就绪/世界坐标错误，使用既有FormalWorldFixture等待正式世界，并走官方坐标设置。原玩法/身份/伤害断言保持。第一轮修正4 PASS、warrior仍FAIL（旧几何块使用屏幕ZERO）；保留historical_fixture_red，修正该块到正式地图锚点后原断言PASS（warrior_fixture_final）。当前合并证据为23项PASS、183/241两项FAIL；最终同SHA25项集合复核尚NOT_RUN，不将组合历史结果当最终完整回归。

## 真正异步 line 投递与直接相关回归

ID79的正式line_magic走真实物理选敌/起手，冻结child后等待原600ms投递，不调用settlement、不改pending/冷却/时钟。旧legacy特殊格子入口没有传观察root；现在由真实调用点接收刚分配的父动作ID，在观察开启时记录root并传给实际child，关闭时不构造字典，也不新增游戏serial。没有读取最近HC release或异步全局上下文。

首轮真实释放目标后，音频选择与retarget在is_instance_valid前使用`is`，触发freed-instance错误；FAIL及timeout原日志保存async_line_red。只交换有效性与类型检查顺序后，positive/目标combat_epoch/来源世界代际/释放目标四案全部得到实际扣血/合法miss或真实拒绝，各child冻结身份完整。最终原始流水及身份在async_related。

`evidence/async_related/runner_results_adhoc_20260927_141537_640_23964.json`：PASS 7/7，engine_log_errors=0、timeout=0。包含async line、真实双目标/生命周期、毒重挂、召唤身体与spawn footprint、召唤释放快照、主人传送、死亡掉落预算队列。最后一项是队列专项，其夹具覆盖落点解析，不能宣称正式火墙群死/地形落点负载已测；该负载仍待T6。

## 显式零攻击间隔与默认值区分

实际反例 `evidence/zero_timing_red/runner_results_adhoc_20260927_141630_907_5680.json`：183/241 raw=0却得到1.55秒默认，FAIL。核对原主服务端LocalDB.pas:1354直接加载ATTACK_SPD，1362-1363将小于200的值钳制200；加载规则不覆盖主源原始数值。增加MonsterAttackTiming的显式值解释（0/1/199→200，200及以上保持；缺失/负/字符串/小数非法），Enemy消费该解释，原21CQ/生成数据不变。不是添加200ms伤害延迟，也没有改变24/76/238/239既有正间隔。

`evidence/zero_timing_fixed/runner_results_adhoc_20260927_141816_996_8632.json`：PASS 4/4，包含raw值保持、数学边界、完整loading、MFC1属性/时钟、Boss间隔。MFC1仍逐ID检查主源raw相等，独立期望按max(200, raw)，不以生产helper自证；loading仍要求字段存在和类型合法，不将缺失等同0。原服务端文件哈希、主源哈希、真实执行源码/测试哈希保留source_identity.json。

这只关闭时间值错误，不为183一次自爆/241身份与零伤害用途补出未验证的行为。其现存profile无专属delivery、canonical AI有unresolved_project_fallback；能力表必须披露，不能称特殊实体族PASS。完整critical/性能/干净检出继续NOT_RUN。

## 既有性能夹具接口适配

三个既有Enemy探针override补可选release_record并转交真实super；原断言不变。HARDCORE_REV07_SCENARIOS=open_pursuit、默认各自count集合，runner_results_adhoc_20260927_141951_497_10660.json为PASS 3/3、engine0。其余scenario本轮NOT_RUN，不能将该有限接口回归当T6。原始输出在evidence/adapter_regressions。
