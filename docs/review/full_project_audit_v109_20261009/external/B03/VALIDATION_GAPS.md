# B03 — 验证缺口与追溯门禁

审计固定源码 `4e77c619249450b7c33e833c2bb3531f3f120bfc`，只读；**Godot原生NOT_RUN / 安卓NOT_RUN / 新APK NOT_RUN**。

## 已有静态证明，不要篡改含义
- GameRoot被动激活已改为necessary事件批次，合格冷怪立即取得target，静态WORLD/terrain LOS不让怪物身体挡信号；正伤害独立wake；不能倒退为8候选/300ms激活。
- 300ms为可延期追击重规划，已提交的攻击、真实移动/碰撞、伤害/死亡继续每physics。
- 怪物source176行为与新HarCore平衡需区分：保留原来源文件tier、C级候选映射，不能据source comment把无验证技能变成正式。
- 156合法runtime ID，64项非标准/Boss/固定宝箱逐ID已记录；**这仅是来源和正式调用链映射，不是逐ID native PASS**。
- ID71 `retired_source_only`保留出处不注册，不再重新做grid试验。

## 最小定向专项建议（本轮仅列，不执行）
1. **B03-001 ID194警卫箭时序**：两条控制臂固定目标ID/生命/地图/攻击输入，一次合法出手后移动避开视觉箭与不移动对照；检查原资料`damageTiming:immediate`是否要求HP once、视觉箭不造成第二次；原具有真实飞行时间的monster physical arrow保留可闪避，静态WORLD阻挡仍按正式规则。
2. **B03-002召唤物远距靠墙跟随**：在已发布地图的墙边站人，召唤物相距超阈值，计算owner facing side offset落在wall时观察碰撞层、最终坐标、owner/zone、路径；不可通过直接取消其真实物理碰撞来“通过”。
3. **B03-003多physics补步CPU预算**：同一个process epoch发生两次以上真实physics，统计`HCDecisionBudget.begin` legacy necessary vs optional process turns，p95/p99/max每process CPU、真实等待、starts/settles/HP、queue age；确认实际old入口频率后再决定是否改。
4. **B03-004满队列召唤**：将M30请求池置于256边界和0可用slot，收到相同life/serial的合法重复事件后空出容量；要求主控选择“超额应永久拒绝”还是“已经承诺则可重试”，保持最多1child/physics，不增加预算/TTL。
5. **非本轮单ID泛化**：ID76/124/160/180/182/195/194/220/222/224的专项先作为十类 representative，随后对`SPECIAL_BEHAVIOR_COVERAGE.json`64记录的特殊变体/直接HP投放/自爆/毒/临时定身/保留source-only等提供最小完整 coverage matrix。不同ID共用同一模板可复用等价专项，不要求每ID重新跑全回归，但实质不同技能一定不可只看祖玛。
6. **残余视觉/资源**：MonsterVisualStreamingCoordinator属B01已修，B03只审动作消费接口；魔法视觉失效由B02主控另行确认；B05后续负责全部GPU及素材、Android实测。
7. **世界持久化/复活**：B04/B06后续核GameRoot死亡成功回执、拾取/掉落、地图转移与MonsterRespawnPolicy正式slot；本批不改掉落、保护、槽位和概率。

## 静态范围与未覆盖
- Manifest: 47路径，45存在并以固定Git SHA读取，2退役grid路径MISSING。
- 8个大型多职能代码文件只闭合本批入口函数与关键消费者；其他职责明确留B04/B05/B06/B07，不能用source fetched替代跨模块全线。
- `B03_SPECIAL_BOSS_COVERAGE`完整表见`SPECIAL_BEHAVIOR_COVERAGE.json`：每ID具体参数和源码证据不同强度，不是实际帧运行。
- 所有用户审批过的独立行为规则不作产品重新设计；原始日志/旧负面实验不删除。
