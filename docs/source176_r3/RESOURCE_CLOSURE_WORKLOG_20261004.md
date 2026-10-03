# 第三树资源准备增量

本增量父审查e9c3ac005bc3e079eab6602375abfcd9c1bf3cc9。单主控串行，真实第三树HEAD/index保留，主树/第二树/冻结MonsterStreaming/真实存档不动。两份e9c3报告已实际读取，全文/身份/读取时间在outputs/framework_v2/publication_closure_20261003/audit_e9c3，双拉取官方PAUSED。

## 已执行

- 原角色未到期真实药效在正常I/O失败建角后丢来源：23项/3FAIL，快照/恢复增加药效表与revision，23PASS；绑定skill_id数值/数组本来正确拒绝，41PASS，生产入口未为该静态候选改造。
- 资源目录与无凭据准备原5项/2FAIL已修复。声明登记hc.resource.item.healing.inventory，精确指向既有GameData主源疗伤药图标；只注册定义，不默认加载或开启新玩法。编译仍是plain graph，实际Texture2D单独持有。
- 正式reload_feature_catalog_async缺失原2项/1FAIL；真实冷路径取得1次线程请求/完成、cache0，带准备凭据的目录与人物结果同步提升。原同步空资源路径保留，非空无凭据拒绝；老目录/装配一直有效。
- 资源已接受工作生命周期反例：精确26项/3FAIL→26PASS。真实Root/Player非空票据近战，目标HP提交后正式源死亡；停用撤新来源，action→batch→queued entry→until_expired state分别强持有旧资源，四周期实际伤害兑现，最后租约与预算退休队列排空。受控生产API与测试推进，不外推自然UI、墙钟时效或GPU。
- 就绪应用漏账反例14项/1FAIL→14PASS；ready验证、人物候选、原子应用及同步观察者在同一FrameBudget量子内完成，完成信号/await在scope关闭后发生。预算仍1200us，共用真实process epoch，无新模拟钟。
- 共享引擎请求反例精确8项/2FAIL→8PASS。外部真实ResourceLoader CACHE_MODE_IGNORE请求保持未领取，旧实现借用其get权；现每个缓存miss job先持有自己的request权，ResourceLoader内部共用任务，再只领取自己的get。外部仍可独立领取同一资源，最后engine token排空。依据对应Godot源码core/io/resource_loader.cpp L646–665、860–918，不是重新造缓存。
- 原生冷热/共享持有、模块依赖闭包路径去重、缺启用依赖拒绝、取消、测试拥有的profile身份改变、错误真实缓存类型拒绝、退休排空共23PASS。profile身份变化和Resource.take_over_path是受控测试输入，不称完整真实角色切换或自然加载失败复现。

每次原始FAIL、GREEN、完整回执、退出与source/invocation/run在outputs/r3_takeover/20260930/validation/feature_resource_*及feature_publication_e9_adjacent_*。不改旧失败标签；早期测试正文补齐null两侧假阳性和固定失败检查计数后重做精确RED，早期失败仍保留。

## 仍需继续的范围

Task3整体NOT_RUN：现声明类型仅Texture2D、首条主源图标；需补活世界非空模块异步启用与life/world变化、已开始引擎线程后取消和失败terminal权利清理原生负例、多请求冷共享/工作量游标上界、资源/持有内存有限轮次和相关自然链最终回归。现代码不以TTL/LRU清去重，也不假设取消了引擎线程。per-lease requested是参与共享job的诊断，跨租约不能相加作物理请求数；服务metrics给出真实request/get调用总数。

Task4异构来源/机制、Task5模板/生成组合/最终回归及APK/Android未关闭。职业preview派生缓存、初始装备后建角独立负例、原v97B MISSING继续单列。没有合主树、改版本或产出APK，不把资源专项当完整RFC完成。

Godot原资源语义参考：https://github.com/godotengine/godot/blob/5b4e0cb0fd279832bbdd69fed5354d4e5ad26f88/core/io/resource_loader.cpp

## 活世界与共享工作增量检查点

原六个自然／独立cold场景在f4219963内容243检查通过后，增加活世界非空模块异步启用。API缺失2/1 FAIL；首版真实生命换代与同步保留子集27/5 FAIL；最小修复后最终29 PASS。同一世界的生命重新READY也不能接纳旧准备，世界退休不能把旧pending变成启动授权；同步停用仅从已有同目录、原模块集合保留资源。32共享请求同帧集中交付12/1 FAIL，改为每量子一个参与者后25 PASS；四轮32请求释放后objects1679、resources131均稳定，不外推总bytes或无限耐久。实际引擎IN_PROGRESS后取消13 PASS，未虚称线程已取消。

最终同52beda6709b0a16e9f62877f4d610042aea85751909d903602939b0611e6abfb内容：30直接／相关+6自然live/cold场景，35完整回执852检查，原生均退出0。38源码／测试／作者数据增量；114原生尝试及14 FAIL原样归档于docs/review/framework_resource_closure_20261004。活世界启用、请求开始后的取消、共享交付游标和有限轮次计数这些原开放项已有本轮证据；Task3仍因terminal FAILED、完整cue/audio/子资源与非空资源自然／渲染／设备验证未关闭。Task4—5继续施工，不把本轮固定增量当整体完成。
