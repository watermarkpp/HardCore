# 1d20d266 Pro 审计：未入树副本持有寿命标记

2026-10-02，已实际读取原《游戏稳定性设计》Pro完整回复。Pro支持保留1d20的已测UI登记/销毁修复、自然30身份与资源归属补证和R3完整格候选复用；未做本机实测。新增下列源码风险由主控原生复核，不把报告当自动裁决。

触发：已登记 Button/ScrollContainer 被 duplicate，副本停留树外、尚未 claim。原控件先销毁。旧metadata保存RefCounted Lifetime，复制引用可能推迟其最后释放，进而延迟死WeakRef清扫。

不变量：登记生命周期由原目标本身销毁结束；未登记副本不拥有原对象退休权。已登记副本仍拥有独立新身份。活动重挂仍保持一身份一登记。

反例：新增 ui_registry_retirement_test 的独立段，原 Button和Scroll登记→复制但不入树→原对象queue_free→4帧无输入/无额外登记销毁→检查原对象已经销毁且死引用为零→副本再入树登记与销毁。先在1d20生产代码运行，保留原始失败，再最小修复。

修复候选：目标拥有一个不参与正常UI子列表/复制的内部Node寿命子节点；metadata仅保存该子节点WeakRef。父销毁必销毁内部子节点，不受副本metadata引用数量影响。目标ID、observer弱引用、角色幂等与延后合并清扫保持；没有逐帧轮询或第二个UI输入权威。

依据：Godot正式Node.add_child文档说明internal子节点不在默认get_children中、不会随Node.duplicate复制，父销毁会销毁子节点。实际Godot4.7原生反例和相关回归仍为最终依据。
https://docs.godotengine.org/en/stable/classes/class_node.html#class-node-method-add-child

验证：UI专项RED/GREEN、原输入先后/滚动/角色滚动/布局回滚、自然live/cold及四轮退休；与新增30死亡/状态同刻场景在最终同源码复核。正式发布、主树、设备和原B缺失边界不变。
