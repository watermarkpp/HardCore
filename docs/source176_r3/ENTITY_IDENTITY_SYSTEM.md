# 统一正式身份体系

核验时间：2026-10-01。用户已授权建立新的统一 ID 体系；本文件记录第三树的实现与验收边界。主树与第二树生产字节未改。

## 身份合同

`hardcore.entity_identity.v1` 使用注册后的 `hc.<类型>.<身份>`。正式查询不按显示名称搜索，不截断小数，不把不同类型的数字视为同一身份。ID 一经登记不得随名称、排序或属性变化重新分配。

| 类型 | 示例 | 已登记数量 | 原有身份主源 |
|---|---|---:|---|
| skill | hc.skill.wizard.lightning | 33 | 技能唯一真源的 skill_id |
| item | hc.item.000085 | 254 | 装备属性主源、正式物品扩展、直接掉落身份映射、正式锻造/圣物资料和默认关闭测试宝石 |
| service_item | hc.service_item.000123 | 538 | 正式服务物品目录的 serviceIndex |
| monster | hc.monster.000019 | 156 | 正式生成怪物目录的 monster_id |
| map | hc.map.910001 | 209 | 基础地图和正式地图身份登记的运行时数字 ID |
| profession | hc.profession.wizard | 3 | 显式职业兼容映射 |
| slot | hc.slot.weapon | 12 | 显式装备、技能贡献和规则贡献槽位映射 |
| currency | hc.currency.gold | 1 | 显式货币身份 |

serviceIndex 和 canonical itemId 是两个既有数字域。47条经逐项规则、素材、价格核对的显式映射把原服务来源登记为已存在 canonical itemId 的兼容别名；未映射的服务物品保留独立类型。对应关系写入 authoring 后，运行时只读取精确 ID 索引，不使用中文名称匹配，也不虚构缺失 canonical itemId。历史 LATE-xxx 地图仅按 GameData 已有的精确 900000+序号合同转成运行时数字 ID，其他未知字符串拒绝。

## 唯一来源与生成链

`assets/data/identity/entity_registry_source.json` 规定身份来源与显式兼容映射，不复制玩法属性。`tools/build_entity_registry.py` 生成 `assets/data/runtime/entity_registry_v1.json`；`--check` 比较全部生成字节。每条记录保存来源路径、JSON 指针和来源哈希。属性、掉落、技能公式与地图几何继续由各自既有主源负责。

运行时 `scripts/identity/entity_registry.gd` 一次验证来源哈希、严格字段、类型、整数边界、唯一性和登记数量，然后同时发布只读目录及查询索引。失败保留原目录；未知/冲突身份不会部分进入索引。热查询不扫描目录或重新计算文件哈希。

## 实际消费者与兼容边界

- GameData 的正式入口 get_entity_record 委托原有严格物品、怪物和地图消费者；get_item_record 支持注册过的物品正式 ID，没有第二份属性数据。
- SkillDataLoader 接受正式技能 ID，保留旧技能公式的明确 ID 适配，并在实际技能定义附带 entity_id。贡献编译和来源绑定使用正式 ID。
- 技能进度保存为 skills.progression.hardcore.v3，运行时 learned_skills 是该唯一进度服务的只读 ID 投影。旧 v1/v2 和中文键的旧存档只在明确导入边界转换；未知或重复身份使整批迁移失败，保留原状态。
- 按钮绑定保存为 gameplay.skill.button_assignments.v4，旧 v2/v3 绑定迁移成正式技能 ID。中文名称从显示字段获取；正式 v4 中的名称键拒绝。UI 提交的名称和 ID 不一致时明确失败。
- 角色保存和测试角色导入验证技能身份；角色加载的身份失败是 terminal，不能通过旧备份覆盖或消掉未知技能。

本次用户授权使技能进度和按钮绑定的保存身份字段变化。原始 P0 保存字节证据不覆盖、不改写；空扩展差分仍比较全部伤害、目标顺序、旧 RNG、掉落、时序与其余保存字节，仅明确转换这些身份字段。

## 实际证据和未完成范围

framework_entity_registry_typed_green_112924_253840：统一身份、技能唯一身份、实际贡献和自然技能配置 lease 四项 PASS，源码稳定。

framework_binding_identity_green_113423_395417：加入绑定旧数据迁移、正式名称拒绝、UI 名称/ID 冲突拒绝后，统一身份及两个生产场景三项 PASS，源码稳定。原始 RED、解析失败与初轮 FAIL 均保留。

framework_identity_legacy_regression_green_113755_465807：进度服务、实际保存重载、输入规则、按钮分配和实际技能书五项 PASS；当轮空扩展字节差分 FAIL 保留。诊断证明差异来自测试期望重编码时把无关整数写为浮点数，生产对象内容一致；现从原始证据字节精确替换三个授权身份对象，保留其余所有字节。framework_identity_bytes_green_114241_046814：2/2 PASS。

framework_identity_migration_terminal_green_121013_525560：未知旧绑定整批拒绝、无效配置不能通过清除操作变有效、未来绑定版本拒绝；统一身份、按钮、实际存档与空扩展差分 4/4 PASS。对应因果 RED 保留。

生成器 --check 验证全部生成字节，Python 9/9 单元测试 PASS，覆盖重复主源 ID、允许重复的明确掉落别名、冲突、数值精确性、类型域和正式 ID 与旧 ID 的一致性。当前生成目录 SHA256：3d90dd0853e7e9044551345fb3049fcb4c3ecb6de1699d97a9a4ac11382df1c5。

framework_loadout_atomic_fixture_green_114713_596692：数值候选在发布前验证，失败保留原 bundle 和编译次数；5/5 PASS。最初两次 FAIL 是用错编译 API 的测试夹具，不称为生产根因的 RED。

framework_legacy_release_stat_green_120248_266881：5/5 PASS。新数值贡献随接受的配置快照保持不变；空数值贡献明确委托旧出手时数值所有者，使圣物首次触发仍参与当前释放。

framework_melee_configuration_green_121626_991817：自然战士近战、自然法术、lease、旧圣物、空扩展和输入规则 6/6 PASS。半月起手后的等级与开关变化不替换已接受的配置，被动定义与等级也随同一 lease 固定；目标位置、方向、实时 MP 和旧火焰充能仍保留各自原提交边界。

P3—P6、性能与设备验收继续保留原范围。上述结果不等于全仓身份迁移或 P2 完成。


## 2026-10-01 13:44 职业实际所有者

PlayerState 的唯一职业状态现为只读 profession_id，正式写入 set_profession_identity 只接受登记的 hc.profession.*；旧 profession 是显示投影和精确兼容导入入口，没有第二份可变中文状态。未知、跨类型和名称误传给正式 setter 均拒绝并保留旧状态。职业切换事务按相同正式 ID 做资格判断与恢复，基础成长缓存按正式 ID 索引；未知职业不再得到默认战士成长。

战士开关/释放、法术分支、颜色选择、正式人物可见性与外观签名使用 PlayerState.profession_id。旧职业数据集的 skillProfiles 与 timingOverrides 在唯一加载边界按准确技能 ID 编译，运行时按 ID 查询；GameData 职业技能和外观入口接受正式 ID，并委托既有主源。

profession_identity_owner_green_132936_256942 五项 PASS。相关首轮 profession_identity_related_regression_133256_730495 为10 PASS/2 FAIL；旧 fixture 与第二树字节相同，正式男 base/装备已含第七个 run 动作、锁定合同已为10GU，旧期望仍为六动作/12GU。profession_identity_fixture_regression_green_133748_005826 为6 PASS/1 FAIL，继续发现装备层也有 run 的旧计数；profession_visual_catalog_exact_green_134110_996400 最终1/1 PASS。三个调用生产/引擎相同，仅两个 fixture 变更，15个唯一相关消费者串行覆盖见 outputs/framework_v2/PROFESSION_IDENTITY_COMPOSED_CLOSURE.json，原 FAIL 不重标。

旧 v10 职业保存字段仍按明确旧 wire 合同使用展示名称，加载时转换一次；新身份 aggregate 与装备槽位/物品容器属于后续 P5 接入，尚未完成。运行时职业完成不等于全仓身份迁移。


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
