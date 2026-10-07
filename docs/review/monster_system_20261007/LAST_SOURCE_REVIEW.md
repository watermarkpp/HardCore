历史静态审查：其enemy hash早于本轮新增绕行修复；最新绕行差异审查见LAST_ROUTE_SOURCE_REVIEW，最终hash见PRODUCTION_FILE_HASHES。

# LAST_SOURCE_REVIEW

核验范围：当前工作树的最后一轮差异；只读审查，不运行 Godot，不修改 scripts 或 tests。核验对象为 scripts/enemy.gd 的 bodies → has_body 改动、surround_target_body_route_test.gd 的 slot 修正、monster_physical_projectile_attack_test.gd 的夹具同步修正，以及相关 production diff 的门禁/断言是否被削弱。

## 结论

- surround 的 slot 修正正确。scripts/monster_crowd_attack_position_policy.gd:4-8 的 DIRECTIONS 顺序中，(-1,-1) 是索引 6；tests/user_feedback_20260930/surround_target_body_route_test.gd:75 现在断言 slot 6，并同时保留了最近西北角目标和已提交外向移动段的断言。该改动是夹具期望值纠正，没有删除 HP、碰撞、目标身体或 committed movement 检查。
- monster_physical_projectile_attack_test.gd 的最后夹具改动保持正式路径：各独立攻击前等待真实 physics_frame；CanFly 跨图后用 set_combat_position 重建正式 combat position；失败时立即退出；清理等待真实 physics/process 帧。现有精确 actor ID、交付描述、伤害/HP、闪避、跨图取消、combat_epoch、墙碰撞及 CanFly 阻挡断言均仍在。没有看到降低负载、降低伤害、跳过正式 admission 或把失败转为通过的改动。主控报告的 9 ID 原生专项 PASS 属于该固定源码阶段的 native evidence；本审查没有重新运行，不能扩展为设备结论。
- enemy.gd:9797-9808 的新循环在 snapshot_peers 已排除 self、记录位置有限且 node 有效后，读取 live can_receive_damage/worldCollision，并在找到第一个合格体后 break。它没有把无效节点、死体、worldCollision=false 的节点算作 body；后续 choose_with_snapshot 仍执行正式 geometry、walkable、world_between 和 live eligibility 检查。就短路实现本身，没有发现绕过正式门禁的路径。

## bodies 门槛复核

该处没有产生门槛变化。旧 query_neighbor_enemy_nodes_into 会把 spatial index 中登记的 actor 自身也放入 peers；旧 bodies >= 2 等价于“自身 + 至少一个合格 other”。当前 monster_crowd_attack_position_policy.gd:22-33 的 snapshot_peers 明确排除 actor 自身，因此新 has_body 在找到第一个合格 other 后 break，等价于旧计数达到 2，只是避免继续扫描剩余 peers。当前 outer surround fixture 正是 self + one peer，且保留其余几何与移动断言。此项确认是行为保持的短路优化，不需要额外产品合同变更。

## 源码指纹与范围

当前 7 个 production 文件 SHA256 与 docs/review/monster_system_20261007/PRODUCTION_FILE_HASHES.json 一致；当前 enemy.gd SHA256 为 570d2b8a4fcec904fcc5b118d818bc8f14805ff0d69b90fa06c305b8e1380c25。相关最终文件仍包含现有受击、Boss clock、snapshot/live eligibility 和正式索引门禁；本轮未发现旧 direct_magic movement delay 执行路径被恢复，也未发现旧 draft API 被重新接入。

审查状态：STATIC PASS（门槛等价已复核）；未运行本轮 native；DEVICE TEST: NOT_RUN。
