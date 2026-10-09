# B06 验证缺口、数据引用范围与回归合同

审计固定源码 `d145826b7305ad918893ba0098db2595ae01f53a`。本轮**Godot native、Android手机、导出APK、强制终止/rename注入测试均NOT_RUN**。报表通过GitHub push仅证明报告接收，不证明项目验收。

## 最少动态故障专项

1. B06-001：只在隔离复制的**单张**人工地图上逐Chunk、manifest、state故障注入/进程中断；逐字节证明最新数据保留或显式停止恢复，另66个地图不改。
2. B06-002：正式runtime晋升后与registry保存前、各自bak/tmp阶段中断；重启tool端只恢复已验证完整publish版本。不得把旧hash临时标为新批准。
3. B06-003：模拟map编辑文档保存失败后按build candidate/publish，必须保持失败可见、不能发布未耐久化修订；之后成功保存才允许publish。
4. B06-004：外部registry numeric ID和工件source.runtime_map_id故意交叉不符，拒绝但不破坏当前67图。
5. B06-005：强杀进程在正常死亡XP已耐久/roll前、roll进行中、部分地面生成/已拾取几阶段；先确定用户崩溃恢复合同，不能自动roll第二次或跳过已提交奖励。
6. B06-006：按地图/字段复核74项来源hash偏移的原因；当前445正式PNG与source byte-equal，不可因此大规模重发布/触碰人工数据。
7. B06-007：在真实Polygon碰撞/玩家实际脚印合同上检测117配置传送端点的正式进入点+边界静态阻挡；至少对地图回环、到达专用门点、无可达落点失败做native。

## 地图已检查/未检查的明确字段

- 已静态从冻结Git对象读取 **67** editor JSON `map_id`/`runtime_map_id`/`editor_meta.revision`/`design.design_size`，及六类semantic layer条目**计数**；67个release registry的`map_key`/`runtime_map_id`/`approved_build_sha256`/`release_state`和相应67个runtime的schema/source/buildSHA，均匹配。
- 132个`semantics.map_exit_points`中配置目标的117个核对`target_map_key`、`target_map_id`、`target_portal_id`、`target_tile`与目标runtime endpoint，未发现错配，余15个arrival_only未误判可主动进入。
- 67份ground manifest/state检查尺寸、dirty array、445materialized chunk `baked_operation_count`、操作数；445个workspace PNG→formal PNG目录对应路径/Git blob完全相等；视觉meta source SHA三字段201次中74个与**当前**source bytes不等，不能据此断定正式运行图像错。
- **未完成**：逐地形像素及polygon具体接触边界、每张地图全部2298+340怪物出生点的静态/动态阻挡、NPC服务原文、WorldContent迁移跨地图每项、地图上传/发布打包Android真实资源内包含性、人工source每次编辑历史、远端资源/实时手机载入耗时。

## 存档与平台未验证边界

- 真实用户存档、密钥、签名keystore未读取，只有源码和生成资料。Primary/backup/journal多文件崩溃、目录不可写、容量耗尽、掉电中断、跨版本未知文档schema都需要隔离fixture和原生回执证明。
- Android包名`com.personal.mafaoffline`和原签名/实际base apk对照是构建时验收；tracked`export_presets.cfg`仍version/code82，`build_android_isolated.ps1 -VersionCodeOverride`可仅在Stage升为109；当前APK NOT_RUN、覆盖安装真实存档保持 NOT_RUN。
- 应用后台/焦点返回、Android返回键、菜单屏障、实际多指抢占问题由已发布B05审查与主控本地修复处理；本B06不采用未推送的新功能，也不声称缺Android试验是源码BUG。
- 跨批：B04/B05部分地图资料本批补正式地图身份/visual hash/Chunk链，仍需B07 source authoring细化；GameRoot、PlayerState、MapEditorApp、DeviceLabRuntime等巨大脚本B06无关职责留B08明确函数清单，不能打勾“全文件审完”。

任何后续实际修复只要求变更影响范围的定向回归，原始旧FAIL记录保留，受测SHA/runner/native退出/stdout/stderr/map字节清单必须一致，未改场景证据可以复用但不能合成伪全量。
