# Journal64 恢复与真实非空世界代次

父提交 `a41a655e81a63a2be091263a405f5d88b2495896`。仅第三树15个源码/测试文件增量；主树v97、第二树和真实存档未改。
受测3510文件内容SHA256 `d9cf182d1b295a0c8d4472fa096f3554d46f98ffc1787d01247338977c92dd6b`；引擎 `4.7.stable.official.5b4e0cb0f`，SHA256 `d8055fb8c7e7f5010d7439ec69be051554055dae55a265f8647bd7301c34161c`。
完整原生源码ZIP SHA256 `1f92d3e8e1935e22ef58b600967386432b53afd86e7a9deefeb74620efd5f4df`，另含两个原有wrapper工具。Git文本可有CRLF/LF归一，ZIP保留受测原字节。

## Journal64 — PASS（新序列协议范围）

旧v1任意字符串身份的64条完整结果全部保留，旧协议满额仍拒绝新身份。新 `hc.item.transactions.v2` 由同一事务端口quote签发 `hc:itemtx:<epoch>:<sequence>`，第一次提交把序列、水位和物品所有权通过既有角色writer原子写入。最近64结果保留；退休水位永久拒绝旧序号，不冒称仍可返回已退休详细结果。没有TTL/LRU、第二writer或独立持久化权威。

真实130次镶嵌/取出，保持原64条v1记录，最后64条v2结果及retired_through=66；独立冷启动恢复同epoch并完成131次。覆盖重复点击、保留旧回调、旧ID换内容、错误epoch/序号、取消、跨world generation旧quote、完成结果重试和全部队列排空。每次最近结果退休时，旧生产者已失去通过序列门禁再次产生工作的资格；旧异步回调只在仍持有当前job时有内存发布权。

RED记录：缺失序列入口；quote新增operation_id使用StringName导致plain图部分捕获而丢ID；同进程旧备份恢复后临时epoch复用。分别补正式签发、完整捕获成功判定和完成后撤销临时签发权。未来schema3与损坏已知物品及有效旧备份混合仍terminal，旧文件保持。

## 非空generation — PASS（真实生产导入与cold）

通过生产load_save处理新建隔离角色的旧clock格式，实际准备路径生成非空代次，不直接给运行时字段赋值。live24/cold13验证档案原字节与语义、正式主档/备份/world ledger、错误代次明确拒绝和独立进程恢复。cold由本轮native成功receipt、runner关联、源码和producer ID绑定。

## 最终验证

同一最终源码15原生场景PASS：12相关、2真实连续事务live/cold、1独立旧备份负例；765完整framework检查，另1原有assert场景不并入765。全部native exit0、源码前后相同、零引擎错误。连续事务重场景60秒，其余30秒。完整命令、receipt、run ID、关联、日志、指纹在RUN_INDEX和各目录。

一次混合suite有9PASS/4FAIL：负例故意保留future档，后续正常启动测试共用该隔离账号，跨profile所有权校验拒绝为invalid_shared_warehouse。原始失败保留；改为各组独立账号后同源码通过，未改变生产逻辑或弱化断言。

## 尚未关闭

Pro刚返回父a41审查，发现带票据烈火在内外两层重复begin_release以及错误release ID拒绝传播缺口。此独立journal/D增量不宣称修复它们；下一项优先原生反证并修复。父提交的冰咆哮预留及受管receipt结构证据保留。
完整P6/R3自然输入、移动战斗、持续与恢复性能继续开放；Android/GPU、写入中强杀进程矩阵NOT_RUN；精确v97原角色B输入MISSING。新角色和v90不能替代原故障因果验收。无主树合并、APK或设备验收。
新增稳定协议身份如上，无新增物品、技能或怪物ID。模块保持default-off。
