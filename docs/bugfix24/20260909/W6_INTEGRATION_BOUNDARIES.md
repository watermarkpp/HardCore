# W6 集成边界（待施工）

本记录只固定跨域接口和验收，不代表对应实现已完成。

- 雷电仅修改 `CasterSkillSkyStrikeVisualEffect` 已证实出错的世界排序；目标足点参与世界 Y-sort，图像偏移不改变足点，同足点保留身体可见。六帧播放 gate、伤害时刻、魔法盾和被动触发视觉冻结。
- 怪物等级从 canonical classification/明确 spawn classification 读取。新增 overhead 兼容入口，保留原四参数 `setup`；EnemyActor 接线由 V3 唯一写者或 integration 完成。Boss 优先于 elite，普通无标，不依据名字和 HP 猜测。
- 名称格式化只在玩家展示边界执行；以已确认的稳定 monster_id 变体集合消除末尾变体编号，不全局删除数字，不改 canonical/任务/音频/掉落身份。
- 光柱只读取冻结的 `assets/data/drop/dpv2_item_tier_authority_v1.json` 精确 item ID/档位。`WOOMA_GEAR`、`ZUMA_GEAR`、`REDMOON_SET` 为明确核心；其他档位逐项裁决，不因售价或名字自行提升。药、书、油、金币一律无光柱。
- 小极品颜色由实例 `drop_affix.applied` 和经校验的 `modifiers` 决定，与模板档位光柱独立。不得把 descriptor 的按模板缓存当实例权威，避免一件极品污染同 ID 普通物品。
- 光柱归属 LootPickup 生命周期；失败保留、确认入账才移除，切图不留孤儿。不采用每件大型粒子/灯光/全局查找。
- W7 冻结实例由 `PlayerState.create_drop_item_instance` 生成。跨树未合入之前可使用精确候选合同夹具，不另写第二个实例生成器。正式联调必须使用主树 API。
- HP 强化水精确 ID 为 910008，当前使用 generic fallback 两图。必须补原始主源精确索引/缺失证据后处理正式两图及绑定。不能指向另一药水冒充命中源；必要的项目补充素材须如实记录。
- 验收分别记录功能专项、真实排序与截图、最终 APK 导出包含、用户设备结果。Headless PASS 不替代视觉或设备接受。

所有权安排：视觉 helper/素材及专项可在隔离树独占施工；`game_root.gd`、`game_data.gd`、PlayerState 和 V3 `enemy.gd` 不向视觉 worker 开放写入。UI 属性面板仍由原 UI worker 独占；用户现已通过校准，要求字体减小 2–3 号后直接使用，专项通过即可整合。
