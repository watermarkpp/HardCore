# HardCore 115：时钟、已接受释放、暂停回执与身份——最终补充

状态：施工前设计裁决。官方源码按函数/区间核对；本轮没有修改生产代码、运行原生验证、构建 APK 或测试手机。

## 0. 最终决定

继续 B 物理方案。S 是唯一游戏与物理所有者；S 内保留 H（logic-physics）与 P（logic-process）两个服务域，二者由同一独立逻辑 iteration 调度，不是两条各自漂移的线程。另设 U（控制/持久回执）非计时服务入口。M 不释放游戏逻辑 epoch，不推进游戏 timer，不消费真实 HP/存档 live 提交。

115 正常运行采用明确的新时钟合同：

- H 的频率 F 取当前正式项目的 physics_ticks_per_second，不改变该配置；h=1/F。
- P 的名义频率首次明确设为同一 F，每个 H 完整物理步之后执行一次 P。P 仍是独立相位，不变成 physics timer。
- E_n 在绝对单调时刻 R_n=origin+n*h 释放。P_n 的依赖是 H_n 完成，不是下一个 R_(n+1)。每个 epoch 的 time_scale 在入口取样，delta 保持 double 运算合同。
- 这明确规范化了原来跟随呈现循环、没有固定 Hz 的 _process。不能宣称旧 _process 原本就是 F Hz；也不能要求新模式同时精确重现任意旧低 FPS 的回调交错。
- 300 ms 仍只属于原决策计划门；不是模拟、P、timer 或 worker 的调度周期。
- 一个世界 simulation 时钟只推进一次。H/P 分别给各自消费者 delta，不能向同一个世界计时器加两遍 h。

## 1. 证据范围与复核结果

生产 GameRoot、Player、Enemy、paused_receipt_pump 的位置和行为，以本轮主控提供的源码核对结果为依据；本轮未取得这些完整最新文件。

通过官方 godotengine/godot 的 4.7-stable 按区间复读：

| 文件 | 已核对内容 | 工具返回的 Git blob 标识（不是本轮计算的 SHA256） |
|---|---|---|
| scene/main/scene_tree.cpp，639–832 | physics/process 相位、timer 原遍历算法 | dd92f0f498c9345acdf0d19ce2f57ac9cc217d29 |
| main/main.cpp，4900–5075 | physics 循环先于 process，max_steps 限制，raw 与 scaled delta 的位置 | b8a7c6c356564f2ac76d6b7a74e6becf4f85e527 |
| core/object/object.cpp，2260–2420、2440–2585 | 原生 Object 登记、ObjectDB add/remove、RefCounted 标记 | d624ba6cfadb0b35d9df93037c716c176233fa7a |
| core/object/object.h，875–980 | ObjectID 组成、get_instance 的锁范围 | 451680a32b5550173c9e75c465f32affcd443392 |

另查官方 ObjectID、RefCounted 源与 SceneTreeTimer 文档。没有下载/校验完整引擎包，也不把该标签当成当前 APK 编译配置的证明。[S1–S7]

关键事实：timer 在对应 process group 后服务；遍历开始截取原尾节点；按插入顺序而非全体绝对到期排序；暂停且非 always 时跳过；扣减后 time_left<=0 才 timeout。默认 create_timer 参数是 always=true、physics=false、ignore_time_scale=false。[S1,S5]

## 2. 每个逻辑 iteration 的固定执行表

| 顺序 | 执行内容 | 明确禁止 |
|---|---|---|
| U_begin | 截取符合时间/顺序条件的控制和输入；在非重入事务边界服务可消费 durable receipt | 不直接提前执行本属 GameRoot._process 的技能输入；不补扣 timer |
| H_prepare | 原 prepare；sync；flush_queries，原同步碰撞回调 | 不从 M 调用游戏 Node 回调 |
| H_group | 原 physics_frame/actor 顺序、连续移动、碰撞、即时攻击；原 deferred/transform 边界 | 不把所有 actor 同时提交，不重复推进位置或 HP |
| H_tail | physics=true 的 timer；原关联 tween、transform、delete 边界 | 不执行 P timer |
| H_step | end_sync→唯一 step→原 post-step/iteration_end 边界 | 不把 step 挪到 actor 之前，不额外 flush 碰撞事件 |
| P_group | 先做原 process 前输入采样，再执行原 process_frame/前置 deferred；原 process 组件顺序，包括 GameRoot._process 的技能输入和持续治疗；原后置 deferred/场景退休边界 | 不改为 H 起点；不把技能输入和治疗交换顺序 |
| P_tail | physics=false 的 timer，同步恢复 accepted continuation；随后原 tween/transform/delete 边界 | 不等下一 H 才执行释放；不按 worker 完成顺序结算 |
| U_end / publish | 服务本边界已就绪的合法持久回执；发布完整已提交表现状态 | 不调用 process(0) 或 timer_sweep(0) 冒充回执服务 |

同名义时刻按上述顺序执行：H_group < H_timer < step < P_group < P_timer。每一组和 timer 内保留原序号。内部调度序号不是新的 ActorRef/release/fact 身份。

输入邮箱在原 H 采样点及 P 前采样点分别取得有序 cutoff；不能把整个 epoch 的输入都锁死在 U_begin，也不能把收到的未来输入回填已经完成的逻辑点。P 的技能调用仍在 GameRoot 原 ordinal；H 的移动输入沿原消费者。输入传送沿已设计的原生桥/邮箱，不借 M._process 的运行次数推进。

S 追赶时也按 H1/P1、H2/P2……执行，不能批量跑 H1/H2/H3 后只跑一次合成大 delta 的 P。回放旧时钟 trace 时，则按 trace 中真实的 0/1/多个 H 再一次 P 执行，用于验证相位适配；二者不是两个同时写生产世界的 owner。

B 的查询许可必须覆盖原来合法的 P_group/P_timer 查询位置。此时唯一 step 已经结束，S 无并发 step，可执行原位置的合法 LOS；不为等待下一 H 而延迟释放，不增加物理 step/flush。原本被配置拒绝的查询也不能借迁移悄悄变成功。

## 3. 时钟合同与等价比较

### 3.1 分开两种验收

**语义等价回放：**向旧参考消费者和新 S 消费者喂同一合法时钟/输入 trace，包括每 iteration 的 H 数量及 delta、P delta、原 unscaled_process_step、time_scale、暂停/生命周期变化点、输入消费点、wall 读取值与 I/O 交付次序。比较释放、移动、HP、timer/事件顺序和旧身份。预算相关比较还需固定准入/消费脚本，不能把不同 CPU 耗时导致的服务次序误判为算法差异。

**115 运行时合同：**真实单调时钟释放固定 E_n，M 渲染频率只影响呈现，不决定 H/P。S 延迟产生的服务 lateness 必须暴露；不以旧渲染卡顿造成的少 process、timer 大步扣减和时间夹限，作为新模式必须模仿的正常行为。

同一组伤害/持续时间常量，在不同合法回调序列下也可能有不同的采样和先后结果。因此“不复现旧低 FPS 交错”是明确的调度合同选择，不是宣称所有历史游戏轨迹都完全相同。

### 3.2 delta 不得混用

原 Main 会先保存未夹限的 _process_step，之后才因 max_steps 调整传给 process 的 process_step。原 timer 的 ignore_time_scale 使用保存的 unscaled step，不能一律用 clipped_delta/time_scale 反推；多次 H 回放时也按原字段执行。[S1,S2]

新模式正常 E_n 中原始 delta=h、缩放 delta=h*s_n；s_n 为本轮入口倍率。回调中的倍率变更不重算已发给本轮的 delta。回放则保留 trace 的不同字段，不做归一化“修正”。

用绝对 epoch 编号和有余数的时刻换算避免持续截断 1/F 的时间误差；timer 本身保留原 double 减法、比较与 get_time_left 行为，不额外加入 epsilon 或改为另一套到期舍入。

## 4. accepted windup 与 timer：精确规则

### 4.1 timer 账本

第一版复用原插入有序账本及遍历算法，不把所有 timeout 改成新 EDF/due heap。每次服务某一 domain 时才截取本次原尾节点，并读取各 timer 的 domain、always、ignore_time_scale 和当时 paused 状态。

| 创建位置 | 新 P timer 第一次扣时 |
|---|---|
| H_group、H_timer 或 P_group；发生在本轮 P timer 扫描开始前 | 本轮 P_tail，扣完整本次适用 delta |
| P_timer 的 timeout/同步 continuation 内 | 下一次 P_tail；不能在本轮同次扫描继续追新尾 |
| U_end、本轮 P_tail 已完成之后 | 下一次 P_tail |
| 暂停期间且 always=false | 保留 remaining；恢复后第一次合法 P 扣时 |

这个排除规则是“同一次遍历中新加入的不处理”，不是“任何 timer 回调创建的新 timer 都必须晚一整 epoch”。例如 H_timer 中新建 P timer，可在稍后的同轮 P_tail 参与；P_timer 中新建 H timer 则等下一次 H。

timeout 同步执行 continuation，再按原实现收尾。较早 timeout 若修改暂停或较晚 timer，较晚元素必须观察到变化。零时长 timer 也不在 create 时直接执行；它在第一次合法扫描触发，暂停非 always 时仍不触发。[S1]

### 4.2 accepted release 规则

每笔已接受攻击/技能保存原 release_id、输入/技能绑定、world/life/combat_epoch 条件及一次性 continuation。替换当前动作、重新瞄准、后续攻击不得覆盖或取消旧 accepted release。死亡、换图、combat_epoch 等原已允许条件才可失效。

在原 P_tail timeout 处检查原合法性并同步完成释放的 gameplay 部分。该 continuation 需要的 LOS/命中/HP 沿原位置由 S 服务，不能移到下一 H 的开头。

结果准备迟到只影响计算副本，不创造新的取消理由。不能把 accepted release 存成“每 actor 只保留最新一个”的槽。

### 4.3 例子：不多等一个 tick，也不改成绝对截止

仅为说明，令某合法 trace 每次 P 的 delta=10ms，windup=25ms，并在 P_n 的 group 中接受：

| 相位 | remaining | 行为 |
|---|---:|---|
| P_n_tail | 25→15ms | 未释放 |
| P_(n+1)_tail | 15→5ms | 未释放 |
| P_(n+2)_tail | 5→-5ms | 在这里释放 |

不能搬到 H_(n+3)。若这只 timer 在 P_n_tail 的 timeout 内创建，第一次扣时是 P_(n+1)_tail，释放相应顺延一次，这是原列表边界，不是线程新加延迟。

也不能改成“接受实际 wall 时刻+25ms”后另行排期；那会抹掉原来当轮完整 delta 的首次扣减。恒定适用 delta=d 时，m=min{m>=1:原逐次 double 扣减后的剩余<=0}；理想实数计算下 m=ceil(w/d)，接受于 group 的释放位置是 P_(n+m-1)。名义时长按 eligible timer 服务度量，不冒充从接收瞬间精确等待 w 秒的墙钟合同。

## 5. 持续治疗、暂停、wall 与 always 服务

### 5.1 持续治疗保持原 P 消费语义

GameRoot._tick_ongoing_heals 继续在原 P_group 位置按 process delta 增加 elapsed，逐次 while 消费 interval；每次治疗及回调仍是独立事实，不合成一次加血。

例：同一个回放 P 的 elapsed 原为90ms，delta=250ms、interval=100ms，应依原 while 处理三次，余40ms。新生产正常会用小的 E_n 逐次运行；比较必须使用同一时钟 trace，不能仅因累计治疗数相同，就断言与一个大 P 的中间玩法顺序等价。

### 5.2 暂停矩阵

| 项目 | 游戏暂停（进程仍获 CPU） | time_scale=0 | OS 停止调度/退出 |
|---|---|---|---|
| 普通移动、普通 GameRoot P、pause-aware 状态 | 按原 process-mode 暂停，无暂停补扣 | 保留原回调与零 delta 行为，不擅自当作 pause | 不伪造暂停期间的执行 |
| accepted windup（always=false） | 不扣，恢复后续剩余 | 不扣正时长；零时长仍按原扫描行为 | 不将未运行时间当作已执行 |
| 默认 death 恢复0.8s（always=true，ignore=false） | 正常扣本 P 缩放 delta | 正时长不扣 | 不保证 OS 挂起期间运行 |
| ignore_time_scale=true timer | 仍先受 always/paused 规则控制；获准后扣原 unscaled 字段 | 可扣 unscaled | 按已登记 suspend/resume 合同 |
| 旧 wall deadline | 用原 wall 时基在原消费者检查，不因游戏暂停冻结 | 同左 | 恢复时按原绝对期限/补偿合同处理 |
| durable receipt | U 继续服务，与 H/P delta 无关 | U 继续服务 | 有 CPU 时排空；被系统终止则由耐久日志恢复，不能声称后台永远执行 |

“process_always”不等于“ignore_time_scale”，更不等于“保证系统挂起也执行”。默认 create_timer(0.8) 不是 wall timer。[S5]

暂停不停止 E_n 的调度基础：仍服务 always 组件、timer 和 U；只按原暂停规则停掉 gameplay 消费和物理积分。若暂停在回调内改变，后续消费者按原位置读取新状态，不能简单把整轮 paused 值永久冻结。

真正 APP_SUSPEND/恢复必须沿现有生命周期合同：保留 scaled remaining，不为休眠期间补跑大量移动/攻击；旧已登记 wall/wake 补偿只执行一次。若 Android 已不调度进程，receipt 也不可能承诺即时 live 提交。此边界不等同于普通 SceneTree.paused。[S1,S8]

## 6. 回执服务与积压：明确不靠渲染续命

### 6.1 U 是非计时事务入口

U 在完整逻辑 epoch 边界，以及空闲/暂停时 I/O 通知唤醒后服务。单个 actor、HP 提交、timer continuation 和物理 step 中不重入提交。正常原 process receipt 消费者如有固定服务位置，也迁到其原 ordinal；额外 U 是显式记录的外部事件交付边界，不双消费。

I/O 唤醒只投递不可变 receipt。S 截取一批本次可处理队列和序号后消费；期间新到结果在下一合法边界处理。不同事务结果不按 worker 完成快慢越过原 sequence/资源依赖。

U 不调用 process(0) / process_timers(0)：零 delta 扫描也会触发已为零的 timer，从而错误地夹入攻击或死亡恢复。

原 frame budget 的线程归属迁到 S，epoch 改为一次 E_n，H/P 不各自重置一份预算；U 也不能通过虚构 epoch 给其他工作加额度。不可逆回执维持必要服务和完整记账，不因 world paused 被整体拒绝。

### 6.2 已补保存链的裁决

接受该结构：

S prepared plan → immutable I/O → durable receipt → S 原 context/sequence/并发消耗 delta 验证 → live 提交与 watermarks → 通知。

必须保留：I/O 不能修改 registry；回执不覆盖准备之后已发生的合法消耗；重复回执幂等；watermark 的持久性和恢复边界沿原协议；world/profile 不匹配时，不能把已发生的 durable 事实当成普通 worker 过期结果直接丢掉。持久侧转交原事务 owner 恢复，live 侧不得污染新世界。

暂停服务的不是允许新战斗随意结算，而是完成原本已经不可逆的事务。旧 M paused_receipt_pump 在新模式不得继续写第二份 live 状态。

### 6.3 积压政策

- M 迟到：不改变 E_n/delta，不造成 H/P 少跑。
- S 短时迟到：保持小步 H/P 成对追赶，timer 和治疗义务不合并、不丢。发布实际 lateness，不回填成准时。
- 每次追赶 turn 的上限取原 max_steps 数量，但含义明确改为“本次最多连续服务多少个完整 E”，而不是丢弃多余物理时间或裁掉 P delta。每个完整 E 边界可检查 U。
- 未服务时间用 next_epoch/debt 表示，不为每个欠帧分配一堆 world/worker 快照；在途任务仍有界。
- 115 初始故障线明确取 L_fault=M*h，其中 M 是构建固定的原 max_steps，h 是原物理步长：欠账超过 M 个完整 E 即 CLOCK_OVERRUN。它是新增的安全故障阈值，不是玩法周期，也不是证明能达标的预算。所有单次 deadline miss 仍分别记录。
- CLOCK_OVERRUN 在当前不可分提交结束后的安全边界进入显式故障状态；不继续伪称正常战斗，不默认慢放、不丢债、不补造准时状态。保留内存中已接受义务，继续必要 U 回执服务；重启/退出按原耐久恢复协议，不承诺未持久化状态跨进程保留。该场景不通过115交付门。
- 故障阈值如需调整，必须在发行配置中事先版本化；不能观察失败后自动放宽。max_steps 的原夹限效果不作为新运行时的正确性目标。

## 7. SimActorHandle 与既有身份

### 7.1 与 B 和唯一权威兼容

S 在 spawn 的原接受位置创建原生、Node-free SimActorHandle，以真实 get_instance_id 进入既有 runtime_id 发放流程。原 ActorRef={world,runtime_id,life_generation}、world_context、release_id/fact_id/credit/chain/死亡去重键不增加第二命名空间。M proxy ID 仅用于显示定位。

handle 不拥有另一份 HP、alive 或计时器；registry 是唯一游戏状态。actor 是否活着、属于当前 world、是否退休，由 registry 判断，不以 RefCounted 还活着作为 gameplay 存活证明。

S registry/必要 continuation 正确持有 native Ref；出生后完整初始化再发布，退休先从 resolve 合同中失效，再安全释放。M/W 只拿身份值或不可变数据，不以 ObjectDB 返回的裸指针跨线程执行业务。旧 mode 与新 mode 不混用 resolve 后端。[S3,S4,S7]

### 7.2 必须修正“spin_lock 已证明全部安全”的推论

ObjectDB add/remove/get 的锁保护表操作；get_instance 在返回指针之前已解锁，不替调用者延长对象生命周期，也不保护其 HP/方法并发访问。[S3,S4]

纯 native handle 应在 S 释放最终引用，避免 script/extension 引用计数回调或销毁连接回到 M。RefCounted 自己的引用计数机制不能替代 owner 规则。[S7]

### 7.3 RefCounted 最高位是一个真正的兼容门

官方 ObjectID 的 bit63 标识 RefCounted；转换为 Variant/GDScript 有符号64位时可能呈负数。因此：

- runtime_id 有效性不能自动沿用 >0；要按原 schema 合法域核查真实64位 ObjectID。
- 禁止 abs()、清高位、32位截断或 float/JSON 数值中转丢精度。
- 完整检查 PlainGraph、字典键、字符串化/种子、序列化、恢复和 C++/GD 边界；本轮没有看到这些新代码，不宣称已经通过。[S3,S4,S6]

固定降级选择：若现有不可变 schema 确实只允许正整数 ID，且不允许修改合法域，则采用 Node-free 原生 Object handle、由 S 明确管理生命周期；不强推 RefCounted，不清位伪造 ID，不新增另一个 actor 编号。

全局 ObjectDB 的发号也不提供跨线程重跑的确定性。M 创建 proxy 等对象的交错可以影响新 ObjectID 数值；原 schema 合法不等于两个独立运行的 ID/随机轨迹必然一致。算法等价回放须向两边提供同一已接受身份与同一原种子输入，不能在结果之后随便归一化身份，掩盖 seed 输入变化。本轮不为此另建身份权威。

## 8. 最小施工顺序与验收门

| 顺序 | 交付内容 | 必须通过的设计对应验证 |
|---|---|---|
| 1 | S ClockFrame/epoch 与 H/P/U 固定相位；只接时钟适配 | 同一clock trace下0/1/多H再P、raw/clipped delta、phase顺序；M不再驱动游戏时钟 |
| 2 | 原 timer 遍历与 accepted continuation | 同轮首次扣时、timeout中新timer边界、跨domain创建、零值/恰好零、暂停/time_scale、动作替换不取消 |
| 3 | 迁入GameRoot真实技能输入/持续治疗、原death/尸体/respawn合同 | 不挪H、不合并while治疗、不用显示节点存在与否取消已接受义务；各timer flags来自真实调用 |
| 4 | U保存回执与S-only identity resolve | 暂停和零倍率仍服务durable回执；乱序/重复/换world回执；64位ObjectID往返、销毁重生、旧生命期拒绝 |
| 5 | 接入B正式writer及真实重工作 | 同物理/HP/释放事实；无M writer；真实完整链的deadline和输入/状态新鲜度，不用微基准代替 |

专项必须包含：在P_group创建timer、在P_timeout创建timer、H_timeout创建P_timer、多个due timer按原插入顺序、timeout回调暂停/恢复、同轮新场景退休、accepted A后动作B替换、death/map/combat_epoch失效、always0.8与pause-aware windup同场景、旧wall过期、paused receipt、新旧runtime_id符号域、已持久化但live失败后的恢复。

这些是同源语义和完整事务验收，不要求用户重复手机复现，也不以减少怪物或禁止原技能交付。正式115优先保留原包名、签名和旧档；如需并装测试系列，使用独立测试数据，不能以换包名掩盖时钟或身份错误。

## 9. 收束

可按本文固定规则推进生产writer迁移：一位S、两服务域、一条绝对release源；step后P；timer保持原首次扣时与列表截尾；accepted release按原失效条件，不随动作替换取消；暂停仍服务always及durable receipt；渲染延迟不控制游戏计时。

不承诺复现旧低FPS造成的全部交错，也不把尚未发生的构建/原生/设备结果写成通过。本文件完成的是时钟与身份边界的设计封口，不是115 APK交付证明。

## 官方来源

- [S1] [Godot 4.7-stable SceneTree，physics/process/timers](https://github.com/godotengine/godot/blob/4.7-stable/scene/main/scene_tree.cpp#L639-L825)
- [S2] [Godot 4.7-stable Main iteration](https://github.com/godotengine/godot/blob/4.7-stable/main/main.cpp#L4900-L5075)
- [S3] [Godot 4.7-stable Object / ObjectDB](https://github.com/godotengine/godot/blob/4.7-stable/core/object/object.cpp#L2440-L2527)
- [S4] [Godot 4.7-stable ObjectDB lookup](https://github.com/godotengine/godot/blob/4.7-stable/core/object/object.h#L875-L942)
- [S5] [SceneTree create_timer 文档](https://docs.godotengine.org/en/stable/classes/class_scenetree.html#class-scenetree-method-create-timer)
- [S6] [Godot 4.7-stable ObjectID](https://github.com/godotengine/godot/blob/4.7-stable/core/object/object_id.h)
- [S7] [Godot 4.7-stable RefCounted](https://github.com/godotengine/godot/blob/4.7-stable/core/object/ref_counted.cpp)
- [S8] [Godot 4.7-stable SceneTree pause / suspend](https://github.com/godotengine/godot/blob/4.7-stable/scene/main/scene_tree.cpp)
