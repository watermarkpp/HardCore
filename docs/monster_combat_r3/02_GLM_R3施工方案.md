# HardCore 怪物战斗 R3 Implementation Plan

> **执行者：GLM。** 按任务顺序使用 executing-plans 与 test-driven-development 流程；每项先记录真正行为失败，再做最小修复和定向回归。不得把缺函数解析错误当行为RED，不得把本包未运行的场景说成审查者已验证。

**Goal：** 关闭固定R2版本剩余的攻击时钟/身份/朝向、双向受击生命周期、身体准入、构建校验及真实验收缺口，让怪物系统在真实战斗中成立，而不是仅使旧报告变成PASS。

**Architecture：** 继续沿用现有EnemyActor、MonsterVisual、PlayerCharacter、身份目录、物理/空间索引和唯一伤害结算。Actor拥有战斗动作时间和生命周期，视觉/声音只消费；身体先通过正式身份准入再进入世界；生成链与测试使用精确、可复核的合同。禁止整体重写AI或额外构建第二套伤害调度器。

**Tech Stack：** 项目固定Godot/GDScript、Python标准库、现有PowerShell runner。以仓库已固定引擎为准，不升级依赖。

**Spec：** 同包 `01_R2远端复审报告.md`、`04_验收矩阵.json`；已有R1/R2要求仍有效，本计划将其未完成部分具体收敛。两份已恢复原始对话继续保留；缺失的一份如实登记，不能编造其内容。

## Global Constraints

1. 审查基线：R2=`2960bbe682b61306eed8f7c9fe0c6eb6c6accb9a`；R1=`9a399c242c51dd4068d2dc155829449f6159c3f1`；BASE=`f5d6308f53162509bffd30f6981987cbfe80fa68`。
2. 保留当前1.5GU中心距离准入与现有EPS；不加身体半径扩大射程、不简单回调2GU。延迟命中的既有明确容差单独登记，不把它误当准入距离。
3. 保留两档身体small=16px、large=0.5GU、玩家=18px；不改变贴图/脚点/黄圈、不从图像尺寸推碰撞、不随Boss标签隐式授权能力。
4. 保留R1修好的空Boss规则基础周期/能力默认关闭、R2的复活耐久与最新受击修复。
5. 禁止用渲染到某帧、纹理加载完毕、声音成功播放作为伤害许可；特殊投递的0延迟不能统一改成200ms。
6. 普通怪物受击、直击法术、火墙、毒DOT分别保留已确认合同；合并视觉反馈不合并伤害、攻击延期、仇恨或状态事件。
7. 保护人工地图、掉落概率和槽、装备/技能数值、持久化格式与版本。AGENTS.md、project.godot、导出配置不借机修改；确需修复生产出生/注册消费者时，可最小修改共享脚本，但必须在变更账本说明调用依据，不以“共享文件零diff”保留已知错误。
8. 无每击Timer/Node/全场扫描；不重置既有寻路/空间缓存预算；启用诊断时也不得无限记录。无APK、设备安装、合并、强推、清树或清存档动作。
9. 最新怪物目录值是来源核对后的基线，不从旧聊天记忆复制数值。任何数据变化要有字段级来源，不允许为了测试通过先改数值。
10. 相关既有故障属于本轮收敛范围；“BASELINE_EXISTING”是来源标签，不是自动豁免。只将有证据不影响该目标的独立项外移。

## Review Focus

- 动作开始于两次绘制之间，再经历暂停、低帧、资源恢复：视觉不能提前结束或过期重播，逻辑伤害不变。
- A的绘制帧还在缓存时B开始：不得用A的帧消费B的音频；新旧动作/生命代际不能混同。
- profile结构自洽但档位错配，或正式身份被拒绝：不准小身体继续运行、不准留可受伤虚拟敌人、不准泄漏Node。
- 致死/复活/耐久广播里同步重入、换图或进入下一次死亡：旧尾部和延迟通知不能越过所属生命；合法耐久不能漏。
- 性能采样名称对应的宠物、AOE、死亡、逻辑帧必须实际出现；否则测试应先按“无效负载”失败，不能输出性能PASS。

---

## W0：固定现场、补证据、建立反例（覆盖R3-10；其他任务的前置）

**文件：** 新建 `docs/monster_combat_r3/BASELINE.md`、`REQUEST_LEDGER.md`、`evidence_index.json`；先落入本包三个反例场景。读取AGENTS与项目合同，但不修改。

- [ ] 在原施工树确认没有独有未提交内容，再获取远端。远端已前进时，先记录新提交并复审重叠路径，不能将新SHA静默当2960。

```powershell
$ErrorActionPreference = 'Stop'
$Expected = '2960bbe682b61306eed8f7c9fe0c6eb6c6accb9a'
git status --porcelain=v1
git branch --show-current
git fetch origin
git rev-parse HEAD
git rev-parse origin/codex/monster-combat-r1-20260925
git rev-parse origin/codex/integration
git diff --name-status $Expected HEAD
```

- [ ] 记录三种内容身份：HEAD、工作树diff、未追踪/被忽略的必需脚本。核对原R2证据ZIP与runner实际文件，将关键日志复制到可交付证据目录；敏感设备标识可脱敏但不得删除错误、时序或测试结果。
- [ ] 保存BASE、R1、R2在场景/技能/掉落/人工地图等受保护域的Git树指纹；只对当前变更域复审，不重新生成地图。
- [ ] 从 `failure_register.json` 读取30项旧登记，另外读取R2 full critical实际34失败集合。分别统计28旧失败、5修复后定向结果、1未定负载敏感，以及不在失败集合中的2项转绿；不能把两集合相加。
- [ ] 将本包三个 `.gd/.tscn` 复制到相同 `tests/hc_monster_combat_r3/`；先临时Git跟踪测试文件以满足runner要求，不提交生产改动。原Godot夹具若有解析/导入问题，先修夹具，再测真正目标反例。

```powershell
git add tests/hc_monster_combat_r3
& tools/run_godot_tests.ps1 -TestPaths @(
  'tests/hc_monster_combat_r3/body_rule_tier_cross_test.tscn',
  'tests/hc_monster_combat_r3/audio_stale_frame_test.tscn',
  'tests/hc_monster_combat_r3/stale_death_notification_test.tscn'
)
```

**结果要求：** 旧源码上的行为失败要逐条记实际断言/日志。若某反例不失败，说明源码已变或假设不成立，先写明原因，不能为了照抄报告去制造失败。测试不算修复，W0不得报“已完成全部整改”。

---

## W1：建立唯一的战斗动作时间和身份（覆盖R3-01、R3-02主体）

**修改：** `scripts/enemy.gd`、`scripts/monster_visual.gd`。按现有真实调用关系最小扩展对应范围/投射物release构建处；禁止新增第二套伤害调度服务。

**新增测试：** `tests/hc_monster_combat_r3/attack_game_clock_test.gd/.tscn`、`attack_parent_release_identity_test.gd/.tscn`。

### 接口与所有权裁决

生产动作身份为四元组 `(source_instance_id, source_life_epoch, action_serial, world_generation)`；来源地图和父节点身份沿用原release合同。一个动作产生多个受害者/子投递时，子`release_id`仍各自存在，并携带同一父身份，绝不能合并所有子伤害。

建议在Enemy既有动作状态增加以下primitive字段（可等价命名但INTERFACES须逐项对账）：

```gdscript
var _combat_action_time_s := 0.0
var _attack_action_start_time_s := 0.0
var _attack_action_duration_s := 0.0
var _attack_action_source_life := -1
var _attack_action_generation := -1
var _attack_action_active := false
```

沿用并明确 `_attack_logic_serial` 为真实动作串号，而不是播放请求串号。`_combat_action_time_s`只在Actor游戏更新的唯一入口随真实delta前进；时间缩放已包含在项目实际delta中，不额外再乘一次倍率。暂停保留动作则冻结；生命周期取消动作则同时使pending/表现/阶段失效。动作处理不得走后台休眠分支而积压到过期补播。

**不得**再把`Time.get_ticks_msec()`或Visual `_clock_ms`当生产战斗年龄。保留旧预览API供预览时使用，但生产必须走身份绑定入口。`_attack_logic_started_at_ms`不能继续做“保存但不消费”的摆设；迁移到明确的游戏时间字段，或删除旧假接口并同步调用方/文档。

### 施工与反例

- [ ] 先建立真实Actor推进、Visual消费分离的夹具。测试数据：duration=.46，攻击前游戏时间=.49，下一次绘制delta=.50但动作实际游戏年龄=.01。余量应约.45，不是0，也不是重开.46。
- [ ] 增加暂停反例：动作推进.10，暂停实际1秒，再恢复；若保留动作，余量仍约.36，pending伤害余量同源；若既有暂停策略取消，两者必须一起取消且不补声。测试明确采用的是项目哪一种策略。
- [ ] 增加相同物理输入、不同绘制频率30/60/120以及一次200ms跳绘制：逻辑起手、release、HP、状态结果必须相同。绘制帧数允许不同。
- [ ] 从 `_hc_try_start` 的真实准入点分配父身份，先冻结冷却、目标/来源代际、release参数，再发布表现。普通/特殊近战、Boss技能、范围、召唤各自的动作生产入口逐个迁移；同一逻辑动作不因重复展示请求再分配新身份。
- [ ] 真实pending记录和子release写入父身份。结算在回调前后按原生命/地图/父节点保护复核，不改变已有命中和伤害公式。
- [ ] Visual持有owner身份与游戏起点，只计算 `duration - max(0, owner_game_time - start_game_time)`；不再次扣render delta。冷加载/离屏恢复只呈现仍有效动作的当前进度，已过期只记诊断，不重新满时长补播。
- [ ] 对同一动作重复begin：幂等，不重置年龄、不再发开始声；旧life或旧serial begin/sync：拒绝。`setup`或死亡结束后再入树，不得接受前一生命的表现。

**具体断言：**

```text
logical_start(A) exactly 1
pending.parent_action == visual.owner_action == audio.owner_action
same action A, update twice -> unchanged serial and no age reset
different render schedules -> same HP delta and child release count
resource missing / muted -> same logical result
source epoch changes before release -> original cancellation policy, no stale replay
```

**回归：** 原Boss周期、普通受击不取消已提交攻击、毒无STRUCK、命中误差/范围快照、投射物生命周期。新增测试与实现一起提交，不能先留一组空接口等待下一轮。

---

## W2：接通身体朝向和音频阶段，保留有界受击反馈（覆盖R3-02音频、R3-03）

**修改：** `scripts/monster_visual.gd::_update_animation_frame/_start_attack_visual`；`scripts/enemy.gd::_audio_observe_visual_state/_audio_attack_started/_hc_tick_melee/_hc_finalize_boss_facing`及实际音频上下文构建。无需重写音频服务限流。

**新增测试：** `attack_facing_policy_test`、`attack_audio_phase_identity_test`；保留本包`audio_stale_frame_test`作为回归，但必须再加真实动作入口测试。

- [ ] 列出当前所有可达delivery的朝向政策：固定起手朝向、明确授权的前摇追踪或投递时追踪。使用版本化策略映射或已存在字段，不按怪物中文名字硬编码。默认保留已确认规则，不冻结所有追踪法术。
- [ ] 将身体attack选行改为消费该动作同一朝向政策；固定型使用捕获朝向，跟踪型由Actor依据已授权策略更新动作朝向。AttackOverlay/身体/伤害几何不能各选一套方向。
- [ ] 测试238/239/76：A起手后目标绕到另一个方向；固定型身体仍显示A方向，下一次B再更新；授权跟踪型则按同一目标和释放时点一致更新。必须读取实际身体current_direction，不只检查 `_attack_facing_at_commit` 字段。
- [ ] 音频phase分成 `reached/consumed` 与 `played`。开始声被预算拒绝后，不能让动作年龄和frame阶段消失。静音/预算仍由原服务决定，测试服务可分别拒绝start、接受frame以验证解耦。
- [ ] 不再通过未带动作身份的缓存`current_state/current_frame`决定当前B阶段。按W1动作elapsed跨阈值提交；第3张零基帧2对应的阈值从该动作正式帧数/时长推导，原有专属音效阶段覆盖优先。资料没有帧声的身份不能合成新声音。

```gdscript
# 阶段纯计算示例；首次阈值0单独消费，完成标志须在外部回调前写入。
func phase_crossed(before_s: float, after_s: float, threshold_s: float) -> bool:
	return before_s < threshold_s and after_s >= threshold_s
```

- [ ] 注入A当前绘制frame4、B刚起手的真实序列：B未达到phase前不得有B的frame音效。注入0→3跳帧：B合法phase只提交一次。重复观察不重复。动作已经结束/取消则不能用R2的“不是attack时补声”分支重放旧声音。
- [ ] 维护R2最新STRUCK合并修复，不改damage/attack-delay计数；对1/16/17/1000个视觉受击事件证明存储上界、最新时长/步屏障、后续不无限补旧反馈。旧预览FIFO与生产关键动作应有明确入口，不能让生产误回FIFO。
- [ ] 对真实死亡、换图、source失效和可见性变化测试音频取消策略。禁止为通过测试去豁免音频预算或强制打开声音。

**验收：** 同动作的身体/overlay方向一致；逻辑、视觉、音频拥有同父ID；没有错读前一动作、无声道成功依赖、无过期补声。新旧R1/R2测试中要求“动作结束补声”的断言要以本任务明确合同替换，并记录原因，不保留与新合同矛盾的断言。

---

## W3：严格身体归属与完整世界准入（覆盖R3-04）

**修改：** `scripts/actor_body_policy.gd`、`scripts/enemy.gd`；核查并最小修复真正消费setup结果的生产出生/索引注册调用点。`scripts/summon_actor.gd`仅在同一身体准备顺序确有缺口时改动。禁止用禁战开关代替准入拒绝。

**新增测试：** 本包`body_rule_tier_cross_test`；另加`body_rejection_world_admission_test`、`body_rejection_lifetime_test`。

- [ ] 在旧2960源码运行cross反例：76保留boss规则但小档半径、24保留default_small但大档半径。需要真正被旧resolver接受才算行为RED；原profile阳性对照保持通过。
- [ ] 统一解析 `identity -> expected_assignment_rule -> expected_tier -> expected_px/GU`。不要再用profile声明的tier自行取expected_px。身份来自已要求的canonical entry，外部传入classification只能交叉核验，不单独授权。拒绝未知/非正ID、空规则、错hash、错tier、错换算及非有限输入。
- [ ] Python生成器与运行时共同遵循同一版本化策略。至少用全ID期待结果和错误矩阵比对两者；生成器已经检查expected_tier的部分保留。
- [ ] 将“身体可用”的解析移到正式怪物对外暴露之前。`_ready`不可先add_to_group再假拒绝。CollisionShape2D在valid后再new/add_child；失败必须释放临时资源，不留孤儿Node。
- [ ] 明确定义实例准入状态（如 `_runtime_admission_rejected`）。正式无效实体拒绝加入敌人组/空间索引/选择/伤害/死亡掉落/计数；工厂失败时回收出生名额与预留，不能留下看不见但阻挡的空间索引条目。正常禁战宝箱仍按原合同存在，不能用`not combat_enabled`实现全局拒绝受伤。
- [ ] 实例在树外setup、树内ready、正式spawn快照/索引注册四阶段使用同一个最终半径。选择“setup完成身体解析”而非让消费者读取默认15/16px再在ready改变；现有调用顺序允许其他实现时，必须证明没有ready前消费者读到旧值。
- [ ] 真实出生失败反例：无效profile进入正式工厂，断言敌人组、空间索引、合法刷新占用与掉落都不增加；有效profile对照正常。重复100次拒绝，场景内Node与孤儿资源计数回到初始容许范围，日志无泄漏。

**不得仅验收：** `combat_enabled=false`、没有CollisionShape、meta存在。这三个事实不能证明从世界查询和受伤链中隔离。

---

## W4：修复目录替换门，验证唯一生成链（覆盖R3-05）

**修改：** `tools/verify_catalog_reswap.py`、`tools/build_canonical_monster_catalog.py`的必要校验部分；不恢复已退役注入器。新增`tests/test_catalog_reswap_contract.py`与字段级差异批准清单。

- [ ] 执行同包Python原脚本反例，保留两项对照和三个违规放行证据。该结果是校验工具的RED，不是Godot运行失败。
- [ ] 新校验器首先对old/new各自独立验证：entries与entries_by_id为正确类型、ID严格合法/唯一、键集相等、键与嵌入ID一致、每个条目完整内容相等。不得只比较body_profile。
- [ ] 再做递归语义diff。没有列入批准表的任何路径变更都失败。来源hash大小写可按既有合同规范化，但不得忽略源的增删或将整个sources放行。拒绝NaN/Infinity、非法ID强制int取整等不确定输入。
- [ ] 审核33/183/241只允许的实际掉落豁免叶子、已授权精英来源依据更新、BODY新来源与相关来源hash变化。每条批准记录明确JSON Pointer、旧值、新值、授权文档位置；无关combat source_evidence不能跟着掉落豁免一起通过。

```json
{
  "schema": "hardcore.catalog.approved_diff.v1",
  "base_sha": "2960bbe682b61306eed8f7c9fe0c6eb6c6accb9a",
  "approved_changes": []
}
```

默认空表意味着本轮不批准额外玩法数据变化。对已有R1→R2重建复核，应建立单独且完整的历史允许表，不混入R3授权。

- [ ] 删除所有“只print差异但返回0”的保护漏洞；验证失败不改原输入、正式目录或已发布文件。成功发布先写临时文件并验证再原子替换，现有真正生产写入入口保持唯一。
- [ ] 在真实工程按正式来源重建到两份临时产物，检查字节一致、目录闭合、来源溯源、输出与当前正式数据的字段级diff。不得先修改hash去绕过语义漂移。

```powershell
python tools/build_canonical_monster_catalog.py --output outputs/monster_combat_r3/catalog_build_a.json
if ($LASTEXITCODE -ne 0) { throw 'First canonical rebuild failed' }
python tools/build_canonical_monster_catalog.py --output outputs/monster_combat_r3/catalog_build_b.json
if ($LASTEXITCODE -ne 0) { throw 'Second canonical rebuild failed' }
$a = (Get-FileHash outputs/monster_combat_r3/catalog_build_a.json -Algorithm SHA256).Hash
$b = (Get-FileHash outputs/monster_combat_r3/catalog_build_b.json -Algorithm SHA256).Hash
if ($a -ne $b) { throw 'Canonical rebuild is nondeterministic' }
python tools/build_canonical_monster_catalog.py --check
if ($LASTEXITCODE -ne 0) { throw 'Checked-in canonical output is not reproducible' }
```

- [ ] 原样运行反例工具对修后脚本`--expect-fixed`，5个合同全部成立。增补空/缺索引、额外索引ID、错嵌入ID、列表与索引全字段不一致、掉落UID/概率变化、错误来源删除和无关证据修改。
- [ ] 将“22086说明修复了漂移”和“DELIVERY仍说待所有者”的矛盾按本轮实际命令输出统一。结果是成功就记录精确hash；失败就具体指出源/字段/原因，不能同时写PASS与BLOCKED。

**验收：** 唯一生产生成路径可重建；正确数据不受影响；错误数据/无授权字段diff被拒绝；不以“条目/槽数量不变”替代逐字段保护。

---

## W5：玩家受击结果、复活耐久与死亡回调的生命周期（覆盖R3-06）

**修改：** `scripts/player.gd`；如果必须让怪物消费接收状态，只在相应 `enemy.gd` 命中投递入口接入，不改技能/装备公式。

**测试：** 保留`revival_durability_test`；运行包内`stale_death_notification_test`；新增`damage_reentry_lifecycle_test`、`monster_hit_followup_receipt_test`。

- [ ] 首先测试两个生命周期反例：公开复活完成后，旧死亡通知不得发；第一次死亡通知等待期间先复活再第二次死亡，第一次token不得借第二次`_dead=true`冒充当前死亡。仅检查_dead还不够。
- [ ] 致死决策在广播前提交，分配 `death_sequence` 并捕获combat_epoch/parent/world identity。复活完成、换图、退出或取消要使旧token失效；0.8s回调在通知前严格复核。保留当前0.8秒表现时长，不改变掉金币比例。
- [ ] 将异步死亡表现/通知从同步伤害结算尾部分离。同步部分可以返回最小结果，旧void公共入口仍可保留适配。不得直接把带await的方法改成Dictionary返回就假设所有调用者同步拿到结果。

建议内部结果字段：

```text
accepted                 本次释放是否被合法接收
receipt_id / release_id   接收/释放身份，允许明确“旧调用未提供”但不能伪造
source_life / target_life 接收时对应生命，已存在者沿用
outcome                  alive / revived / dead / rejected
hp_damage / mp_paid      结算期间真正的两类支出，不能用复活后的净HP差替代
physical_component      为耐久/已确认吸血等保留原语义
post_hit_allowed         当前代际是否允许接续控制/毒等效果
failure_reason           拒绝原因，不能统一变成成功0伤害
```

- [ ] 测试耐久广播中同步触发第二击：独立合法第二击须被正常接收；外层回到struck尾部时复核当前alive/epoch，已死亡/换图不得再排旧受击。不要用整个damage函数粗锁来吞掉第二击。
- [ ] 复活消耗、普通物理耐久分别按本击身份恰一次；被其他回调改变的后续生命不能补消费旧物品。固定raw3995反例继续通过；高防、护身MP全支付、混合伤害、零伤害和致死分支分别核对原公式。
- [ ] 怪物附加效果依据合法接收结果，不依据“take_damage调用返回了”。死亡/拒绝/换代的目标拒绝旧控制上毒；攻击者已经死亡不得通过回执后的吸血变回活体。吸血基准保留正式来源，不能凭最终HP净差统一改造。
- [ ] 中毒检查种子必须实际施加毒，不能在空状态断言“复活没有遗留毒”。分别验证正式死亡和自动复活戒指的已确认政策；没有明确依据不得顺手把两种复活的毒规则改成一样。

**验收：** 死亡通知、掉金币、物理耐久、复活消耗和命中附加效果，均能按所属release/生命对账；原攻击/法术已提交释放不被普通受击伪取消；地图切换不接收旧尾部。

---

## W6：真正的全怪物战斗、身体与双向受击验收（覆盖R3-07、R3-09）

**修改/新增：** `tests/hc_monster_combat_r3/monster_runtime_behavior_census_test.*`、`boss_real_attack_sequence_test.*`、`body_pair_production_matrix_test.*`、`struck_delivery_matrix_test.*`；更新相关旧断言及 `tools/run_godot_tests.ps1` 正式注册。旧R2表现/加载单元测试可保留但改准描述。

### 6.1 全身份清单与可达性

- [ ] 从正式目录取得允许集合、正式地图刷新集合和敌方召唤可达集合，逐ID对账。156以及9个禁战是当前基线核验值，不是用来跳过新增/缺失身份的魔法数字。
- [ ] 每行记录：ID、分类、body rule/tier/PX/GU、runtime允许理由、禁战合同、目标获取与移动权威是否有效、delivery kind、起手range/形状、基础/有效攻击间隔、真实release时点、伤害通道、实际验证场景、失败理由。
- [ ] 对只召唤/自爆/固定范围等身份使用其真实能力合同，不能强行要求普通近战动作；但不许用“播放动画成功”掩盖缺时序/缺AI。33/183/241的来源缺口必须逐项核清：真实数据缺失则修正式来源；合同确实无需普通攻击时序则建立明确例外及能力测试。

### 6.2 三Boss的20次真实攻击

- [ ] 238、239、76分别配置真实Player、正式地面投影、开放地形和空间索引；不把它们的真实setup结果改成手工假数值。给靶子足够HP或用合法测试方法隔离致死，但保留伤害入口和随机种子。
- [ ] 等待真实SceneTree物理帧，让AI自行获取、接近、准入、冷却、释放。禁止循环`_play_attack_animation`制造“20次起手”。
- [ ] 每只收集20个不同父动作：起手物理帧/游戏时间、距离、body方向、音频阶段、release/受害者、HP结果。测量连续间隔与 `_current_attack_interval()` 及受击延期的关系；允许按物理步长量化，不能固定500ms推进假钟。
- [ ] 分别测试不还手、持续物理还手、直击法术、火墙、移动绕圈、墙后、安全区、资源冷/热与暂停。特殊魔法/混合通道仍走原通道，不能为了统一日志改成普通物理。
- [ ] 只在专门的准确率对照测试固定命中roll；其他用例允许miss，必须区分未准入、miss、护盾支付、真实HP伤害，不以“每击都掉血”强迫改变命中规则。

### 6.3 身体对与实际运动

至少覆盖小怪→玩家、大怪→玩家、大怪→骷髅、大怪→神兽、骷髅→大怪；神兽的3×1攻击足迹独立按正式合同测，不能错套1.5GU普通近战。

- [ ] 每对8方向从范围外真实移动到停止；核对物理形状、空间索引、脚点中心、停点、未穿身、准入和伤害。再在1.499/1.5/1.501做独立静态边界对照。
- [ ] 1.5为包含边界且尊重现有EPS；在1.501必须拒绝普通近战起手。设置现有延迟容差时分开测试“起手拒绝”和“已提交释放容差”，不混淆。
- [ ] 增加墙角、狭通道、障碍占用出生、宠物截停、被击退强制位移、重召后的索引位置与body半径。不得使用“精确尺寸相等 OR 小于射程就好”的宽松断言。

### 6.4 双向受击矩阵

- [ ] 怪物：普通STRUCK不锁移动、不取消已提交释放；真实直击法术在资格满足时延后下一步，当前步完成；MAC压至0、抗魔躲避、等级边界、火墙、毒DOT分别按正式规则验证。通过生产CombatRuntime调用，不只直接调用延期方法。
- [ ] 人物：真实request_attack/request_skill之后受击，先记录真正的release到达，再检查排队受击；不靠手动把 `_pending_combat_action_active=false`假装动作完成。覆盖普通命中、强制受击、魔法盾、护身MP、混合伤害、毒与正式死亡/复活。
- [ ] 验收门本身加破坏性自检：在独立临时测试候选中使 `_hc_try_start`恒false、禁止伤害派发、让空间索引不更新，三种破坏都应使对应集成测试失败。反例注入不得提交或残留到正式候选。

### 6.5 相关基线失败关闭

逐项写入新的failure register：`test_path / root_function / production_reachable / scope_reason / verdict / authority_ref / fix_commit / final_evidence`。

- 70旧1GU、祖玛旧召唤池/上限：先对账用户已确认合同，再更新测试，补新的边界/池成员/上限断言；不可回滚正式1.5GU或新召唤数据。
- all_monster_loading、MFC1、world policy count、安全区移动执行器：先验证生产功能，修数据/代码或明确合同测试；不能因为R1也失败就外移。
- caster ready期add_child、快照/真实火墙入口、实际法术释放：检验是否阻断双向怪物战斗验收；相关故障本轮最小修，不用怪物包名排除共享生产链。
- 完全独立的缺工件/装备断言等只有在证据证明不影响本任务时方可登记外部债务。需要工件的测试首先生成合法工件，不把缺文件变成测试skip。

**验收：** 核心怪物/双向受击相关失败为0；旧29/30项登记不得再批量填“零调用交集”。每个允许身份有真实能力或正式非战斗理由，不靠一个播放方法普遍放行。

---

## W7：重建真实负载的配对性能与最终发布门禁（覆盖R3-08、R3-10）

**修改：** 性能测试可以改名保留微基准；新增真实 `tests/hc_monster_combat_r3/paired_scene_performance_test.*` 与结果汇总工具。正式门禁加入需要长期保证的正确性测试，昂贵性能矩阵可单独运行并交付证据。

### 7.1 三类负载必须实际发生

| workload | 必须有的生产对象/事件 | 作废条件 |
|---|---|---|
| small_swarm | 实际10/20/30参战怪、真实追击位移/接近及已接受攻击 | 只把target字段赋值但没追击/没起手 |
| large_and_pet | 大身体敌人 + 实际SummonActor宠物，双方有寻敌/运动或攻击 | 用两只小怪冒充宠物、实际宠物计数0 |
| aoe_mass_death | 正式AOE路径作用于怪群，实际HP损失/致死/死亡队列/清理；必要时分波正式出生 | 没调用AOE、没有死亡、只在计时后free节点 |

AOE群死如需固定靶HP，应在测试中明确通过运行时测试控制赋值并记录；不能给setup传一个会被canonical覆盖的hp字段再假定它生效。掉落阶段是否纳入要明确：真实完整帧试验纳入所声明范围，不纳入的单独列出。

- [ ] 初始化正式测试地图、投影、索引、寻路调度和视觉；跨真实物理帧采样。不得在同一引擎帧内用120次手动physics函数调用冒充120帧。
- [ ] 记录 `Engine.get_physics_frames()` 的起止差、真实抽样帧数、game elapsed、active actor/pet数、accepted starts、releases、damage、deaths、deferred清理及fallback计数。计数不符合负载先FAIL，不进入性能比较。
- [ ] 预热与冷启动分开；计时包含范围清楚的正式段。使用已有性能计数器/有界采样，不每击写磁盘或做深拷贝；采样窗口结束再输出JSON。
- [ ] 每条件至少3次独立配对运行，顺序BASE/CAND交替且记录seed/地图/输入轨迹。3个workload不是3次重复。主要比较BASE f5→最终候选；9a→最终候选可附作增量参考，但不能替代前者。
- [ ] 获取P50/P95/P99、长帧次数、实际帧数和工作量；分别报告函数微基准、整帧CPU、渲染/设备未测范围。headless不支持断言手机FPS，不能用计时变小宣称画面丝滑。
- [ ] 用同版本A/A配对评估运行噪声；不能看到+11%就凭主观称噪声。若关键条件P95/P99超过已登记噪声范围且稳定退化，先定位成本、修复后再一次局部重复。不得靠降低活动怪物/逻辑/视觉质量换性能。

建议结果字段：

```json
{
  "source_sha": "2960bbe682b61306eed8f7c9fe0c6eb6c6accb9a",
  "source_tree_clean": true,
  "engine_version_command": "godot --version",
  "workload": "large_and_pet",
  "scale": 30,
  "replicate": 1,
  "seed": 260926,
  "actual_physics_frames": 1200,
  "active_enemy_count": 30,
  "actual_pet_count": 1,
  "accepted_attacks": 0,
  "damage_events": 0,
  "death_events": 0,
  "workload_valid": false
}
```

此结构示例使用被审R2的SHA；执行器必须用本次Git实际SOURCE_SHA替换，记录实际引擎命令输出。示例中的0与false是展示“未发生行为必须作废”，不是验收目标。真实CPU采样时间长度由场景保证有效动作数量决定，不能只采一秒无动作窗口。

### 7.2 最终验证与交付

- [ ] 定向反例与相关回归先收敛。GDScript解析、资源加载、引擎错误日志与返回码一起核对，测试自印PASS不能覆盖引擎错误。
- [ ] 冻结最终候选源码提交。以该提交执行本轮一次full critical；之后发现新增回归则修复、做精确影响回归，并如实说明“全套运行的旧源码与最终源码差异”，不得伪装同SHA全通过；优先安排在所有生产修改完成后才跑全套。
- [ ] 干净检出同一候选、隔离userdata和import缓存，按项目标准挂接工具/必要源资源；至少完成导入、R3全部正确性门与核心生产冒烟。因系统故障没做完则继续标NOT_VERIFIED，不能合并。
- [ ] 正式数据与受保护路径做前后hash/diff；对白名单数据变更给精确语义证据。新增.gd与.tscn必须tracked，禁止忽略规则再次吞文件。
- [ ] 将实际runner JSON、关键stdout/stderr、精确源SHA、错误裁决表、生成链两次hash、性能每次原始采样、A/A噪声与A/B比较装入可交付ZIP。哈希清单必须对应真实文件，不只列本机路径。
- [ ] 新DELIVERY分开写SOURCE_SHA和DOCUMENT_SHA；列实际通过/失败/未执行，不写“全部完成”同时保留相关P1。正常推送同施工分支后核对远端HEAD；主树保持不动，不打包、不清树。

## 完成定义

只有W1–W7的核心正确性门闭合，才能写“R3怪物整改可以进入合并评审”。证据仍缺或有相关生产故障时，状态保持CHANGES_REQUIRED，明确剩余项与原因。设备体验未测要单独写NOT_RUN，即使桌面正确性已通过。

## 本包三个测试的用途限制

`body_rule_tier_cross_test`验证错误档位/正确规则错配；`audio_stale_frame_test`验证B误消费A的缓存帧；`stale_death_notification_test`验证旧死亡通知跨复活。这些是精确回归入口，不是完整系统测试，也不是已经验证的生产补丁。接口改动后可对齐夹具，但必须保留原场景的失败语义并补真实调用链。
