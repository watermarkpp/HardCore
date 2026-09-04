# 来源证据矩阵

| 信息 | 首选来源 | 状态 | 施工规则 |
|---|---|---|---|
| 33个技能成员 | CN 1.76技能页 | historical_verified | 固定6/14/13 |
| 学习等级 | CN 1.76技能页 | historical_verified | 不接受异版本候选覆盖 |
| 熟练度门槛 | CN 1.76技能页 | historical_verified | 每段升级门槛，升级后归零 |
| 熟练度每次增长 | lzxsz/MIR2源码 | source_formula_reference | 成功事件1–3 |
| MP数组 | 当前项目+内嵌服务端候选 | project_canonical | 保留当前四档，注明非官方证明 |
| 人物施法6帧×100ms | Mir2/Crystal帧结构 | source_formula_reference | Vanilla 600ms |
| 火墙范围 | CN页2×2 vs源码十字 | project_canonical | 选择CN 2×2 |
| 诱惑精确概率 | Pascal源码明确标注2020年提高成功率，旧门槛留在注释中 | project_canonical | 采用旧注释重建分支；不得宣称为盛大官方原概率 |
| 魔法盾减伤四档 | 历史资料冲突 | project_canonical | 15/30/45/60% |
| 双盾精确点数/时长 | 资料不足 | project_canonical | 本包公式 |
| 红毒耐久压力 | CN文字确认、精确算法不足 | project_canonical | 每次有效受击额外耐久1 |
| 召唤神兽5护身符 | 开源服务器源码 | source_formula_reference | 新召唤5张，召回不耗 |
| 神圣战甲术属性 | CN页疑似笔误+服务端type分支 | source_formula_reference | 只加AC |
| 幽灵盾属性 | CN页+服务端type分支 | historical_verified | 只加MAC |

## 关键原则

不能找到盛大原始Magic.DB，不等于可以用另一版本的数据库冒充。
本包通过“证据身份+项目冻结值”解决可施工性，而不是隐瞒不确定性。

| GetPower13舍入 | `Magic.pas`源码 | source_formula_reference | 1/3固定部分、2/3缩放部分、DefPower和随机项相加后只ROUND一次 |
