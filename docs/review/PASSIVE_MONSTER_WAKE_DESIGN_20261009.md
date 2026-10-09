# 被动待战、人物侧激活范围与取消回出生点

2026-10-09 v108真机反馈之后的最新规则覆盖下文旧分页方案：范围内所有合法冷怪在人物真实移动事件中同步获得正式target，受真实正伤害也同步获得合法冷目标；不再等待8候选分页、optional额度或300ms规划。继续保留同一空间索引、精确6/9/12、地图/代际/生命/隐身/安全区及静态直线LOS；rich observation、追击/路径和非急行为仍按300ms/帧预算运行，不能由halo结果伪造。30自然冷怪同调用30/30、canonical firewall tick30/30及必要拒绝门已原生验证，证据与修复边界见[v108反馈修复记录](v108_runtime_bug_repair_20261009/CURRENT_RESULT.md)。下文为历史设计及证据，不代表最新target接线。

2026-10-09用户最终规则：普通怪6格、精英怪9格、Boss12格，由人物及道士召唤物侧触发激活。未入战及已脱战怪物被动等待，不主动寻找玩家，不返回最初出生点；原怪还活着时原刷怪槽不得生成新怪。

这一决定覆盖“继续保留逐怪旧索敌范围”的中间方案。旧正式资料普通5/6/7、精英7/9、Boss9/16只保留为来源，不作为新数值的下限。新数值必须为精确6/9/12，不能用max规则保留普通7或Boss16。范围几何继续按正式格子矩形规则；不新画光环UI，不做三次重复空间查询。

## 因果证据

ON03原生PASS，但完整服务FAIL：四个最老请求target_id=0、active_leg=false、attack_active=false，仍is_physics_processing=true；等待264/219/173/128 process，约4.41/3.66/2.89/2.14s。reserved_owner_max5、epoch_owner_max1。轻量时钟仍运行不代表当前有可执行战斗规划。旧0.5s冷态Timer主动寻敌，primary_target全局玩家引用被错误当作可服务战斗资格，四个冷态owner占住四个预留槽。不能增加预算、放宽公平、减少34/30负载或用TTL掩饰。

## 数据与责任

- 正式authoring override经原build_monster_runtime_authority.py生成runtime authority；人物側和Enemy接收端消费同一份6/9/12政策。仅ordinary/elite/boss生效；special、non_hostile、version_difference及DATA_HOLD不臆造为这三类，不改移动、攻击范围、focus、disengage、碰撞、掉率或分类身份。
- Enemy拥有被动、外部唤醒待处理、正式战斗状态。无目标且无真正唤醒/伤害/仇恨事件时，不主动搜索，不申请或保留owner_window。进入被动时撤销本人旧追击请求，不能每个轻量时钟回调重复扫描整个队列。
- GameRoot沿实际玩家位置发布、地图进入、出生和目标丢失事件标记唤醒工作；使用既有RuntimeCombatSpatialIndex找附近候选。最大范围在出生登记时缓存，不在每次查询遍历全地图。候选游标不被连续移动反复重置，每真实process最多8个候选并参与现有共享FrameBudget；旧generation候选撤销。
- 道士骷髅、神兽作为真实独立激活源接入同一中央队列，不借玩家身份代替召唤物。玩家及召唤物隐身时不产生光环；群体隐身可覆盖召唤物。原隐身时长、攻击破隐、脱战和特戒隐身体感不变。位移、隐身开始／到期／破隐、生命周期和传送由事件标脏，不增加每帧召唤物全量扫描。共享每process候选上限和预算，各激活源公平排队。
- request_passive_target_wakeup(candidate, expected_map_id, expected_generation)只记录真实世界/身份/life候选许可，不写目标、不制造攻击或伤害；正式动作回调再次验证当前范围、地图、generation、生命、安全区、隐身及既有静态LOS。玩家已离开时不能拿旧事件占住队列。
- 活动怪的普通追击继续300ms。合法就绪攻击、紧急法术、已接受伤害、受击、实际移动碰撞不等该周期。队列资格代表可运行rich工作，不只看is_physics_processing。
- Boss冷态不能为了维护阶段时钟进入玩家候选枚举。祖玛阶段/召唤保持已有正式时钟，牛魔王等战斗紧急法术不降频。伤害与有效仇恨仍可唤醒，不能让受远程攻击的怪物无反应。
- 脱战停止追击和回程，在当前真实位置等待；原spawn metadata不修改。刷怪链的_spawn_slot_is_alive按slot_id与generation检查存活，和当前坐标无关；脱战、离开原出生点不释放刷怪槽。
- 定点雕塑表示没有寻敌/追击/寻路AI。已有生命时钟、持续伤害、恢复、受击/死亡、已提交动作和必要表现仍有正确处理，不能为性能省略战斗数据。

## 验证与108

direct47纯被动及人物激活原生PASS；ON04完整群怪运行FAIL（已释放候选进入typed调用，导致scope未闭合），direct48修复边界回归PASS。新召唤物／隐身链direct49因GameRoot新变量Variant推断解析错误FAIL，修复后待复测。direct50新召唤物／隐身与释放候选回归PASS。ON05完整服务FAIL：actual targeting 28/30，数秒请求等待仍在；原生无错误、9531绑定不变，但不能作为性能提升。根因继续收敛到pending wake重新睡眠，以及后台轻量时钟被当rich服务资格。正在最小修复，未接主树、未出108。需要验证纯被动无请求、人物触发正常入战、障碍/安全区/隐身拒绝、脱战原地与再次激活、未死不重复刷新、伤害唤醒、Boss维护和即时技能，以及不破坏已提交攻击/受击/死亡。

完成后保持34正式怪、30入战、48掉落、300真实physics及完整回调计数测量；分别报告整体CPU、峰值、实际帧间隔和服务等待。所有旧FAIL保留，不能把这项设计成立当成群怪FPS已验收。

最终从完整codex/integration接入、固定构建来源再封装108。107及后续音频、拾取、价格/概率、特装、HUD、Loading、零掉落、首次攻击和受击时序保持。旧107研究树只作尺子，不能整树覆盖主树。主任务清单：TASK108_DELIVERY_PLAN_20261009.md；旧改动保全：POST107_WORK_SUMMARY_20261009.md。

## 后续真实服务修复记录

- direct51 FAIL 暴露测试选取了非budget-owned怪物，旧PASS受background错误掩盖；direct52明确选取正式ordinary owner，所有原断言保留后PASS。新增pending wake不得重新休眠、后台clock不得预留rich slot、真实Timer callback仍可运行的边界。
- ON06完整场景FAIL：实际29/30，仍有末尾请求等待4.54s。已served的max wait23process不能代表末尾未served请求。
- TRACE07诊断FAIL保留。其snapshot证实最老请求owner clock已越过due、retarget0、foreground/runnable，不是“尚未到300ms”。32条公平拒绝均是resource_completion。前五预留集合让较新回调先取得category服务，最老回调随后被其他模块公平门挡住，造成永久饿死。
- 修正为真正FIFO begin顺序，不关闭其他模块公平，不增加1200us预算，不删除等待年龄。direct53因测试清理错误FAIL；direct54修正清理后全部正式专项PASS，包括较新实际owner先回调不能越过已排队旧owner。
- ON08为该最终修复的首次完整34/30/48负载测量，正在执行；性能、主树集成与108依旧未结案。

## 17:10 收尾记录（历史失败不删除）

- ON08已原生PASS，实际34/30/48/300/10200负载完整；CPU974.998ms，最大process CPU5.140ms。当前周期队列10个有效pending，最老174863us；已服务最长434919us，scope为0。持续产生周期请求时不要求队列瞬间为空。
- OFF08原生FAIL为legacy队列在采样结束仍有一个16帧有效pending；没有open scope。该观测不能证明泄漏或预算收益，保留FAIL，不能与ON08拼成已通过性能对照。
- 冷Boss阶段绕过预算的生产路径已补准入；direct60原生PASS，包括拒绝后保留正式阶段anchor、恢复许可后正式召唤一次，以及224/124预算为零仍完成法术HP结算。direct55–59的fixture初态、真实epoch、physics runnable和scope关闭失败完整保留。
- direct64原生PASS：300ms规划、立即攻击、已提交动作、真实碰撞与即时死亡/地图/安全区失效。direct61修正的是“缓存旧grant tick必须等于-1”错误读法；真正断言为本次攻击tick未取得规划许可。
- direct66原生PASS：真实Enemy近战→Player HP→三个hit帧→100ms/240ms锁与跑步衔接。direct63失败原因是只推进渲染而没推进正式Player时钟，测试时序已按现有权威修正。
- direct67原生PASS：原掉率/结果对照及30怪真实死亡掉落切片。零掉落修复和6083槽保持，不实施加权表重设计。
- 6/9/12原生几何测试仍在定位旧fixture缺少的世界/地形身份；不恢复主动扫描、不弱化LOS或范围断言。主树接入和108暂未执行。

审查中的两项玩法变化已有用户明确授权：怪物不回出生点、在当前位置再次激活，因此旧spawn-origin候选限制移除；普通脱战与其他非急维护进入300ms周期。死亡、地图、安全区和已提交攻击仍走即时必要链。召唤物实际位移标脏属于新增引怪入口，查询与玩家共享预算和每帧8候选上限。

## 直线光源规则与新增验证

用户补充确认：人物及未隐身召唤物类似光源，唤醒信号只沿光源与怪物之间的直线传播；被墙体或障碍阻挡就不能激活，不绕墙传播。该决定覆盖此前只在正式retarget时验证LOS的中间实现。

request_passive_target_wakeup在地图、generation、生命、隐身、安全区、6/9/12范围验证之后，记录pending许可和退出后台之前，调用既有正式静态地形LOS。地形身份缺失则拒绝；正式retarget仍重新验证当前位置与LOS。该入口只由中央有预算候选处理触发，不恢复逐怪逐帧搜索。伤害/真实仇恨唤醒规则不变。

direct72：FAIL。整格阻挡、部分格多边形阻挡、无遮挡直线的新增唤醒断言已经经过，但原几何测试另有两项失败：等Manhattan距离的浮点投影偏差、部分多边形用例之后未恢复原直线绕行场景。不能把通过的子断言说成整组PASS。原失败与源码快照保留，修复测试初态后必须完成整组原生验证。

## 17:56 最新完整负载与受伤唤醒

- ON09：PASS。最新Enemy a3ef2a56...，9531来源前后不变；34存活/30入战/48掉落/300物理步/10200回调，整体怪物CPU962.170ms，对固定107控制2061.931ms下降53.33646%。CPU P95/P99/最大3.952/4.705/4.800ms；实际process间隔P95/最大17.696/19.407ms。仅本地单次最新窗口，不冒称新的中位数、全游戏GPU或手机FPS。证据outputs/release_v108_20261009/FINAL_LOCAL_PERFORMANCE.json。
- 10次已提交攻击均结算并完成，141伤害；实际人物移动7.551526GU/159移动步。107是16次/174伤害/3.501084GU，说明300ms追击产生真实接触机会差异，不能宣称相同攻击量或相同实际吃药时间。
- 最多5 owner/process；已服务最长434838us/26帧。采样末仍有10个正常周期pending，最老175692us；所有scope为0，原子工作超额173us保留。不能以队列结束非零推断泄漏，也不强制取消有效请求。
- direct82：PASS。光环外8GU的真实Player作为伤害来源，物理与magic-defense正伤害都即时扣HP、退出休眠、恢复physics、记入仇恨；零预算不丢唤醒，恢复后两个真实帧选中攻击者，最终强断言保留。正式ground-tick伤害同样唤醒但不插播受击；致死伤害沿死亡所有者处理。该专项验证Enemy接收端，不冒称已重新测试全部玩家施法投射链。
- 光环不是唯一入战入口。玩家/召唤物靠近由直线激活信号触发；真实远程伤害和仇恨不依赖6/9/12光环许可。不能把未激活怪变成受打无反应的雕像。
- 整组几何测试602断言经过但native退出崩溃仍FAIL（direct74–81）；修改parent清理、nested subclass、正常bootstrap未解决，历史失败保留。隔离direct83三项纯policy/418检查native退出0；direct84八项actor/184检查native退出崩溃。direct85仅runtime-map身份组native退出0（含该子组自身PASS标记），不能当全组通过。正在依据这些范围定位actor路径，不恢复主动扫描或放宽断言。
- 正式authority生成检查已留实际命令和stdout：156 records/runtime_allowed156 PASS，builder/override/runtime前后哈希不变；AUTHORITY_GENERATOR_CHECK.json补的是缺失收据，未再次生成数据。


## 18:20 接入与验证闭合

2026-10-09 18:20 最新阶段：已精确接入完整 codex/integration 主树，12生产+18测试文件；HEAD215f0b2保持、真实index ddacea4e保持，344个无关dirty文件指纹保持。生产即最新ON09来源：34存活/30入战/48掉落/300物理步/10200回调，CPU962.170ms对固定107的2061.931ms下降53.33646%，最大process CPU4.800ms；仅本地单次最新窗口，不冒称手机FPS或新中位数。光源直线LOS、普通6/精英9/Boss12、人物及未隐身召唤物激活、纯被动冷怪/不回出生点已接入；光环外真实物理/法术/持续伤害独立唤醒，direct82原生PASS。最终寻敌几何602检查direct90原生PASS/退出0/error0；历史74-88退出崩溃保留，单因素改fixture匿名投影为正式静态Callable闭合。Boss60/owner64/真实受击66/掉落67/中央唤醒73按不变函数与来源边界复用。生成器仅删EOF空行，AST相等，正式156条authority check及diff-check PASS。音频、拾取、HUD、特装、Loading、零掉落与post107受击修复保留。固定108来源、正式构建与包核验正在执行，尚不冒称通过；DEVICE TEST: NOT_RUN。证据：outputs/release_v108_20261009/INTEGRATION_RECEIPT.json、ACQUISITION_FINAL_REVIEW.json、FINAL_LOCAL_PERFORMANCE.json。旧段落为各历史阶段，不代表当前状态。
