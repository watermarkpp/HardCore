# UI 响应与遗漏系统的主控闭环

本文件记录主控实际生产修复与串行测试，补充先前只读审计报告。未改已接受美术、人工校准、装备格、背包 100 格、商店商品格或仓库容量。

## 按钮反馈

背包、仓库、商店、任务、复活结果回调原先强制等待一个 process_frame，操作已完成却仍显示 busy；成功提示保持 1 秒，失败 0.45 秒。现已取消人工等帧，收到真实结果即呈现；公共主题定义成功 0.20 秒、失败 0.30 秒，系统菜单和技能绑定发送提示也消费统一时长。

保留真实事务等待、购买短锁和复活 transition 锁。反馈序号使旧定时器不能清掉新 busy、选择或重开后的操作；计时结束不改变动作 disabled 和布局。

`ui_result_feedback_timing_test` 使用六个真实面板，检查即时结果及真实纹理反馈层颜色、提前保持与及时结束、选择保留、新 busy、正式仓库请求等待、复活重复请求拒绝、关闭和释放。最初 RED 是 inventory.sort 同步回执仍为 busy；测试原版曾误读 AdaptiveButtonStyleBox.fill_color，主控修正为实际绘制的 feedback_style/feedback_background_styles，未更改美术或弱化为只看 metadata。

旧 shop/warehouse/quest 测试要求额外一帧 busy，按本轮用户响应要求改为立即结果；真实请求尚未回执时的 busy 断言保留。system_menu 旧预期为设置行距 112，按已接受 v81 `4f4462ad` 三行布局核对精确位置 (72,148)/(72,230)/(72,312)，生产布局未改。

## 隐藏背包统计

原 profile_changed 直接调用 `_refresh_character_stats`，即使面板隐藏，也重建 identity/属性富文本并重新布局。主控新增仅统计 dirty 状态：隐藏期间不计算，打开消费一次；可见同帧信号合并到一次 deferred stats-only 更新，完整 refresh 消费统计 dirty，关闭前排队的更新保留到下次打开。

真实 StatsSpy 每个覆写均调用 super。100 次隐藏信号：100 次统计/文字/布局→0；100 次可见同帧信号：100→1。原隐藏同步派发约27.1ms，可见约21.6ms；候选约0.051/0.058ms，显示统计另执行一次约1ms。该数据为 headless 同类场景 CPU 诊断，不能当手机帧率。

新测试 84 项检查包含最新资料、富文本原文/解析、几何字号、完整100格、full refresh 不重复和关闭重开；结果 PASS。详见 `evidence/hidden_inventory_stats_comparison.json`。

## 已补的系统覆盖

`runner_results_adhoc_20260922_180107_118_18388.json`：16/16 PASS，engine_log_errors=0。

- shop、warehouse、quest、system_menu 实际面板与交易/任务/设置回归。
- 仓库 `transfer_warehouse_prepared`、银行 `transfer_shared_gold_prepared`：真实 UI 入口、并发拒绝、外部文件字节变化、WAL/失败回滚及 UI 销毁后的事务。
- 角色删除事务：确认/取消、写入失败、其他角色保护；旧存档坐标迁移。
- 设置功能与音频配置严格验证、音频偏好应用、关闭保存。
- 公共触摸滚动、角色列表滚动、商店选择身份。
- GameRoot 城镇音乐 READY 门、装备技能等级词条输入。

其他直接证据：

- `175309_808_6176`：按钮/隐藏统计 RED 0/2。
- `175438_619_10636`：隐藏统计 PASS，按钮测试样式观察错误已分类修正。
- `175749_057_5044`：新按钮测试及死亡/背包/隐藏背包/反馈对齐 PASS；旧三个忙碌预期和旧设置布局共4 FAIL，后续在180107复验PASS。
- `180234_627_5800`：技能面板、六面板反馈、火墙动画 batch 3/3 PASS。
- `174704_335_6132`：地面过滤隔离、地图编辑器网格与碰撞/点击/文档隔离 2/2 PASS。

上述新增回归及真正遗漏的持久化消费者已注册默认 critical，注册检查 PASS。最终完整 critical、APK身份/覆盖、设备帧率/触摸/听感仍单独记录，不把分批 PASS 合成为未执行的整体结果。
