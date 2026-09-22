# v92 密集地图、技能分层与成长整改

本记录由主控复核生产消费者及实际 Godot 结果。状态以各项证据为准；Android DEVICE TEST: NOT_RUN，未将 headless 帧间隔换算为手机 FPS。

## 密集地图与火墙

正式采样地图 913203 黑暗地带、913207 死亡棺材、916003 赤月系列各保留 62/71/54 只 authored 怪物，8 场实际 fire_wall，每场 9 格，共 72 格；通过正式 `_execute_canonical_skill`、MAC 和 MAGSTRUCK_MINE 结算。每场 5 次伤害时钟，重复伤害 0，方向不一致 0。完整比较摘要见 `evidence/formal_dense_maps_cpu_comparison.json`。

火墙高度压缩提交 `96a659133a0339c68ffc86ae9caf0adf51d6c97f` 同时改变高度、脚点排序与 2×2→3×3。每场视觉格从 4 到 9，数量增加 2.25 倍；高度本身仅是 Y×0.6，不能把三项修改的影响都归因于高度。保留当前 3×3 范围、高度及排序规则。

`CasterSkillAnimationBatch` 每场只计算一次当前帧，9 个视觉格共享呈现时钟；移除每格独立物理寿命/每帧动画回调和废弃共享时钟 setter。动画只在帧改变或资源尚未就绪时提交，cold resource 继续可重试，取消释放 lease。游戏寿命、范围、伤害/重叠去重仍由 FireWallFieldController 管理。真实9格测试验证高度0.6、相同帧、冷启动恢复、取消无lease残留。

33 个正式技能采用精确 ID 分类表，区分 physical/spell、投射物、直接单体、范围、持续区域、增益/控制/召唤，未知 ID 正式入口拒绝。公开几何/查询/资源设施共用，物理命中/AC与法术MAC/anti-magic/硬直语义保持各自入口。仅抗拒火环和困魔咒需要 generic context.targets；其它技能的无用附近敌人搜集被删除，标量锁定目标与友方候选仍保留。困魔咒边界候选不会变成额外受困目标。

每技能100次 context 构建：黑暗地带 fireball/hellfire 的候选记录各从2000到0，中位0.762/0.764ms降到0.048/0.047ms；magic_shield从1.071到0.356ms；fire_wall从0.509到0.390ms。死亡棺材火球0.898→0.051ms；赤月采样0.438→0.047ms。两种控制技能仍保持原查询。正式消费者测试验证锁定、生物/不死、真实墙探测和友方受益不变。

整体窗口 p95 为黑暗12.014→11.687ms、死亡棺材10.998→10.833ms、赤月9.577→9.552ms；不能称为显著手机FPS提升。八次施放样本较少，死亡棺材施放p95 5.688→8.257ms、赤月5.960→6.132ms波动变差，均如实保留。墙钟AI/对象ID导致活动次数并非完全相同，因此不把 aggregate enemy_physics 总量减少当作严格行为等价加速证明。确定证据是移除的查询/回调/重复提交和专项行为一致。

地狱火原长帧200ms中重复提交4次中间纹理；所有逻辑步仍推进，只提交一次可显示的末态。RED实际4次，GREEN实际1次；4×50ms与1×200ms的记录、帧、纹理、位置、偏移完全相同，完成时全部隐藏。

## 物理与法术结算

精神力战法旧runtime有加准确描述符，普通攻击未消费；现在物理近战从该原始描述符读取准确加成，rank3实际+8，命中strict roll<accuracy。法术和宠物不继承此人物被动。

原普攻/半月/烈火绕过AC，仅刺杀预扣AC。统一在GameRoot._apply_physical_hit命中后扣一次实时AC，刺杀第二段显式ignore_ac，红毒AC降低由敌方实时读取。特殊即时处决继续使用已结算伤害接口。真实38/39/57怪物对比验证raw20为20/1/20，MAC法术对比20/20/0；红毒AC/MAC不混用，过期回收。

骷髅正式释放消费AC；神兽 primary TSpitSpider / GetMagStruckDamage 按准确-敏捷命中后扣MAC，可降到0，不添加人物直接法术anti-magic和walk-delay。原源码证据 ObjMon.pas:674-701 / ObjBase.pas:22441。两类均测试精确命中边界、冻结范围、重复释放。

## 宠物成长与毒归属

用户明确主人直接补刀不共享，宠物直接补刀仅自己得成长；毒致死由最后实际造成正伤害的活宠物领取，双宠不重复，无参与/最后宠已死不转赠。EnemyActor仅保存弱引用并在毒死亡边界一次消费，检查主人/地图/生命状态，不改变玩家经验、掉落和毒无硬直语义。

独立项目成长策略 `skills.summon.growth.hardcore.v2` 每次合格击杀给予monster level×2，原verified baseline门槛、严格大于、每击杀最多一级、余数和旧存档XP单位不改。骷髅rank1在蜈蚣26级目标下到cap3由27次补刀变14次，人物19→20同怪13次；rank3宠3→7由97次变49次，人物26→27为72次。未照搬人物约42.86倍门槛加速，避免宠物一击满级。

`skills_changed`/`equipment_changed`、同类召回和跨图恢复同步当前技能rank；活宠rank/cap只升不降，不替换、不回血、不清等级/XP，最高cap7。无额外补发历史经验。真实GameRoot测试覆盖rank1→2召回、rank3跨图、降rank保持cap、双宠/主人/毒归属及死亡账务后不重复计分。

## 当前运行证据

- `runner_results_adhoc_20260922_172514_609_17532.json`：精神力与宠物出伤 RED 0/2，真实生产断言失败。
- `runner_results_adhoc_20260922_172843_986_17464.json`：上述GREEN及火墙batch 3/3 PASS。
- `runner_results_adhoc_20260922_173259_998_4068.json`：技能分类+正式context消费者 2/2 PASS。
- `runner_results_adhoc_20260922_173313_031_10124.json`：人物AC RED，原raw20绕过AC100。
- `runner_results_adhoc_20260922_173354_461_8632.json`：成长倍率及旧cap RED 0/2。
- `runner_results_adhoc_20260922_173647_426_13256.json`：成长/跨图/毒、人物AC、精神力、战士攻杀共5/5 PASS。
- `runner_results_adhoc_20260922_173706_612_9144.json`：地狱火200ms实际重复4提交 RED。
- `runner_results_adhoc_20260922_173948_481_7316.json`：相关13项12PASS/1FAIL。失败为旧召唤范围测试仍认circle/2GU，历史7e8a34af已改为1.5×1/3×1；按既有权威修测试边界，生产几何未改，随后专项PASS。

所有原始runner JSON位于 outputs/test_logs。最终完整回归、提交、APK及设备证据另在交付记录绑定。

## 最终补测与局限

原始30怪三场景和六火墙已完成同条件最终复测，原始→最终p95并未统一改善：约+2.34%、+2.90%、-0.18%、+7.32%。完整数据、攻击次数、每次CPU与fixture差异见 `FINAL_VERIFICATION.md`。不能以之前正式地图的局部改善替代这组结果；手机流畅度NOT_RUN。最后火墙公共执行结果已返回真实owner，5项收口及16项相关回归PASS；安全区默认字典分配移除后3项PASS。
