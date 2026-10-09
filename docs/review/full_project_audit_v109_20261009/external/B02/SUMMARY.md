# HardCore 109 — B02 人物、伤害、技能与动作时序审计（当前子批）

**固定审查源码**：`ed2d87121de80c84caaa3f096c3a5acb71d4946f`，仓库 `watermarkpp/HardCore`，分支 `codex/v108-runtime-bug-review-20261009`。本次只读，不访问施工中的本地 dirty 工作树；主控B01修复另行施工、未纳入本SHA。未修改生产/测试/配置/数据，未运行Godot、未构建109 APK、未作手机实测。

## 裁决

**B02_PARTIAL_SOURCE_REVIEW_WITH_FINDINGS，未达到B02全量深入审查完成标准，不授予109发布PASS。**

实际从固定提交读取清单三组**59个路径**，逐一取得完整Git blob及函数/结构索引；其中13个进行了B02核心路径语义核查，15个完成部分语义核查，余下31个只有源码/索引或引用检查，均在COVERAGE逐一标记，不将读取过当作完整审完。其他模块标NOT_RUN。跨模块消费路径见附录。

## 实际追通的主要链

1. 玩家输入/触控准入（GameRoot._try_ordinary_attack_intent、_try_release_skill）→ Player.request_attack/request_skill → 单一accepted action+epoch冻结 → 受击锁/冷却 → _emit_*_after_windup → GameRoot._on_player_attack/_on_player_skill。合法提交后不应由后续移动或视觉取消：源代码确有epoch和live owner门。
2. 技能单规划：SkillCastRequest → SkillRuntimeRouter.build_canonical_plan → SkillExecutionPlanContract.build_canonical_plan → GameRoot._commit_canonical_resources → _apply_canonical_effects_from_plan → CombatRuntimeService/Enemy或Player现有HP权威。DamageBatch捕获实际HP事实，EffectRuntime有原单owner的队列、reservation与world generation过滤，没有在本批发现第二个HP写入owner。
3. 一次性AOE沿冻结release snapshot和空间索引做exact命中；FireWallFieldController独占每跳查询/判定并与GroundSkillEffect共享claim表；视觉cell无伤害；投射物在每physics用swept-segment查询并命中。必要差异：飞行体可以通过实际位移避开，其余快照不能被后续视觉撤销。
4. PlayerState能力/生命/MP及装备聚合、Player命中/护盾/持续中毒双lane和正式死亡门；EffectRuntime的持续模拟时间由GameRoot physics delta推进，窗口pause不该消耗该simulation时钟。

## 已确认的源码控制流缺陷或重大风险

- **B02-001（P1，SOURCE_CONFIRMED_TIME_DOMAIN_BUG）**：Player两种动作windup定时器未设置pause-aware，菜单pause后计时器默认继续，待释放伤害可能发生在暂停菜单内。必须按真实GameRoot、确定命中、真实pause验证并只修时间所有者。
- **B02-002（P2，FIRST_CONTACT_ORDER_RISK）**：飞行物一次物理线段命中多个怪时，只按stable_combat_order选择第一个，不按物理最先接触；若游戏合同确认为“碰到谁先算谁”，需修改exact候选选择而非扩大查询。
- **B02-003（P2，MOVEMENT_EVENT_GAP）**：玩家零运动碰撞分离发生在position_before_move记录之前，纯恢复位移不会发movement_performed，可能漏即时halo。
- **B02-004（P2，EQUIPMENT_STEALTH_REARM）**：换装导致装备隐身标志变化时会直接清除破隐位；与“脱战才恢复装备隐身”专用边界有潜在冲突。

## 不能擅自认定BUG的合同

- **B02-005**：破隐发生在skill最终preflight之前，但Player.request_skill明确注释承接“提交尝试也破隐”的既有用户覆盖，是否改为仅成功才破隐须新产品判定。
- **B02-006**：Player.can_request_skill没有显式quote.valid判断，确实存在条件性漏洞，但当前33原生技能的道士材料已按用户规则免除，未找到合法非MP invalid的现网触发，因此不能报成已发生故障。
- **B02-007**：旧装备吸血按攻击原值，Feature吸血按真实HP损失；公式不一致是源码事实，选哪一种属于玩法/平衡权威，不得自动改。

## 最小后续闭合

优先核对B02-001暂停中受理动作的真实时间合同并做小范围原生对照；B02-002按首接触合同反转怪出生序测试；B02-003碰撞恢复只位移测试；B02-004换装与保持交战测试。**补完COVERAGE中所有INDEX_ONLY和PARTIAL的必要正式消费链后才能把B02写成深审完成。**不跑未经安排的测试。B01待修工作保持独立，不重审。

**交付**：FINDINGS.json / csv逐项包含触发、行为、链、位置、修复与必要验证；COVERAGE.json和SOURCE_BINDING.json逐路径给blob哈希及覆盖状态；REDUNDANCY与VALIDATION_GAPS记录未删候选/验证缺口。DEVICE TEST: NOT_RUN。
