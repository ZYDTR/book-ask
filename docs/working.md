# 工作记录

## 当前 Delta 入口

- 2026-09-20 右上角固定位置已安装并验证，网关模型只读核对结果见 [位置 Delta](../deltas/reading_panel_top_right/PRD.md)。

- 2026-09-19 主 Agent 已接手未完成验收，当前代码、受控安装与阻塞状态统一见 [Delta TEST](../deltas/books_selection_copy_and_focus/TEST.md)。

## 2026-09-18 Delta 文档入口

- 按用户要求仅补自动复制取词与窗口交互的增量文档，入口为 [README](../README.md)，唯一当前状态与下一步见 [Delta 索引](../deltas/INDEX.md)。未改代码、构建、安装、运行验证或回灌长期合同；下方既有实施记录保留。

## Changelog

### 2026-09-18

- 按 project_scaffold skill 创建本地私人项目骨架；用户已明确本地 Repository。
- 确认原书正在 Apple Books 打开，现位于 Introduction 第 3 页。
- PopClip 未安装且属于付费产品，采用免费系统服务与原生浮窗。
- 已定位既有 LiteLLM URL 和凭据 locator；配置含 Gemini 3.5/3.7 Flash，实际可用性待测。
- 以真实 `/models` 确认 Gemini 3.5 Flash 与 3.7 Flash，配置选择 `gemini-3.7-flash`。
- API streaming smoke PASS：首段与完整回答约 5.99 秒，解释 `you're liable to`；实际答案见 `evidence/api_smoke.json`。这只是网络测试，不是图书 UI 验收。
- 已生成 1132 段纯英文上下文索引，中文词汇脚注排除，Introduction 真实书页段落唯一匹配 `OPS/body1.xhtml#2`。
- 已构建并安装 `~/Applications/读书提问.app`，pbs 注册读书提问服务与 `E` 快捷键。真实菜单和快捷键待 UI 确认。
- Offline PASS：2 项 EPUB 解析测试与 6 项 Swift 上下文断言。
- Computer Use 读取到 Apple Books 中 The Mom Test 第 3 页，但截图与后续操作被系统锁屏阻断。已通知用户解锁；尚未通过拖选、服务接收、实际回答和连续追问 E2E，不能宣称完成。

## Lessons Learned

- Apple Books 的实际 bundle ID 是 `com.apple.iBooksX`。
- API 凭据只读既有文件，不能回显。
- 本书注释 EPUB 的 spine 引用一个不存在的 `OPS/body.xhtml`，索引生成会明确记录缺失；不修改书籍。Introduction 正文位于 body1，目标段落存在。
- 主线程仅处理小型本地文本与 UI；URLSession 异步流式请求，取消后用 generation ID 隔离过期响应，SSE 提前结束或长度截断不标成功。

## 2026-09-18 解锁后与交互修订

- 真实 Books 页内已选中短句，截图可见；本机 Books 未显示文本服务。
- 复制即问未通过 E2E，且用户要求无 ⌘C，已完全替换为辅助功能划选读取。
- 用户已亲自开启辅助功能，应用确认已授权。
- 新版已编译安装：划选稳定后聚焦问题输入；只有发送时调用模型；仅响应前台 Books；无剪贴板监听或合成按键。
- 离线 PASS：2 项 Python、9 项 Swift 断言。
- 正在验证前台激活、真实选区自动弹窗和回答，尚未通过 E2E。
- 更新本地 ad-hoc 签名构建后，系统设置保留旧条目显示已开启，但新版 AXIsProcessTrusted 仍为 false；切换开关与重启没有解决。已请用户在系统 UI 移除旧条目并重新添加已安装应用。未修改 TCC 数据库、未绕过系统权限。
- 原版本已真实通过原书选区 → 自动窗口 → Gemini 首轮回答（2026-09-18 13:43:11，6.06 秒），无需复制。记录含唯一匹配的三段上下文。随后发现换行问题并更新程序，导致签名变化、授权再次失效；用户也报告当前划选无反应，不能把旧版本成功当成当前版本通过。
- 已冻结当前二进制，优先恢复当前版本划选与对话验收；系统授权更新正在等待触控 ID，用户明确授权由 Agent 添加同一应用。暂不继续界面修改。
- 用户报告划选仍无反应时，对应日志明确为 booksInForeground=true、accessibilityTrusted=false。使用 macOS 官方 `tccutil reset Accessibility com.zydtr.book-ask` 仅清理本应用旧批准状态，再通过系统设置恢复用户已确认的同一权限；没有直接写 TCC 数据库。
- 进一步复测发现 Books 切换焦点时短暂返回空选区，导致返回原书又弹同一句；已修复为保留最近接收文本。当前最终构建在 14:01 重新安装并通过系统 UI 授权。
- 最终版本原生选区检测 PASS：14:01:44 收到 `The truth is down there somewhere, but it’s fragile.`；返回原页后至少 1 分钟未重复触发，之后切换另一真实选区 `you’re liable to smash it into a million little pieces` 再次自动弹窗。
- Computer Use 的鼠标 drag 在本机遇到 AXError.noValue；最终稳定验收使用 Books 原生 selectText 选择实际书页文本，截图可见真实选区，未向应用注入伪文本，也未使用复制或粘贴。更早鼠标拖选得到真实片段 `fragile. While each blow with your shovel gets`，已由应用自动接收。
- 最终版本真实首轮 API 回答已显示在 UI。连续追问正在验收；用户的直接鼠标使用反馈待回。按用户要求，视觉排版暂不作为本轮继续迭代项，不宣称排版问题已完全修好。
- 最终版本连续追问 PASS：同一 session 的 turn 1/2 都已完成、且原生窗口中可读到真实内容。完整去密结果、耗时、当前安装二进制 SHA-256 见 `evidence/ui_e2e.json` 和 `evidence/ui_transcript.md`。所有证据再次通过实际 Key 扫描。应用保持运行；没有提交 Git 或发布。

- 用户实际操作进一步确认：Agent 停止选区操作后，新收到 `s down there somewhere, but it’s fragil`、`a bulldozer` 和完整条件句三个选区；用户点击解释表达后，第三次真实 Gemini 回答已在原生窗口核对。此前“用户手动反馈待回”更新为已观察到真实手动使用链路（文本确认尚未收到）。

## 2026-09-18 提示词 review 与横向滚动修复

- 用户确认核心划词接近完成，要求审阅按钮提示词，并保证窗口任意缩放时仅可竖向滚动。
- 提示词逐条读取，全文、按钮映射及建议见 docs/prompts.md；没有擅自替换线上提示词。
- 离屏真实 AppKit 回归复现根因：初始宽度 0 的 NSScrollView 中放置宽度 540 的 NSTextView，Auto Layout 扩大视口时保留多余 540 点宽度；578 点视口对应 1118 点文档，并可横滚到 x=180。
- 将两者初始宽度对齐，文本容器随视口变化，禁用横向滚动条及横向弹性。共用组件同时修复原文与回答。
- 修复前 FAIL、修复后 PASS：500/610/1000/1500 点多次缩放，中文、英文、超长无空格 URL 和流式增量替换；断言文本不越视口、水平滚动约束为 0、长文可竖向延伸。测试接入 scripts/test.sh。当前尚待安装后的真实界面验收。
- 新版已构建安装，使用官方 tccutil 对本应用刷新原有辅助功能授权，再在系统设置开启同一权限；日志已确认 accessibilityTrusted=true。没有更改其他应用权限。
- 最终安装版本在 14:20:56 实际收到 Books Introduction 中以 `While each blow with your shovel` 开头的 153 字符选区，关联同一段及前后文。此前自动化后台选字不能满足前台门控，已请用户将图书切前台；未绕过该门控、未注入伪选区。
- 14:21:37「解释逻辑」真实 Gemini 3.7 Flash 回答完成，耗时 5.303 秒，原生窗口内容已核对。
- 真实布局验收 PASS：500 点窄窗口原文/中文回答自动换行；对原文向右滚动、回答向左/向右滚动均不横移；竖向滚动条从 1 到 0，正文随之上下滚动。通过拖动右下角扩大窗口（截图由 500×575 变为 572×733），正文重新排版且完整显示。保持应用运行、回答可读、输入框可继续提问。
- 本次提示词仅审阅未改写；全文与候选见 docs/prompts.md。当前安装二进制与构建产物 SHA-256 一致，证据见 evidence/layout_fix.json。未提交或发布。

## 2026-09-18 单一自动解释模板与默认尺寸

- 用户选定当前外框 500 × 539 点（原生截图与 NSWindow Frame BookAskPanel 一致），改为每次启动的默认尺寸，保留已保存位置。
- 自动解释默认开启，与选区读取解耦；关闭时继续显示新选区但不发请求。切换开启只影响下一次新选区，避免重复调用。
- 提示词置于窗口上方，可编辑并自动保存；开关也持久化。空模板不自动发送。
- 初始模板采用简单英文释义 + 同表达新例句，避免无关比喻；系统不再强制中文和 180–300 字。
- 移除原来的两个解释预设、复制回答、回到图书；发送/停止合并同一个按钮。辅助功能入口移到菜单栏。
- 离线解析、上下文、横滚回归通过；已构建安装并恢复同一辅助功能授权。窗口截图确认 500 × 539，正进行自动发送/关闭/模板持久化的真实 UI 验收。

- 用户进一步要求模板收起，仅编辑时展开；已增加右上编辑/收起入口，默认隐藏编辑器，展开不改变窗口尺寸。
- 已明确说明本机 history.jsonl 保存选区、实际提示词/追问、完整回答、模型、时间和上下文，不记录 Key；失败或取消保留事件，不冒充成功答案。
- 首次自动英文模板实际响应夹杂 Markdown 与中文，已收紧为全英文、两个简短自然段（释义 + 同表达例句），等待最终安装构建复测。
- 设置持久化 PASS：通过原生 UI 增补模板并关闭自动解释，窗口临时拖至 505 × 632，退出重开仍保留模板和关闭状态，并恢复 500 × 539。随后恢复初始模板，再按真实回答质量收紧语言与格式要求。
- 关闭开关 PASS：真实选区 `The truth is down there somewhere, but it’s fragile.` 进入窗口，session 09ECCF7F-5EAC-4979-961C-806383C0220D 没有 request_started/answer；关闭时正在生成的自动请求也正确 cancelled。
- 最终安装版 SHA-256：48c54ffff65b029b3276c86404b6842a60ee6b297c19e8b08fed74d1566d8774。已恢复同一辅助功能授权，截图确认启动默认收起、展开/收起不改窗口尺寸。
- 最终构建真实自动链路 PASS：14:37:52 收到原书 `too blunt an instrument`，自动使用收紧后的已保存模板，14:37:59 完成真实 Gemini 回答（7.125 秒）。实际 UI 核对为两段英文纯文本，释义加同表达例句，无 Markdown 或中文；500 × 539 内完整换行，横向滚动操作不移动内容。
- 最终构建连续追问 PASS：通过输入框回车，回答 `This is too heavy a box to carry alone.`，同一 session 两轮记录均已保存。模板保持收起，自动解释开启，应用运行中。
- 真实去密证据见 evidence/automatic_ui_e2e.json；区别记录了前一构建的关闭/持久化测试与最终构建的自动回答和追问，没有混用版本。源码、文档和证据再次检查不含实际 Key；没有提交或发布。
- Computer Use 前台经验：Finder 打开 Books 后，若立即对其他 App 读 AX，可能令 Books 仅短暂前台，来不及稳定选区。把 Finder 打开动作留作该次 UI 工具调用最后一步，随后处理非 UI 文档工作，可让真实检测与自动请求顺利完成；无需调整前台门控或选区防抖。

## 2026-09-18 取消全局置顶

- 用户指出窗口始终盖住其他应用；代码确认为 NSWindow.Level.floating + canJoinAllSpaces。
- 改为 normal + moveToActiveSpace，保留新选区触发时前置、500×539 默认大小、模板收起和自动解释行为。
- 新版已构建安装并刷新本应用原有辅助功能授权。增加 window_policy 启动诊断，核对实际窗口层级。安装版运行日志已确认 level=0、joinsAllSpaces=false，辅助功能已恢复 true，构建与安装二进制一致。证据见 evidence/window_policy.json。Books 阅读窗口在测试中发生切换，本轮没有重新完成模型回答链路，不沿用旧版结果宣称本轮全链路通过。

## 2026-09-18 选区不弹出修复

- 用户报告普通窗口版划词不弹出。旧版只验证 level=0，不足以证明链路可用。
- 增加临时诊断后，权限 true、AX 根节点读取成功；起初 Books 画面选区与 AX 空范围不同步，重启 Books 并恢复同一本书和原阅读位置。保留黄色高亮与中文脚注。没有把重启推断为已确认的软件根因。
- 之后诊断连续实际读到 bulldozer（9 字符），同时 booksInForeground=false。旧代码在读取前后按前台判断丢弃，此阻断已确认。
- 改为仅观察 Books 的真实新选区；SelectionTrigger 以后台启动基线、稳定 400ms、鼠标松开及去重防止旧选区误发。增加 AX 通知与 common timer 兜底；Books 前台期间保持用户请求的监听活动，仍允许系统休眠。普通窗口 level=0 和 moveToActiveSpace 保留。
- 回归已接入 scripts/test.sh：新选区在 false 前台状态下仍触发；旧门控反事实稳定失败。上下文、EPUB 与横向滚动测试全部通过，Swift 构建无警告。
- 关闭临时诊断，安装二进制 SHA-256：cfe76dc1cab9cef7aa5cd1a39e4af1242593b8ec13f03687473897120edde127；与 build 一致，刷新同一辅助功能授权。
- 15:15:22 fragile 真实选区自动触发，Gemini 3.7 Flash 4.903 秒返回英文释义和例句；同一 session 4F4BCC21-89F5-4BCC-A386-6EA0F9F7AA8F 手动追问 2.882 秒完成：Be careful, the glass is fragile. 已在原生 UI 核对。
- 关闭自动解释后，too blunt an instrument 真实选区进入窗口，没有 request_started/answer；恢复开关后新选择 you’re liable to smash it into a million little pieces，6.677 秒真实自动回答完成。
- 15:17:12 另收到前台 Books 的 pieces 选区（非本次 Agent 选择动作），3.396 秒完成自动回答。继续保留运行状态、自动开启、模板收起、500×539 窗口。
- Computer Use 的原始 drag 在 Books 中未可靠建立选区，本次确定的自动化证据来自 Books 原生 selectText 与右键选词，实际高亮、AX 数据、应用原文和真实 API 回答均吻合。未用伪选区/固定回答冒充端到端；跨 Space 全屏前置与长时间后台休眠不宣称已覆盖。证据：evidence/selection_recovery_e2e.json。无 Git commit、无远端或发布。

## 2026-09-18 全屏往返失效调查（未修复）

- 用户真实反馈：候选版本在全屏划词、退出全屏划词都没有弹出。不得把此前普通窗口成功算作本问题通过。
- 当前候选增加 normal 层级的 nonactivatingPanel / canJoinAllApplications、Space 与窗口模式变化后重连 AX observer、逐元素超时、导航子节点与鼠标位置补查。Swift 编译和既有离线回归通过，但上述修改没有解决用户的全屏往返问题。
- 15:51:50（本地时间），重新打开同一本书的阅读窗口后，原生右键选中 fragile，应用真实接收并在 4.671 秒获得 Gemini 3.7 Flash 回答，原生 UI 已核对。
- 随后再次通过 Books「显示 → 进入全屏幕 → 退出全屏幕」，原生右键选中 bulldozer，截图清楚可见灰色选区；15:53:12–15:53:27 AX 根节点读取成功、完整遍历结束、所有选区范围为 0、selectedText 为空，未产生 selection_received。读取循环并未停止，授权仍有效。
- 同时观察到全屏后 ibooks:// 链接子节点消失，退出后未恢复；重新打开阅读窗口可恢复这些子节点与选区读取。这是可重复关联和临时恢复方法，不足以证明 Apple Books 内部根因，也不应自动关开用户书籍冒充修复。
- 未证明系统有永久禁止；Apple 提供可加入其他应用全屏空间的窗口行为。当前阻点是 Books 暴露的选区与实际画面不一致，仅调整浮窗不能完成需求。原生全屏截图在工具中缺字/黑屏也限制了全屏内自动验证。
- 保留故障证据 evidence/fullscreen_investigation.json。真实全屏兼容性状态为 FAIL，不能发布为已修复。没有提交或远端发布。

- 最终临时恢复再次确认：关闭并重新打开同一阅读窗口后，15:55:02 bulldozer 实际收到，15:55:07 Gemini 回答完成（4.376 秒）；恢复到普通窗口、自动开启、提示词收起。已关闭详细读取诊断。构建与安装二进制一致，凭据扫描通过。全屏兼容仍标记 FAIL。

## 2026-09-18 词本入口

- 用户要求界面直接查看词本。在主窗口上方、应用菜单和菜单栏小图标菜单加入「词本」；主问答窗口继续 500×539、提示词收起。
- 新增原生词本窗口：左侧最近词句、搜索，右侧完整解释和历史追问；同书同词句合并，保留每次划词时间与会话。词本直接读本机 history.jsonl，不迁移、不修改既有记录，打开与搜索不请求 API。
- JSONL 在后台读取，诊断行和未完整写入的尾行跳过，取消/失败不虚构答案。真实历史读取已有 16 个词句；以后 selection_received 显式保存书名，旧数据使用本书配置补齐。
- 已加入解析测试：跨会话交错答案、重复词、不同书、未回答/取消、尾行截断、大小写搜索；实际本地历史旧 bulldozer 回答保留。
- 原生首次视觉验收发现内容视图缩成 59pt、列表和详情仅 1pt；复用 NSWindow 自带内容视图并降低竖分隔线 hugging 后，离屏布局恢复到 560pt 内容和 502pt 列表/详情，加入 640/800/1000pt 真实 AppKit 回归。

- 最终安装原生 UI PASS：词本完整 800×588 外框，搜索 fragile 展示两次划词与历史追问，无结果与清空恢复通过；16:08:46 原书真实选中 shovel，Gemini 4.176 秒回答，词本增至 17 项并实际点开核对完整答案。提示词保持用户最新音标版本、未覆盖。权限已恢复 true、诊断关闭。证据 evidence/wordbook_ui_e2e.json；构建/安装一致、凭据扫描通过。全屏兼容性旧问题未变，不列为本次已修复。

## 2026-09-18 选区错词与持续诊断

- 用户截图明确高亮 bulldozer，但显示 er, forci。先保存用户原截图与修改前 history 到 evidence/selection_mismatch_20260918；旧记录 16:22:52 her, forcin、16:23:01 er, forci 均发生于 API 请求之前。旧版缺少选区节点和范围，无法从旧日志独立确认更早一步。
- 新增默认持续诊断：独立串行队列、毫秒时间、运行/二进制/样本/会话/请求关联、原始/显示/请求选区、AX 来源与范围/附近正文、触发决策、鼠标与全屏变化、API 状态；30 次样本预触发缓存；6×10MiB 轮换、0700/0600、凭据脱敏。词本历史不轮换。
- 增加应用菜单及顶部「书问」菜单的「记录划词问题并打开日志」，保存独立 incident 并打开 Finder；已实际点击，应用确认现场保存成功。
- 对未重开的故障书页采样：AX 静态文本属于下一段 They are…，location=29/length=9、AXSelectedText、AXStringForRange、AXValue 相同范围都为 er, forci；可见画面为 bulldozer。CUA AX 也返回下一段，与截图冲突。
- 重新打开阅读窗口后真实右键选择同一 bulldozer，日志中相同范围对应正确段落，真实答案完成。两种情形的 BoundsForRange/VisibleCharacterRange 均零，不将其错误地作为拒绝规则。故障根因仍未修复，恢复不冒充修复。
- 读取范围优先 Books 事件/焦点/阅读窗口，命中点仅允许同 Books PID；不读取其他应用的命中节点。新手势清掉待稳定候选，读取期间手势变化丢弃旧结果。未通过语言猜测替换原选区。
- 测试入口新增日志预触发完整性、脱敏、关联字段、毫秒时间、权限、轮换、incident 保存；补充稳定区间不得跨手势延续的断言。历史、词本与布局回归仍通过。

- 最终安装版日志链路实际验收 PASS：原书 fragile 真实选择、界面原文、AX 原始文本与请求 selection 一致，selection_received/request_started/HTTP/first_content/answer 用同一 sampleID 串联，请求阶段 requestID 一致，预触发 30 次样本存在；二进制匹配、真实 Key 全文件扫描干净、目录/日志权限正确。已默认持续开启。证据 evidence/selection_mismatch_20260918/diagnostics_e2e.json。

## 2026-09-18 Books 自动复制取词与窗口前置（Delta 进行中）

- 当前 Delta 的方案、实现与验收状态只维护在 [deltas/books_selection_copy_and_focus/](../deltas/books_selection_copy_and_focus/PRD.md)（PRD/RFC/TEST），实施记录与证据见 evidence/books_selection_copy_and_focus/run_20260918a/；本行仅为导航，不复制进度。


## 2026-09-20 收起交互、划词反侧定位与模型比较

- 本轮收起交互实现、原生验收边界与真实 15 次 API 比较统一见 [对应 Delta](../deltas/reading_popup_dismissal_and_model_latency/PRD.md) 和 [TEST](../deltas/reading_popup_dismissal_and_model_latency/TEST.md)；本行仅导航。

- 用户确认换边可用后授权保存当前版本到个人私有 GitHub；首次 Git 快照的远端与执行绑定见 [Delta 索引](../deltas/INDEX.md#个人-github-快照绑定2026-09-20)，原始私有证据保留本机。

## 2026-09-20 菜单栏常驻

- 移除 Dock 图标的实现与验收统一见 [menu_bar_app Delta](../deltas/menu_bar_app/PRD.md)。窗口视觉重做当前仅讨论。

## 2026-09-20 纸感视觉重构

- 用户随后授权按纸感颜料Skill重做真实UI，浅暗主题的当前需求与验证见 [paper_reading_ui Delta](../deltas/paper_reading_ui/PRD.md)。

## 2026-09-20 精确词条复用

- 当前行为变更、旧记录清理与验证统一见 [wordbook_exact_cache Delta](../deltas/wordbook_exact_cache/PRD.md)。
