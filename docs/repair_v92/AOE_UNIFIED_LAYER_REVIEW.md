# AOE 与全技能分类分层静态调查

> 历史采样说明：以下保留调查时点的候选与验证状态。主控后续生产修复、动态结果和剩余边界见 [CONTROLLER_REVIEW.md](CONTROLLER_REVIEW.md) 与 [USER_REQUEST_RECONCILIATION.md](USER_REQUEST_RECONCILIATION.md)；本文的旧 NOT_RUN/旧数量不代表最终当前状态。

日期：2026-09-22。审查基线 HEAD：`b961cedff8040c9fc81534e094241ad9fa2330ad`，对象是含主控未提交修复的工作树，**不是该 HEAD 的干净源码**。主控并行继续修改 `game_root.gd`；行号代表本次读取位置，符号和末尾哈希用于定位版本。

范围：SOT 全部 33 个正式玩家技能的分类、正式生产入口、伤害与表现所有权；火墙压缩历史、AOE/投射物/特效更新和墙体排序直接链。原只读调查仅写本报告；后续主控批准新增分类策略和独立测试，详见第 8 节。未运行 Godot、性能采样、截图、设备或 Git 写操作；道士/宠物成长细节由另一专项调查承担。所有“成本候选”均为静态可证工作量，不能直接等同蜈蚣洞或赤月卡顿根因。

## 1. 结论与可立即交给主控的候选

1. **火墙高度 0.6 本身只缩放 Sprite 子节点，未发现它进入伤害快照、GU 查询、命中半径、tick 或寿命。** 但是引入它的提交同时改了世界排序和火墙 2×2→3×3；视觉 cell 从 4 个变 9 个。历史关联不等于“高度压缩导致卡顿”。当前 3×3 是用户主源，不应回退。
2. **通用法术上下文收集存在已定位冗余工作。** `_canonical_target_context` 对除已预解近战以外的请求建立敌人列表，并逐敌人探测地形、创建 Dictionary；职业 runtime 只有抗拒火环与困魔咒消费 `context.targets`，只有抗拒火环消费 `path_blocked`。多数技能随后另做正式命中查询。密集墙体和怪群会放大这项释放帧成本。
3. **正式投射物仍走分配候选记录的旧式查询接口，并每物理帧重建 segment snapshot、每候选重复验证。** 共用空间索引已经有 caller-owned node 输出接口，但该消费者未接入。必须保留最先命中选择、稳定顺序、映射/距离/碰撞合同，不能用无序替换证明性能。
4. **火墙“共享时钟”并未共享调度。** 每 field 是 1 个 controller、9 个 cell 物理更新、9 个动画 `_process`；默认 8 field 上限即 72+72 个子节点更新。没有显式离屏/遮挡脚本更新门控。此项与怪物查询已经分开，不能误称每 cell 扫描怪物。
5. **地狱火轨迹仍在长帧内逐步刷新所有 sprite。** 普通动画已合并 catch-up 到最终帧，该特殊表现分支尚未同样处理。它还把不同深度的轨迹 sprite 放在同一个不再递归 y-sort 的代理下，存在穿越墙体深度时的表现候选。
6. **统一只应收敛生命周期、调度、空间查询接口、资源租约、地图代际和可追踪的 owner。** 必须保持物理攻击、直接法术、持续法术、控制、治疗、召唤各自的结算。火墙 `MAGSTRUCK_MINE` 不能被改成普通直接法术的走路延迟；治疗不能通过负伤害实现。

## 2. 权威与 33 个技能完整映射

全集来自 `assets/data/vanilla_176/skills_source_of_truth_v1.json:skills`（33，战士 6、法师 14、道士 13），经 `scripts/skills/skill_data_loader.gd` 装载、`skill_runtime_router.gd` 路由三个职业 runtime，再由 `skill_execution_plan_contract.gd` 规范化 `gameplay_actions`、visual/projectile/ground/summon descriptors。下表是分类映射，不新增第二技能权威，也不修改 SOT。

入口缩写：**M** = Player 攻击释放 → `GameRoot._on_player_attack:7033` → 释放几何及目标 → `_execute_canonical_melee:8088` / 普通攻击；**C** = Player 技能释放 → `_on_player_skill` → `_execute_canonical_skill:7728` → router/plan → `_apply_canonical_effects_from_plan`。M 与 C 可共享不可变 release snapshot 和空间设施，不能合并命中与伤害策略。

表现缩写：**V** = `CasterSkillVisualEffect` + `CasterSkillAnimationPlayer` + 资源 registry；一次表现由动画完成释放，魔法盾表现由 buff 状态释放，转图 `zone_content` 清理；**PV** = `SkillProjectile` 及其动画子节点；**WV** = `WarriorMeleeVisualEffect`（Polygon2D/tween 自有寿命）。表内“状态 owner”指真正继续计时/处理的对象，绝非 visual 替代玩法状态。

| stable skill_id | 名称 / 层与类别 | 正式入口及 gameplay action | 生命周期、表现 owner |
|---|---|---|---|
| `warrior.basic_swordsmanship` | 基本剑术；物理被动准确 | M；`resolve_warrior_melee_modifiers` / `passive_stat_modifier` | 角色已学技能/属性；不创建独立伤害或常驻特效 |
| `warrior.slaying_swordsmanship` | 攻杀剑术；物理攻击修饰 | M；每合法动作一次 proc，准确加成和主体后伤害加成 | 同一次 melee action；主体视觉/WV，不新增法术 |
| `warrior.thrusting` | 刺杀剑术；物理线型多目标 AOE | M；两段 `melee_hit`，共享该次 DC，第二段免 AC | 释放帧目标清单；WV/tween |
| `warrior.half_moon` | 半月弯刀；物理扇形 AOE | M；`melee_arc` 主/侧目标倍率 | 释放帧目标清单；WV/tween |
| `warrior.wild_rush` | 野蛮冲撞；物理动作/无伤害位移控制 | C/warrior runtime；`level_gated_push` | 原子路径预检和移动执行；无通用伤害 |
| `warrior.fire_sword` | 烈火剑法；物理蓄力/下一次单体攻击 | C 建 `next_melee_charge`，M 合法攻击消费；也有直接触发合同 | GameRoot charge deadline + Player 显示/冷却；WV |
| `wizard.fireball` | 火球术；法术单体投射物 | C；`projectile_damage` → PV | PV 移动、segment 命中、射程/转图释放；命中时法术 sink |
| `wizard.repulsion_ring` | 抗拒火环；法术范围控制、零伤害 | C；`adjacent_push` | release 目标/等级/概率/路径检查；V |
| `wizard.temptation_light` | 诱惑之光；法术单体控制/驯服分支 | C；`temptation_resolution` | Enemy 状态/所属关系负责持续；V 一次表现；概率分支不可改为 MAC 伤害 |
| `wizard.hellfire` | 地狱火；法术即时线型 AOE | C；`line_damage`，5×1 线，命中全体相交目标 | release 立即结算；V 特有 firegun trail 是表现，非逐段伤害/引导 |
| `wizard.lightning` | 雷电术；法术直接单体 | C；`targeted_sky_strike`，按目标身份结算 | release 直接法术 sink；V sky strike，明确不创建水平投射物 |
| `wizard.great_fireball` | 大火球；法术单体投射物 | C；`projectile_damage` → PV | 与火球同 PV 生命周期，非爆炸 AOE |
| `wizard.teleport` | 瞬息移动；法术自身位移 | C；`server_random_teleport` | 合法目的地/概率/位置提交；V；无伤害 |
| `wizard.exploding_flame` | 爆裂火焰；法术即时 3×3 AOE | C；`area_damage` | release 快照一次结算；V 完成释放 |
| `wizard.fire_wall` | 火墙；法术持续地面 3×3 AOE | C；`persistent_ground_damage` → 专有 field controller | registry/cap/refresh + controller tick/wallclock；9 个纯 visual cell；`MAGSTRUCK_MINE` |
| `wizard.laser` | 疾光电影；法术即时穿透线型 AOE | C；`piercing_line_damage`，8×1 线 | release 一次结算；V beam 的 continuous 表现策略不代表连续伤害 |
| `wizard.hell_lightning` | 地狱雷光；法术自身中心范围 AOE | C；`caster_centered_area_damage`，半径 2、不含中心、上限 24 | release 一次结算；V |
| `wizard.magic_shield` | 魔法盾；法术持续自身增益 | C；`refreshable_damage_reduction_buff` | Player buff 负责持续；V 跟随 active buff，重放替换旧视觉并 queue_free |
| `wizard.holy_word` | 圣言术；法术单体特殊即死检查 | C；`holy_word_resolution` | eligibility/概率/即死专用分支；V；非普通直接伤害公式 |
| `wizard.ice_storm` | 冰咆哮；法术即时 3×3 AOE | C；`area_damage` | release 一次结算；V |
| `taoist.healing` | 治愈术；法术友方单体治疗 | C；`dedicated_heal` | 友方治疗 sink；持续治疗由 GameRoot._ongoing_heals 调度；V；不走 damage |
| `taoist.spiritual_warfare` | 精神力战法；物理准确被动 | 角色属性/`passive_stat_modifier` | 物理 melee hit 属性；不加到火符或法术命中 |
| `taoist.poison` | 施毒术；法术单体持续减益 | C；`poison_resolution`，抗毒专用 | Enemy 绿/红毒状态负责 tick/到期；V；正式 action 不是 PV 的兼容 poison 分支 |
| `taoist.soul_fire_talisman` | 灵魂火符；法术单体投射物 | C；`talisman_projectile_damage` → PV | 延迟释放合同/PV；命中 MAC 法术 sink |
| `taoist.summon_skeleton` | 召唤骷髅；召唤/召回 | C；`main_pet_spawn` 或 `recall_existing_main_pet` | 正式召唤 sink、SummonActor/主宠状态；V；不在本报告深入成长 |
| `taoist.invisibility` | 隐身术；法术自身持续增益 | C；`monster_aggro_stealth` | 角色 stealth 状态/移动破除；V 一次表现 |
| `taoist.mass_invisibility` | 集体隐身术；法术友方范围增益 | C；`area_monster_aggro_stealth` | release 固定友方集合，各 actor 状态 owner；V |
| `taoist.magic_defense` | 幽灵盾；法术友方范围 MAC 增益 | C；`friendly_defence_buff` | 各友方 actor buff 负责合并/到期；V |
| `taoist.defense` | 神圣战甲术；法术友方范围 AC 增益 | C；`friendly_defence_buff` | 各友方 actor buff 负责合并/到期；V |
| `taoist.revelation` | 心灵启示；法术单体信息状态 | C；`hp_information_reveal` | 当前 GameRoot sink 调 GameHUD.show_message；V；零伤害，未见持久 reveal 状态 |
| `taoist.entrapment` | 困魔咒；法术范围持续边界控制 | C；`monster_boundary_control` | 目标 Enemy 边界状态 + EntrapmentBoundaryController；入界/到期/转图解除；V |
| `taoist.mass_healing` | 群体治疗术；法术友方 3×3 治疗 | C；`dedicated_area_heal` | 友方集合/专用治疗；GameRoot._ongoing_heals 调度持续部分；V；禁用负伤害代替 |
| `taoist.summon_divine_beast` | 召唤神兽；召唤/召回 | C；`main_pet_spawn` 或 `recall_existing_main_pet` | 正式召唤 sink、SummonActor/主宠状态；V；成长另审 |

职业 action 证据：`scripts/skills/runtimes/warrior_skill_runtime.gd:12`，`wizard_skill_runtime.gd:10`，`taoist_skill_runtime.gd:45`。部分被动兼容 planner 可返回同名 action，但正式每次 melee 入口使用 modifiers，不能把其兼容函数当每次真实调用成本。

## 3. 火墙压缩、伤害、排序、裁剪与清理

### 历史确证

`git show` 只读检查提交 `96a659133a0339c68ffc86ae9caf0adf51d6c97f`（2026-09-13，Repair touch inventory, crowd queries, durable loot and world effects）及其父提交：

| 项 | 提交前 | 提交后/当前 |
|---|---|---|
| `GroundSkillEffect.FIRE_WALL_HEIGHT_SCALE` | 无 | `0.6`，仅 `candidate.scale.y *= ...` |
| 世界排序 | fire wall 固定 z=-1 | `WorldEffectRenderOrder.create_proxy`，z=0、脚点 y-sort |
| SOT geometry | square 2×2 | square 3×3，用户 request 5 明确覆盖 |

JSON 在 git diff 被仓库识别为 binary；本次用 `git show REV:path` 读取完整原始 JSON 后按 `skill_id` 精确比较，未用 diff 文案猜测。4→9 是每 field visual cell 数量变化，不是伤害频率乘以 9。

### 当前数据隔离

- `ground_effect.gd:62` setup 独立保存 damage/radius GU/visual radius/duration/tick/snapshot；`:296` 安装动画，`:307` configure 的 desired extent=0，`:313` 才压缩动画 y scale。registry 中火墙是 `source_pixels/source_scale=1`，6 帧、40 ms、loop，native extent=73×179；压缩后的图像范围约 73×107.4 像素（纹理各帧 bounds 不同）。它不是把 GU 高度改为 0.6。
- `fire_wall_field_controller.gd:118` 持有 canonical snapshot，`:128` 严格校验；`:312` 一轮 envelope 查询，`:354` 将 enemy 实时脚点按注入地图投影转 GU，做 snapshot 精确相交。没有读取 Sprite scale/texture bounds。
- cell `cell_ground_offset` 是视觉/诊断附带值，正式 controller 命中读取 field canonical snapshot；不能把它当第二伤害源。
- `ground_skill_visual_cell.gd:23` 覆盖 parent physics，只减视觉寿命，不运行 parent legacy damage tick。controller 是唯一 field damage/claim owner。
- controller `:191` wallclock expiry；`:246` 先检查真实时钟到期再更新视觉时钟、duration、tick；`:202` 同位置刷新同步更新 cell duration；registry 在 GameRoot `_clear_fire_wall_field_registry:10352` 清除。转图 `game_root.gd:4200` 先清旧 map 空间索引，`:4209` 清 zone_content，`:4215` clear generic manager，`:4218` 单独清 field registry。
- 动画 `caster_skill_animation_player.gd:300` acquire sequence lease，`:318` exit release；一次动画完成也 release，循环由节点离树 release。统一调度如果只隐藏不释放，不能据此宣布生命周期已结束。

### 墙体/相机边缘

`world_effect_render_order.gd:9` 设置 owner z=0/y-sort，proxy `(0,-0.01)` 且其 `y_sort_enabled=false`；`:22` 子视觉补 `+0.01`。脚点和画面坐标分离，height scale 不移动 owner。`world_background.gd:1700`、`:2594` 的 actor_y_sort 墙节点被放到同一 GameRoot 平面（root 直系子节点、z=0）。当前每片火墙每 cell 自有 proxy，可按各自脚点排序。

未发现火墙/GroundSkillVisualCell/动画 player 以缩放后的高度做 CPU 视域或遮挡裁剪；因此不能声称“0.6 导致视域判定漏画”。Godot 自身 draw culling/GPU overdraw/墙遮挡效果需要主控真实画面验证，本次 **NOT_RUN**。相机边缘只停 visual 提交的候选也必须保证 offscreen 伤害继续、wallclock 到期继续、离树租约释放继续；不能按可见性停 gameplay。

地狱火不同：`CasterSkillVisualEffect._add_world_visual:338` 为整条表现复用一个非递归排序 proxy，`:471` 所有 trail sprites 加到这个 proxy，`:520` sprite 位移沿线推进。若一条向上/斜向线穿过墙体脚点 y 的前后两侧，整条 sprite 群只能按 effect 原点参与 y-sort。这是**静态排序粒度不一致候选**，不等于已确认画面错误；最窄验证是固定墙 y，线两端跨过墙 y，逐步推进镜头并比较每段脚点应有前后关系。激光单个长 sprite 也只有单锚点，但是否应拆段属于表现合同，不能未经确认推成必修缺陷。

## 4. 具体成本候选与最窄验证

### C1：不消费的通用敌人上下文及墙探测

证据：`GameRoot._canonical_target_context:8284`，search range 起于 `SpellTargetLockPolicy.LOCK_RANGE_GU` (`:8297`)；`:8560` 只以 `hostile_targets_pre_resolved` 跳过，未按 action 所需数据分流；`:8576` 空间查询；`:8583` 已有 snapshot 时先精确过滤；`:8611` 每个保留候选分配 target Dictionary；`:8617` 调 `background.is_environment_point_blocked`。不是所有技能都扫 12 GU：已有 exact snapshot 时使用 snapshot AABB，attached shield 可非常小，必须逐技能测量候选数。

生产消费搜索：`scripts/skills/**` 中 `context.get("targets")` 只有 WizardRuntime `_resolve_repulsion:151`、TaoistRuntime `_resolve_entrapment:657`；`path_blocked` 只有 repulsion `:172`。其余伤害技能走 `_apply_canonical_spell_damage:9242`；firewall controller 和 projectile 更晚自己查询。友方技能另建友方集合，敌方上下文不会变成其目标权威。

触发：每次 C 释放，规模 O(上下文包围盒中敌人数) 的列表、相交和地形 probe；密墙增加每次 probe 的真实成本须量测。最窄验证：同一真实 production release 分别放 0/30/100 个候选、可行/密墙地图，计 context broadphase、path probes、后续命中查询；火球、冰咆哮、火墙、雷电、魔法盾、治疗各一个，再用抗拒/困魔咒作必须保留消费的正例。任何实现都需比较目标 ID、伤害、RNG 消费、释放/硬直状态，不应删控制上下文。

### C2：投射物持续记录分配及重复严格校验

证据：`skill_projectile.gd:407` 每物理帧建 swept capsule snapshot，`:427` 验证；`:448` 调 `RuntimeCombatSpatialIndex.query_segment_candidates:188`。索引 `:571` 每候选创建 record Dictionary，`:583` sort；projectile `_swept_segment_intersects_enemy_footprint:534` 对同一 cast snapshot (`:543`) 和本帧已验证 segment (`:551`) 按候选重复 strict 检查。索引已有 `query_enemy_nodes_segment_unsorted_into:309` 等接口，但正式 projectile 仍用 record API。

触发：P 枚在途投射物、F 次物理 step、每次 K 候选，segment 构建 O(PF)，额外验证/record O(PFK)，排序按每次 K。火球/大火球/火符是本表真实消费者；雷电、地狱火和激光不是该路径。最窄验证：固定映射和随机种子，1/8 枚 PV、K=0/8/40，比较首个实际命中 ID、地形停止、边界接触、射程耗尽、map generation 无效拒绝，并计 snapshot build/strict validation/records。不可直接无序替换稳定候选顺序。

### C3：firewall visual 的多个调度入口

证据：controller `:154` 按位置建 9 cell；cell `_physics_process:23`；animation `_process:325` → shared clock `:416` 每 player 每 render frame Callable/fmod/floor，只有 frame index 不同时 bind frame。controller `:349` 每 damage tick 对各 visual cell `queue_redraw()`，但 `ground_effect.gd:392` 有 Sprite 或 stable skill_id 时 `_draw` 立即返回，形成无内容 redraw 请求。

触发：1/4/8 fields 对应9/36/72 cell，8 field 理论产生72个cell physics +72个animation render callback（另8controller），无显式 offscreen update gate。60Hz 双环下约 8640 次子节点回调/秒是静态计数推算，不是 measured ms。frame change 约25Hz；没有“每帧都 bind texture”的证据。cell 使用只读 snapshot 也在创建时各自校验一次，这是释放时冗余，非每帧9次重建。

最窄验证：伤害/怪物规模不变，只比较相同8fields在镜头内、边缘、镜头外的 visual callback/frame bind/CPU ms，并覆盖冷载→常驻、刷新、cap淘汰、转图、暂停后超期。先记录成本再决定是否由 field 统一 visual frame 提交；不得减 field 数、cell数或 tick频率制造性能结果。

### C4：地狱火长帧 catch-up 重复显示提交

证据：`caster_skill_visual_effect.gd:481` while 循环按每 50ms 逐步 `_advance_hellfire_trail:488`；每步 Dictionary age、remove/push_front (`:503`) 后调用 `_update_hellfire_sprites:512`，对最多6 sprite 设置位置/manual frame。registry 的 hellfire 是6帧/50ms。相反 `caster_skill_animation_player.gd:338` 普通动画已只提交最终 catch-up 帧。

触发：200ms 长帧最多推进4步，每步遍历6sprites；更长 stall 会在尚未 finished 时补全部剩余步，有限但会叠加同帧成本。只影响表现，伤害在 release 已一次提交，不能把逐步表现误当多次伤害。最窄验证：相同 elapsed 时间，多个小 delta 与一个200/600ms delta 比较 emission count、records age/position、最终画面和完成释放，同时计 set_manual_frame 次数与 lease归零；候选是分离逻辑推进与最终一次视觉提交，不能漏最后一帧或改变完成条件。

### C5：物理 AOE 对同一 plan 的两次 broadphase

证据：`_on_player_attack:7086` primary 查询后，刺杀`:7100` /半月`:7112` 调 secondary；`_physical_primary_targets:12010`、`_thrust_secondary_targets:12410`、`_half_moon_secondary_targets:12478` 各自对传入相同 plan.ground_aabb 调 `_aoe_query_enemy_candidates_aabb`。已预解列表之后 `_execute_canonical_melee` 不再重查，`hostile_targets_pre_resolved` 也已经关掉 C1；不能把同一 bug重复计三轮。主体 mode变化时重新取不同geometry是合法独立请求，不可随便跳过。

触发：每次刺杀/半月物理 release；相同 envelope 候选扫描2次，再各自分层筛选/排序。最窄验证：用同一 scratch候选供两个 selector，比较primary/secondary互斥、locked优先、边界、攻击mode切换、各目标命中RNG顺序和AC策略，计同plan broadphase次数。它只能作为物理层内部候选，不能与法术selector合并。

### C6：效果身份/调度所有权仍不统一

证据：`_spawn_canonical_cast_nodes_from_plan:9135` fire wall 单独spawn后`:9152` 返回空数组；`_apply_canonical_effects_from_plan:8750` 的 spawned_ground_effect_ids 从 returned nodes 收集，因此field不出现在该公共结果列表，实际身份在独立registry。generic `PersistentGroundEffectManager` 管别的ground registrations，正式firewall不经过它。统一结果若只看空数组会误判未创建，或未来无法通过公共release handle取消。这是可观测性/生命周期接口缺口，当前转图有专门registry清理，不能声称已泄漏。

最窄验证：每个formal descriptor创建后，release结果可枚举真实owner ID/类别/map generation；firewall same-tile refresh与cap eviction应返回/追踪现有或新owner，不可把9cell当9damageowner。cancel/转图后实际node和registry/lease全部归零。此项不证明有帧率收益。

### C7：物理 AC 消费差异（独立正确性候选）

`game_root.gd:8219` 刺杀 `melee_hit` 调 `WarriorCombatMath.resolve_enemy_physical_damage`，primary扣AC、secondary明确免AC。半月`:8233`、烈火`:8250`、normal`:7263` 直接把body结果交 `_apply_physical_hit:12206`；该函数只做accuracy/agility命中，再到 `CombatRuntimeService.apply_enemy_physical_damage:49`，后者仅转 `EnemyActor.take_damage:6193`；`EnemyActor._apply_damage_core:6244` 直接从HP减amount。沿这条链未见一般/半月/烈火消费target.defense。这与SOT半月 physical/AC描述不一致，不能在报告中把“共享物理sink”描述成已经统一算过AC。

静态差异已定位，动态 **NOT_RUN**。建议主控另立最窄真实release测试：相同body DC、同seed保证命中，target defense=0/80，对normal、半月primary/side、烈火、刺杀两段分别比较HP差；先确认现行用户合同，再裁决修复。不是蜈蚣洞卡顿解释，不建议在性能改动里顺手修改。

## 5. 已收敛路径、兼容旁路与不得混同的边界

- 即时正式 CELL_UNION 伤害 `GameRoot._canonical_spell_geometry_targets:9749` 内正式 branch（约9863）已是一轮包围盒 +每候选解析相交，并返回；后面逐格fallback不等于3×3正式路径。`SkillFootprintSnapshot.intersects_target_combat_footprint_ground_gu:1347` 对cell union等正常形状用解析判定。现有测试包括 `player_aoe_spatial_broadphase_parity_test`、`aoe_shape_edge_counterexample_test`；本次未跑。
- 火墙controller已单查询/每候选一次精确判定、同caster目标tick claim；原全enemy group/directdamage旁路已收敛。相关 `fire_wall_single_query_per_tick_test`、`fire_wall_single_exact_test_per_candidate_test`、`fire_wall_no_group_scan_test`、`fire_wall_visual_cells_pure_test`、`fire_wall_tick_claim_parity_test` 可作为回归，不应重新报告旧全扫已存在。claimsGC已有节流，不重复主控既有优化。
- generic `CasterSkillRuntime.create_ground_effects:195`/`_configure_ground_runtime:560` 仍有兼容路径；GameRoot generic ground field分支为每position建立GroundSkillEffect/manager注册。当前33正式SOT只有火墙产 `persistent_ground_damage`，且`:9135`提前分流，故不能把generic manager的按registration工作量当当前firewall真实负担。未来新增持续地面技能要先明确“每field一次伤害”还是“每cell独立伤害”，不能沿旧接口自动复制whole snapshot给所有cell并假定安全。
- 正式 PV 命中 `skill_projectile.gd:692` 对可anti-magic的damage进入法术服务；`:678` poison/control/charm及`:709`直take_damage仍在类内，但正式施毒action是`poison_resolution`直接状态，不应根据该兼容分支宣称当前施毒用投射物或绕MAC。未展开第三方/测试自建projectile的合法性。
- `CombatRuntimeService.apply_enemy_direct_spell_damage:71` 保留anti-magic→MAC→damage。`:133` DIRECT_MAGSTRUCK在进入magic-defense阶段后会延后walk tick，即使MAC后damage0；正伤才ordinary STRUCK。firewall `_apply_canonical_ground_tick:10522`明确传 `MAGSTRUCK_MINE`，不延walk tick，但正伤可普通STRUCK。poison状态以DamageHealth方式tick，不ordinary STRUCK（`enemy.gd:6227`）。这些是至少3种不同法术/状态交付语义。
- M层attack release、accuracy/agility、每动作一次proc、耐久写入及刺杀免AC，与C层cast deadline、projectile到达、anti-magic/MAC不同。Player pending release与受击串行保护已由主控本轮修复，本报告不提议统一计时器取代状态机。
- 物理 WV使用自身Polygon/tween，约0.30秒，`TWEEN_PAUSE_PROCESS`，z=-1；caster ground/effect用WorldRender z0；projectile是自身Node2D脚点+直接动画child。表现owner未统一不自动等于缺陷，各层语义需要显式保留。
- 怪物地刺属于敌方行为，不在33玩家skill全集。`MonsterGroundSpikeEffect`的metadata明确damage owner为`enemy.fixed_area_ground_spike_release`（`:215`），它是`zone_content`一次视觉，不能迁成玩家spell action。赤月场景采样应单独标记敌方地刺/玩家AOE数量；本报告未审全怪物技能或宠物成长。

## 6. 统一层的最小接口边界（供主控裁决，不是实施）

允许共享的东西：稳定skill_id/release_id/map generation、不可变canonical snapshot、spatial query的caller-owned输出、effect owner注册/refresh/cancel、visual资源lease与完成信号、显式world footpoint、只针对表现的可见性/帧提交。一个release可以有多个表现节点，但应能明确列出唯一或明确数量的gameplay owner。

必须分别保留的东西：物理选择器和AC/accuracy/proc；直接单体和即时AOE的MAC交付；投射物在途/命中时点；firewall tick/claim/MAGSTRUCK_MINE；毒/控制/即死检查；友方治疗/增益；召唤/召回状态。不要把它们收进一个接受任意type并统一扣血/硬直的函数。当前已有formal plan，应补齐消费接口及owner闭环，不应再建一份全技能权威表替代SOT。

## 7. 验证状态与源码身份

| 项 | 本次状态 | 证据/限制 |
|---|---|---|
| 33 skill_id全集及runtime action静态映射 | PASS | 从SOT机械枚举；与报告表一一校验 |
| 火墙height提交及同提交geometry/sort变更 | PASS | git show父/子原始文件，只读比较 |
| height到GU damage/snapshot/timing调用链静态隔离 | PASS | 直接读取ground/controller/animation/WorldRender消费者 |
| 冗余query、per-frame分配/更新候选 | PASS | 符号/调用点可复核；这里只表示静态发现有证据 |
| 新旧性能对比/主控RED→GREEN | NOT_RUN | 本代理不运行Godot；主控独立负责 |
| 蜈蚣洞、赤月真地图帧时间 | NOT_RUN | 不能用静态O()或callback计数冒充ms |
| GPU/墙遮挡/相机边缘截图、Android设备 | NOT_RUN | 无画面验收；排序候选需实际场景证实 |
| 后续授权分类策略/测试施工 | PASS | 仅新增第 8 节三个文件；未改旧生产/测试、SOT、地图、掉率 |

读取时关键文件raw SHA256（以正文符号为导航，主控后续源码改变需重新核对）：

```text
ce0f7829172530bc1d29a61784ae132b6782a3afe5511d6357b3caf7b0547d8b scripts/game_root.gd
7e3b08e09b3349d9625fdab2e6cefefb263cfed9aceb02d9a00a64e64c659ad9 scripts/ground_effect.gd
b413492b11f1f47926b2a363cd92e8e8d4f3bcde4e34db4e3faf262cb29166d6 scripts/fire_wall_field_controller.gd
e3e6d065d1105049a314b67abc3d8abd49216f35ced212ea7c6aeec2d6131328 scripts/ground_skill_visual_cell.gd
7aba2614d202e7ec36484521a646a74d755b1efb1a32436621cf88ea79fcf8d8 scripts/caster_skill_animation_player.gd
58935ef4619005153334dfc2358c57eadce57ecdd208189dfddb009335b1d323 scripts/caster_skill_visual_effect.gd
e4f61caa844ad9199ac60ee4b6ca426f8a989a3e997b7f878d83a9a186019b25 scripts/skill_projectile.gd
d6fb8a233b19743e5d4ffe6956b486429f9b2cd86d2db88437957d4a7401daf5 scripts/world_effect_render_order.gd
7575c45a7bd147f8e60d2efdb15c6c5e9781445ddc2f748e73dd69ed386a62ab assets/data/vanilla_176/skills_source_of_truth_v1.json
```

## 8. 后续批准的最小共同策略实施

主控随后授权新增纯静态 `scripts/skills/skill_runtime_classification.gd` 和独立 `tests/skill_runtime_classification_test.gd/.tscn`。不改 GameRoot、SOT 或职业 runtime；GameRoot 消费接入、Godot 编译/测试、真实地图性能对比由主控完成。没有增加 Node、scheduler、damage service、别名 fallback 或第二套几何/数值权威。

公共接口：`profile(skill_id)`、`needs_hostile_context_targets(skill_id)`、`needs_push_path_probe(skill_id)`，另 `skill_ids()` 供精确全集验证。unknown 返回空 profile；helper 对 unknown 为 false，调用方必须先拒绝空 profile，不能把 false 当成已识别无上下文技能。profile 为副本，外部修改不污染策略。

`context_targets` 是唯一供本轮上下文优化使用的字段。它只控制通用敌人数组及其中 repulsion path probe；target_instance_id、目标等级/不死属性、LOS等 scalar context 与所有 friendly 候选保持其正式消费链。shape 是分类标签，不替代 canonical snapshot 的长度、半径、单元格与投影。domain 不从职业名推断；圣言尽管当前 sink借用了 physical delivery helper，语义仍是 spell special kill，不可据helper名字改成物理攻击。

以下 owner 已核对实际消费者：持续治疗为 `GameRoot._ongoing_heals`（10806/10824），并非各actor独立计时；心灵启示当前仅 `GameHUD.show_message`（9071起），不能根据SOT duration推断实现了持久信息buff。后者属于分类时记录现状，并未在本轮修复实现差异。

| ID | domain | delivery | target_shape | target_semantics | lifetime_owner | context_targets |
|---|---|---|---|---|---|---|
| warrior.basic_swordsmanship | physical | passive | none | physical_accuracy_modifier | PlayerState.computed_stats | none |
| warrior.slaying_swordsmanship | physical | melee_modifier | melee_front | physical_melee_modifier | GameRoot._on_player_attack | none |
| warrior.thrusting | physical | melee | line | hostile_damage | GameRoot._execute_canonical_melee | none |
| warrior.half_moon | physical | melee | arc | hostile_damage | GameRoot._execute_canonical_melee | none |
| warrior.wild_rush | physical | direct | line | hostile_control | GameRoot._apply_wild_rush_displacement | none |
| warrior.fire_sword | physical | melee_charge | single | self_physical_charge | GameRoot._canonical_fire_charge_expires_ms | none |
| wizard.fireball | spell | projectile | single | hostile_damage | SkillProjectile | none |
| wizard.repulsion_ring | spell | direct | ring | hostile_control | GameRoot._apply_canonical_effects_from_plan | adjacent_push |
| wizard.temptation_light | spell | direct | single | hostile_control_or_tame | EnemyActor | none |
| wizard.hellfire | spell | direct | line | hostile_damage | GameRoot._apply_canonical_spell_damage | none |
| wizard.lightning | spell | direct | single | hostile_damage | GameRoot._apply_canonical_spell_damage | none |
| wizard.great_fireball | spell | projectile | single | hostile_damage | SkillProjectile | none |
| wizard.teleport | spell | direct | self | self_teleport | GameRoot._apply_canonical_effects_from_plan | none |
| wizard.exploding_flame | spell | direct | area | hostile_damage | GameRoot._apply_canonical_spell_damage | none |
| wizard.fire_wall | spell | persistent_ground | area | hostile_damage | FireWallFieldController | none |
| wizard.laser | spell | direct | line | hostile_damage | GameRoot._apply_canonical_spell_damage | none |
| wizard.hell_lightning | spell | direct | ring | hostile_damage | GameRoot._apply_canonical_spell_damage | none |
| wizard.magic_shield | spell | actor_status | self | self_buff | PlayerCharacter.shield_time | none |
| wizard.holy_word | spell | direct | single | hostile_instant_kill | GameRoot._apply_canonical_effects_from_plan | none |
| wizard.ice_storm | spell | direct | area | hostile_damage | GameRoot._apply_canonical_spell_damage | none |
| taoist.healing | spell | actor_status | single | friendly_heal | GameRoot._ongoing_heals | none |
| taoist.spiritual_warfare | physical | passive | none | physical_accuracy_modifier | PlayerState.computed_stats | none |
| taoist.poison | spell | actor_status | single | hostile_debuff | EnemyActor | none |
| taoist.soul_fire_talisman | spell | projectile | single | hostile_damage | SkillProjectile | none |
| taoist.summon_skeleton | spell | summon | adjacent_spawn | main_pet | SummonActor | none |
| taoist.invisibility | spell | actor_status | self | self_buff | PlayerCharacter.stealth_time | none |
| taoist.mass_invisibility | spell | actor_status | area | friendly_buff | PlayerCharacter/SummonActor | none |
| taoist.magic_defense | spell | actor_status | area | friendly_buff | PlayerCharacter/SummonActor | none |
| taoist.defense | spell | actor_status | area | friendly_buff | PlayerCharacter/SummonActor | none |
| taoist.revelation | spell | direct | single | target_information | GameHUD.show_message | none |
| taoist.entrapment | spell | actor_status | boundary | hostile_control | EnemyActor/EntrapmentBoundaryController | boundary_control |
| taoist.mass_healing | spell | actor_status | area | friendly_heal | GameRoot._ongoing_heals | none |
| taoist.summon_divine_beast | spell | summon | adjacent_spawn | main_pet | SummonActor | none |

测试来源及状态：

- 测试文件先于策略实现写入；根据主控串行执行限制，本代理未跑 Godot，RED/GREEN 均 **NOT_RUN**，不声称已运行通过。
- 全集从正式 `SkillDataLoader.skill_ids()` 获取，验证精确一一对应和职业6/14/13。没有复制一张33行expected profile来同义自证。
- 消费需求由SOT `mechanics.runtime_family` 中 `area_push_no_damage`/`monster_boundary_control` 验证；assert仅2个hostile-array消费者、仅1个push probe。被动accuracy必须归物理；SOT单体projectile家族必须保持single/projectile。
- 调用真实WizardSkillRuntime（读真实定义）验证雷电targeted_sky_strike无水平投射物、大火球projectile、地狱火非channeled line、疾光piercing line、火墙persistent ground与tick；调用真实TaoistSkillRuntime在友方candidate上验证dedicated_area_heal。此类测试验证分类与真实action保持边界，不mock掉实际runtime。
- unknown中文名、截断/扩展ID及返回副本修改隔离有明确断言。
- 本代理Python静态校验已 **PASS**：33个策略ID与当前SOT集合完全一致、6/14/13、上述family/context不变量、三个新文件无行末空格。GDScript编译/执行依然 **NOT_RUN**。
