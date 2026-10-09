# B06 地图/存档/platform 冗余候选审查

固定源码 `d145826b7305ad918893ba0098db2595ae01f53a`。**只读分析，无删除/自动合并。**

- `WorldContent`和`RegionContent`中旧地图/怪物数据具有reference/migration/测试及planned-unbuilt角色；正式生产只认MapEditorRuntimeBridge `implemented_playable` + approvedSHA，**不能因为GameRoot正式路径不直接调用而删除历史资产**。更不能恢复旧裸`_spawn_enemy`或组扫描fallback。
- `AuthoredMapLoader`与`MapEditorRuntimeMapService`职责不同：前者供特定legacy map.json读取/测试，后者是正式map release SHA/type核验；不是两套并行可玩地图authority。
- `map_editor_workspace/**` **1311条**归正式人工地图工件，含源编辑JSON、ground state/manifest/chunk预览PNG和编辑器隐藏登记；虽不被Android直接打包读取，但源头/发布可复现性依赖它们，禁止视作dead code、删地图或以旧备份覆盖。
- `assets/data/runtime/map_editor/*.runtime.json`是正式gameplay发布资料，`*.visual.json`及deduplicated formal ground chunks属于另一种只读地形渲染发布权威；源艺术与运行渲染不是可以无证据合并的重复对象。B04/B05错分的68/74个资产属于本批地图职责。
- `MapEditorBuildRuntimeService.build_candidate`和`publish_runtime_release`不是重复写入：候选不改变正式playable，只有发布后registry+工件同SHA才授予资格。
- `JsonPersistenceService`的profile与world持久实例是不同document namespace，同一协调器代码，没有独立第二套HP/奖励业务权威；`SaveUpgradeBackup`仅升级前raw before-image，不能代替正式profile writer。
- `WorldMonsterClockLedger` death_event与`PlayerState` profile/world snapshots是序号回放协议，不是多结算经验；保存文件名相似不得机械删其中一条。
- `HCPPolyGeo`、`HCPPolyRuntime`、`HCPPolyBuild`、`HCPPolyVisualSnapshot`分别 authoring/build/runtime validation/render binding；源中兼容旧blocked_tiles字段不代表正式游戏回到强制格子移动。人工多边形碰撞必须保留。
- `tools/build_android_isolated.ps1`、Android seal双遍、签名源注入和环境隔离各有独立验收边界，不能删掉签名/版本验证以让打包表面成功。
- `DeviceLabPatch` autoload在release`OS.is_debug_build()`门禁下不注入用户PCK。调试路径不可直接当作生产危险模块卸载，应沿B08审查其mailbox和隐私输入，当前B06未对它全部1400行精审。

没有经过所有场景资源/反射/生成器使用查证和同工作量性能基线的安全删除建议；本轮删除：**NONE**。
