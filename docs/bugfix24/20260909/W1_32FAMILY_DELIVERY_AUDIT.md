# W1 32-family actor/delivery audit（只读）

**审计边界**：2026-09-09；来源树 `C:\Users\Administrator\Documents\HardCore-worktrees\bugfix24-v3-close-20260909`，HEAD `f14f0b058092c5ee977048463fafc0c9fa3902a4`。本包未跑 Godot，未改源码、正式 data、cache 或 allowlist；仅新增本文件。原始服务端 A lane 由 `assets/data/source_priority_policy.json:359-365` 明确为 `source.original_gameofmir.server_suite` primary，不能用低级源替代。证据 SHA256：`monster_delivery_inventory.csv` `A31CE688846076F46E9DA937253852260B82B3C1496CF8F9CDB393BE2433EAFC`；`V3_R3_1_CLOSURE.md` `851A8308751D6D1439D7437D50D06A90B60AEE7AE601E3FDA5A47CF076466CAE`；`monster_behavior_profiles.json` `95D8F5E569D08A5EAC769C829BE9A642C0427F2D4A87ECBBAE44F7014B866C76`；`canonical_monster_catalog.json` `0A8E05B5A284534FDDFBF7C3CEC2C04A63F0E1EDBB60E35B46964247367855F6`；`monster_runtime_authority_v1.json` `FA536723DC76AFCF5EC07318BD42D509AB9390C4A4C2430D9A2581E33AC82A42`；`monster_movement_source_master_v1.json` `79D2EF2E67809F1B585293BFD506F547D74CFC530C065EFFBDFDBC5AE3D66AAD`；`monster_special_delivery_sources_v1.json` `8FC7DA44F3C804F6FF3BF2C0EC00769D8898D3507F89A39F0CD9189351CF0E6E`；`ObjAxeMon.pas` `9D42ABF6B34B7A74FBD2AD802B08629CC67E0864CABDA694E13764DE750F28C0`；`ObjMon.pas` `E32425C0C056CD83E0DD449F752813C613E829DA4EABC21C26CBAD45FFA59CE2`；`ObjMon2.pas` `983C098130D7A83B34F19746FC484609DCEF975344864C435526D254F98D0BCD`；`ObjBase.pas` `65D59610B8A1F7F4DCF76058A753651D1A97997AD273FC4DF8E468E65A989262`；`UsrEngn.pas` `E9E1735511CE0AEC8F90E52D38F504FD7430DF1AA490D6E82B29D62D7C6E84D3`。

## 结论与施工差异

CSV 共 153 个 runtime ID、32 个 `(actor_family,race)` 组；闭环文档 `V3_R3_1_CLOSURE.md:50-56` 的现状是仅显式填了 projectile `50/150/152/206`、special melee `70`、area magic `124`、fixed area `180/195`、target magic `220/222`。空 `delivery_kind` 不能自动解释为近战。

| actor/race（精确 ID） | 当前缺口 | 生产应接的最小规则（原始证据） |
|---|---|---|
| `TArcherMonster/104`：42,145,186（150,152,206 已填 projectile） | kind 缺失 | `physical_projectile`；`ObjAxeMon.pas:41-100,182-202` 的 `FlyAxeAttack`→`CanFly`、目标 `GetHitStruckDamage`、`RM_FLYAXE`。`max(cheb)*50+600` 是源端反馈/表现时序，不是 HP 扣除证据；`AttackTarget:72` 源码把 X 差写了两次（同样 `:91`），不要静默改成另一规则；Archer `m_nAttackMax=6` 是 burst 次数而非范围。工厂 `UsrEngn.pas:1908`。 |
| `TThornDarkMonster/93`：62,174 | kind 缺失 | 同一继承 `TDualAxeMonster.FlyAxeAttack` projectile；`ObjAxeMon.pas:19-25,41-100,184-188`，`m_nAttackMax=3` 只作为 burst/family 参数而非范围；不能当普通近战。 |
| `TSpitSpider/82`：18,103,104,185 | kind 缺失 | `area_attack` 的 **SpitMap 5×5 定向形状**（不是现有 broad fixed-area）；`ObjMon.pas:55-63,659-745` + `ObjBase.pas:18504-18530`：`TargetInSpitRange` ≤2、`SpitAttack` 每格 `GetMagStruckDamage`、毒状态、300ms presentation。需新增形状/毒字段；不要套 `target_magic` 或触龙神 `area_magic`。 |
| `TElfWarriorMonster/114`：146 | kind 缺失 | 继承 `TSpitSpider.AttackTarget/SpitAttack`，但 `ObjMon.pas:219-231,1707-1802` 构造时 `m_boUsePoison=False`，另有隐身/出现/换脸时序；接 `area_attack(spit_map)` 前必须保留该特殊激活与无毒差异。 |
| `TGasAttackMonster/90`：46,60；`TGasMothMonster/105`：128,168 | kind 缺失 | 相邻 `special_melee`（魔防伤害+毒石）或明确新 `gas_adjacent`；`ObjMon.pas:78-86,859-934` 的 `GetAttackDir→sub_4A9C78→GetMagStruckDamage/MakePosion(POISON_STONE)`。Moth 的 `ObjMon.pas:193-206,1567-1608` 继承该攻击，并有 `STATE_TRANSPARENT`/搜索变体；不能归 `target_magic`。工厂 race90/105/106 在 `UsrEngn.pas:1879,1909-1911`。 |
| `TLightingZombi/94`：79 | kind 缺失 | 定向 `area_attack`/独立 line-magic 形状；`ObjMon.pas:129-137,1118-1189` `LightingAttack` 发 `RM_LIGHTING`，`MagPassThroughMagic` 走 9 格线；`ObjBase.pas:2536-2567`。触发为目标轴向差 `<6`、冷却后施放，不能误用 cow `target_magic`。 |
| `TElectronicScolpionMon/200`：224（220/222 已填 target magic） | 同 family 漏 ID | `target_magic`，`ObjMon.pas:119-128,1805-1881`：目标绑定、`GetMagStruckDamage`、低于 50% HP 或 X/Y 轴恰为 2 才 `LightingAttack`；既有正式 profile `monster_behavior_profiles.json:165-210`。类随后仍走继承 `TMonster.Run` 的普通相邻攻击，不能做成 magic-only。 |
| `TCowKingMonster/92`：76,77,235,236,239 | kind 缺失 | `special_melee` 的 **mixed hit+magic target-tile**；`ObjMon.pas:101-118,1019-1116` `Attack:1039-1049`→`HitMagAttackTarget`；`ObjBase.pas:22631-22659` 对目标格对象同时 `GetHitStruckDamage+GetMagStruckDamage`。`Run:1063-1115` 另有 30s teleport、HP 阶段和攻速切换；不要当 `target_magic/area_magic`。 |
| `TCentipedeKingMonster/107`：226,227,234（124 已填 area magic） | **行为 HOLD；不接 area** | `server_race=107`/`TCentipedeKingMonster` 仅为 `CANDIDATE/B_CANDIDATE` exact binding；`ObjMon2.pas:35-45,442-582` 与 `UsrEngn.pas:1911` 是类候选证据，不能继承 area/毒/隐藏攻击。三项均受 HUMAN_FROZEN `treasure chest is a fixed non-combat entity` 约束，等待正式 exact-ID `combatEnabled=false` 门禁；保留可受伤/掉落。 |
| `TExplosionSpider/117`（不在本 153 条 CSV） | 现行 inventory 未纳入，不能伪造 ID 映射 | 若未来纳入，应是特殊激活：`ObjMon2.pas:67-76,727-814` `sub_4A65C4` 自杀、接触 ≤1 格，命中/魔法各半、700ms；Run 每 60s 也可爆。建议 `area_attack(contact)`+自爆字段，不能当 generic melee。工厂 `UsrEngn.pas:1917-1921`。 |
| `TArcherGuard/112`：194 | kind 缺失 | 仅视觉可归 `physical_projectile`，语义必须 guard-special/direct-target；`ObjMon2.pas:87-95,887-980` `sub_4A6B30` 直接 `GetHitStruckDamage/StruckDamage` 后发 `RM_FLYAXE`，无 `CanFly`、无目标延迟释放，view range 12。不要复用 `TDualAxeMonster` 的飞行门禁/释放记录。 |
| `TStickMonster/85`：30 | kind 缺失 | 相邻物理近战 + `special_activation.rooted_contact`；`ObjMon2.pas:7-22,153-297` `AttackTarget:174-198` 调用普通 `Attack`，但 fixed-hide、目标 `<4` ComeOut、超距 ComeDown。现有 profile 的 `cannibal_flower` 仅说明 rooted/stationary，不能丢接触规则。 |
| `TScultureMonster/101`：153,155-159；`TScultureKingMonster/102`：160 | kind 缺失 | 前者无 Attack override，醒石后走 generic 物理近战；`ObjMon.pas:170-179,1355-1442` 有 ≤2 唤醒全石与范围 7 传播。后者 `ObjMon.pas:180-192,1444-1566` `Attack:1502-1509` 用 `HitMagAttackTarget(0,nPower)`，故是 mixed `special_melee(target_tile)`，并保留醒石/低危险度召唤。 |
| `TBeeQueen/103`：126；`TSpiderHouse/116`：182 | kind 空是可接受的“无伤害 channel”，但需特殊规则 | `ObjMon2.pas:24-34,368-436` 与 `:56-65,646-725` 为 fixed-body summoner；`RM_ZEN_BEE` 延迟 500ms、上限 15，不应填攻击 kind。现有 `summonRule` 路由已记录。 |
| `TBigHeartMonster/115`：180,195 | 已有 fixed_area | `ObjMon2.pas:46-54,585-644` 全可见目标 ≤16、RM_DELAYMAGIC 200ms；保持既有 `areaAttack.fixed_area`，不扩散到其它 family。 |
| generic：`TATMonster/53,81,86,88,89`（97,100,24…240）、`TSlowATMonster/83`（19,21,28,34）、`TScorpion/84`(45)、`TCowMonster/97`(64,66,68,73-75)、`TMonster/TChickenDeer/52`(96)、`TDigOutZombi/95`(81,143)、`TZilKinZombi/96`(83,85,87,166)、`TWhiteSkeleton/100`(187) | kind 当前空；可按证据接普通近战，但不能抹掉激活 | `ObjMon.pas:383-413` `TMonster.AttackTarget` 相邻后调虚拟 `Attack`；`ObjBase.pas:2689-2692` `TAnimalObject.Attack→AttackDir`。DigOut/White 初始隐藏/出现（`ObjMon.pas:1191-1260,1315-1353`），ZilKin 有死亡重生（`:1263-1313`）；这些是 `special_activation`，不是新 projectile/area。 |

## W1 exact-ID binding level

`source_priority_policy.json:358-365` 将 `source.original_gameofmir.server_suite` 设为 server-rules primary。逐 ID `monster_runtime_authority_v1.json` 当前给出的等级应这样解释：

| exact IDs | targeting binding | primary/候选支持 | 施工边界 |
|---|---|---|---|
| 50, 42, 145, 186, 62, 174, 224 | `CANDIDATE / B_CANDIDATE`，source `UsrEngn.pas:1831-1938`；family rule `A_LOCKED` | `ObjAxeMon.pas`（50/42/145/186/62/174）或 `ObjMon.pas`（224）提供 primary class behavior；candidate route 仅连接 exact ID→class | 可按上表接入并做真实 Actor 回归，但必须保留 exact-ID 校验，不能用名称/variant 补 ID |
| 226, 227, 234 | `CANDIDATE / B_CANDIDATE`，race 107 / `TCentipedeKingMonster`；same primary factory/class source | `UsrEngn.pas:1911`、`ObjMon2.pas:442-582` 是候选类证据；movement 的 exact Monster.DB 行是在 routed server-data 缺失后由 M00R 审计接纳的 B 候选 | 仅 class candidate 可施工；human `HUMAN_FROZEN` fixed-noncombat 规则优先，必须由 exact-ID `combatEnabled=false` 禁自主攻击/投递/音效；不接 area/poison/burrow |
| 228–233 | `DATA_HOLD / UNKNOWN`，`server_race=null`、`pascal_class=null`、无 class source | 只有 movement compatibility 的 reused race107/`SOURCE_ROW_MISSING`；不得把 candidate Monster.DB 行当 actor primary | 仅逐 ID stationary/noncombat gate、受伤/掉落身份回归；class/delivery 保持 HOLD |
| 41, 59, 78, 123, 161, 190 | `DATA_HOLD / UNKNOWN`，无 exact actor source | movement master 的 base-row 提示同样是 `SOURCE_ROW_MISSING`；无 primary class/delivery | 不施工、不按 family 继承，保持 DATA_HOLD |

因此 `CANDIDATE` 不是“一律不可用”：有 exact primary factory/class 证据且候选路由被审计接纳的 10 个 ID 可继续施工；`DATA_HOLD` 的 12 个 ID 仍缺 exact actor evidence，不能用相似 race、名称或后缀越级放行。

## 未决 12 个 ID：必须保持 HOLD

`41,59,78,123,161,190,228-233` 在 inventory `:3-154` 为 `UNRESOLVED_ACTOR_AND_DELIVERY`。正式 authority 的记录起点分别为 `monster_runtime_authority_v1.json:3418,6112,8820,14894,22165,26511,32500,32743,32986,33229,33472,33715`；每条 `targeting` 都是 `server_race:null`、`pascal_class:null`、`class_binding_status:DATA_HOLD`、`class_binding_source:null`，并写明“no exact Monster.DB source row; reused base-row Race cannot authorize target acquisition”（例如 ID41 `:3517-3530`，ID228 `:32617-32630`）。movement master 只给兼容提示（例如 ID41 race81/`oma_warrior`、ID123 race81/`evil_centipede`、ID228-233 race107/`race_107`），且对应 `SOURCE_ROW_MISSING`（`monster_movement_source_master_v1.json:237-267,293-363,469-475,597-604,773-819`）；`vanilla_176/monsters.json` 只有 `baseName/variantCode`（ID41 `:545-549`、ID228-233 `:4737-4860`）。这些字段不能推出 actor class 或 delivery；228-233 另有逐 ID HUMAN_FROZEN stationary / `treasure chest is a fixed non-combat entity` 人为语义，但这只冻结移动并等待 exact-ID combatEnabled 门禁；不能因复用 race107 直接套 `TCentipedeKingMonster`。行为 profile 的 `profileByMonsterId` 只到现有明确 ID（`monster_behavior_profiles.json:213-245`），`legacyNameToProfile` `:247-278` 是兼容映射，不能用于 runtime 身份/规则推断。

## integration 交接

1. 以 exact `monster_id` 在 canonical builder/profile 增补，保留上表每个 family 的 activation、damage channel、范围、延迟和状态；不得把 blank kind 全部补成 melee，也不得把不同 `RM_*` 视觉当同一伤害语义。
2. 专项测试应覆盖：42/62 projectile 的 CanFly/延迟；18/146 spit 5×5 与毒差异；46/128 gas magic+毒石；79 line pass-through；224 target magic+继承近战；76/160 mixed target-tile；226–234 固定非战斗 Actor（无自主攻击/投递/音效，仍可受伤并保留掉落身份；不测 area/burrow/poison）；194 direct-hit guard；30 wake/contact；126/182 summon；generic hidden/revive。另断言 12 个未决 ID 仍无 actor/delivery，而不是用名称或 variantCode 放行。
3. 本文件只提供证据和施工边界；未声明 runtime 修复、测试 PASS 或 APK 可用。
