# 极光电影预览失败：视觉保护与只读裁定

状态：原完整 critical 的旧预览断言 FAIL 保留；固定 BASE 的两个原测试 PASS。根因已核实为本地主树过期导入缓存；刷新后包括两原测试、新平移测试及相关回归共 11/11 PASS。最终完整 critical 仍 NOT_RUN。

## 用户冻结

用户说明此前将极光电影从人物脚点向头部方向整体平移，让出手位置自然。此意图保留，不能用旧脚点预期自动撤回人工位置。位置、尺寸、素材与当前测试预期均未修改。涉及这部分修正先询问用户。

## 当前证据

- 源码 HEAD：257d50bd006b02c606b964c44fa947f92efc48e3。
- 原流水：final_critical/runner/laser_direction_visual_extent_test.stdout.log 与对应 stderr/runner 结果。
- 该测试显式使用 legacy V1 preview snapshot，通过非零 alpha 像素的本地坐标和 sprite.transform.basis_xform 计算轴向区间；没有纳入父节点与世界坐标平移。它不能独立证明游戏中出手高度不对。
- start_err、end_err、extent_err=(end_err-start_err) 分开记录。纯平移使两端增加同一个投影量，不改变可见长度；当前 E extent_err=-4.8px、SE=-37.5px，不能把全部失败仅归因于上移。
- 固定 BASE 1381d283..当前 HEAD：beam visual、base visual effect、visual registry、caster_spell_geometry、两份视觉 manifest、wizard effect 素材、该旧测试均无 Git 差异。
- 共享 animation player 的差异只有 BackBufferCopy 由进入树时危险 sibling 改为自有 child/show_behind_parent，以及对应可见性/销毁处理；没有几何或像素坐标变换差异。此为实际副本准备错误修复，不证明旧预览失败无关，仍需 BASE 实际复现。
- 当前正式 beam range / terrain cutoff 等测试已经通过；它们不替代此预览测试的失败。

## 后续实证与用户批准的恢复

- 原线程与归档提交 `c8dbbb67b553ecde78f4172a3f29e1466c8f30e2` 中找到完整的整束上移 28 像素及按方向遮挡人物改动。当前主树及接管前 f5d6308f 均未包含；两文件当时与归档父提交相同。归档不是当前主树祖先，因此不能说本次怪物合入撤销了它。
- 用户已明确批准“恢复原来的 28 像素整体上移”。只应用归档原视觉源码补丁和原对应测试补丁，未用归档完整文件覆盖新主树。所有束的绘制节点上移，地面 origin/end、伤害几何、宽度、长度、素材与时序保持。
- 新独立 `laser_chest_translation_test` 检验 21 个方向、6 帧共 126 项实际节点世界平移、整束核心与外辉、方向层级及 snapshot 不变。原端点测试保留执行，没有删除或放宽其断言。
- 固定 BASE 原两测试实际 2/2 PASS；主树原始 96 帧 PNG 与 BASE 相同，但 96 个 ctex 均不同，96 个记录的 source_md5 均不匹配当前 PNG。具体见 `laser_import_cache_review.json` 和 `laser_original_base/`。
- 扩展到 caster manifest 及 warrior effect 的精确 PNG 范围：609 项，225 个缓存有效、384 个过期、0 缺失。只读扫描见 `skill_import_cache_scan_before.json`。
- 导入前备份 1,920 项缓存/metadata/translation，并记录 609 张源 PNG 的 SHA256 和 mtime_ns。正常导入 exit=0，无脚本错误。导入后 609/609 源 SHA256 与 mtime_ns 不变，93/93 已跟踪 translation 不变，609/609 source_md5 有效，laser 96/96 ctex 与独立 BASE 相同。详见 `skill_import_refresh/verification.json`。
- 源 caster frames 与 manifest 相对已验收原游戏 B 素材提交 `368a16e6c` 无差异。原游戏混合路径与火墙避免重复 viewport copy 的优化仍保留。没有用 v93 或旧专业树覆盖当前人工主树。

最终完整 critical、最终性能配对及干净检出仍 NOT_RUN；当前定向 PASS 不能替代它们。所有原 FAIL/timeout 原始记录保留。
