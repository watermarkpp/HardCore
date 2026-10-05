# R3 工程主控续做记录

施工包：`HardCore_GLM_R3_扩展施工与验收包_20260930.zip`，SHA256 `3361E2BAFCFB6948AC6C4F8468F4381297240B1D80B223A00D8B3D5A6DA967D4`。
计划：包内 `docs/02_R3施工计划.md`；规格：`docs/01_R2独立复审.md` 与 `inputs/R2_原定施工计划_不修改.md`。
接管工作区：已有 GLM 镜像；起点 HEAD `5d9ceb0121980ca9636d9d1cc2e19982949fbf63`。未提交内容以 `outputs/r3_takeover/20260930/takeover_baseline.json` 和 `.patch` 留存。

## 接管与裁决

- Ruling: 附件中的“执行者 GLM”和旧分支所有权不决定本次执行者。用户明确授权当前工程主控接着做完；主控串行施工，GLM 只适用当前四类只读机械辅助限制。
- Ruling: 保留镜像已提交和未提交实现，在实际失败基础上逐函数续做；不套旧整文件补丁，不删除已有实现来重演测试流程。
- Ruling: 镜像 bootstrap 因未知分支和无路由文件失败。按根规则完成等价预检：读取规则、索引、现况与冻结合同，核对分支、HEAD、共同祖先、dirty 和日志现场；采用怪物领域规则且不修改 bootstrap 白名单。
- Ruling: 当前根规则禁止工程 reviewer agent；最终审查由同一主控在实施后独立一遍自审，不启动并行工程代理。
- Ruling: 本计划使用 R30—R37 的外部包格式，进度直接记录本文件和 COMPLETION_LEDGER；保持测试与原始证据，不依技能临时目录或自动提交步骤改变用户 Git 现场。

## 共享接口预检

| 上游 / 下游 | 共享接口 | 核对与约束 |
|---|---|---|
| R30 / R31—R37 | tested SHA、dirty 指纹、日志路径 | HEAD 不能证明未提交源码；每次验收记录实际运行文件 hash |
| R31 / R33—R34 | 原生帧轨迹、时钟、实际位置 | 真实帧测试不得借用手动循环的许可和时钟 |
| R32 / R33 | 实际承诺腿、全足迹与攻击 access | 静态与动态检查使用最终实际段；盒内仍需合法通路 |
| R34 / R35 | actor life、tick、source serial、parent action | 许可和父动作须跨换代失效，子释放保留原生命周期 |
| R35 / R36 | canonical appearance 与动作元数据 | 资源驻留只影响可画贴图，不定义逻辑时序 |
| R36 / R37 | 精确 ID / 技能集合、源码指纹 | 候选覆盖与基线失败分别列证，禁止用数量下限冒充全覆盖 |

## 执行进度

- R30：进行现场与已有日志核验；旧 R1 critical 不作 R3 全量证据。
- R31：已有 48 场景和 runner 草稿；先复验首个真实帧场景及夹具。
- R32：待执行精确端点、同 cell、窄通道与路程验证。
- R33：待执行盒快照、完整边界与身体合法性验证。
- R34：待执行来源时钟、闲置唤醒与许可换代验证。
- R35：待执行父动作入口、窗口与冷热元数据验证。
- R36：待执行 33 技能与全 canonical / appearance 身份导出。
- R37：待相关回归、性能、最终 critical 和主树只读兼容性审查。

所有以上进度描述均不是 PASS。正式结果由逐项证据与最终完成清单给出。

## 续做现场进展（2026-09-30；以验证目录中的精确时间为准）

- R30：新增 `tools/source176_r3_validation.py`。每轮保存 before/after 文件集合 SHA256、dirty、受测 HEAD、引擎版本/二进制 hash、退出码、runner JSON 和独立原始日志副本；相关字节变化即 FAIL。既有日志仍保留原受测身份。
- R31：48 原生场景已在接管前两次通过，接管后先复测首例。旧 R2 手动测试已明确标注不能作为自然帧证据。三种实际入口变异（禁止攻击、时钟两倍、时钟不推进）均返回预期 FAIL，零引擎错误，证据 `validation/mutations_164206_559964`。真实发布地图用例正在校验。
- R32：窄通道小数实际端点的真实 RED 已复现；修复 `_hc_neighbor` 格心代理否定实际腿的问题。新增短段预算测试真实 RED 为丢失 0.00249993062268 GU/150 连续运动帧。修复后预算、独立端点、真实 polygon 导航和自然64场景 4/4 PASS，证据 `validation/budget_green_163416_693566`。
- R33：真实盒快照/消费者的 RED 已复现并修复；144 个独立边界记录和普通64/89命中消费者通过，补测冻结 EPS 带。通路、真实身体和动态压力仍须相关回归证明。
- R34：同 generation 同 tick 重新 setup 借旧生命许可的 RED 已复现并修复。真实 pause/.5/1/2 时钟通过；后台深睡中时钟停住、维护用墙钟的 RED 已复现并修复。只保留 O(1) 原生时钟/来源维护，重 AI 仍按 Timer 唤醒；30秒 idle oracle 已通过，追加3/10/30后5秒追击及DIRECT事件轨迹。
- R35：正式ID33四帧冷/热相位差异及遗漏warning窗口的 RED 已复现并修复。正式124/180/195范围释放绕过pending、父ID与生命未冻结的 RED 已复现；修复后新测试和原正式特殊交付回归3/3 PASS，证据 `validation/area_green_162356_118315`。不以父pose仍活跃要求已释放child重新收费。
- R36：exact 156 canonical/appearance/runtime setup 对账 PASS。226—234 的 `runtime_allowed=true` 不代表 `combatEnabled=true`；这九个明确非战斗对象按现有正式行为只读解释，未改数据。33技能 exact SOT/registry、正式planner及真实DIRECT/MINE/错误sink拒绝2/2 PASS。89为尸王，239为暗之沃玛教主；完整语义与实际生产消费者的证明仍待152语义合同和生产回归。
- R37：尚未最终 critical/配对性能，不宣布整体验收解除 HOLD。主树只读三方对账显示27bf唯一增量是僵尸雷电追击测试，非生产源码；不自动合并。

Ruling: 真实发布地图冷启动第一次未在共享夹具5秒热门内READY，记为fixture/readiness FAIL，保留原始日志。新场景先独立观察最多20秒冷启动再进入共享热门，不修改生产门、不弱化原共享断言。

## 最终回归前的专项闭环（2026-09-30 18:12 起）

- R31：真实发布地图 64/89/81 接近与伤害通过；3/10/30 秒 idle 后追击均通过。原生 physics60、render60/30/20/15 与表现停绘间隙的行动/RNG/伤害序列一致；漏采样夹具已修正为 actor 后采样。
- R32：新增真实 PointMotor 的完整八向路径证明，实际长度 14.071067956 GU，对照独立 `7+5√2`；正常空地只有一次主转向。此为点到点结构性导航，玩家自然接近仍在攻击域提前停，不混为同一验收。
- R33：独立边界扩展为五个实际普通代表（64/89/24/81/238）各 72，合计 360；30秒首次超时的证据保留，60秒重场景复验 PASS。真实 Player/骷髅/神兽身体与 WORLD 通路拒绝的 9 个检查通过。
- R35：物理预备释放、已释放物理 child 和目标魔法绑定 parent/source instance/life/generation/target life。真实 RED 显示旧生命可跨复用命中，修后生命周期测试与实际 ranged delivery 回归通过。目标已跨世界时必须在 parent/RNG/cooldown 前拒绝；parent 已准入后 child 取消不能归还同 tick mutex，取消子释放的 RED→GREEN 已完成。
- R36：全部技能语义、职业及真实生产消费者相关回归通过；DIRECT 的49/50级、MINE、躲避、MAC归零、无效对象拒绝通过。导出身份只证明实际 canonical/appearance/runtime 绑定，不宣称未核对的历史源码继承。
- R37：同夹具、同数量和输入的 PC headless ABBA 成对性能四轮 12/12 场景进程通过，每轮含18种组合（10/20/30×冷热×三轨迹）。基线独立副本曾缺 PNG 导入索引，前两次记环境 FAIL；补齐逐素材哈希相同的 import 索引后再从头测量。完整测量与候选的字段/源码身份已留存。
- 性能裁决仍未完成：7种组合的 P95/P99 在两个重复的观测范围外。重复基线的移动路程/查询量存在波动，须额外调查/测量，不以两个样本的范围冒充置信区间；现阶段 `PAIRED_PERFORMANCE_COMPARISON.json` 状态为 FAIL，不能宣布性能通过。
- 18:12 的正式 critical 已结束：652 项，621 PASS / 31 FAIL，源码稳定；这些失败已与相同测试的独立 R2 基线对照。该轮是历史身份，不覆盖之后修复的当前字节。

## 新架构依赖与 GLM 机械辅助

- 用户提供未来架构共享对话和完整 v2 RFC 后，主控判断 R3 是可复用的运行时底座，先完成 R3，再建立固定字节的新镜像。施工裁决与第一纵向里程碑计划在 `outputs/r3_takeover/20260930/FRAMEWORK_IMPLEMENTATION_SCOPE.md`；尚未建立新镜像、尚未修改框架生产源码。
- `R3_LOG_INVENTORY_20260930_1825` 通过 Codex CLI `glm` profile，只读/low/never；实际模型上下文为 `glm-5.3-flash`。4次真实命令、CLI退出0、turn.completed；25个已完成验证目录的计数与失败名称逐项本地对账 PASS。当前 critical 目录被明确排除。
- GLM原答复保持 CANDIDATE_EVIDENCE；主控复核证明与实际会话记录分别在 `glm_log_inventory_verification.json`、`glm_log_inventory_events.jsonl`。GLM未参与实现、失败裁决或最终验收。


## 用户追加缺陷及 2026-10-01 闭环进展

- 玩家碰撞继续持有移动输入/朝向与跑步表现；怪物零位移追击继续行走相位，控制/攻击/命中/死亡优先级与模拟暂停保持原合同。真实墙/敌方身体及原生相位专项已通过，统一回归待完成。
- 即时战士开关原 profile_changed 同步保存造成主线程停顿；改为已有持久化协调链中的有序角色快照保存。实际 HUD/Camera2D 连续移动六次切换、21 次即时/最终 durable 及药水交错回执已通过。
- 疗伤药 910007 按精确来源优先级补 Items/DnItems 14 映射与 provenance；生成器支持精确 ID，未变已有 PNG。万年雪霜 920001 原有 art 260 的背包和地面均通过。没有新增稳定物品 ID 或修改药效。
- AOE 两/四/八/三十只追击通过后，继续真实三十只八位包围。实际第一腿、投影残差、稳定 flank、连续轴/角位占用问题逐一 RED/GREEN。远距离认领实验造成退步已撤回，无新增全局 reservation 或延迟。
- 桶内候选完整性 RED/GREEN 证明出生、移除、同帧强移及跨桶会失效，桶内活体位移每次重算 narrow phase；motion_bucket_membership_green_004103_334407 三项 PASS，旧 crowd 查询 10907、真实伤害 21。
- surround_mixed_native_motion_wall_004309_591934 八项 PASS：混合体型八位、玩家原生移动后八位、西墙后五个可用位置、原空间/批次/强移回归。
- runner 已显式登记全部 26 项 user_feedback_20260930，进入 monster/critical；提供 source176_r3 与 user_feedback_20260930 窄套件，正式 critical 当前成员随证据机检。
- 当前统一用户反馈回归执行中，随后完整 R3、重复 ABBA 和最终 critical。旧 PAIRED_PERFORMANCE_COMPARISON.json 的 FAIL 保留，新轮使用 V2 文件避免覆盖。
- 用户授权的原架构对话「游戏稳定性设计」已收到四项建议并留档 FRAMEWORK_PRO_ADVISORY_20261001.md。建议基于远端 5d9，不是本地 R3 复验；主控独立核验、施工和验收。第三镜像与 P0—P6 仍未施工，不因专项 PASS 缩小最终目标。
- 主树 v97 APK 大小 488711865 字节、实测 SHA256 02E3E86D90F2437C64F211A83E052578A728EEF53D4912C80FAE8867C5C90CDD；本次没有重新打包或修改主树生产现场。


## 01:21 后的重复性裁决

- final_feedback_complete_004943_096612 已结束，25 PASS / 1 FAIL；大身体非整格用例仍只有六位，其他 25 个用户反馈场景通过。不是统一验收 PASS。
- 无站位后排外圈等待试验 unassigned_rear_yield_native_green_010919_313090 为 4 PASS / 1 FAIL；大身体退至五位，已撤回该等待行为及本怪等待点字段，没有新增等待计时器。
- 最终故障链是移动障碍与目的地占位混淆：一个在对齐自身东位的前排被当成永久占用空的东南位；向角位移动的身体也会使另一轴位 owner 放弃目的地。候选规则同时核对实际身体和其当前有效目的地覆盖，经过者仍由每次真实 body sweep 拒绝。
- 候选桶成员身份加入目标的站位候选缓存，使同帧新生/移除/跨桶立即刷新；单位真实 RED 两项已复现。测试保留实际空位不应永久被移动者排除的不变量；临时外圈方案不是玩法合同。
- transient_front_destination_native_011812_863741 五项 PASS：候选/同帧新生、大身体非整格、普通大身体、原生玩家移动后八位、旧 crowd 门槛。正在独立重复原不稳定场景，仍需最终统一复验与 R3/性能/critical。

2026-10-01 01:44：front_destination_repeat_1/2 PASS、repeat_3 FAIL。东北空位的远处目标持有者 #7 与实际更近身体 #12 形成选择/运动互锁，前者目标否定后者，后者实体挡住前者。新增 exact native unit RED（两断言），当前尝试保留已站稳占位、未站稳按实际距离选择，不增加预留或计时器。bootstrap 本次仍仅失败于旧分支路由和缺规则路径；实际分支/HEAD/现场/两树已重新核对，旧 monsters 专业所有权规则由最新根 AGENTS 集中施工规则取代。

2026-10-01 02:04：nearest_station_contender_red_014219_905256（0/1 FAIL）→ nearest_station_contender_green_014329_836858（4/4 PASS），三次 nearest_station_repeat 独立原生运行均八位 PASS；最终反馈 final_feedback_nearest_complete_015002_192676 为 26/26 PASS、源码固定、engine_log_errors=0。未站稳的物理竞争者按实际站位距离解除互锁，已到位者保持占位；没有远处预留、ID 特例、强制位移或新计时器。仍不能宣布整个目标完成。

2026-10-01 02:36：final_source176_r3_complete_020308_475752 已结束，75 PASS / 0 FAIL，执行退出码 0、源码固定；统一用户反馈仍为 26/26 PASS。runtime 旧直接 fixture 在测试开始前就绪合法来源 cadence，并把移动后攻击初始位置从旧圆形 1.501GU 改为方形边缘外 1.01GU；连续两次攻击观察窗口由实际移动/来源许可/攻击间隔推导，保留 starts>=2、实际 HP 与收敛断言，范围断言加强为正式方形 1.0GU。final_runtime_source_fixture_023348_194303 为 1/1 PASS、源码固定。生产代码未因旧测试假设改变。开始 V2 串行 ABBA 性能对照，随后当前正式 critical；第三镜像/P0—P6 尚未施工。

2026-10-01 02:51：V2 ABBA 四次运行及各自三场景均正常 PASS/sourceStable，但数值对照 FAIL，18 个条件中 15 个 P95/P99 高于两次基线；30 warm lateral CPU P95 8.912/9.463 → 10.6/10.711ms。候选真实 moves 4943/5018 对基线 3556/3566，位移 61.51/61.78GU 对 51.60/49.95GU；不能通过恢复卡住或减怪降成本。已追到粗桶候选名单内远身体仍做资格与 exact core 工作。motion_live_envelope_red_024723_900600 0/1 FAIL，仅因远身体 1943 次无用资格检查；160 个原 core 结果相同。当前 live coordinate + conservative segment/body envelope 预筛复用原 exact core，无缓存位置/命中，motion_live_envelope_green_024842_164114 4/4 PASS（候选复用、非整格大身体、移动玩家八位、旧 crowd）。正在测当前 30 怪成本，后续仍需最终统一反馈/R3/critical。先前 26/75 PASS 是修正前字节身份，不能冒充新增优化后的受测文件集合。

2026-10-01 03:03：V3 ABBA 4 轮/12 场景全部正常完成，但 18 条件中的 14 条仍有 CPU P95/P99 高于两轮基线，性能门槛保持 FAIL。30 warm lateral：移动策略调用 3552/3626 → 4986/4905，真实 moves 3521/3600 → 4958/4881；策略单次 104.38/107.68 → 114.78/115.23us。30 warm reverse：策略单次 124.91/126.39 → 111.60/115.32us，但调用 3917/3915 → 4948/5131；static 单次 126.24/125.77 → 105.60/105.48us、调用 3891/3894 → 5470/5470。恢复运动增加真实工作量、横向每次成本仍有增加，两者必须分别保留；不能把此测量写为普遍性能胜利。原 V1/V2 及修正前 FAIL 均留存。R37 按包内要求明确性能限制，手机/GPU为NOT_RUN。

正式 critical 已在当前固定字节启动，标签 final_critical_live_envelope，预期 678 唯一场景，包含全部 75 R3 与 26 用户反馈。运行期间不再修改 scripts/tests/scenes/data/runner。主树和第二树 AGENTS 已同步最新 Codex CLI glm 与单主控/集中施工规则；旧第二树规则副本、前后哈希在 AGENTS_RULE_SYNC.json，用户数据和凭据未复制。第三镜像/P0—P6仍未施工；完整施工顺序已补 FRAMEWORK_SERIAL_EXECUTION_PLAN.md，不作为完成证据。
