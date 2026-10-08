# 107群怪实践与Pro协作记录（2026-10-09）

当前性能目标：FAIL。没有候选接入主树，没有新APK，DEVICE TEST: NOT_RUN。研究仍在继续。

固定107 edae6fdef6a6551a951fab1ea8c6ade43359d603，同蜈蚣洞913203、34正式怪（30参战/4背景）、48掉落、同身份顺序/布局/输入政策/seed20261008、300真实physics tick。107保全两轮CPU中位2057.2785ms，目标≤1028.63925ms。CPU不是手机FPS。

| 实践 | 总CPU中位 ms | 相对107下降 | 结论 |
|---|---:|---:|---|
| local_pool | 2096.7840 | -1.92% | FAIL：未证明有意义的整体收益 |
| projection_guard | 2036.1410 | 1.03% | FAIL：未证明有意义的整体收益 |
| typed_root | 2024.2715 | 1.60% | FAIL：未证明有意义的整体收益 |
| pro_p1_minimal | 2050.9840 | 0.31% | FAIL：未证明有意义的整体收益 |
| pro_p2_prune | 2048.6100 | 0.42% | FAIL：未证明有意义的整体收益 |

P1仅一轮探索，未作为稳定收益；其它每项两轮也不足以证明1%左右的波动有因果意义。原生专项PASS仅覆盖相关安全边界。P2一轮末尾decision_budget_not_drained FAIL（1个合法待处理请求、最大等待2帧、无开放scope）完整保全，不改断言、不丢失败。

Pro本轮原文已实际读取并保全为PRO_RESPONSE_20261009.md。建议P1真实移动终点局部复用、P2评分下界剪枝、P3同池实时数值读取复用、P4观察scope复用；不能按physics frame无条件冻结状态。主控已分别验证P1/P2。Pro第二轮实际结果已读取并保全PRO_RESPONSE_ROUND2_20261009.md：仅普通近战同步读片段显式传值，原生移动、回退、攻击回调、地图/生命/目标变化切断旧值；公共getter保持实时；不承诺50%。原生移动既有计时漏前置恢复且含索引同步，继续定位。

20段高频细分插桩诊断：分类122942、自身投影guard114983、环境revision133098、ground入口73364、真正转换约16058。插桩让总CPU约增96%，只用于调用次数和定位，绝对时间不能作为正式收益。

P2真实几何对照使用同一actor identity、同一批活体blocker、同地形和target，比较最终邻居/step override/flank waypoint/anchor。主控静态复核先修正夹具里移除blocker和不同instance parity问题，再执行stock RED→生产剪枝 GREEN。有限数下界才剪枝，原顺序和严格同分保留，far first-legal及rear relief未动。

GameRoot typed成功路径只是去掉GameRoot结果字典包装，不是给已有Enemy Vector2路径再加缓存。所有formal resolver/runtime identity仍实时校验；同帧runtime replacement、未知地图失败、显式unmapped往返与实际67地图覆盖专项PASS，但总CPU只约1.6%波动，未晋升。

研究源每项独立从stock起步；失败候选完整归档后撤出，主树后107 Loading/掉落/首次攻击/受击修复始终保全。最终优化必须在最新主树再做行为时序和同负载配对。

证据入口：outputs/crowd_v107_practice_20261008/PRACTICE_VERIFICATION.json（相关输入/源码指纹、原始结果和各阶段runner receipt），同目录每次*_01/UUID等保留stdout/stderr/godot/native_result完整链。研究推送341854c仅为审阅，不是最新发布版本。
