# 第三工作树架构升级实际进展

核验时间：2026-10-01。本文记录当前受测结果；完整目标仍是 P0—P6，阶段证据不能替代整体验收。主树 v97 和第二树修复现场保留，未集成、提交、推送或打包。

## 已有基线

- 精确镜像 PASS：245 个复制路径、3298 个运行时文件和 2278 个 authoring 文件已逐项核对。固定镜像内容集合 SHA256 为 `543e5eb23094f24c68f577e83121d52b18ca75e7b565264c540179e5461e0c95`。记录：`outputs/framework_v2/baseline/MIRROR_MANIFEST.json`。后续架构施工会改变第三树字节，不改写该镜像基线。
- P0 门禁 PASS：真实原生执行验证缺少回执、零检查、错误断言和测试期间改源均不能获得正式 PASS，同时验证有效正例。五项门禁结果见 `outputs/framework_v2/negative_gate_evidence/NATIVE_NEGATIVE_GATES.json`。
- P0 引擎 epoch PASS：`framework_p0_frame_epoch_094254_629832` 验证 process/physics/deferred 入口和同一主循环内多个物理步。
- P0 空扩展行为基线 PASS：真实 AOE、目标顺序、实际 HP 写入、旧 RNG、正式稳定物品 ID 和保存字节已采集，并由独立执行重复比对。采集记录 `framework_p0_empty_behavior_identity_capture_094535_509747`，重复记录 `framework_p0_empty_behavior_repeat_094622_233657`，基线 `outputs/framework_v2/baseline/EMPTY_EXTENSION_BEHAVIOR.json`。旧名称入口采集失败保留为 FAIL，没有覆盖基线。

## 正在施工

- P1 实际生产接入及专项组合 PASS：共享主循环预算接入路径、死亡、资源完成和 ordered JSON writer；worker 真实完成边界、结果所有权、暂停回执、可继续 frontier、弱生命周期所有者与世界/时间合同均经过原生测试。
- 原组合 `framework_p1_integrated_closure_102358_616658` 为 14 PASS / 2 FAIL，保留原失败；两个旧 fixture 把固定轮询次数误当 durable promotion，现改为等待真实 PROMOTING 阶段，全部原业务断言保留。复测 `framework_p1_durable_stage_receipt_green_102730_643249` 为 2/2 PASS。两次生产文件和引擎字节相同，唯一差异为两个 fixture 和共享测试 helper；16 项合成覆盖详见 `outputs/framework_v2/P1_COMPOSED_CLOSURE.json`。
- 资源流送相关回归 `framework_p1_streaming_full_regression_102027_423063` 为 13/13 PASS；真实五动作资源游标、真实 32 死亡队列和空扩展行为回归通过。必要业务和 Node 验证没有硬帧时间上限；共享账本不代表整个引擎帧被限制。总体压力、性能和发布仍待 P6。
- P2 正式内容编译、贡献来源、统一 1205 个登记身份、旧进度/按钮迁移、数值候选原子发布及自然法术/战士近战 lease 已有专项 PASS。旧保存/输入/技能书和空扩展全字节差分通过；原始 FAIL 及其分类保留。旧圣物出手加成与新接受配置分别按明确合同取值。P2 相关完整回归和最终审查尚未完成，不能宣称整阶段完成。详见 ENTITY_IDENTITY_SYSTEM.md。
- P3 实际 HP 提交事实、显式批次、默认关闭点燃、共享预算内持续伤害及表现端口已有生产专项 PASS；全阶段闭包、目标死亡/复活奖励及压力仍 NOT_RUN。详见下方 13:15 记录。
- P4 旧反隐身能力单一所有者及相关原生六项 PASS；能力只改变隐藏目标资格，旧距离、控制、生命、WORLD 和安全区消费者回归通过。最终组合闭包仍待 P6。
- P5 版本化物品 codec、经济事务和默认关闭测试宝石：NOT_RUN。
- P6 组合闭包、真实压力、队列延迟及最终回归：NOT_RUN。

## 仍须保留的失败和边界

第二树专项 R3 75/75、反馈修复 29/29 PASS；组合 critical 658 PASS / 25 FAIL。25 项已分类，仍保持 FAIL。第二树配对性能 V4 为 FAIL，不能宣称发布性能通过。相关原消费者被框架修改时重新追溯这些失败。

GPU、APK、安装和设备验收：NOT_RUN。完整阶段清单见 `outputs/framework_v2/baseline/FRAMEWORK_SERIAL_EXECUTION_PLAN.md`，不得以接口存在、单个 marker 或本文件代替真实验证。

## 2026-10-01 13:15 专项证据

- P2 战士相关回归 `melee_configuration_related_regression_122019_047432` 为 8 PASS / 2 FAIL；两项为旧 fixture 中文技能字典键及旧 override 签名。精确更新三个相连 fixture 后，`melee_configuration_fixture_regression_green_122301_165461` 为 3/3 PASS，所有原业务断言保留。之后 P3 接入改变生产字节，这些记录保留为各自受测集合证据。
- P3 HP 提交事实因果 FAIL `damage_commit_fact_red_122609_511525` 和持续状态因果 FAIL `periodic_effect_runtime_red_123524_980844` 保留。对应 `damage_commit_fact_green_122900_088105`、`periodic_effect_runtime_green_124132_330415` 均为 4/4 PASS。事实采集在实际 HP 写入后、同步治疗及死亡回调前，真实治疗/过量伤害测试验证没有事后重采样。
- 生产接入 `feature_effect_production_green_124858_921277` 为 8/8 PASS，包含真实 AOE、战士烈火、世界时间、旧近战及空扩展。自然起手后关闭贡献仍使用已接受配置；扩展关闭时不启动新效果时间/调度入口，旧 RNG 不被新触发或周期伤害消费。
- 边界 `periodic_effect_boundaries_green_125654_950205` 为 5/5 PASS。22 条边界检查覆盖强弱刷新、保留下一跳相位、暂停、源撤销/节点销毁、当前魔防/免疫、历史归属、表现 start/refresh/stop、声明可降级的表现缺失和世界撤换清空；同轮自然 AOE 33 条、自然烈火 19 条和空扩展通过。各次均正式 runner 退出、回执核对且受测源码固定。
- 新稳定扩展标识：`hc.effect.ignite.v1`、`hc.ignite.ice_storm`、`hc.ignite.fire_sword`、`hc.cue.ignite.v1`；封闭能力 `hc.can_see_stealth`、`hc.immune.periodic`。点燃模块默认关闭，没有投放正式平衡。尚须补目标生命/奖励、重复批次、容量及组合闭包验收，不宣称 P3 已完成。
- 原 CLI 施工会话已经结束上一任务，其配置为完整写权限/高推理，不接入机械派活。新的原生 Codex CLI `glm` 任务使用独立 read-only / low / never，限定六个文件归集旧职业/槽位引用；连接与实际工具已经核验，但本次机械清单 FAIL，详见后续记录。

## 2026-10-01 13:29 补充

- `actor_capability_owner_red_131137_463664` 为因果 FAIL（22 检查，授予后旧 bool 消费者不追踪），`actor_capability_owner_green_131225_671469` 为 6/6 PASS。旧 `anti_stealth` getter/setter 委托同一能力集合，canonical 投影只拥有自己的来源，setup 新生命清空旧来源；两个独立来源撤一不丢另一。未引入 bool OR capability。
- `periodic_effect_lifecycle_red_131621_884780` 为因果 FAIL：运行时替换表现所有者、缺表现世界清理未通知 stop、取消未计终止。修正后 `periodic_effect_lifecycle_green_131717_084616` 为 7/7 PASS；18 条生命周期检查验证跨批次重复不刷新、换生命拒绝旧写入、运行中不移交所有者、世界/显式清空 conservation 及缺表现的显式停止。
- `periodic_effect_death_production_132012_028592` 为 2/2 PASS，正式地图真实 Enemy 死亡连接及旧死亡队列回归通过。实际 Player 死亡、贡献撤销后，周期伤害在第二跳致死；一次死亡/一次现有奖励 job，canonical XP 在原 settlement 才授予，继续 pumping 不重复死亡、XP、drop 或旧 RNG。
- GLM 原生会话 `01a0f5d8-5ee0-76d2-bc62-595a4137765e` 的实际配置为 `glm-5.3-flash` / read-only / never / low，16 个真实工具命令已执行。模型反复重扫同一六文件而无最终清单，主控只终止该有界任务 PID 17036，CLI exit -1，标 FAIL，原 TUI PID 21852 未动。`outputs/glm_cli/IDENTITY_LEGACY_USE_SCAN_20261001.controller_audit.json` 保存模型/权限、六文件字节哈希和主控独立清单；A=24、B=119、C=52、唯一行186，B 包含展示文案候选，不当作业务身份根因。连接可用与本次任务完成分别记录，不接纳中间输出为 PASS。
- 职业正式身份正在施工：角色单一 `profession_id`、旧属性的明确导入/显示投影、运行中职业判断及源职业成长/技能/外观适配器。首个 RED `profession_identity_owner_red_132648_823102` 已保留；新源码复测未结束，暂不列 PASS。装备槽位、物品 wire、经济事务及全部剩余闭包仍待继续。


13:44 更新：职业实际所有者已通过五项专项及15个唯一相关消费者串行覆盖；生产/引擎一致证明和两处过时 fixture 分类详见 ENTITY_IDENTITY_SYSTEM.md。主源动作不删减，实际男 base/对应装备 run 完整检查，正式10GU锁定边界未改生产。

GLM_READONLY_COMPLETION_PROOF_20261001 PASS：原生 CLI exit0、turn completed、恰一条真实工具命令、最终 JSON 与本地1080字节/哈希/ALLOWED行精确一致；实际会话模型 glm-5.3-flash、read-only/low/never 均核验。证据 outputs/glm_cli/GLM_READONLY_COMPLETION_PROOF_20261001.controller_audit.json，会话01a0f5f9-1e48-7411-a200-db7e31f52915。先前六文件机械任务 FAIL 保留；后续派有界可复核小批清单，不授权 GLM 工程施工。


2026-10-01 14:12：新增 hardcore.character.identity.v1 存档子合同（profession_id），SAVE_VERSION10 保持兼容；旧名称仅在 codec 导入边界精确转换，新角色、当前保存、开发测试角色、设备导入与恢复快照使用同一正式身份。unknown/cross-kind/名称冲突/未来子版本或非法类型为 terminal，校验先于其他字段恢复与备份覆盖；实际坏主档+好备份测试证明原始字节、等级、金币、物品、装备、任务及当前职业保留，保存被锁住。下一次合法旧档保存迁移身份，不覆盖原 P0 字节基线。character_identity_save_red_140107_505590 为真实25检查/13失败；character_identity_save_green_140245_834608 五项 PASS。扩展回归首轮4 PASS/4 FAIL，包括新 codec 非法类型比较错误、旧中文技能期望、带新身份却模拟旧职业改名的冲突 fixture 及旧固定武器遮挡预期；原失败保留。修正类型校验后 character_identity_save_type_green_141000_697084 三项 PASS/一项新 fixture 解析 FAIL，解析修正后的 developer_character_identity_visual_green_141115_359800 1/1 PASS，生产逐帧遮挡规则和主源素材未改。多角色、设备入口、原经济事务及空扩展在各自固定源码调用已有 PASS；不将组合记录重标为整阶段当前源码 PASS。详见 outputs/framework_v2/CHARACTER_IDENTITY_EVIDENCE.json。

账本身份：profile_identity_generation_owner_red_135026_031473 为真实六检查/三个失败；旧适配器把32位十六进制字符串转换成整数，导致不同存档生命周期被视为相同。capture_profile 保留原实际 string generation，无第二生成器；profile_identity_generation_green_135129_237286 五项 PASS。最初两次 RED 是使用了错误恢复入口和 reset 会生成代号的 fixture 假设，分类为 fixture FAIL，不冒充生产因果证据。实际恢复入口 _restore_creation_runtime 验证换图保留角色结算身份、换账本拒绝旧身份。P5物品 codec/经济端口、槽位迁移及P6尚未完成，性能FAIL/设备NOT_RUN继续保留。


## 2026-10-01 物品绑定身份闭环及 GLM 清点

正式快捷物品绑定为 `gameplay.item.quick_slots.v2`，值使用既有注册物品/服务物品 ID；名称只作显示。旧名称绑定经显式迁移入口导入，正式未知 ID、跨类型 ID、版本和冲突投影终止整档恢复。绑定使用按 ID 重新定位实际背包记录，不依赖旧索引。

27 项专项断言 PASS，包含未来版本主档加有效旧备份仍保留原始字节并阻止保存、真实加载和有身份物品的名称变动。同生产源及引擎的串行组合为 11 项专项/相关测试 PASS；全部原 FAIL 与夹具修正证据保留于 `outputs/framework_v2/ITEM_BINDING_COMPOSED_CLOSURE.json`。没有删除断言、变更图标或触摸几何。

GLM 清点任务 `GLM_ENTITY_REGISTRY_INVENTORY_20261001` 成功退出，有一次真实只读工具执行；实际会话为 glm-5.3-flash/read-only/low/never。1205 条身份、8 类计数、0 组重复 ID、375172 字节及 SHA 与主控本地逐项复核一致。CLI 的模型元数据和长会话提示作为警告保留；它们不替代模型身份及完成记录。证据：`outputs/glm_cli/GLM_ENTITY_REGISTRY_INVENTORY_20261001.controller_audit.json`。

没有新增实体 ID。普通物品接收与其余名称业务入口、装备槽身份、P5 扩展容器及事务端口、P6 组合压力和设备验收仍未完成；本条 PASS 仅覆盖上述绑定闭环。


## 2026-10-01 物品扩展容器纵向接入

`hardcore.item.container.v2` 的 wire 结构为 contract_id、format_version、entity_id、base、extensions；entity_id 必须与 base 中实际登记身份一致。旧无扩展记录形状不变，旧掉落严格白名单原样保留。运行时沿用现有扁平物品记录，私有字段只持有扩展，没有第二份基础属性。已有 v1/v2/v3 词缀和掉落规则原样 roundtrip，不调用生成器重洗。

正式 codec 接角色保存/加载/备份、共享仓库初始化/存取/多文件提交、即时和后台拾取、装备校验及名称/地面极品表现。未知容器、命名空间或扩展版本为 OPAQUE_UNSUPPORTED，先于已知损坏字段阻止备份恢复；真实未知角色和共享主档加有效备份的字节保留、写保护已验证。拾取外层 ID 与实例内 ID 必须一致。

专项 87 项断言 PASS，覆盖真实锻造成功/失败的后台保存、重启解码与工作台转移。当前同生产字节/引擎串行组合 18 项 PASS，包含空扩展、身份存档、原掉落规则、锻造、仓库、异步死亡回执、药水即时保存和战士开关镜头。仓库 preparation 另修复 finished 标志早于 worker 实际退出时的主线程等待，16 项专项断言及本轮回归 PASS。证据：`outputs/framework_v2/ITEM_EXTENSION_SCOPED_EVIDENCE.json`。

原 parse/fixture/因果 RED 全部保留。loot_stable_identity_save_test 在第109行的已有异步断言仍 FAIL，没有删除或放宽断言；一次未暂存镜像场景触发 runner 门禁为 FAIL/未执行，精确暂存原字节后六项复验 PASS。

本条只关闭容器和列明消费者的纵向范围，不宣称 P5 完整：填充测试宝石及镶嵌取出、交易 operation journal/局部预留/旧排队快照重建、出售/分解/详情专门测试、普通物品和装备槽 ID 迁移、P6 仍待完成。没有新增实体 ID、正式玩法概率、费用、图标或 APK；R3性能 FAIL 与 GPU/设备/集成 NOT_RUN 保留。


## 2026-10-01 镶嵌测试物品与经济事务纵向闭环

新增正式 ID `hc.item.990001`（数值 990001）。测试宝石从明确 primary 的 default-off authoring 文件读取，经正式身份生成器进入 1206 条注册表；254 item、538 service_item，其余计数不变。旧名称目录不暴露此测试物品，生产掉落、商店、图标和正式玩法费用未启用。

`hc.item.transactions.v1` 是现有角色存档内唯一操作日志，最多64条，满额拒绝新增且不丢弃旧幂等凭据。quote 不改状态，commit 以实际实例 ID 重定位、检查配置版本、局部预留所有权，使用现有有序异步 writer 在队首重建待提交文档。磁盘确认后只应用相关所有权变化；实际战斗磨损、药水、金币与随后死亡奖励不会被旧全量快照覆盖。镶嵌和取出是 default-off、无随机和收费的测试能力。

13项专项/相关场景 PASS；事务51项、宝石身份22项、容器87项断言 PASS，实际磁盘与重启幂等、死亡结算、装备 accuracy 贡献撤回、备份写保护及跨背包/装备/嵌入实例重复防护均覆盖。测试期间源稳定，当前运行固定字节证据见 `outputs/framework_v2/SOCKET_FIXTURE_SCOPED_EVIDENCE.json`。真实 late-wear 和未来版本优先级 FAIL、parse/夹具 FAIL、一次无最终回执的部分运行都保留，没有拿中途标记当完成。

圣物详情原专用分支遗漏镶嵌展示已接同一展示函数；药水测试仅调整观察顺序，先确认 writer 完成再读取主文件，原即时生效与不丢消耗断言保留。普通物品/槽位身份、拾取第109行既有 FAIL、P6和性能/device 门禁仍未关闭；本条不表示全部P5或架构升级验收完成。


## 2026-10-01 普通物品身份和旧经济事务迁移

`hardcore.item.identity.v1` 表示角色及共享仓库物品采用注册后的 item_id 或 service_index。新接收、普通装备工厂、堆叠、计数、任务批次、商店价格和拾取缓存使用实际身份；名称作展示和明确旧 API/存档导入。未知、冲突、缺失正式身份或未来子合同终止恢复并保留原字节。没有重排既有数字ID、扩张属性主源或修改正式费用。

注册表仍1206条，但新增47条经过逐项实际规则、素材和价格一致性验证的显式 service→canonical item 映射；索引一次发布为只读，正式直接物品桥接不再使用中文名称。未映射服务物品保持独立稳定身份。价格源中不能作为背包物品持有的装备服务 SKU 继续按其既有精确价格来源解析，不拿显示名替代缺失价格。

16项专项/相关场景同源码及引擎 PASS；普通身份124项、旧事务迁移10项断言 PASS，身份生成器12单元 PASS、正式 --check PASS。覆盖真实磁盘加载、未来主档加好备份写保护、47条规则/素材及47条价格相等、名称索引全部撤下后的正式规则/图标查询、拾取缓存计数、真实商店/锻造/仓库/金币事务。固定字节证据见 `outputs/framework_v2/ORDINARY_ITEM_IDENTITY_SCOPED_EVIDENCE.json`。

普通金币事务保留已合法的身份头原始数值表示，正常结构比较不增加全量重新编码。只有首次身份升级差异才作限定 canonical 比较；模拟第二文件失败时，回滚重新验证已知旧 wire 并保留原 before-image 形状，避免升级破坏恢复哈希。原因果、parse 和 fixture FAIL 全部留存，原 P0 基线没有改写，只投影用户授权的新身份字段，其余伤害/顺序/RNG/掉落/保存字节继续严格比较。

装备槽唯一身份 owner、其余技能书和物品动作路由、既有拾取第109行 FAIL、P6及性能/设备门禁仍未关闭，本条不宣称统一身份体系或完整架构升级已经验收完成。


## 2026-10-01 异步拾取与真实调度资格闭环

既有 loot_stable_identity_save 的 READY 假设已由实际输入就绪边界修正。随后追踪证明，PREPARE worker 已完成，但父节点 DISABLED 的资源 owner 仍以 is_processing 标志占据公平顺序，292帧未让出资格。FrameBudget 现在同时核验 can_process，覆盖继承禁用和物理 owner；显式同步驱动仍允许生命周期/隔离夹具工作，恢复 owner 保留原排队年龄，没有新计时器或重试。

两项拾取与一项死亡旧夹具不再把两次旧 stage_result 或一次可延后的 pump 当成实际提交。观察精确队头 PROMOTING 并等待真实 worker 完成后才注入生命周期变化；死亡准备跨原生帧等待实际 PERSISTING。原取消/换图/退出/重启/跨角色隔离、RNG和只入账一次断言均保留。死亡因果记录证明原同帧保存已花14139us，不能要求1200us预算下立即准入可延后结算。

最终10项专项和相关回归同源码/引擎 PASS；共享预算41项断言 PASS，连续拾取、死亡/拾取原生退出、暂停回执、大文档 worker 转移、镶嵌51项和共享仓库均通过。历史 FAIL 和未执行的路径输入错误保留；证据 outputs/framework_v2/PICKUP_OWNER_SCOPED_EVIDENCE.json。原拾取失败已关闭。装备槽和剩余物品动作身份、P6及性能/设备/主树验收继续保留未完成状态。


## 2026-10-01 装备槽正式身份和原档归档闭环

运行时 equipment、轮换游标、穿脱/交换/修理/磨损命令、角色工厂、实际纸娃娃、背包交互及贡献来源使用既有 hc.slot.*。十个物理槽保持原顺序与坐标，两个贡献伪槽不能进入装备所有权。名称从登记显示字段获取，旧槽名和 authoring 枚举只在明确导入入口转换；没有中文键镜像或重复属性主源。新增 hardcore.equipment.identity.v1 子合同，SAVE_VERSION10 和1206条实体登记保持不变。

正式槽名、轮换组、未知/冲突/未来合同严格校验；两份占用别名即使字节相同也拒绝，旧空洞与占用记录按明确兼容规则保留。原始P0基线未改，差分仅投影已授权的装备身份字段，伤害、时序、RNG、掉落及其余保存字节断言继续保留。52个机械变换测试文件的1635条assert全部保留。

真实人物预览回归揭示两项生产边界。其一，原档归档经普通 writer 被前向转换，导致归档摘要与原档不符，重复导入失败；实际因果RED复现摘要/重试两个断言，迁移和金币归档现在校验原所有权但保留原wire形状。正式存档仍正常升级。其二，人物选择页退出后后台PackedScene仍加载；真实free的RED证明 IN_PROGRESS，现由退出边界加入所有已接受路径，包括替换后旧请求，正常交互继续预加载。

最终同生产字节与引擎27项专项/相关场景PASS，原生均正常退出；槽位46项、真实单/双路径资源退出、原档中断/重复恢复、世界死亡进度、仓库事务、镶嵌/取出、装备破损与UI、连续拾取及空扩展均覆盖。证据 outputs/framework_v2/EQUIPMENT_IDENTITY_SCOPED_EVIDENCE.json；全部历史FAIL、类型/夹具错误和因果RED保留。资源游标fixture明确设置初始准入预算，加载与取回仍是真实ResourceLoader。

本条关闭列明装备槽与归档/资源退出范围。技能书与物品动作、来源类别/圣物身份、P6组合压力仍继续；R3性能FAIL，GPU/设备/主树接入/APK仍NOT_RUN，不将阶段PASS写成完整目标验收。


## 2026-10-01 技能书物品与技能正式关系闭环

既有物品主源新增33条明确的 learnSkillId 声明，连接已登记的技能书物品/服务物品与 hc.skill.*，没有新增或重排实体ID。生成器校验完整性、唯一性、实际书类型和正式技能目标，17项单元与 --check PASS；登记仍1206条，当前SHA为25e67d115309236e86e54a1ec7034c149e105dd3d3ae47bbaeb4bbf842acdb46。除33个声明外，原主源所有字段和值结构相同，技能SOT、概率、价格、属性、图标和等级规则未变。

GameData 正式 rank 查询按已有 skill_id，名称仅是明确旧UI入口和显示；书关系只读索引按正式ID。背包使用、学习、错误索引重新定位和技能面板读实际物品/技能身份。53项真实检查PASS，覆盖改名仍学习、伪同名药品拒绝、不耗错物品、正式/旧UI两入口、真实保存拒绝回滚及全部33条正反查询。不支持的73个后续技能书保持无当前学习入口，不按同名启用。

初次新fixture错误给只读 profession_id 赋值，没有进入真实职业所有者；该分类保留。修正为正式setter后49项PASS。随后只临时恢复两个旧名称取书分支，同一正确fixture真实出现7项学习失败，正确源码按原始字节恢复；这份因果记录证明名称依赖回归会被捕获。

13项唯一专项/相关消费者在同生产字节/引擎下串行覆盖PASS。首次组合11PASS/2FAIL，二者分别从装备专用接口制造无ID技能书、直接修改只读技能投影；只调整这两个fixture为实际书目录/正式进度入口，三项精确复测PASS，原提示、只一次、门槛、有效等级及装备等级贡献断言保留。未重标原组合FAIL；组合证据 outputs/framework_v2/SKILL_BOOK_IDENTITY_SCOPED_EVIDENCE.json 明确逐项来源与两处fixture差异。

临时物品增益、药品/卷轴请求和祝福油身份、类别/圣物路由、P6仍继续；性能FAIL和GPU/设备/主树/APK NOT_RUN仍保留。本条不是全仓ID完成或整个架构目标验收。


## 2026-10-01 临时药水增益正式身份闭环

临时物品增益入口只接受已登记且有实际运行时记录的物品ID；状态以 canonical entity_id 唯一持有，中文仅为展示元数据。实际背包使用传正式身份，同组刷新仍保留首次开始时间并替换旧效果，不改变12种主源药水数值、时长、叠加规则或持久化边界。到期只发当前物品ID，提示与HUD通过同一ID投影已有显示和图标；service-only图标不需伪造物品数字ID。没有新增或重排实体ID，登记仍1206条，SHA仍25e67d115309236e86e54a1ec7034c149e105dd3d3ae47bbaeb4bbf842acdb46。

26项真实检查PASS；实施前同26项存在13项因果FAIL，记录保留。覆盖真实改名使用、展示名称/未知/跨类型拒绝并保持状态不变、同组替换/不同组共存、原定时边界、全部统计归零、到期恰一次、真实写入失败回滚及实际HUD/中文提示。六个直接消费者fixture改为真实注册ID，115条原assert保留。

12项唯一专项/相关回归PASS，实际退出码、receipt和运行前后源码/引擎指纹均核对。首次组合10PASS/2FAIL：canonical目录测试仍期待153条，当前HEAD目录结构明确允许全部156条；即时保存混合fixture绕过物品工厂手工生成无ID技能书。仅修正这两处fixture为当前完整目录合同和实际工厂，原153数量断言改为权威156而没有删除，原即时生效/后台落盘/五类混用断言保留。三场景精确复测PASS；生产字节/引擎相同，原FAIL不重标，组合证据见 outputs/framework_v2/TEMPORARY_ITEM_BUFF_IDENTITY_SCOPED_EVIDENCE.json。

消耗品/卷轴请求和祝福油身份、类别/圣物路由、P6仍继续；R3性能FAIL及主树/APK/GPU/设备NOT_RUN仍保留。本条仅为临时药水身份范围的闭环。


## 2026-10-01 物品使用请求与祝福油身份闭环

消耗品/卷轴成功完成信号只携带 canonical 物品ID；真实GameRoot消费者只读正式物品入口，按既有主源effect/restore字段执行，拒绝中文名称、未知或跨类型事件。祝福油真实事务以 hc.item.920033 和明确service709别名核验，改显示名称不影响使用，冒充同名其他物品在真实RNG取样前拒绝。概率、抽样函数/顺序、武器预留、提交与失败回滚保持原路径；使用通知与音效原归属保持。新增ID为零，登记仍1206条、SHA仍25e67d115309236e86e54a1ec7034c149e105dd3d3ae47bbaeb4bbf842acdb46。

20项真实检查PASS，正确隔离的原路径RED为10/20失败；首个RED含连续无效事件污染fixture和名称候选数量8/6错误，分类与原记录保留。覆盖改名真实信号/效果、延迟药水仍排队、真实保存拒绝零派发、卷轴成功恰一次、改名祝福油/明确别名、伪同名拒绝且RNG状态不变、保存失败完整油/武器回滚及实际完整目录的旧名称分支清单。目录证明名称fallback仅剩service123的旧行为；改为该稳定ID明确兼容分支，保持30HP/30MP/+2防御60秒，未把当前identity任务扩大为其主源unlock_curse玩法修订。

14项唯一专项/相关回归PASS；首次组合13PASS/1FAIL，旧地图fixture仅等两帧即在实际初始加载输入锁未解除时尝试过门。fixture改为等待真实bootstrap/transition/input READY（有测试超时，生产无新计时器），保留全部矿洞/尸王殿/回城/死亡/兽人古墓路径、落点和几何断言，二项精确复测PASS。两次生产字节/引擎完全相同，只有该fixture差异；原FAIL不重标。证据 outputs/framework_v2/ITEM_USE_ACTION_IDENTITY_SCOPED_EVIDENCE.json 包含每场景实际退出、指纹与receipt。旧幸运fixture回调仅观测完成，不重复应用已经由事务提交的油效果；新增被拒绝零派发断言，原幸运/诅咒和存档断言保留并使用正式槽位。

类别/圣物路由、P6仍继续；R3性能FAIL，主树/APK/GPU/设备NOT_RUN仍保留。本条仅关闭列明物品动作身份范围。


## 2026-10-01 圣物技能关系与配方职业正式身份闭环

既有圣物authoring主源新增skill_pools：按3个 hc.profession.* ID 明确列出原17个 hc.skill.*，以及3个徽章skill_profession_id。旧字段、显示、图标、属性、金币、材料、概率均结构不变；逐项复核新17条顺序与旧固定技能池的精确主源ID一致。登记实体和counts完全不变，仍1206条；仅该来源hash由正式生成器更新，当前登记SHA为05d1cd2ba2218120f225a63f2afdb455bf98a2b8a07d114bf6362546f7eddbfa。生成器新增关系端点/缺失/重复/跨职业校验，22项单元和 --check PASS。

运行时只从该主源读取正式职业与技能关系，移除中文技能名业务表；旧公开UI/导入参数精确转换一次，内部目录和真实合成quote由profession_id持有。既有v1圣物roll继续保存原稳定内部skill_id与modifier scope，不重编号、不重掷旧实例。实际玩家职业资格读同一profession_id；中文配方标题、角标和说明按ID投影，布局与位置不变。实例校验由真实item_id/roll/count/modifiers决定，显示文字不再成为身份。候选技能池/六条目录全部核验后一次发布，没有半成品缓存。

35项真实检查PASS，原正确主源fixture在实施前9项FAIL；初fixture的两个预期技能符号修正为主源实际ID，原记录保留。固定原生seed4816仍得到 wizard.ice_storm，RNG state9008858216091737753完全相同；正式与旧导入入口整份roll一致。全部17关系、真实改名校验、正式/默认quote、未知/跨类型拒绝且无随机数变化、真实合成及重复提交拒绝均覆盖。

11/11直接/相关原生回归PASS：合成、实际装备与恢复、真实战斗触发、后台工作台回执、锻造保存、布局、面板流程、扩展loadout、镶嵌事务和空扩展基线。源码/引擎前后固定，真实退出码0及receipt核对，见 outputs/framework_v2/RELIC_IDENTITY_SCOPED_EVIDENCE.json。旧fixture改为正式技能进度入口和装备槽位，原断言全部保留并加一条真实进度设置检查。

类别路由、P6及总目标验收仍继续；R3性能FAIL，主树/APK/GPU/设备NOT_RUN仍保留。


## 2026-10-01 物品类别正式身份与生产消费者闭环

新增唯一authoring主源 assets/data/identity/item_categories_v1.json，合同 hardcore.item_categories.v1，注册32个 hc.item_category.*；旧1206实体逐记录完全一致，当前总数1238。类别表包含实际运行28类别、明确旧衣服/盔甲别名、测试宝石导入，以及旧价格的装备参考/消耗品类别。中文只是显示及精确旧枚举导入元数据；未知/跨类型/重复关系/未来版本不猜测。注册表SHA b6bf47a8f6c3bf94cbf94536324b45e6f6f3652f3a486fee9a6a2b156c558da1，source_priority_policy登记独立primary类别身份lane，不替代装备属性主源。

实际GameData目录、175主源装备API、11纯度黑铁矿、圣物、默认OFF测试宝石及价格记录绑定category_id。装备槽位关系只有类别主源一份，原左右槽顺序保持。玩家装备/幸运/保存校验、背包槽位、物品详情、掉落实例、锻造规则/等级/事务/面板与价格类别修正均读取类别ID；公开旧枚举入口只明确转换一次，原数值、时序、属性、布局、存档版本保持。

49项类别原生检查与21项唯一直接/相关回归PASS（真实退出0、各场景前后源码与引擎不变、receipt核对），生成器27项及 --check PASS。首次组合20PASS/1FAIL，掉落实例保存fixture仍读取旧中文槽位；唯一后续变更为saved_q.equipment["hc.slot.weapon"]，原断言全部保留，精确2项复测PASS。两轮生产/引擎字节完全一致，旧FAIL不重标。当前受测3439文件内容集合 5b864af12061f457648a84e9de8bafed888568097d87cf1b7fb92b01305f68fb。旧类别缺失RED、实现中的解析/遗漏类别/详情面板preload失败保留并修复。旧价格候选名称身份及itemBps名称fallback属于下一身份范围，未声明已完成。证据 outputs/framework_v2/ITEM_CATEGORY_IDENTITY_SCOPED_EVIDENCE.json。

用户新提供六项独立审查风险保留为施工中候选，需自然检查点固定受测版本后逐项反例复核。P6、完整架构/性能/主树/APK/设备验收未完成；R3性能FAIL不被本范围PASS覆盖。


## 2026-10-01 独立审查增量1：烈火已接受配置的最终冷却

33项真实检查因果RED为3项FAIL：合法timing.cooldown_ms×0.5在起手定义为4000ms，最终却8000ms；起手后模块OFF仍8000ms；起手后实际profile消费者把速度变成3，最终被改成2667ms。Root最终冷却调用没有传递已接受lease，Player重读基础定义和实时速度；主控据实确认根因。

仅修改scripts/game_root.gd和scripts/player.gd：Root传递同一已接受配置；Player通过正式lease definition resolver取烈火定义，有数值扩展时使用已接受主属性中的施法速度，空扩展保持原release owner的速度合同。未改基础技能/authority/lease合同、冷却提交时刻、MP、几何、旧开关状态机或存档版本。没有新增登记实体。

33直接检查及8/8相关原生回归PASS，合法配置三例均4000ms，空扩展8000ms；每次真实接收者HP下降且MP仍93（原耗7）。回归包含近战/法术lease、战士状态机、开关镜头、烈火派生效果与空扩展基线。前后受测源码固定，真实退出0、receipt核对；当前源码指纹 4ced9bda2a234c22e5c69e55d49e16fa5476fe607369041125e7973a43853da5。模块fixture只替换内存内容输入，走实际编译/资格/激活/输入/lease/单planner/HP/冷却；本用例不声称覆盖磁盘模块路径信任入口。原RED与既有退出ObjectDB警告保留。证据 outputs/framework_v2/FIRE_COOLDOWN_CONFIGURATION_SCOPED_EVIDENCE.json。

固定远端审查提交723972322b837da1a287172c85412076df0e118d不变。增量2-6、P6与总目标继续；R3性能FAIL，主树/APK/设备NOT_RUN不被本范围PASS覆盖。


## 2026-10-01 独立审查增量3：未来所有权与真实旧备份恢复

主控原生复现：145项反例76项FAIL，未来大/深容器、未知namespace、未来socket schema、未来仓库+已知损坏物品均被旧备份恢复覆盖。修复后145项PASS；新增未来合同版本编码变化、缺失旧合同字段及超int64未来仓库版本反例188项中27项FAIL，补齐浅层所有权识别后188项PASS。浅层检查中一次缺失String守卫的真实回归失败已修复，所有原失败证据保留。

仅修改ItemExtensionCodec与PlayerState实际验证/迁移边界：未知所有权在当前图容量/深度/私有字段/物品解码之前识别为OPAQUE，已知版本仍保留4096节点/16深度与字段校验。仓库只提前识别可确认未来版本，未知物品+畸形仓库schema仍terminal，不恢复旧备份。没有TTL/LRU/journal清理或缺失ID猜测。

相关回归发现真实旧字符串装备在世界时钟导入时提前进入正式编码器；补21项检查（总209），原生8项因果FAIL。中间时钟导入主档/匹配备份按已验证legacy wire保存，旧运行时入口仍负责正式实例/耐久创建与正常正式保存；显式legacy String入口先验证精确已登记物品，未知String整档只读。原始迁移archive字段/源digest保持，当前正式encoder仍拒绝字符串装备。

209直接检查与16项唯一相关原生场景PASS；真实退出0、固定源码/引擎、receipt核对。16项由最终三轮组合，只有旧clock备份fixture变化：真实backup通过codec消费后核验同一instance，原断言保留并新增known断言。其他旧fixture仅为已知备份明确item_id=80、默认cycle断言改正式槽位；未知身份未恢复fallback。authoring/registry/project全部冻结，本范围无新增实体。

当前源码集合 b72a5e92505b7cf1ac766a74216225305eb5efbf8848e61a1bfc30c36a8f2708（3443文件），引擎 4.7.stable.official.5b4e0cb0f / d8055fb8c7e7f5010d7439ec69be051554055dae55a265f8647bd7301c34161c。证据 outputs/framework_v2/FUTURE_ITEM_OWNERSHIP_SCOPED_EVIDENCE.json。固定远端审查提交723972322b837da1a287172c85412076df0e118d不变。

增量2/4/5/6、P6、价格名称身份、完整目标验收仍继续，R3性能FAIL与主树/APK/设备NOT_RUN不被此范围PASS覆盖。用户后续手机独立覆盖升级/自动迁移作为新增交付范围记录。


## 2026-10-01 手机覆盖升级存档接入检查点

启动在CharacterSelect前完成原始整账户备份和已知身份转换。原始文件按字节保留并登记哈希；所有profile、共享仓库、WAL和引用世界时钟先只读核验。未知所有者关闭门禁，不以旧备份覆盖；失败可重试，完成回执必须持久化，冷进程不重复转换。既有显式debug QA开关延后到原始备份及转换完成后。

真实v90归档SHA 18989f8b6d0f672b653cb0237ebeb33913f46885a508b716fe8c2b1ae5ffd7de 的3角色/13文件在隔离user数据、test_mode=false生产保存链完成转换。进度、背包和共享仓库所有已占格的位置、数量、实例、耐久和增强属性及银行/仓库幂等记录均核对保留。两个实际遗漏药品通过authoring源和正式生成器登记hc.item.920017/hc.item.920042，精确服务别名666/667；未新增玩法数值。

17项因果RED复现超大future save_version整数收窄漏判及未来snapshot/world_state/schema/death_event被旧备份恢复。修复后215直接、13冷重启、20真实Startup检查PASS；13/13相关原生场景真实退出0、receipt有效、受测源码稳定。此后仅增加5条真实库存/银行记录断言，2/2直接及冷重启再次PASS，运行时代码与13场景受测版本完全一致。multi_character测试3处中文武器字段按既定规范改为hc.slot.weapon，原耐久断言不变。证据outputs/framework_v2/MOBILE_SAVE_UPGRADE_SCOPED_EVIDENCE.json；内容指纹8d2cc049ef9cac447d9ff7340d57f6417746cd6ac401868d5e952fdc4c7998b7。

手机APK/签名/安装/设备仍NOT_RUN；A→B圣物与徽章故障定向回归仍NOT_RUN，不以迁移PASS结案。六风险余项、P6、R3性能FAIL与整体集成继续。固定审查SHA723972322b837da1a287172c85412076df0e118d不变。


## 2026-10-02 多角色圣物/徽章生产链检查点

第三树以真实State、test_mode=false、新隔离账户，通过实际create_character执行A→B。每角色4次工作台合成/4次入包，首对圣物和徽章各真实装备、卸下并销毁，再合成一对装备保留；两产物同时入包时验证无关武器装备及药品销毁。实际异步worker回执、revision保存完成和每步磁盘validator均记录；新原生进程冷重启A/B验证原实例/roll、已销毁实例不复活、无关背包装备/销毁继续可用和两队列排空。327热流程+32冷进程检查PASS，两场景真实退出0。

首轮71检查/32FAIL来自fixture使用了接口未支持的通用entity_id记录键；仅改为现有receive稳定ID入口，工程源码未因该fixture失败改动。全部原断言保留。受测源码a70edc8917c07b87bd3ccaf60c522076ca8c85044e37fac43590918a1d5e0af8，证据outputs/framework_v2/RELIC_MULTI_PROFILE_PRODUCTION_SCOPED_EVIDENCE.json。

这证明第三树指定新账户生产路径；尚未在固定v97生产基线及用户所报触发数据复现，v97故障修复仍NOT_RUN，不以本PASS或架构升级结案。下一步独立临时导出固定v97生产代码，保持主树、第二树、实际手机存档及固定审查SHA不变，补基线/历史数据反例。

### 2026-10-02 v97 固定源码三职业生产链检查点

- 固定源码提交 `a945e921e849b4aa81439183f60cec95e63d725c`；隔离导出11954个运行时文件，内容集合SHA256 `0dc8947ce5978c049e8a6700a7f1bdcf63cf6a099d0ab1f8c642086944245aa8`，引擎4.7/既有固定console SHA。逐文件核对Git blob，资源准备和原生测试前后生产字节均一致；主树v97及真实用户存档未写入。
- 使用实际全局PlayerState、test_mode=false、隔离APPDATA及默认生产存档路径；A战士/B法师/C道士，各自真实合成950101与职业徽章950201/950202/950203→入包→普通武器及合成物装备/卸下/销毁→真实保存回执；500项PASS。新原生进程定向加载三角色、实例/roll/删除/金币/普通背包装备销毁及队列排空，49项PASS；均退出0、无SCRIPT ERROR、harness字节稳定。
- 适配仅在测试边界按v97数字物品ID与中文槽位schema执行。普通装备测试种子使用已核对的数字身份解析包→真实掉落实例factory→item_instance→receive_record；不修改旧版生产代码，不恢复新系统名称fallback。
- 历史307项“PASS”标记同时存在2次脚本错误并漏20项，主控已明确判FAIL保留；首次资源准备超时及不完整掉落fixture失败也保留。新launcher同时核对真实退出、全部receipt、脚本错误和前后生产/fixture指纹。
- **用户报告的旧B角色整个背包故障仍未结案**：新建三职业场景未复现，具体历史B状态MISSING，v97修复状态NOT_RUN；不能用本专项PASS或架构升级替代该故障验收。
- 范围证据：`outputs/framework_v2/V97_MULTI_PROFILE_BASELINE_SCOPED_EVIDENCE.json`；所有userdata、缓存、原始trace及诊断导出位于本树忽略outputs中，不上传真实存档。


### 2026-10-02 容量施工检查点：原子转移 PASS，完整准入 FAIL

+唯一主控在第三树完成两个原生因果 RED：真实 pending8192 满后消费权丢失（16检查/2失败）；三个 AOE 目标各有16个合法历史状态时，新源仍接受动作并提交基础HP，随后拒绝状态（19检查/3失败）。源码在每次运行前后保持一致。

+本段仅修复 damage_batch 非消费计数、effect_runtime 整批容量先检查后 consume、GameRoot 对非空提交失败的明确诊断；基础HP不回滚，合法miss/空扩展路径保持。最终队列容量-1/满/+1、双目标整批拒绝与精确重试等25检查 PASS；八个直接相关原生回归147检查 PASS。完整接受前容量仍 FAIL，最终19检查仍3失败，不以局部GREEN关闭P3/P6。源码内容指纹 `6d5ca9e1540f99dae93ec6a8e11569d71bc4d80c6ab333196287dc0bce7d4970`；证据 `outputs/framework_v2/CAPACITY_SCOPED_EVIDENCE.json` 和 `docs/review/framework_capacity_20261002/`。

+架构待讨论：在释放时仍按all-intersecting选目标且windup中可出生/换代的合同下，准入所需fanout上界必须有权威来源；不能以30目标测试规模设新玩法上限，不能增加魔法常量或丢合法目标。候选是由现有EffectRuntime拥有、随ActionConfigLease转移的容量许可及producer/consumer结束协议，尚未实施。完整容量、死亡credit切profile窄时序、receipt安全退休与P6组合/公平性/P95/P99继续保留。已闭环的烈火、future保护、宝石纵向及身份范围不重做，不开放正式玩法；journal64不淘汰。v97精确B输入 MISSING、故障修复 NOT_RUN，APK/GPU/设备 NOT_RUN。


### 2026-10-02 默认启动根修复与合法周期致死退出检查点

真实默认路径启动 RED（2检查/1失败）证明 SaveUpgradeBackup 把 user:// 截为 user:/；本段只修正该备份组件的 scheme 根及对应 containment 前缀，未改 PlayerState 加载、存档格式或业务权威。真实周期HP致死但deferred回调未执行时，经实际Root返回选角菜单守卫排空死亡/掉落/任务/经验/存档；A一次入账、B原档字节不变，合法切换及独立冷进程37+13检查 PASS。先前B任务全字典断言因int/JSON float类型不等 FAIL，保留证据并按完整JSON持久化表示建立预期；未删除业务断言。三个保存升级直接回归248检查 PASS，绿色运行源码稳定、引擎/脚本错误0。源码3464文件 SHA256 `be07efff6ce3e3fba9ea246068bbc9138235adf72d549db8292abf28c8671f06`，证据 docs/review/framework_credit_20261002/。旧profile-switch fixture只读未变、NOT_RUN。

此处只闭合法UI生命周期窄时序，不证明越过Root守卫的直接选角调用，也不宣称v97背包根因。完整容量 FAIL；pending消费前缀回收、receipt退休、完整P6/公平性/P95/P99继续施工。精确历史B输入 MISSING，用户背包故障因果修复 NOT_RUN；主树整合/APK/GPU/设备 NOT_RUN。默认新玩法仍关闭，地图、权威源、第二树和主树v97保持。
