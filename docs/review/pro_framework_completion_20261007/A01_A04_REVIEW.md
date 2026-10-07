# 架构逐项复查：A01—A04 已修复切片（不是全项目验收）

基线：761c00c5c3a4ae436f99bdd20d99a627c2ffae88。仅原第三树，无APK/设备构建。
规格：原RFC全文及CURRENT_PRODUCT_CONTRACT_20261005；同种DOT完整替换，新施加时钟、来源与期限，显式独立层才叠加。

## 本次实际闭合

- A01：排队后首次施加错误沿用旧fact时间，缩短完整期限。原23检查7FAIL；改为实际simulation应用时刻后同23PASS，历史fact时间不改。
- A02：替换状态继承旧chain_owners，反复替换永久保留无剩余工作root。原64检查31FAIL；新实例只持自己的状态owner，旧根有其他状态或已接受child仍保持，最终64PASS。两份旧测试仅更新已经被用户新替换合同否定的多根共享预期。
- A03：同句柄新Cue继续持有旧资源及音效，并存在同步通知返回清理新owner风险。原有效27检查8FAIL；原Presentation端口新增精确onset身份、旧owner先脱离、受控资源替换，最终27PASS。早期parse失败单列，不冒充功能RED。
- A04：逐目标预留按source handle而非认证species/layer，既误拒合法普通替换，也漏掉同handle不同已接受独立层。有效RED执行93检查9FAIL；GREEN执行101检查全通过。测试字节相同，差8是旧拒绝使业务分支未执行。17层饱和仍在HP前拒绝；未变16槽、8192空间、1200us和正式数值。

## 最终同内容相关验证

15场单项调用、15完整framework回执、1081检查，原生exit0、无timeout，内容e296fce17c01822770eaf92149bee35b23689cabca113c50e1f2b2948f5e74e9；每轮SOURCE_BEFORE/AFTER相同。受测时HEAD仍为基线且有已声明候选dirty，不能写clean checkout实跑。

包括四直接场景、完整trifold/child准入、周期callback退休、frame budget139、旧life/状态贷款、周期时域、mixed380、真实二代Root周期child27、Cue音频/attach重入及空扩展生产。原生回执见A01_A04_RESULTS.json和证据ZIP。

RED→GREEN文件集合差异：A01仅runtime；A02仅runtime；A03 runtime+presentation；A04仅runtime。未弱化原HP、planner、writer或释放时几何；未打包。

## 当前进度的计量边界

生产脚本清单358份（基线154459行）；本轮全文件静态阅读49份。其余仍NOT_RUN。52465 tracked路径大量为历史证据、素材或测试，不等于52465份生产代码。PRODUCTION_FILE_REVIEW.json逐文件记录实际范围，机械哈希扫描不当语义审查。

P0证据机制继承，本轮源/回执已关联；P1底座已读且预算139通过，但自然时效/原子量子和长期内存未闭；P2主要编译/lease已读，canonical非法请求返回和真实发布者退休仍有候选；P3本切片修复，不外推所有周期组合；P4出生视图已读，Root/Queue全调用链继续；P5 codec/port/journal已读，当前源正式恢复/混合写回归继续；P6模板、自然35秒/完整性能/物理平台仍分项开放。

候选B01：canonical入口拒绝非Dictionary后，拒绝builder仍request.get，需原生反证。候选C01：资源service物理exit清requests却不送终态，需正式等待者反证。候选不是已复现故障，不把缺文档推成实现缺陷。

## 保护与失败保存

无真实profile写入、无first/second树改动、无reset/stash、无APK。原分支bootstrap白名单失败保留，以实际HEAD/dirty/worktree/进程/隔离目录完成等价保护预检，未改白名单。A04早期错误测试属性及StringName键失败均原样保留；不作为有效业务RED。
