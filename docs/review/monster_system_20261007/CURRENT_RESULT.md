# v105 怪物系统修复候选

2026-10-07，codex/integration，施工基线 aa75c5bc9845b49ee3ce67ce064442cc3fb3c43c。

用户最新裁决：停止重复群怪性能采集，以用户在原测试手机的实际游玩体感作为流畅度验收。已有性能序列保留，不能据此宣布掉帧修复。必要功能回归继续，不能降低怪物数、HP、碰撞或伤害工作量制造通过。

已实施直接魔法正伤害只延后下一攻击，移除移动延迟；保留已提交攻击及原 RNG 连续性。祖玛阶段召唤由正式行动循环按有目标8秒/无目标1秒检查，4–7只/次、15只上限；Boss 基础攻击间隔读取21CQ，显式狂暴保留。群怪取消长期站位认领、轴角互等，使用一次邻居快照选最近可达空位、局部让路，移动仍检查真实身体和地形。空间索引全部候选一次稳定排序；存在有效邻居判定找到首个即结束。

已通过的专项不等于整个架构升级或设备验收。最新相同源码阶段18项功能回归PASS，原生退出0、无引擎错误；APK BUILD NOT_RUN，DEVICE TEST NOT_RUN。最终 receipt 已写入本文件及FINAL_FUNCTIONAL_RECEIPTS.json。

## 保留的问题与覆盖边界

- 旧 monster_summon_hard_cap 夹具没有正式 producer/lease，B01 FAIL 保留；真实祖玛 main/queue 回归另列。不能宣称所有非Boss召唤上限已通过。
- ID169 没有正式运行绑定，正控制分支 MISSING。
- ID193 吸血的正式当前结算按AC前伤害比例；缺少外部权威明确其应按AC前还是AC后，MISSING，不擅自改变数值。
- 所有特殊行为已按配置与正式消费者普查，部分家族仍缺逐ID生命周期/地图/控制组合验收；详见 SPECIAL_CURRENT_ACCEPTANCE_REVIEW。
- v105现场祖玛快速掉血因果尚未在原手机绑定完整状态。MC40/47固定夹具确认每秒一次同施法者火墙claim，分别36/44HP，不能外推所有装备或用户实际角色。

## 原失败证据

final_boss_special / projectile62_diagnostic / projectile_native_tick_corrected / projectile_first_failure_bound 均保留。物理投射测试同物理帧启动多次独立身体动作导致首个拒绝与后续旧碰撞体污染；真实物理帧同步和正式位置写入修正后九ID通过。
final_crowd_spatial 保留退休站位所有权的旧断言失败，final_core_sealed 保留新夹具将西北坐标误写slot5的失败。实际 DIRECTIONS 西北是slot6，独立只读几何审查和三项原生回归确认修正；未改碰撞或已提交移动。

## 封装前自动入战与障碍检查

新增真实engine physics检查：setup仅提供可搜索primary_target，正式target由生产扫描获取，不写target、cadence、clock或attack timer。三场景独立30秒runner窗口；每case720实际物理帧上限，未放宽任何既有测试期限。

首次开阔测试把玩家放7GU外，ID64正式发现范围5GU，所以未发现属夹具条件错误；改为4GU时自然发现并移动。短墙初稿在首次foreground观察前插入遮挡导致缺少known_position；改为等待正式已知位置后再发布墙体。上述失败日志保留，不改变正式发现规则。

随后短墙实际FAIL定位到过度绕行：正式polygon路径经(11.20001,12.30005)大面中心，怪物已恢复视线仍强制完成远处路线。修复只在已观察目标、有活动polygon路线时检查完整canonical两腿；两腿均通过真实footprint terrain、WORLD、live body、endpoint后恢复直接接近。不是仅以一单位前缀清晰撤销完整路线，不撤销已提交移动。静态审查见LAST_ROUTE_SOURCE_REVIEW。

natural_route_shortcut_regression/191112_485033：8 PASS/0 FAIL/0 engine errors，原生退出0，source稳定；内容指纹15b63efb24a518f6d008355f14479b802a16fe98989ecc8af4c1b357f3a58666。涵盖自动发现移动、真实短墙绕行实际HP、真实窄道通行实际HP、C05 detour、完整八方向腿与窄道、目标身体绕行及已提交侧路。短墙最终(7,9)、实际HP损失25，不使用规划路线存在作为通过。

## 综合及超时证据

final_functional_candidate/185523_205916：46 PASS/1 FAIL，source0257fe46...，D3持续压力60秒原生超时，无完整receipt；其余46场景原生通过。不能把此综合场景记录为全绿。
natural_entry_obstacle_and_d3_diagnostic/190524_531482：D3保持同生产源码、负载、所有伤害/入战/暂停断言和60秒期限，仅增加阶段日志，原生PASS；末阶段在45.295秒结束、随后完成暂停及late draw。首次超时原因未有充分证据，保持MISSING，不将复测解释为性能提升。此阶段另外2个新自然夹具FAIL保留，后续上文关闭。

最终生产文件hash按PRODUCTION_FILE_HASHES记录。较早特殊行为回归与最新路径修复证据分阶段，不能混为一个源码阶段的全量通过。祖玛main实际召唤、30怪持续包围及墙边包围最终复验已按同一源码阶段通过（详见后续receipt）。

已有性能记录停止新增，未进行手机FPS对照采集。最新用户追加的封装前自动入战、障碍绕行要求已纳入自然engine三场景；绕行生产修复不能归为夹具修正。

final_summon_surround_behavior/191252_852810：3 PASS/0 FAIL/0 engine errors，原生退出0，source稳定，内容指纹同15b63efb...。真实祖玛main queue 4waves/15births/有目标至少8秒阶段间隔/地图退场清理；30怪完整2700物理帧包围开阔8个可用点、真实西侧WORLD墙5个可用点，实际玩家HP降低。保持数量、伤害、碰撞与原期限。

final_related_combat_after_route/191634_030270：7 PASS/0 FAIL/0 engine errors，原生退出0，source稳定，同15b63efb...；连续受击真实移动、持续移动/压力/暂停、Boss行动、MC47火墙、索引候选顺序、简化包围、九ID真实物理投射。最终相同源码阶段合计18场景PASS，完整receipts见FINAL_FUNCTIONAL_RECEIPTS.json。先前不同阶段的46/47、超时及夹具失败原记录不改。
