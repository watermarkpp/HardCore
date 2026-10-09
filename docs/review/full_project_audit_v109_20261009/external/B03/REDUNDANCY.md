# B03 — 冗余与退役候选（只登记，不删除）

固定源码：`4e77c619249450b7c33e833c2bb3531f3f120bfc`。删除需证明Godot场景tscn、autoload、preload、反射Callable和fixture均不依赖，而不只grep直接调用。

1. **Grid试验已退出固定树**：`scripts/monster_ai_package/grid_crowd_trial.gd`与`grid_occupancy_service.gd`是B03清单中的退役遗留条目，固定提交GitHub NOT_FOUND，不能恢复、不能算精审文件；项目人物/怪物移动是continuous GU和真实physics。
2. **`scripts/enemy.gd::_return_to_spawn`**：目前只检索到函数定义，未检索到现行`Enemy.gd`静态调用。可视为孤立兼容候选，**不得仅凭grep删除**；进一步需要固定场景/Callable/fixture上下文与主控确认“禁止主动回出生点”。确认其非正式行为不等于实际调用成功。
3. **`MonsterGroundAlignmentDraft`、`MonsterGroundRuntimeDiagnosticOverlay`**：一个是authoring lab草稿（写源仅在编辑器/验收路径），一个是Android debug+显式CLI才启用的坐标探针；不是第二套移动/碰撞系统，不得视为可无条件删除。
4. **`MonsterSource176SkillReactionRegistry`**：表中33项是角色技能伤害消息家族，不能因怪物另有attackDelivery就说两张表重复。
5. **`MonsterAttackSourceOverlay`、`MonsterTargetMagicEffect`、`MonsterGroundSpikeEffect`**：视觉只读消费者，不与Enemy正式HP结算重复。若ID194源修复，必须保留观测箭动画但不重新通过视觉做第二次伤害。
6. **`MonsterNaturalRegenPolicy`与`MonsterSourcePoisonState`**：前者6秒恢复，后者来源毒单独tick，不是双HP或双状态写入；Enemy仍唯一HP owner。
7. **`MonsterCrownAttackPositionPolicy`**（正式名称`monster_crowd_attack_position_policy.gd`）：临时Peer快照只在一次同步邻居决策生效；跨帧负结果缓存已归档失败，不允许把相似接口误判“相同冗余优化”。
8. **`HCDecisionBudget`新process追击与旧physics观察入口**不是可直接删除的两份预算。B03-003应先证明真正调用比例和预算口径冲突，再收敛为一个唯一会计，不可直接删掉necessary战斗提交。
9. **`HCM30ContextToken`、`HCPathSearch`共享goal field**是bounded源上下文缓存；缓存失效按token/地图/修订，不以其引用名相似判重复。

**没有可证明“删除即更快50%”的同工作量证据。本批不建议执行任何冗余删除。**
