# HardCore 109 · B02_followup：人物、技能、伤害动作时序补审

**只读源码基线：** `ed2d87121de80c84caaa3f096c3a5acb71d4946f`（watermarkpp/HardCore）。原B02报告固定保存于 `external/B02/`，原始接收提交 `ac4c3f285053e10993b20712e7ab99ee107a1512`。**本补审仅新增B02-008起的发现，不重写B02-001～007，不碰生产/测试/数据/配置、不运行原生测试、不构建APK。**

**结论：`B02_FOLLOWUP_STATIC_SCOPE_CLOSED_WITH_FINDINGS`，非动态/产品/发布PASS。** 按原`COVERAGE.json`精确补齐先前31个`INDEX_ONLY_PENDING_DEEP_REVIEW`与15个`PARTIAL_SEMANTIC_REVIEW`文件，46/46各有实际正式入口、已看函数、状态/唯一写入owner、异常/取消边界、仍余验证缺口；原13个`REVIEWED_CORE_FUNCTIONS`保留既有结果、不进行重复审计。共59个manifest文件有B02范围的静态审计记录，**不代表**`player_state.gd`全部10265行、`game_root.gd`完整其它职责或所有视觉辅助/地图/数据模块的跨批审查已经完成。

## 固定合同与纠偏

- 攻击/施法的**提交动作就破隐**为最新用户合同，不能擅自改成成功命中才破隐；旧B02-005非待修bug。
- **虹魔/原装备吸血按传入伤害**为已确认玩法，与Feature扩展按实际HP损失可有不同依据；旧B02-007不应因公式不同改成HP损失。
- 隐身戒指破隐后，应走**真实脱战恢复**；旧B02-004的状态讨论交主控现有规则核实，本补审不另行复刻或提出新玩法。
- B02-001暂停windup和B02-003碰撞后移动发布由主控正在独立修复验证；不重跑、不跨固定提交借用尚未push修复。
- 近战/已锁法术提交后，不随玩家移动/视觉取消伤害；一次性AOE冻结施法快照，FireWall逐跳重新判当前区域，投射物按真实飞行段命中。

## 跟踪覆盖的代码链（补审重点）

1. **角色及技能数据：** CharacterSelect `_enter_selected_character` → PlayerState角色身份/重算技能有效等级/穿戴授予 → SkillProgressionService合法学习与旧档load_snapshot → SkillDataLoader正式33技能定义 → SkillRankResolver与ExpansionPolicy区分实际数值/时长；预览、等级和UI状态独立不拥有HP写入。
2. **技能纯规划：** `SkillCastRequest.create/validate` → `SkillRuntimeRouter._plan` → Warrior/Wizard/Taoist运行时`execute` → `SkillExecutionPlanContract`冻结计划；三职业runtime只返回正式效果descriptor，没有第二套HP/MP或第二个planner。GameRoot仍是资源提交和实际效果的owner。
3. **释放几何：** CombatReleaseGeometry冻结live locked target release轴 → SkillGeometryService离散网格或CasterSpellGeometry连续GU/地形裁剪 → SkillFootprintSnapshot V2正式map-id、converter和各种exact footprint → SkillFootprintQueryPlan在同release内生成只读broadphase；GameRoot最终仍由CombatRuntimeService触达Enemy/Player HP端口。
4. **持续/友方与控制：** TaoistSupportPolicy选择真实友方、弱者优先、平局自我/距离/ID，full-HP也可合法承接持续治疗；FireWallFieldController独占实际每跳伤害并用正式spatial index exact验证，CasterSkillAnimationBatch与visual cell无HP写权限。技能持续效果的真实状态仍在现有Player/Summon/FeatureEffect owner。
5. **视觉与资源：** CasterSkillRuntime从冻结plan生成合法描述节点 → CasterSkillVisualFactory派生Beam/SkyStrike/Base → AnimationPlayer对整序列resident申请/释放lease，CasterSkillVisualRegistry维护有界LRU和combat async warm，GameRoot保有加载结果消费责任。**当永久加载失败时缺少visual terminal出口**是本次实质问题，不是取消已提交伤害的理由。
6. **人物视觉：** PlayerVisual按Player动作时钟和实际移动状态显示hit/run/death，PlayerHealthBar/StatusMarkerStrip/NoticePresenter只读或UI自有队列；正式HP/MP仍唯一由PlayerCharacter和PlayerState既有来源更新。

## 新发现（详见FINDINGS）

| ID | 严重度/类别 | 核心事实 | 裁决 |
|---|---|---|---|
| B02-008 | P2 · 条件性源码生命周期缺陷 | 合法视觉序列某资源持续FAILED时child等待整序列，parent也因`visual_loaded=false`不进入完成/清理，可能重复施法积累视觉节点 | 源码失效路径成立，真实负载须定向专项；不得影响HP |
| B02-009 | P2 · 条件性目标几何缺陷 | `SkillGeometryService.cells`把`Vector2i(0,0)`既当合法target_tile又当“未提供目标”，目标中心技能可能被重定位至caster | 需确认正式可达目标位于(0,0)的地图与受影响技能；不是已证手机复现 |
| B02-010 | P3 · 非生产元数据漂移 | `SkillSpatialProjectionContract`仍写火墙2×2、刺杀2.5GU、半月1.5GU，正式源码当前分别3×3、3GU、2GU | 未找到直接参与正式HP，报告为资料一致性问题，不改正式玩法 |

另外**确证一处纯冗余**：`CasterSkillAnimationPlayer.configure`有两个连续、完全相同判定条件的`elif (_desired_axis_extent >0 and not _fit_axis_world.is_zero_approx())`，后一个分支不可能触达。只记入`REDUNDANCY.md`，不删除。

## 本轮剩余边界

B02静态相关函数/消费链已补审；但HP/魔法的真实场景回归、Godot native、Android FPS、连续施法资源失败、0格位置、技能素材像素和全部史料一致性仍为`NOT_RUN`。跨批B03怪物/B04物品/B05 HUD和声音/B06存档地图/B07 authoring、旧审计B01在此轮均未审。此前13核心文件其它模块职责仍按原`COVERAGE.json`保留，不转成“全文件”完成。

**主控建议顺序：** 先接收B02-followup; 修B02-008的既有异步失败终态/Node收尾，不动HP和预算；确认0,0是否正式可达再决定B02-009；B02-010交正式资料维护，不将历史标签当正式战斗规则。B02-001/003继续在主控独立施工；B02-002首接触命中策略仍按既有产品合同处理。

**文件门禁：** 本轮只写 `external/B02_followup/` 七个报告文件；固定审计SHA始终 `ed2d87121de80c84caaa3f096c3a5acb71d4946f`。GitHub receipt核验属于文件接收，不授予产品/发布PASS。
