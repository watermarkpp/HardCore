# B08 可删除/重复权威审查

fixed_source_sha: dbb1bd0878ab24a4e5bd6a1877d32f304f5623e5

结论：未证明任何可安全删除的生产组件或测试/数据/素材。没有修改或删除文件。

正式资源不能仅按普通文本调用判冗余：当前 project.godot autoload: ContentLayers、GameData、PlayerState、GameModes、RuntimeServices、LootRuntime/CombatRuntime/DomainRuntime、音频与发布服务；class_name、tscn/tres、signals、Callable、dynamic call/has_method、编辑器/正式生成调用、兼容/保存 ID 都要逐边核查。
已实际看到 GameRoot._service_passive_monster_wakeup_batch 使用 enemy.has_method 与 enemy.call 进入 request_passive_target_wakeup、GameRoot地图操作使用 Callable 引用、PlayerVisual连接 GameData.database_reloaded、scene startup_loading加载与 Godot全局 autoload。无普通直接文本调用不证明未使用。
Mode 和 ContentLayers 两套表述并非可删第二权威：GameModes owns active_mode; ContentLayers owns package flags/merge; GameData owns runtime catalog; PlayerState owns saved game_mode_id. 真问题是事务序与失败传播，不是删除任一 autoload或创建第三个缓存。
scripts/monster_streaming_coordinator.gd 是索引阶段一个猜测路径，固定 SHA 无此文件；已从 GameRoot:59–61实际 preload 定位 scripts/monster_visual_streaming_coordinator.gd，绝不能把不存在的猜测文件当当前生产冗余。
tests/helpers/loot_runtime_pre_slice_20261009.gd 是旧掉落 delta oracle、tests/source176_r3/helpers/cadence_reference_r2.gd 是冻结R2节拍对照，非运行权威，不应据此恢复概率/HP/300ms逻辑，也不能删除 fixture 历史证据。
26个本地退役 grid 实验路径与 user maps、authoring 数据、fixtures、原失败证据均保留。召唤蝙蝠127权威选择未解决且不准通过fallback补齐。只有已获消费者与动态反向引用/兼容存档排除证据且主控确认的具体路径才能讨论删除；本轮无此候选。
