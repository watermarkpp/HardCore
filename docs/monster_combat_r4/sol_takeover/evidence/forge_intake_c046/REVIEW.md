# 固定 c046 源码的锻造合并预览（未集成）

主树 `c0461f25ab2d02f2ea304dcf43be36cb868ab9d0`，锻造 `da41da3642123c180723ef03dec193ef1fc4cb1b`，只读 merge-tree 对象 `2cd9c40169fcb41bd403f5a33103d411a9667c82`。预览命令 exit=1 为五项真实内容冲突，不是成功合并；工作目录/index/HEAD 未改变。旧3b预检仅作历史参考。

五冲突仍为 loot_pickup、player_state、live_attack_resolution、melee_lock_fallback、warrior_skill_state_machine。主树固定掉落名称/一次纹理取得、F03后台事务/稀疏世界账本/延迟耐久、R4真实READY近战夹具保留；加入新尺寸/工作格/圣物/多宠，不整体覆盖共享文件。

## 已串行源码核对的候选与后续实际证明

1. 四个新 PlayerState 公共写操作没有 `_before_state_transaction()`；其生产调用来自界面包装入口，内部 service 在改变 collection/gold 后才 `_commit_save`。当前主树兼容门禁消费旧已批准回执，应放在这些公共入口取回滚副本/校验报价/RNG之前。先原生 PROMOTE 未主线程 ACK 的拾取与真实工作格操作 RED，再修复并验证唯一物品/金币/落盘回读。不能只测试静态字符串或mock保存。
2. 新实例校验把 item_id/count 强制 int，需真实小数/字符串反例；整数及JSON整值float必须保留。旧心3–5运输实例继续兼容。范围只限新增圣物/徽章身份，不更改朋友的旧普通装备迁移。
3. 圣物每帧同步的缺ID路径复制完整 GameData 记录、按同identity+ID早返回绕过后续校验；实际同实例已激活proc后缺失/非整ID/count应清除proc。先真实触发 RED，再去除该无效fallback并加廉价身份门禁。`is_relic/is_badge/is_synthesis_item`也通过 `record_for_id()`深复制记录；正确正式缓存存在性可直接查询，任何优化需与真实校验/属性行为回归一起证明。
4. 徽章当前每physics仅 int转换item_id，按ID变更重置timer，需新增非整ID/count的真实恢复反例。保留1秒四舍五入、同合法ID节拍、卸下重置以及149→1/49→0的正式测试。
5. 自动合并预览：player 增加徽章tick；summon 新effective rank/slot与伤害more、队形、恢复；plan只增pet_slot_index；hud增加强化面板/遮挡targetbar/新图标尺寸。接收后必须证明主树观察来源、身体半径/空间索引、极光28px、F03/F05和旧存档未回退，自动合并不是PASS。
6. GameRoot多宠涉及保存groups、已用slot、合法出生/回收/到达以及rank cap；保留主树新版召唤半径与释放快照。逐hunk保留双方生产合同后，跑正式召唤链和真实多宠存档/技能回归。
7. 八地图仅NPC名字变更。实际集成后先按正式identity与发布registry分出正式/历史工作区，核对NPC identity消费者，再决定精确发布目标。禁止为名字批量迁移地形/spawn或用旧source覆盖人工保存。

以上状态是源码候选与整合检查项，不是已运行RED或已修复。当前542项累计回归期间生产/测试/runner保持c046固定；不合并、不提交改变HEAD，不启动第二个Godot实例。最新用户边界为推送和安全清理后停在打包之前，旧交接APK要求被该边界取代。

## 原始字节与Git对象核验

初次把交接清单的工作目录SHA256直接和Git对象字节比较，73个既有文本报FAIL；原始结果保留 `preview_manifest_check_initial_fail.json`。现场 `core.autocrlf=true`，game_root实际是CRLF/LF混合工作字节，Git对象统一LF；单纯LF→CRLF扩展并不等于原件，实际仅Git清理CRLF后的字节完全一致。

因此按清单自身提供的两个身份分别核验：原工作树原始字节SHA256精确匹配清单，`git hash-object --path`正式clean转换后blob匹配清单git_blob，source9dcd与tipda41的blob也相同；预览对象再和已提交blob字节比较。最终180/180源身份PASS，170/170非共享预览字节保持，10共享仍需实际整合和语义验收。没有手改源换行、删原始FAIL或放宽源码内容断言。
