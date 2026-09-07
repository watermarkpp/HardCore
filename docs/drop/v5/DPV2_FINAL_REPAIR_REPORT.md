# DPV2 V5 远端审查候选报告

**本报告不是全量完成证书；没有执行的验收一律保持 NOT_RUN。**

- BASE_SHA: `ffcdc76b360d5976eef2ce17a45664ddaf550590`
- CODE_SHA: `NOT_RECORDED_YET`
- REPORT_PARENT_SHA: `ffcdc76b360d5976eef2ce17a45664ddaf550590`
- FINAL_SHA / REMOTE_HEAD_SHA: 以 PUSH_REVIEW.ps1 提交后打印并核对的 SHA 为准，避免文档自引用。

## 执行结果

| 项目 | 状态 |
|---|---|
| python_build | PASS |
| godot_v5 | PASS |
| critical | FAIL_OR_TIMEOUT |
| apk_build | NOT_RUN |
| device_test | NOT_RUN |
| world_item_node_creation_performance | NOT_RUN |
| actual_duplicate_death_award_test | NOT_RUN |
| actor_death_map_spawn_trace_context | NOT_CONNECTED |

## 来源与平衡

来源覆盖：{"UNVERIFIED": 143, "EXPLICIT_NON_LOOT": 9, "PROJECT_EXTENSION": 1}
覆盖身份数量：153
本次通过网页证据生成的修正候选数量：0
优先级审计物品数量：233
优先级修改物品数量：26
技能书启用身份：[]
K 状态：BLOCKED_SOURCE_UNVERIFIED
K：1
沃玛最终无装备率 before/after：0.5058004784734509 / 0.5058004784734509
新衣服最坏情况保留证明：`balance.json#armor_retention_proof`；已生成 6 条。
离线模拟身份数量：18
离线模拟失败项：[]

## 明确未关闭的后续工作

1. 网页解析失败、来源冲突、物品或重复槽数量差异：以下精确清单；Flash 不补写解析器、不猜分母、不改 6809 等冻结数量。
2. 真实 actor 的 death_event_id/map_id/spawn_id 接线没有在本包中完成。新增调试日志只称 roll event，不冒充死亡事件。
3. 10/20/50 次实际掉落服务调用的耗时不等于真实地面节点创建耗时、峰值帧时间或引怪 AOE 实机验收。
4. 真实重复死亡发奖、拾取闭环与 Android 设备验证没有自动取得 PASS；必须有独立实测证据才能关闭。
5. 现有 Critical 若因冻结测试夹具或其他原因失败，保持失败，不允许 Flash 删除、放宽或改写断言。

## 精确阻碍清单

```json
[
  {
    "monster_id": 141,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:邪恶毒蛇"
  },
  {
    "monster_id": 18,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:毒蜘蛛"
  },
  {
    "monster_id": 19,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:蛤蟆"
  },
  {
    "monster_id": 21,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:稻草人"
  },
  {
    "monster_id": 24,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:多钩猫"
  },
  {
    "monster_id": 26,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:钉耙猫"
  },
  {
    "monster_id": 28,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:森林雪人"
  },
  {
    "monster_id": 30,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:食人花"
  },
  {
    "monster_id": 31,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:多钩猫王"
  },
  {
    "monster_id": 32,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:钉耙猫王"
  },
  {
    "monster_id": 34,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:半兽人"
  },
  {
    "monster_id": 36,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:半兽战士"
  },
  {
    "monster_id": 38,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:半兽勇士"
  },
  {
    "monster_id": 39,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:半兽勇士1"
  },
  {
    "monster_id": 41,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:半兽勇士9"
  },
  {
    "monster_id": 42,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:半兽统领"
  },
  {
    "monster_id": 43,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:山洞蝙蝠"
  },
  {
    "monster_id": 45,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:蝎子"
  },
  {
    "monster_id": 46,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:洞蛆"
  },
  {
    "monster_id": 47,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:骷髅"
  },
  {
    "monster_id": 50,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:掷斧骷髅"
  },
  {
    "monster_id": 52,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:骷髅战士"
  },
  {
    "monster_id": 54,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:骷髅战将"
  },
  {
    "monster_id": 55,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:骷髅战将0"
  },
  {
    "monster_id": 56,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:骷髅精灵"
  },
  {
    "monster_id": 57,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:骷髅精灵1"
  },
  {
    "monster_id": 60,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:粪虫"
  },
  {
    "monster_id": 62,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:暗黑战士"
  },
  {
    "monster_id": 64,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:沃玛战士"
  },
  {
    "monster_id": 66,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:沃玛勇士"
  },
  {
    "monster_id": 68,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:沃玛战将"
  },
  {
    "monster_id": 70,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:火焰沃玛"
  },
  {
    "monster_id": 73,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:沃玛卫士"
  },
  {
    "monster_id": 74,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:沃玛卫士1"
  },
  {
    "monster_id": 75,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:沃玛卫士2"
  },
  {
    "monster_id": 76,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:沃玛教主"
  },
  {
    "monster_id": 77,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:沃玛教主1"
  },
  {
    "monster_id": 79,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:僵尸1"
  },
  {
    "monster_id": 81,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:僵尸2"
  },
  {
    "monster_id": 83,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:僵尸3"
  },
  {
    "monster_id": 85,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:僵尸4"
  },
  {
    "monster_id": 87,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:僵尸5"
  },
  {
    "monster_id": 89,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:尸王"
  },
  {
    "monster_id": 90,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:尸王1"
  },
  {
    "monster_id": 91,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:尸王2"
  },
  {
    "monster_id": 92,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:红蛇"
  },
  {
    "monster_id": 94,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:虎蛇"
  },
  {
    "monster_id": 96,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:羊"
  },
  {
    "monster_id": 97,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:猎鹰"
  },
  {
    "monster_id": 100,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:狼"
  },
  {
    "monster_id": 101,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:盔甲虫"
  },
  {
    "monster_id": 103,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:威思而小虫"
  },
  {
    "monster_id": 104,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:沙虫"
  },
  {
    "monster_id": 105,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:多角虫"
  },
  {
    "monster_id": 107,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:巨型多角虫"
  },
  {
    "monster_id": 110,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:蜈蚣"
  },
  {
    "monster_id": 112,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:黑色恶蛆"
  },
  {
    "monster_id": 114,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:跳跳蜂"
  },
  {
    "monster_id": 116,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:巨型蠕虫"
  },
  {
    "monster_id": 118,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:钳虫"
  },
  {
    "monster_id": 120,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:邪恶钳虫"
  },
  {
    "monster_id": 121,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:邪恶钳虫1"
  },
  {
    "monster_id": 122,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:邪恶钳虫2"
  },
  {
    "monster_id": 123,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:邪恶钳虫9"
  },
  {
    "monster_id": 124,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:触龙神"
  },
  {
    "monster_id": 126,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:角蝇"
  },
  {
    "monster_id": 127,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:蝙蝠"
  },
  {
    "monster_id": 128,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:楔蛾"
  },
  {
    "monster_id": 129,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:红野猪"
  },
  {
    "monster_id": 131,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:红野猪3"
  },
  {
    "monster_id": 132,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:黑野猪"
  },
  {
    "monster_id": 133,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:黑野猪0"
  },
  {
    "monster_id": 134,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:黑野猪3"
  },
  {
    "monster_id": 135,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:白野猪"
  },
  {
    "monster_id": 136,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:白野猪0"
  },
  {
    "monster_id": 137,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:白野猪1"
  },
  {
    "monster_id": 138,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:蝎蛇"
  },
  {
    "monster_id": 140,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:蝎蛇3"
  },
  {
    "monster_id": 142,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:邪恶毒蛇1"
  },
  {
    "monster_id": 143,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:石墓尸王"
  },
  {
    "monster_id": 144,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:蜜蜂"
  },
  {
    "monster_id": 148,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:大老鼠"
  },
  {
    "monster_id": 150,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:祖玛弓箭手"
  },
  {
    "monster_id": 152,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:祖玛弓箭手3"
  },
  {
    "monster_id": 153,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:祖玛雕像"
  },
  {
    "monster_id": 155,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:祖玛雕像3"
  },
  {
    "monster_id": 156,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:祖玛卫士"
  },
  {
    "monster_id": 157,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:祖玛卫士0"
  },
  {
    "monster_id": 158,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:祖玛卫士3"
  },
  {
    "monster_id": 159,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:祖玛卫士00"
  },
  {
    "monster_id": 160,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:祖玛教主"
  },
  {
    "monster_id": 162,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:双头血魔"
  },
  {
    "monster_id": 163,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:双头金刚"
  },
  {
    "monster_id": 164,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:血巨人"
  },
  {
    "monster_id": 166,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:血僵尸"
  },
  {
    "monster_id": 168,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:月魔蜘蛛"
  },
  {
    "monster_id": 170,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:黑锷蜘蛛"
  },
  {
    "monster_id": 172,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:钢牙蜘蛛"
  },
  {
    "monster_id": 174,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:暴牙蜘蛛"
  },
  {
    "monster_id": 176,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:天狼蜘蛛"
  },
  {
    "monster_id": 178,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:花吻蜘蛛"
  },
  {
    "monster_id": 180,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:赤月恶魔"
  },
  {
    "monster_id": 182,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:幻影蜘蛛"
  },
  {
    "monster_id": 185,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:剧毒蜘蛛"
  },
  {
    "monster_id": 188,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:虹魔猪卫"
  },
  {
    "monster_id": 189,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:虹魔猪卫0"
  },
  {
    "monster_id": 190,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:虹魔猪卫9"
  },
  {
    "monster_id": 191,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:虹魔蝎卫"
  },
  {
    "monster_id": 192,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:虹魔蝎卫0"
  },
  {
    "monster_id": 193,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:虹魔教主"
  },
  {
    "monster_id": 195,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:千年树妖"
  },
  {
    "monster_id": 196,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:恶灵僵尸"
  },
  {
    "monster_id": 198,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:恶灵尸王"
  },
  {
    "monster_id": 199,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:恶灵尸王0"
  },
  {
    "monster_id": 200,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:骷髅锤兵"
  },
  {
    "monster_id": 202,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:骷髅长枪兵"
  },
  {
    "monster_id": 204,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:骷髅刀斧手"
  },
  {
    "monster_id": 206,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:骷髅弓箭手"
  },
  {
    "monster_id": 208,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:黄泉教主"
  },
  {
    "monster_id": 209,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:黄泉教主0"
  },
  {
    "monster_id": 210,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:牛头魔"
  },
  {
    "monster_id": 212,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:牛魔战士"
  },
  {
    "monster_id": 214,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:牛魔斗士"
  },
  {
    "monster_id": 216,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:牛魔侍卫"
  },
  {
    "monster_id": 218,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:牛魔将军"
  },
  {
    "monster_id": 220,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:牛魔法师"
  },
  {
    "monster_id": 222,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:牛魔祭司"
  },
  {
    "monster_id": 224,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:牛魔王"
  },
  {
    "monster_id": 226,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:宝箱"
  },
  {
    "monster_id": 227,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:宝箱1"
  },
  {
    "monster_id": 228,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:宝箱2"
  },
  {
    "monster_id": 229,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:宝箱3"
  },
  {
    "monster_id": 230,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:宝箱4"
  },
  {
    "monster_id": 231,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:宝箱5"
  },
  {
    "monster_id": 232,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:宝箱6"
  },
  {
    "monster_id": 233,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:宝箱7"
  },
  {
    "monster_id": 234,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:宝箱8"
  },
  {
    "monster_id": 235,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:暗之双头血魔"
  },
  {
    "monster_id": 236,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:暗之双头金刚"
  },
  {
    "monster_id": 237,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:暗之黄泉教主"
  },
  {
    "monster_id": 238,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:暗之骷髅精灵"
  },
  {
    "monster_id": 239,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:暗之沃玛教主"
  },
  {
    "monster_id": 240,
    "status": "UNVERIFIED",
    "reason": "SOURCE_IDENTITY_UNVERIFIED:暗之虹魔教主"
  }
]
```

## 审查入口

`source_audit.json`、`overflow_audit.json`、`balance.json`、`simulation.json`、`ARTIFACT_HASHES.json`、`EXECUTION_STATUS.json`、各阶段日志。

只有审查分支允许推送；本包没有授权自动合并 codex/integration。
