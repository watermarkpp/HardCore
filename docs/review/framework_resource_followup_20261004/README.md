# 第三树：资源声明、发布取消与持续服务增量

父审查提交 `1a3e6263a094b9ed004465be12b5a9c22b97ca9c`。本轮源内容 `7acfe4aef78a10a3a258fa53b6e63a60a58602478487ff239fcdaf079ae0bb4b`，3668个源码/场景/数据文件，20个源码/测试/作者数据增量。真实施工HEAD仍5d9ceb0121980ca9636d9d1cc2e19982949fbf63，原index与两受保护树不改；审查提交另用专属index固定。不是完整RFC、主树、APK或设备完成证明。

## 已修改及原生反例

- 正式候选读取器先检查资源声明成功，再构造允许路径；资源-free候选也不能吞掉失败声明。受控失败缓存反例8检查/4FAIL，修复后8PASS，旧目录/bundle/stats/compile_count/通知保持。缓存注入不冒充损坏正式文件的自然UI。
- 同步原子提升与可取消准备分开。发布通知中正式取消保留外层锁；直接服务cancel_all跳过正在应用的请求，其他被取消等待者在budget scope关闭后恢复。原14检查/6FAIL；补另一等待者后最终16PASS。准备阶段立即取消语义及自己欠引擎的终态获取权仍保留，不回滚已发布配置。
- 准备器内部工作、应用、退休轮流服务，至多三个获准服务量子给每个非空类别机会。原两个合法持续调用者180帧完成176、已就绪发布始终未完成、退休峰174；GREEN继续完成89、ready epoch9→complete10、峰1，8PASS。没有增加1200us、强pump、伪造epoch或减少调用者；机会保证不外推为在全局预算争用下无条件墙钟截止。
- 资源类型增加AudioStream，既有烈火音频按稳定event和明确sound137导入边界解析现有音频authoring/generated映射，再核主源client_assets tier与源SHA。新资源ID hc.resource.sound.fire_sword.attack，真实路径assets/audio/sfx/client/137__M26-3.wav。没有新增/修改声音文件，也不按中文名称找身份。原6/2FAIL→17PASS，typed音频+required子模块图标闭包同时准备、原子提升、类型替代拒绝、依赖撤销保持；25声明负例检查整候选拒绝。

## 真正的引擎加载失败负例

只临时损坏第三树独立`.godot/imported/Items_00014...ctex`，主源PNG/import映射/源码不改。真实引擎到THREAD_LOAD_FAILED，等待者明确拒绝，旧配置保持，一次get领取自己的terminal权，scope/队列排空；还原原缓存字节后，原正式API新请求成功取得真实Texture2D。

最终负例 `feature_resource_terminal_failure_negative_051309_781002` 同当前源码，15业务检查全部通过，进程正常终态。通用runner仍为FAIL，因为故障注入恰好产生三条引擎ERROR：损坏header、指定ctex加载失败、指定主源PNG路径加载失败。`negative_supervisor/terminal_failure_gate_*.json`仅在原FAIL、完整receipt/run/invocation/source、精确错误集合、无额外脚本错误、未超时和缓存字节一致时判有界预期错误门禁PASS。原runner/日志不改标签，不扩通用allowlist，也不将它混入41个正常成功场景。

监督脚本保留原字节且finally恢复；原生前后和监督恢复SHA均为6af7a27e3a4d31ae670a86b7cc37a2b3a67fd35f10bb1ecc14bf629c17517cc4。脚本、恢复回执和578字节备份在negative_supervisor。此夹具应通过外层监督脚本运行；单独启动脚本并强杀不能代替已验证的恢复协议。负例包含普通新请求恢复，不是生产自动重试策略。

## 最终采用范围

只采用本内容两个正常最终调用：

1. `feature_resource_followup_final_direct_051409_858126`：35场景，34完整框架回执/683检查；另一个普通新角色启动包场景。
2. `feature_resource_followup_final_world_052151_910018`：6场景/243检查，组合效果、合法退出、自然战斗各自live/cold，本轮成功producer且同源码。

合计41唯一正常场景、40完整框架回执、926检查，全部确认正常退出、无timeout、零引擎日志错误。另述同源码15业务检查的预期引擎错误负例，不合并成通用runner PASS。61原生尝试的6条FAIL保留（4条业务反例、2次预期错误故障注入）；阶段结果不计入最终集合。

SOURCE_MANIFEST、SOURCE_DELTA、RUN_INDEX、NATIVE_MANIFEST、SCOPED_EVIDENCE、PROTECTION和逐成员验证的源码/原生ZIP在本目录。源码Git文本/受测原字节换行关系另列SOURCE_GIT_BINDINGS；ZIP保存真实受测字节，不声称干净checkout实跑。child exe hash仅文件身份，非新增逐调用映射证明。

本轮SOURCE_GIT_BINDINGS核对全量3668文件，2870份Git blob与受测原字节只有CRLF/LF表示差异，逐份归一化一致。这不是2870个施工改动，也没有批量转写工作树；本轮实际源码增量仍20。以前报告的少量换行映射是增量范围，不用它冒充全量映射。

## 审计与开放项

Pro原对话完整报告已实际读取，来源身份和读取时间见audit_1a3e6263，两个新条件链均先原生复现再修复。小可爱该旧轮完整报告尚未实际读到，继续按既有有界拉取策略等待；不把Pro报告伪称双审计已全部读到。

Task3整体仍NOT_RUN：实际关键音画/子效果消费、资源启用的自然混合负载、GPU首次绘制和设备联合门禁继续施工。本轮typed音频就绪不等于实际声音播放/设备听感，required模块不等于异构死亡连锁。Task4异构来源/机制、Task5模板/生成组合/完整P6/R3/最终交付仍开放。原v97B MISSING、掉电/外部旧primary替换边界保留；主树/APK未动。资源源码新增后已重跑必要相关测试，不用早期Texture2D专项代替这些未覆盖部分。
