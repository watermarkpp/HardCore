# R4 实际能力与行为覆盖

目录数量由当前正式目录及真实Enemy.setup提取，不用156作为永久合同。当前156项是一次实际结果；inventory PASS只证明清单可建立，不证明这些身份都实际攻击过。逐ID原始表在evidence/capability_inventory/r4_runtime_capabilities.json，所有行behavior_verification默认NOT_RUN，行为覆盖必须按下表独立引用。

| 实际delivery_kind | 当前数 | 本次直接行为证据 | 状态与限制 |
| --- | ---: | --- | --- |
| 空（需再区分普通、area、summon和禁战） | 125 | 24/238自然20起手、96边界相应组、横移/压力、身体组合 | 24/238 PASS；不宣称其他123项全测 |
| mixed_target_tile | 6 | 76/239自然20、边界、真实同格玩家+骷髅、完整流水 | 76/239 PASS；另4项NOT_RUN |
| line_magic | 1 | 79自然起手及实际600ms投递，正例、目标epoch、来源代际、目标释放 | PASS；未以任意缩pending加速 |
| special_melee | 1 | 70既有monster_special_delivery_runtime实际MAC/墙门禁 | PASS（相关回归）；非本次20次自然合同 |
| area_magic | 1 | 124同一既有runtime实际冻目标/0.6s延迟/严格边界 | PASS（相关回归）；本次source账全族归属NOT_RUN |
| directional_spit_map | 5 | 既有源码和正式规则清单 | NOT_RUN（本轮实际归属族） |
| gas_adjacent | 4 | 既有源码和正式规则清单 | NOT_RUN（本轮实际归属族） |
| guard_direct_projectile | 1 | 既有源码和正式规则清单 | NOT_RUN（本轮实际归属族） |
| physical_projectile | 9 | 既有源码和正式规则清单 | NOT_RUN（本轮实际归属族） |
| target_magic | 3 | 既有源码和正式规则清单 | NOT_RUN（本轮实际归属族） |

空delivery中实际area_attack为180/195，summon_rule为126/182；不能当普通近战证明。226–234九个ID实际combat_enabled=false，目录仍允许实体存在；它们的合法禁战动作门与伤害生命周期不得混作缺失起手。其他辅助runtime回归与最终critical待完成。

183/241的原始攻击间隔0已按原服务端加载规则处理，raw没有改。它们当前profile没有专属delivery、AI元数据仍是unresolved_project_fallback；183自爆语义和241具体用途没有实际行为证据，仍NOT_RUN。不得因为loading/MFC1通过就对这两种特殊用途标PASS，也不得按名字给241绑定火焰类。

召唤出生半径接口已完成RED→GREEN：GameRoot规划查询、SkillExecutionPlanContract释放快照和实际创建校验读取同一ActorBodyPolicy。旧15/21px半径已移除，运行时骷髅16px、神兽0.5GU保持。8项相关回归通过（evidence/summon_radius_chain）；性能中宠物真实参战负载仍NOT_RUN。
