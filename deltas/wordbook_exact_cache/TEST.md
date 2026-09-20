# 精确词条复用验收

当前安装二进制SHA-256：`8189ef9d5876f16b25bf4f999dcd2644cc4b33bb204aea16d15af989a6c13de2`，与build一致。HEAD仍为8ea90000…，本轮未提交/推送，既有Dock/浅暗UI dirty改动完整保留。

## 代码与请求验证

`zsh scripts/build.sh`、`zsh scripts/test.sh` 均退出0。新增/重写的测试已进入统一入口；预期旧行为反事实报FAIL，入口只在其错误地通过时失败。build/tests原始输出位于evidence/wordbook_exact_cache_20260920。

| 断言 | 证据与结果 |
| --- | --- |
| 一个精确term一条 | wordbook.swift检查大小写、标点、内部空白保留差异；跨书同term仍一条。旧多次初始释义只取最新完整一份，较新失败不覆盖成功，历史主动追问保留。PASS |
| 重复选词零请求 | wordbook_cache.swift调用真实BookAsk.receive/send，隔离文件与URLProtocol统计HTTP；首次已有fragile为0，A→新B→A总计仅1，空发送不增加，关闭自动解释仍读取缓存，重启后读取本地解释及追问不增加。PASS |
| 主动追问 | 恢复历史消息后输入问题，仅新增1次请求，同一词条保留初始解释和追问。PASS |
| 异步与错误边界 | 先选A立即选B，A的旧查询不能覆盖B；同词生成中重复不另发；半截SSE、取消不生成缓存；损坏词本读取及重试不向模型放行。PASS |
| 可恢复迁移 | 隔离目录测试首次原样备份、重复启动幂等、原审计历史保持不变；损坏数据不覆盖，原子写失败不污染内存缓存。PASS |
| 回归能够捕获旧行为 | --old-no-cache以原先直接ask方式绕过查词本，实测FAIL于已有term零HTTP断言，正常路径PASS。不是只测字典查找。 |
| 既有交互/样式 | 全部选区/Copy事务/竞态/收起/计时/反侧位置、词本布局、浅暗主题和禁止横滚回归通过。 |

上述请求测试全部使用隔离目录、测试凭据和进程内模拟SSE，未访问真实模型、未写用户history。它验证实际产品调用链和HTTP次数，但不冒充真实Books手势或网关E2E。

## 实际本机数据与原生界面

更新前CUA实际看见bulldozer的3次划词与三份释义。更新后在真实词本搜索并点开bulldozer，仅显示一份完整解释；列表不再显示“几次划词”。原有暗色纸面和文字布局正常。窗口首次切换发生一次AXError.failure，后续取树/搜索/选择/截图均正常，应用未异常。

实际迁移得到33个唯一词条、26份完整初始解释和5条有效追问；旧history共46次选区会话，7个term重复，多出的13次会话不进入词本展示。新版wordbook.json与迁移前独立预览逐字段一致，权限0600，原历史只作为审计材料保留。自动备份：
`~/Library/Application Support/BookAsk/backups/history-before-unique-035EB320-4608-4CD2-B405-82167C2E5201.jsonl`

本机证据包括baseline/、previous.app、history_before*.jsonl、migration_preview.json、migration_result.json、wordbook_after_migration.json、verification.json。凭据实际字节扫描通过；新模型请求仍用原配置和用户Prompt。

权限已恢复：06:10:30.619Z日志accessibilityTrusted=true。已请用户在Books实际划bulldozer→crate→bulldozer，当前该真实输入链路仍待验证；自动化拖动不进入Books的OS全局手势监视器，所以不以伪输入或直接调用receive冒充物理E2E。

## 回滚与覆盖边界

旧安装包和迁移前源文件已保存在本机evidence。回滚应用即可继续读未改写的history；新版wordbook.json和backup保留可恢复，不要直接删除用户数据。没有更改Books文件、数据库、输入法、模型/网关设置或Git远端。全屏/物理多屏等旧未覆盖边界继续保留。

当前结论：代码、请求次数、数据清理与原生词本已通过；本包真实Books缓存命中链路待用户操作。

## 用户接受与快照推送

用户随后明确确认“这个版本已经很不错了”，要求先推送当前版本，再改词本为同窗导航。8189ef9d…真实运行还记录了2026-09-20T07:49:35.436Z对instrument的cache_miss，随后请求并于07:49:40.924Z完成回答；这是新词的真实Copy/API链路，不能代替重复命中验证。重复命中已有隔离HTTP计数回归，三次真实手势仍未单独核对；用户按当前版本接受并授权保存快照，原边界如实保留。
