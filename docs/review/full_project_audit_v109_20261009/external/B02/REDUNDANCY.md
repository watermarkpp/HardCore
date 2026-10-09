# B02 冗余候选复核 — 未删除任何代码

1. `scripts/skills/skill_runtime_router.gd::_plan` 与 `build_canonical_plan` **不是两个并行Planner**：后者调用前者产生纯域计划，再由 `SkillExecutionPlanContract.build_canonical_plan`封装快照。删除前者会破坏现有正式路径。状态：NOT_REDUNDANT。
2. `scripts/skills/legacy_skill_adapter.gd` 是历史/兼容API。正式GameRoot使用新router并不证明旧方法无其它load/preload/reflection或fixture入口。本轮只得到结构索引，未逐一定位动态依赖，**不建议删除**，候选身份：COMPATIBILITY_RISK、NOT_PROVEN_UNUSED。
3. `GameRoot._spawn_projectile` 与 `CasterSkillRuntime.create_projectile` 可能分别承担兼容直接发射和正式计划描述符；缺少反射/fixture全量调用证据，NOT_PROVEN_REDUNDANT。
4. `GroundSkillEffect` 的legacy damage tick与正式 `FireWallFieldController` 是不同的现存消费者；FireWall正式路径视觉cell不负责HP，但其它持续地面效果仍可能使用GroundSkillEffect。不能仅因FireWall不使用而删除它。
5. `PlayerVisual` 的显示计时与 `Player` 的动作/HP时钟是presentation读取与playback，**不等于第二套HP或技能planner**。
6. 真正重复工作（如同一步验证的geometry query）本轮缺乏同源精确CPU/Android证据，判MISSING，不给性能删减建议。
