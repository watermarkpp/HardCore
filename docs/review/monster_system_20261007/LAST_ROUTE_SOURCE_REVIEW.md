# LAST_ROUTE_SOURCE_REVIEW

核验范围：当前 enemy.gd 新增 _hc_direct_source_route_clear() 及 _hc_neighbor() 的 active polygon route 直接恢复条件。只读审查；未运行 Godot，未修改 scripts 或 tests。

## 结论

当前修复符合“完整路径确认后才恢复直接追击”的边界，未发现生产门禁被绕过。

- enemy.gd:9884-9889 只有在 observed、current 到 anchor 的 WORLD 直线可见，并且 ordinary melee 已存在未完成 polygon route 时，才调用 _hc_direct_source_route_clear()。没有把一段短 prefix 的通过结果当作整条 route 的通过结果。
- enemy.gd:10104-10120 的 helper 以 SourceStepPlan.next_leg() 将 origin 到 destination 拆成完整的 canonical monotone 八方向腿；每一条非零腿都分别执行 HCPolyRuntime.segment_walkable、_hc_world_between、_hc_motion_clear 和终点 _hc_point_walkable。任一 terrain、WORLD、live body 或 endpoint 检查失败即返回 false。
- helper 只被用于决定下一步是否可以退休旧 polygon route；它不清除 committed movement，也不重置 attack、HP、碰撞或 cadence 状态。现有 _hc_step_override 仍由实际 movement admission 使用。
- _hc_motion_clear 的 live body 检查仍排除 self 和正式 hit target；当 surround goal 有效时，它另外检查目标身体 envelope，避免绕到目标身体内部。普通直接追击到目标时排除 hit target 是既有接触语义，不会把目标本身误判为路障。
- _hc_neighbor() 的已有 flank、route、C05 和 blocked-wait 分支仍保留。active route 未通过完整两腿检查时继续走稳定 route vertex；不会因为第一段 fractional prefix 清晰而清除 route。live body 阻挡仍进入 FRONTLINE_BLOCKED/flank 处理。
- active route 的直接恢复仍要求正式 polygon context；缺少 context、非法 projection、非有限点、零长度或任一 segment/endpoint 失败都会保守返回 false。目标移动、世界变化和 live body 变化会在当前决策重新读取。

## 负路径核对

- target body：surround destination 会经过 _hc_motion_clear 的目标 envelope 检查；普通接触路径将 hit target 作为合法终点，不把目标自身当作中途 blocker。
- C05：route 未完成时必须通过完整 canonical route check；清晰的第一小段不会触发 _hc_route.clear()。
- world wall：_hc_world_between 对每条完整腿单独检查；原先自然短墙的过度绕行场景因此只会在完整直接路径确实清晰时恢复。
- live peer：_hc_motion_clear 每次读取当前 candidate 的位置与 eligibility；未使用静态 prefix 结果替代正式 body 检查。
- committed segment：直接恢复判断发生在新 step 选择前；没有撤销已提交段。

## 结果

STATIC PASS：本轮 route-source diff 未见明确生产缺陷或断言放宽。主控正在执行的 native 专项属于独立证据，本审查未重复运行；DEVICE TEST: NOT_RUN。
