# 清理前独有提交核对（尚未清理）

本次只读核对主树 bc55d71ff6bd05f2f664af6d581e0bec57074be0、23 个实际 Git 工作目录及两个历史独有提交。`inventory.json`保留原始路径、HEAD、dirty 和独有提交；不是删除许可或清理完成证明。

## bfe90 性能诊断

固定提交 bfe90de4b4546b4b7001cdcbe214122691ae53b8 的全部 8 文件差异逐项查看。有效改动已由当前主树保留或后续正式实现接替：

| 原改动 | 当前实际路径及裁定 |
| --- | --- |
| GameRoot 整帧/拾取准备/背包容量桶/完成提示计时 | game_root.gd 仍保留这些计时。F03 将 save bytes 记录移到实际后台回执之后，并有 `plan.has("bytes")` 门禁；不会恢复旧准备阶段读取 bytes。 |
| 掉落标签整批重排计时 | 已由用户批准的逐物品 `place_at_home` 和 `loot_name_placement_*` 取代。不会恢复整批扫描及重排。 |
| MonsterVisualStreamingCoordinator.poll_once | 与 bfe90 的完整函数规范化文本及 SHA256 一致。 |
| Player physics 最大耗时 | player.gd 保留 `player_physics_max_ms`。 |
| 纯金币无需背包复制/重量/空位扫描 | receive_loot_batch_partial 完整函数与旧提交只差开头的 F03 `_before_state_transaction` 门禁；原金币分支及其测试断言仍在。 |
| PlayerVisual 外观签名与强制数据库重载 | 外观签名保留，分别记录两套身份字段，避免别名变化漏刷新；数据库重载函数与旧提交完全一致。refresh_profession 消费签名，不再无条件清空贴图；职业/性别本身是签名输入。 |
| WorldBackground._rebuild_source_collision_chunk | 与旧提交的完整函数规范化文本及 SHA256 一致。 |
| loot_inventory_transaction_batch_test | 原纯金币不改背包、重量及占位扫描为 0 的断言完整保留；最终当前 full critical 原生结果仍待完成。 |

这是源码保留核对，不能替代功能回归或性能验收。

## 86331 自制雷电旧素材

固定提交 86331feb719e78c7a4e13196bdf3aee5afdeef5c 包含旧自制雷电 PNG/APNG 来源、火墙 60ms 配置及相关生成/校验。用户后来明确批准全技能恢复原始 Magic 素材的 B 混合效果；旧自制雷电图不能重新覆盖当前已验证素材。火墙 60ms 属于仍有效配置，继续保护。源 APNG、未知 dirty、ignored 保存/素材及最终包仍须逐目录保留后才可退休目录。

## 已建立的本地保护引用

使用 Git 创建引用时明确要求旧引用不存在；若已存在则必须指向同一完整 SHA，未覆盖其他引用：

- refs/heads/codex/preserve-perf-bfe90-20260928 → bfe90de4b4546b4b7001cdcbe214122691ae53b8
- refs/heads/codex/preserve-lightning-86331-20260928 → 86331feb719e78c7a4e13196bdf3aee5afdeef5c

两条引用实际回读一致；未改变当前 HEAD、任何工作目录或远端。引用只保护已提交内容，不能代替未提交和 ignored 内容的外部备份。锻造 7 个独有提交仍是后续正式集成对象，不能据此清理。

当前状态：源码核对 PASS；最终功能复验 NOT_RUN；工作树退休 NOT_RUN；远端推送 NOT_RUN。
