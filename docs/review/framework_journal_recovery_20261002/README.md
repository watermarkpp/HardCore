# 旧 v2 备份恢复的事务身份修正

父提交 `4f65e01f09bfcaaaaa0b497bc72b85e182b00f90`。第三树13个源码/测试增量，生产代码仅journal、port、PlayerState三个文件。主树v97、第二树、真实存档未改。
受测3523文件内容SHA256 `95ff6265376ec96656b09f6c13141782c6eb7dc58f22134f9d529e3aad490b01`；引擎 `4.7.stable.official.5b4e0cb0f`，SHA256 `d8055fb8c7e7f5010d7439ec69be051554055dae55a265f8647bd7301c34161c`。
完整原生源码ZIP SHA256 `7cff17817308264aef9c1083cd3aef9a0f8b19f4b0588843dd408251e9c873ee`；另含两个原有wrapper工具，Git文本可CRLF/LF归一，ZIP保留受测原字节。

## 原生反例与最小协议

真实端口连续完成2或130次镶嵌/取出，然后把同一隔离角色的有效v2 checkpoint1或65作为.bak并损坏主档。正式load_save恢复后，旧实现重新接受原ID2或66为replay=false，再次创建writer并改变恢复后的物品状态。同进程和独立cold各10个业务FAIL，零引擎错误；cold seed14检查PASS并由runner绑定。本报告不称用户真实档已经资产增殖。

既有备份恢复入口现在将恢复物品与新的随机epoch通过原临时文件校验/原子提升一起持久化，再允许载入。使用明确 `hc.item.transactions.v3` / schema3：健康v2不重写，v2/schema3仍未来terminal。v3保留原legacy最多64条和最近序列最多64条、连续序号及水位；最近窗口允许不同epoch，每条序号必须匹配连续位置。新提交只接受当前durable epoch的下一序号，旧epoch缺失结果一律拒绝；完整保留结果仍精确只读重放，换请求仍冲突。再次从v3备份恢复也关闭旧epoch。无TTL/LRU、第二writer、额外持久化权威或简单清空历史。

恢复期间temp写入/校验/提升不成功时保持拒绝。原有load_save生命周期入口先排空已有writer；旧plan完成回调仍只能持有当前job才能发布。新协议沿用原16字节Crypto身份生成，失败或命中可见旧epoch明确拒绝。

## 最终同源码验证

23原生场景PASS，22framework场景1018完整检查，另1旧assert场景不计入1018。native exit0，零引擎错误，所有source before/after与引擎一致。完整命令、场景ID、run/invocation、receipt、cold成功producer关联、日志及指纹在RUN_INDEX和各子目录。

- 同进程61检查：2→1、130→65、旧ID换请求、无新writer/资源/文件变化、保留结果重放、新意图继续、迟到旧回调、v3再次恢复、临时文件open失败和解除后恢复。
- 序列31检查：原64条opaque结果、130健康序列、恢复后的混合epoch窗口跨68个新操作、退休/未知版本/缺口/错误身份。
- 独立seed/cold/restart：cold实际消费本轮成功seed的腐损主档与旧v2备份；再一进程证明新epoch和完成结果持久化，而非内存签发缓存。
- 健康主档130事务/live-cold131、无序列旧备份、物品codec/资格/仓库/未来版本、非空generation、合法退出及迁移回归。
- 默认root启动前旧档与v90原归档复制件均live/cold PASS；原归档及13个参考文件哈希保持。v90不替代精确v97角色B。

第一轮同进程业务RED有效，但并组seed被同账号重名阻塞、cold有变量重名解析错误，均保留。随后独立账号修正后的正式RED才作为cold缺陷证据。首版生产修正对JSON容器int/float直接比较而误拒绝临时读回，保留FAIL；改为写入文本逐字核对及正式validator后通过。未弱化业务断言。

## 边界与后续

该修正覆盖系统支持的损坏/缺失主档→有效备份恢复；不声称检测外部把有效旧文件直接替换为健康primary的任意人工降档，也没有外部单调存储。故障注入为temp open；磁盘物理掉电及恢复中强杀进程NOT_RUN。
Pro已支持关闭父4f65两项释放缺陷；其建议的未关闭producer重复内部规划、batch建立失败分支补证作为下一独立小项。完整P6/R3自然输入、移动战斗、持续恢复继续开放。原v97角色B输入MISSING；Android/GPU/设备、主树集成/APK NOT_RUN。本次不新增玩法、物品/技能/怪物ID，新增版本化协议ID如上。
