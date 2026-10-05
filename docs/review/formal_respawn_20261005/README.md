# 正式刷新规则接入与验收

15 张地下城地图的 203 个缺失规则组已通过正式作者保存、Build Candidate、单目标 Publish Runtime Release、实际 Bridge 和墙体派生发布接入。149 个普通怪物组明确为 `normal_cave / 480s`；54 个特殊对象保留既有 `beginner_outdoor / 300s`。精英、Boss 和 canonical `special_normal` 继续由既有身份规则决定，不改数量、坐标或掉落。

作者文件只改变授权刷新字段及对应 approval metadata。精确保留作者原始文本的 Save 可选入口仍使用原子保存、临时文件校验和既有备份链；不匹配、损坏或不精确的数值文本在文件操作前拒绝。原实现原生 RED 为 51 检查中 19 FAIL；最终 Save 专项为 56 检查 PASS，含整数安全边界和布尔类型反例。

全部 15 个正式发布原生进程 exit 0。独立复核确认静态几何、实例、地面和墙体像素载荷不变，527 个非目标文件、非目标 registry 条目原始字节和真实暂存身份不变。最后汇总的路径分隔符误判 FAIL 原样保留；恢复核验不重跑 apply、不重写正式文件。原文精度保留造成的 document/authoring/build 指纹变化被明确记录，其他候选载荷须完全相等。

最终同源码 11 场景 PASS；5 份完整 framework receipt 共 6880 检查。正式审计经实际 Bridge/Policy 扫描 67 张地图，缺失规则、无效规则、不稳定 slot、仍需作者规则的普通 slot 均为 0。旧 audit 把 canonical 精英／特殊刷新误当普通作者字段的 214 项 FAIL，以及新增 transport 检查误把缺失原始秒数当实际刷新期限的阶段 FAIL，均保留并分类。最终检查同时验证怪物身份、原作者字段、投影 policy、transport 和真实 Policy 解析期限。

- 内容指纹：`4ff6fde6f8f35643324ba527ed76e103be1e3105dafcea4bd8b7f6b77a122ab0`。
- 引擎：官方 Godot 4.7 `5b4e0cb0f`，完整引擎指纹及运行关联见下述 JSON。
- 发布关联：`outputs/framework_v2/formal_respawn_20261005/preserved_source_integration/generation_apply_352221145d4e4423a2f72caa5f82d3af/FINAL_VERIFICATION.json`。
- 最终原生关联：`outputs/framework_v2/formal_respawn_20261005/preserved_source_integration/FINAL_NATIVE_ASSOCIATION.json`。
- Save RED/GREEN：`outputs/framework_v2/formal_respawn_20261005/preserved_source_integration/VERIFIED_SAVE_ASSOCIATION.json`。

这是当前接入增量的验收，不能替代整体架构、自然持续 R3/P6、原 v97 B 存档故障或 Android 验收。APK 与设备测试均 NOT_RUN。当前 HEAD 仍为 `5d9ceb0121980ca9636d9d1cc2e19982949fbf63` 加未提交成果；受测内容绑定上述 manifest，不声称干净 checkout 或已推送固定提交。
