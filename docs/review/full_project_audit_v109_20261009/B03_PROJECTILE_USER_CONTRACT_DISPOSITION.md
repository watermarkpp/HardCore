# B03-001 projectile user contract disposition

审计范围：fixed `4e77c619249450b7c33e833c2bb3531f3f120bfc`，当前 published source `878775` 所对应的本地工作树。只读核对 ID194「恶魔弓箭手」的 formal identity、source-priority 路由、delivery profile 和 runtime consumer；未修改生产/测试文件，未运行 native。

## 当前 authoritative identity

ID194 在 `assets/data/monster_behavior_profiles.json:1218-1289,1376` 绑定 profile `w1_guard_archer_194`；`assets/data/monster_runtime_authority_v1.json:27445-27690` 将其登记为 `runtime_allowed=true`、`behavior_profile_id=w1_guard_archer_194`，delivery kind 为 `guard_direct_projectile`。该 profile 的关键合同是：

- `damageChannel=physical_defense`
- `rangeShape=manhattan_diamond`
- `viewRangeGu=12.0`
- `bodyOnly=true`
- `damageTiming=immediate` 指的是命中结算通道的 damage timing，不是发射时锁定目标并立即扣 HP
- presentation 为 projectile observer，flight presentation delay 按 source/target ground distance 计算

`assets/data/canonical_monster_combat_source_v1.json:3650-3671` 的 ID194 只提供基础属性和旧 `ai_code=112`，没有覆盖 special-delivery contract。`assets/data/service_monster_runtime_catalog.json` 中的 `viewRange=7` 属于 service attribute record，不能覆盖 server-rules special-delivery profile 的 `viewRangeGu=12.0`。`assets/data/source_priority_policy.json` 的 lane 规则将 monster AI / combat / special delivery 路由到 server-rules；因此本次判定使用 runtime authority/profile 与其 primary `ObjMon2.pas` evidence，不用属性 catalog 的距离字段重写 delivery。

相关 source SHA256：

| 文件 | SHA256 |
|---|---|
| `assets/data/monster_runtime_authority_v1.json` | `CFCBE9998634EC98839477D815EFE6E0A9598F1457F82900DC957D7FC68BF071` |
| `assets/data/monster_behavior_profiles.json` | `8CCCD9C0E88D5440E774164CA17C8D7E3DA4AB2A304A9ACE99D15B9EFE1C0818` |
| `assets/data/canonical_monster_combat_source_v1.json` | `81D52DB743FD6D18DE09A18F98D9375DE65990A9A2DBE700375FE758523DD07D` |
| `assets/data/source_priority_policy.json` | `58ADF6E75EEA5549C4A535098E568505408EFA621901A1DADB868798739AC3C7` |
| `scripts/enemy.gd` | `4EB42E585F30C3401366184CD240771ACD9BC25A066BCEC9AE859E38A71DDF2A` |
| `scripts/monster_ranged_projectile_effect.gd` | `9F73FD20DF9A8DF05CA9807EDC0BA04D942CACE52517AAA571616306D0221548` |
| `scripts/game_root.gd` | `2EA2DC8E90239E8C1DB9260CABBB57A7991EC14B82999C89B2035661E90E5C93` |

## Runtime wiring

当前 Enemy 代码已把 ID194 的 delivery 从 attack admission 接到真实 projectile contact：

1. `scripts/enemy.gd:1472` 从 behavior profile 读取 `attackDelivery`。
2. `scripts/enemy.gd:3404-3408` 在真实 attack admission 后，对 `guard_direct_projectile` 走 `_queue_guard_projectile`，不走普通 melee immediate hit。
3. `scripts/enemy.gd:5585-5592` 把 release frame、target combat epoch、map identity 与 parent release 冻结为 windup record；`scripts/enemy.gd:4599-4609` 在 windup 到期后调用 `_launch_monster_special_cell_delivery`，仍需重新验证 target epoch/map/liveness。
4. `scripts/enemy.gd:4829-4901` 建立当前 source/target footprint、victim record 和 release record。对 `guard_direct_projectile` 只发 descriptor，不调用 `_settle_monster_special_cell_release`；注释明确说 first contact 由 projectile node 拥有，避免第二次即时扣血。
5. `scripts/enemy.gd:5478-5528` 将 `release_record` 转成不可变 projectile descriptor，并通过 `MonsterRangedProjectileEffectScript.create_visual` 创建实际飞行节点。
6. `scripts/monster_ranged_projectile_effect.gd:196-216,270-285` 在飞行期间检查碰撞/目标 instance identity；命中时回调 `_on_guard_projectile_contact`，错过时回调 `_on_guard_projectile_miss`。
7. `scripts/enemy.gd:5705-5739` 在 contact 回调重新验证 target instance、life/map/combat epoch，再调用 `_settle_monster_special_victim`；miss 不产生 damage settlement。

这条链与用户最新合同一致：真正飞行中的 projectile 有 flight interval，玩家可通过移动避开；命中结算在 contact，不因旧 record 的 `damageTiming="immediate"` 把 HP 提前到发射点。相反，Lightning、AOE、beam 等不是该 delivery kind：它们沿各自 release/area/line consumer 在 release snapshot 上结算，不能套用 projectile dodge 语义。

## 与历史“immediate”记录的关系

历史 source evidence 将 `TArcherGuard` 描述为在 `ObjMon2.pas:904-921` 通过 `GetHitStruckDamage` 立即得到 physical damage，同时发出 `RM_FLYAXE` presentation。该记录解释了 `damageChannel` 与旧 server timing，但不能凌驾当前用户明确选择的交互合同，也不能单独证明当前 runtime 应在 projectile creation 时扣 HP。

当前实现已经把这两个事实拆开：攻击 admission/roll 发生在 action commit，projectile flight 负责 first contact，contact callback 负责最终 HP delivery。恢复旧式发射即扣血会直接绕过玩家躲避合同，并造成 projectile contact 的重复伤害风险。因此 **不应仅依据历史 immediate metadata 恢复即时 damage**。

## 判定与缺口

| 项目 | 状态 | 判定 |
|---|---|---|
| ID194 formal identity → `w1_guard_archer_194` | PASS | runtime authority、behavior profile、stable ID 显式绑定。 |
| ID194 delivery → `guard_direct_projectile` | PASS | runtime authority/profile 与 Enemy dispatch、projectile descriptor 一致。 |
| 发射后玩家移动可避开 | PASS（静态 wiring） | first contact 在 projectile node，miss 不 settlement；尚无本轮新 runtime receipt。 |
| Lightning/AOE/beam 是否错误套 projectile dodge | PASS（静态分流） | 各 delivery kind 有独立 release consumer；本报告未扩大其语义。 |
| historical immediate damage 是否要求恢复 | NOT_REQUIRED | 与用户最新合同冲突，不作为修复依据。 |
| 本轮 native/runtime 验证 | NOT_RUN | 按任务要求未执行。 |

最小必要后续验证应使用 ID194 的真实 GameRoot/Enemy/Player 链：固定已发射 projectile、在 contact 前移动玩家并记录 HP 不变，再保留原位置验证 contact 恰好一次；另外用 Lightning 与一个 release-settled AOE 做负对照，证明它们仍按 release 结算。测试不得把 projectile 直接改成 melee hit，也不得以 visual delay 代替实际 projectile node/contact 证据。

## B03-004 关联澄清

前一份 B03 disposition 已确认 `HCM30SummonQueue.enqueue()` 的 `MAX_PENDING_BATCHES` 拒绝发生在 job/reservation 创建之前，因此 capacity 满时不存在“已接受 job 丢失”。本次用户合同没有要求自动 retry；该 rejection 可保持现状，后续 release serial 是否在下一轮重新尝试属于明确产品合同之外，不应借 B03-001 扩大修改范围。
