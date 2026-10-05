# 新增功能模块交付模板

本模板落实 RFC v2 的新增功能交付要求。定义、装配、动作规划、HP、效果调度和存档写入继续使用既有服务。模板注册表是独立验证入口，所有示例默认关闭；正式内容必须使用自己的已登记身份与经过验收的数值。

## 可复用的作者数据

| 入口 | 作者文件 | 机制与来源 |
|---|---|---|
| 数值与技能字段 | `assets/data/features/templates/numeric_skills.json` | 一个属性贡献与一个技能字段贡献；两个独立 mechanic ID |
| 直接命中点燃 | `assets/data/features/templates/direct_ignite.json` | 只订阅 direct 提交事实；原模拟时间域和四跳样例 |
| 有限子连锁 | `assets/data/features/templates/finite_chain.json` | direct/child 可点燃，direct/periodic/child 的首次死亡可请求有限子动作 |
| 完整装配样例 | `assets/data/features/templates/template_registry.json` | 通过既有 rule 来源逐项绑定五个 mechanic；默认不启用 |

这些 JSON 是完整作者输入，进入原 `FeatureCompiler`、`ContentLayers` 与 `PlayerState` 编译/发布链。修改源文件后验证，不直接改 bundle、状态、事件队列或生成后的运行时数据。正式 `module_registry.json` 不自动引入这些示例。

## 1. 身份、定义和接入

交付说明必须列 module ID/version、mechanic ID、涉及的已有稳定实体/技能 ID、来源 kind 与精确绑定。中文名称仅用于显示。新物品/技能身份先在对应权威登记；旧名称或数字只在明确的导入边界精确转换一次。未知、重复或冲突身份必须失败，不能在热路径按名称补查。

新增模块沿现有 schema 声明 core API、依赖、冲突、能力、handlers、资源闭包、成本、默认开关、scope、activation boundary、mechanics 与真实测试路径。现有可表达的行为使用数据。需要新 handler 时另行明确读字段、输出命令、检查点、最大工作和退出边界，仍不能接管 HP、planner 或 writer。

装配在 registry 中选择 item、embedded_item、affix、skill 或 rule。涉及 affix/rune 时按 `contribution_sources.json` 的精确身份与物品扩展读取，不能用后缀、中文名称或未验证物品索引代替来源。不同物品实例、槽位与 mechanic 具有独立 handle；移除一个来源必须保留其余来源。

## 2. 数值和接受快照

属性贡献进入现有基础属性计算之后的贡献编译；装备属性主源仍为 `equipment_attribute_master.json`。技能字段只能选择 `FeatureAuthority` 已授权字段，并通过原 STRICT_V2 canonical plan 验证。

动作接受前准备所需资源与容量，冻结配置、来源、历史 credit、世界与 actor life。起手后配置撤销/替换不能改变该动作已经接受的范围、耗蓝、冷却或后续扩展承诺。接受票据只能由外层释放入口领取一次；内部使用已验证上下文。错误/旧回调必须在额外资源、RNG、HP之前拒绝，合法回调随后仍能完成一次。

编译图的不可变性只证明数据快照；正式功能还要运行真实 Root/Player 起手、释放与命中专项。模板的格式验证不能替代这些生产测试。

## 3. 事实、效果与有限子动作

handler 只读已提交的不可变事实，返回声明过的命令。伤害基准明确使用 actual HP loss、合法伤害通道和来源类别；零损失、无效目标和免疫按正式合同处理。扩展概率使用自己的版本化 RNG 域，不额外取旧攻击或掉落随机数。

Ignite 不订阅 periodic，避免周期自激。DeathBurst 通过原 ChildActionLease、canonical planner、Root 执行与 DamageBatch 查询释放时的实际几何。目标移动、合法出生或换代不能被一个起手时目标列表冻结；目标数量不能通过隐藏 AOE 截断减少。

每个周期事实拥有独立 release ID 与明确 parent/root lineage。周期事实在原 runtime 的预算 quantum 内使用已接受驻留承诺，真实首次死亡生成的子命令仍由旧根持有直至消费。死亡碰撞立即消失；已提交 HP 不回滚。旧 actor life、旧世界和旧票据不能重新获得资格。

状态/receipt 驻留容量、有限子动作配额、累计周期工作与服务时效分别列证据。按当前 `hc.framework.world_status_contract.v2`，同种 DOT 默认完整替换：较弱的新伤害也生效，使用新周期、从成功施加时刻计算的完整期限与新来源/credit；不同种共存，只有接受前冻结的显式叠加天赋许可才拥有独立层。准备失败保留旧状态，已提交旧周期事实和已接受 child 按原 root 排空。短于周期的合法重复替换可能不断后移 next_due，不能恢复旧相位制造通过。`max_ticks` 只约束单次配置，不能替代整链累计工作和服务时效证明；详见 `docs/architecture/pluggable_framework/CURRENT_PRODUCT_CONTRACT_20261005.md`。本条是当前交付要求，不声称旧 runtime 已完成替换实现。

## 4. 生命周期和资源

每种效果明确作用目标、叠层键、强弱替换、刷新、免疫、驱散、来源撤销、暂停、死亡、换图、到期顺序与保存策略。模拟时间不在暂停时积累墙钟欠账；旧火墙/毒的时间权威继续沿原合同。

资源先在 registry 声明并通过正式准备服务获得 lease；按照 `source_priority_policy.json` 的 lane 与逐项 missing 证据选择来源。必要表现必须准备成功才允许动作承诺，命中回调不做同步 I/O。冷/热与 cache hit/线程完成分别记录。

表现按 target ActorRef/world/life 与 effect handle 消费资源。refresh 不重复创建 cue 或起始音频。销毁、树外释放、换代与旧音频回调不能作用到新实例；在途消费者结束后才释放 lease。实际 CanvasItem/AudioStreamPlayer 消费、GPU 像素与 Android 设备分别验收。

## 5. 经济功能和兼容

新宝石/符文等物品使用现有 extension codec、所有权 validator、ItemTransactionPort/journal 与唯一持久化 writer。quote 后提交必须再次校验完整身份、profile/revision、物品内容与 writer epoch。不得另建物品数据库或存档写入权威。

交付说明列版本升级/降级、unknown 模块保留与 aggregate 只读、未来版本 terminal 拒绝、主/备恢复、损坏主档与缺失主档、缓存旧 quote、重复操作、晚到回执及独立 cold。receipt 安全退休与 journal 恢复是两套协议，不用 TTL/LRU、简单清空或旧备份低水位重开已完成身份。仅使用测试拥有的隔离数据。

需要正式经济示例时从已有 `socketing_fixture`、来源组合及 rune 生产测试扩展；本交付模板不增加正式物品、价格、概率或独立事务 schema。

## 6. 必须随模块交付的验证

1. 格式/依赖/身份：正式 compiler/publisher 接受完整合法输入，拒绝重复模块/来源、未知 mechanic/schema/能力与错误资源闭包。
2. 装配：默认关闭为原空扩展索引；item/affix/gem/rune 的真实来源独立；逐项移除与重装正确，旧已接受图保持。
3. 生产动作：真实接受票据、资源 lease、起手与释放；技能配置变化、错误回调、空结果与 explicit Batch failure 在正确边界结束。
4. 状态/子动作：直接/周期分类、零损失、免疫、多来源、首次死亡、动态几何、一代/二代终止、历史 credit、重复投递、换世界与同 slot 新 life。
5. 资源与经济：必要 cue/audio、冷加载需求与具体 key 结果；经济 quote/commit/writer、失败与独立冷恢复，原生 producer 绑定本轮成功 receipt。
6. 时效与规模：自然输入、移动/战斗、30 目标的合法 90 状态和至少 360 周期结算。90 状态须来自三种真实 DOT 或已登记、默认关闭且显式启用的独立层验证天赋；三来源默认仍只有一个同种状态。保留目标数、HP、节奏与业务期限，另验死亡身份集合与收益/掉落 exact-once、资源/持久化排空、实际服务迟到、最老等待、最大量子、帧分布及持续内存观测。
7. 设备与故障：固定包/内容/引擎/输入的冷热与持续运行；Android/GPU、强杀/掉电和真实旧存档输入分别记录，不外推 headless 或合成夹具。

使用既有 runner、隔离 APPDATA/cache/output 与完整最终 receipt；普通显式30秒，已知 heavy 60秒，用户明确批准的专项例外另记。0 检查、坏断言、截断/错误 receipt、失败 live 复用旧 expectation 必须失败。原始 FAIL 保存，源码变化后阶段结果与最终同字节结果分开。

## 7. 最终交付记录

模块说明填写：需求与作用范围、作者/生成/消费者链、所有新增稳定 ID、开关与撤销规则、权威写入位置、资源来源/闭包、容量证明及未证明范围、兼容/恢复策略、最终源码 SHA/内容与引擎指纹、准确命令、run/invocation/producer/cold 身份、完整测试与原始失败路径。

正式对外状态仅 PASS、FAIL、BLOCKED、NOT_RUN、MISSING。局部通过不得称完整架构、主树、APK或设备验收完成。源码与证据固定后集中独立审计；经主控审查集成与最终必要回归，再按 APK 身份/签名/内容门禁构建。设备测试绑定实际 APK SHA。
