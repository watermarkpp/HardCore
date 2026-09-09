# W1 跨系统伤害与状态消费

代码：原子混合伤害 `d6c59a0c`，来源毒状态与召唤物定身 `416ebeb4`。证据见 `evidence/v3_main_integration/cross_system_d6c59a0c_171247`。这是消费者专项通过，不代替新怪物家族完整接线验收。

## 混合伤害

`PlayerCharacter`、`SummonActor` 提供 `take_monster_mixed_damage(physical_raw, magic_raw, context)`。Enemy 是释放与目标合法性的唯一 owner；目标分别使用自身 AC/MAC 和现有增益，分量最低为0，相加后只调用一次已有 HP/护盾/受击/死亡流程。来源是 primary `ObjBase.pas:22414–22469,22631–22659` 的 `GetHitStruckDamage + GetMagStruckDamage → StruckDamage`。它们本身不额外进行准确/反魔法抽签；需要命中门的攻击由源端释放规则处理。

返回 `physical_damage/magic_damage` 是防御后、公共护盾前分量，`applied_damage` 才是一次实际 HP 减少，不虚构护盾后各通道分摊。公共法术护盾沿用项目既有整次伤害处理，而不是照搬 Pascal 每分量的护盾实现；护身戒指、耐久与死亡继续由当前玩家管线负责。纯技能和既有单通道 API 未改。

专项使用真实 Player/Summon、实际防御、护盾及死亡处理。验证分别防御、一次提交、护盾只消费一次、零伤害、不接受负输入、Loading隔离、致死后不重复提交或重复增加代次。

## 来源毒伤与定身

`apply_monster_poison(damage, seconds, interval_seconds)` 单独消费有来源的怪物毒，不改旧 `apply_poison` 的技能/物品语义。两个目标共同使用 `monster_source_poison_state.gd` 的时钟；没有第二个伤害 owner。刷新同一种来源毒不叠加多个计时器，暂停期间不推进，死亡后清理。

来源链：`ObjMon.pas:709` 的 `MakePosion(POISON_DECHEALTH,30,1)` → `ObjBase.pas:22730` 保存 greenPoint=1 → `ObjBase.pas:4255–4263` 使用配置周期并 `DamageHealth(point+1)`。`M2Share.pas:2073` 默认2500ms，可由 `PosionDecHealthTime` 配置覆盖；最终数据包负责记录配套配置核查，不把源码默认当所有发行版事实。测试明确以2.5秒输入验证30秒时钟；它不是在API里硬编码周期。

`ObjBase.pas:2451` 的 `DamageHealth` 绕过 AC/MAC 与法术护盾，但保留 MP 护身戒指。玩家新增来源毒类型因此只绕过现有公共管线的法术护盾步骤，仍由同一管线处理护身戒指与死亡，且不触发受击硬直/物理耐久。旧毒支路不受此条件影响。

召唤物新增 `apply_control(seconds)`，取消已排队攻击、在剩余时间内停止自主移动，同时继续处理生存时长/主人有效性。玩家沿用既有控制入口。Gas/Spit 的命中门、抗毒值归属与状态随机均在 Enemy 的 source descriptor 中处理，不放进目标消费者猜测。

专项覆盖实际HP、间隔边界/到期、无AC和法术护盾减伤、MP护身戒指、切图隔离、死亡、召唤物清空pending与停止移动。现有 ObjectDB 退出告警完整保留；不把 runner 的允许后错误计数写成原始日志零错误。
