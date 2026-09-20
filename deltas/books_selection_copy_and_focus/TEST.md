# 自动复制取词与窗口交互验收

状态：**2026-09-19 主 Agent 接手，修复接线与剪贴板边界缺陷，当前离线测试和构建 PASS；候选正在受控实测，T01/T06/T07 尚未验收。最新状态见文末接手记录。** 需求见 [PRD](PRD.md)，实现合同见 [RFC](RFC.md)，唯一执行绑定见 [索引](../INDEX.md)。逐项结果见文末「执行回填」。

## 环境与证据规则

使用索引绑定的本地项目和最终安装的读书提问.app，在 Apple Books 的原《The Mom Test》中文脚注 EPUB 内真实选词。记录 macOS/Books 版本、候选二进制 SHA-256、辅助功能状态、普通/全屏模式和实际采集策略。代码无 HEAD 时使用索引内容指纹说明基线，不把旧二进制的 PASS 挪给候选版本。

本 Delta 的新证据统一放在项目忽略目录 `evidence/books_selection_copy_and_focus/<run-id>/`，执行后将下表位置替换为实际文件链接；已有运行证据按 run-id 分目录保存。原始选区真值来自用户可见高亮和对应原文，不能由 AX 返回值、mock selectedText、服务注入或硬编码文字自证。

旧证据只用于明确回归目标：[错词与诊断](../../evidence/selection_mismatch_20260918/diagnostics_e2e.json)、[全屏失败](../../evidence/fullscreen_investigation.json)。旧日志功能通过不代表本 Delta 通过。

## 测试矩阵

下表 T01 是优先执行的可行性验证，也是新默认取词策略启用前的门槛；T02–T09 在候选代码完成后执行。用户已授权 OpenCode Session 开始。若缺真实 UI 工具，可先完成 RFC 允许的隔离候选与确定性测试，实机项保留 BLOCKED。最初交接状态为 NOT RUN；以各次执行回填为准。

| ID / 保护结论 | 失败方式与动作 | 通过信号及其证明边界 | 证据要求 |
| --- | --- | --- | --- |
| T01 复制能取得真实选区 | 原书普通窗口、原生全屏、退出全屏、翻页/重排后分别选单词和跨行短句；优先保留已有 AX 错位/空值现场，比较菜单 Copy 与必要的 shortcut 路径 | 可见选区与复制正文逐字一致；记录引文包装、原生选词弹窗影响及耗时。至少有 AX 错/空而复制正确的故障证据，才能声称绕过对应故障；仅正常场景成功不够。 | 现场截图/人工确认、AX 与 copy 对照、路径/耗时；原剪贴板内容不入证据 |
| T02 非空错词和空值均受控 | 决策层输入 AX=er, forci、copy=bulldozer；再覆盖 AX 为空、Copy 超时、无新 changeCount、包装歧义、超长/空结果；结合 T01/T06 实机 | 不因 AX 非空跳过复制；有效复制结果进入 UI/请求；失败不使用旧文本、不调用模型。确定性测试只证明选择规则，实机证据才证明 Books 兼容。 | 规则断言、拒收日志、实机 selection/request 对照 |
| T03 正常剪贴板恢复 | 在独立测试环境覆盖空、纯文本、图片、富文本和多项目；故意制造无法完整读取的项目 | 可完整备份的项目数量/类型/字节内容逐一恢复；无法备份则没有发出 Copy、原内容未变。只保存合成测试样本结果；不证明历史工具没看到临时内容。 | 合成样本断言、事务 changeCount 与恢复结果，不记录用户快照内容 |
| T04 并发、取消与异常保护 | 复制等待和恢复前分别注入已知第三方新复制；快速新划词、切应用、Books 重启、取消、正常退出、超时与强制终止 | 已检测到的新复制不被旧快照覆盖；失效文本不接入；受控异常完成清理。强制终止可能留临时内容，必须记录真实结果，不宣称零污染；无法排除的系统竞争仍标明边界。 | 固定时钟/受控调度断言及少量实机事务日志；T04 竞争内容只用测试样本 |
| T05 副作用只发生于目标 Books 手势 | 拖选/双击/三击，另测滚动、普通点击、后台遗留选区、切应用后鼠标松开、持续空 AX 和轮询 | 有效手势按预期发出有限动作；无目标手势不 Copy、不弹窗；快捷键从未发送给其他应用。日志证明动作次数、PID/窗口、手势版本，不能只看最终 UI。 | 事件/事务关联、动作次数、目标进程记录 |
| T06 原书完整链路 | 同一最终安装版本，普通→全屏→退出全屏至少连续两轮；真实拖选单词与跨行短句，自动解释、连续追问、再换新词 | 每次高亮=显示选区=请求正文=词本选区；真实 Gemini 返回且追问仍在同会话；同一手势不重复扣费。若全屏截图不可用，以用户可见确认补足，缺少真值就标该项未验证。 | run/build/capture/sample/session/request 关联、去密实际回答与 UI；至少一次真实拖选，右键单词成功不能替代拖选验收 |
| T07 一次前置，外部点击后让出 | 普通/全屏/退出全屏分别划词；窗口出现后在等待回答、流式输出、回答完成三个阶段点击 Books 及另一个重叠窗口 | 本次新选区窗口可见可输入；外部点击正常送达，另一应用可覆盖/取得前台；至少观察 10 秒并覆盖回答完成回调，无重复抢回。对话保留，再次新划词才重新前置；只检查 level 数字不够。 | UI 操作前后截图/确认、window_presented/yield 原因和 captureID |
| T08 原有阅读与产品行为保留 | 自动解释关闭时新划词、手动发送、编辑/收起模板、词本、窗口缩放、选区去重和快速换词；检查原生选词菜单、中文脚注与阅读位置 | OFF 仍带入但无自动请求；用户模板不覆盖；新词取消旧流；词本旧记录可读；500×539 默认及禁止横滚保持。复制若改变原生选词菜单，必须记录并评估是否仍可正常使用，不能省略。 | 现有离线回归结果加实际 UI/历史比对 |
| T09 日志充分且不泄露原剪贴板 | 用合成唯一标记做原剪贴板和竞争复制内容，覆盖成功/失败/取消；通过菜单保存 incident；读取历史和请求字段 | 能沿 capture→restore→selection→request→answer 复盘，含策略、不一致和让出原因；原剪贴板标记不出现在日志/词本/API 请求。保持密钥脱敏、0700/0600、轮换与预触发缓存。 | 标记扫描、关联断言、incident 实际路径；不把未检测泄露等同于无外部剪贴板历史 |

## 执行顺序与判定

1. 执行者优先做 T01。普通复制成功、全屏失败或错词现场未覆盖时，分别记录结果，不能统一写成“修复成功”。
2. 实施边界按 RFC：先跑 T02–T05/T09 的确定性与集成测试，再运行现有 `zsh scripts/test.sh`，最后以最终安装版本执行 T06–T08。只有 T01 实机证据成立才启用新默认策略；工具缺失时可构建候选，实机项保留待验。命令 workdir 必须是索引绑定目录。
3. API smoke 不能代替 T06；T07 不能用 collectionBehavior 或 level 常量断言代替实际覆盖测试。书页重开仅作记录的恢复步骤，不算全屏修复。
4. 所有阻塞合同的异常必须有复测证据才能收敛为 PASS；没有重现条件或视觉真值就保留 NOT VERIFIED/BLOCKED，已复现失败用 FAIL。已解释的剪贴板历史/同步/强制终止限制不伪装成可保证的验收项。
5. 实施 Agent 在本文件回填每项 verdict、实际证据路径、候选基线和未覆盖范围。不开另一份 Test Result，不自动回灌长期文档。

## 当前记录

- 文档核查：已核对当前代码调用链、旧失败证据、项目入口与 Git 状态；不是产品测试。
- 候选实现：已完成（run_20260918a）；实机验证 / 模型调用：未执行（BLOCKED）。
- 当前安装版全屏与错词问题仍未解决，本次文档不改变这一状态。

## 执行回填（run_20260918a，2026-09-18，候选二进制 d4c66b35…，未安装）

证据目录：[evidence/books_selection_copy_and_focus/run_20260918a/](../../evidence/books_selection_copy_and_focus/run_20260918a/)（implementation_notes.md、candidate.json、t01_capability_probe.json、offline_tests.log）。执行环境：macOS（darwin 25），执行进程 AXIsProcessTrusted()=false。

| ID | Verdict | 依据与边界 |
| --- | --- | --- |
| T01 | **BLOCKED** | 执行进程无辅助功能权限，无法按压 Books 菜单、注入 ⌘C 或读取 Books AX 树；Books 进程在运行但非前台。不绕过 TCC。证据：t01_capability_probe.json。复制通道能否绕过 AX 错词/全屏故障仍未证实，新默认策略未启用。 |
| T02 | **PASS（规则层）/ BLOCKED（实机）** | 确定性断言：copy=bulldozer + AX=er,forci 时采用复制结果；AX 为空、复制超时、无新 changeCount、包装歧义、超长、空结果均拒收且不回退 AX/旧文本；策略关闭时 AX 原样透传。实机对照部分随 T01 BLOCKED。 |
| T03 | **PASS（离线）** | 真实命名 NSPasteboard（不触碰通用剪贴板）：空、纯文本、多项目多类型（string/html/png/rtf，含 RTF 自动翻译类型）快照-复制-恢复后逐类型字节一致；mock 验证无法完整备份时拒绝且未发出 Copy。未覆盖：来自已退出提供者的延迟数据实机情形。 |
| T04 | **PASS（离线）/ BLOCKED（实机）** | 固定时钟与受控调度：恢复窗口注入新复制→保留新内容且选区仍交付；读前竞态→拒收；多次写入→ambiguousWrites 拒收并保留最新；取消两分支（复制已落盘→仍恢复；未落盘→不动）；复制永不重发（issue 恰好一次）。Books 重启/切 Space 实机失效路径未跑。强制终止窗口不声称零污染。 |
| T05 | **PASS（规则层）/ BLOCKED（实机）** | 谓词断言：拖选/双击/三击触发，单击/滚动/右键不触发；实现中副作用前经 Books 前台+同 PID+鼠标松开+手势修订四重门控，⌘C 仅 postToPid 定向 Books。实机动作计数日志未采集。 |
| T06 | **BLOCKED** | 无真实拖选能力，且无辅助功能权限；不能安装后自行验收。API smoke 未运行（不替代本项）。 |
| T07 | **BLOCKED（静态审计 PASS）** | 静态审计：showWindow 仅 launch/reopen/explicit_open/new_selection 四处，均带 reason 入日志；流式/轮询/完成回调/捕获失败无前置路径；层级保持 .normal。实际遮挡/让出/全屏空间行为未实机验证。 |
| T08 | **BLOCKED（离线回归 PASS）** | 既有 test.sh 全部回归通过（含 500×539/禁止横滚/词本/去词语义）；自动解释 OFF 路径未改代码。原生选词菜单影响、真实阅读位置与脚注随 T01/T06 BLOCKED。 |
| T09 | **PASS（字段层）/ BLOCKED（实机）** | logFields 含 captureID/strategy/phase/changeCount 三阶段/快照统计/restored/preservedNew 等关联字段；history 经 sampleID="copy-<captureID>" 关联；原剪贴板内容仅内存暂存、不进任何日志（实现审计 + 字段形状断言）。合成标记实机扫描与 incident 路径未跑。 |

下一步：由具备辅助功能权限的环境执行 T01（普通/全屏/退出全屏的真实拖选 + 菜单 Copy 对照）；通过前不开启 `copyCaptureEnabled`、不替换安装版。候选代码、构建与离线测试均已就绪，实机解锁后按 T02–T09 顺序补验。


## 主 Agent 接手（run_20260919_takeover，2026-09-19）

用户要求接手 OpenCode 未完成的 Computer Use / 日志验收。本轮读取原 Session 的完成消息并确认 idle；未重启已停止的错误 Session，未再派发。证据目录：[run_20260919_takeover](../../evidence/books_selection_copy_and_focus/run_20260919_takeover/)。

- 接手时实际源码与 build 的指纹已不同于 OpenCode 的 09-18 报告，逐文件记录在 `baseline.json`；以本次重跑结果为准。原安装版 2fe559f6… 已备份为 `previous.app`。用户模板和偏好备份仅在本机私有证据目录，词本未改写。
- T01 采用暂时打开内部 `copyCaptureEnabled`、关闭自动解释的受控候选安装，目的是执行真实事务探测，不代表已批准启用新的日常默认策略。源码默认仍 false。确认不可行时按 RFC 回退；通过前不能声明修复完成。
- 测试进程 1309337a… 已通过系统设置刷新同一项辅助功能授权，日志 `accessibilityTrusted=true`。Computer Use 可读取书页；右键后 Escape 的截图可见 bulldozer，AX 同时为 bulldozer。此例仅证明当前原生选区，不能证明拖选触发或复制绕过故障。
- Computer Use 的拖动、双击未产生可核对的 `copy_capture_scheduled` / outcome；不能把工具动作返回成功算作真实 E2E。通过 Finder 原生打开确认 Books 前台后仍未取得完整鼠标事件链，已请求用户仅做一次物理拖选用于区分工具投递与应用监听问题。09-19 03:14:17Z 日志曾出现单个 leftMouseDown，无配对释放，不能计作有效拖选。
- 本轮没有模型请求或 AI 回答。原书、书签与注释未修改；原书仍在 Introduction 第 3 页。

### 本轮发现、修复与验证

| 问题 | 修改与证据 | Verdict / 边界 |
| --- | --- | --- |
| mouseUp 安排取词后，紧接的 poll 再次递增 revision，取消刚安排的同一手势 | `SelectionInteraction.event` 同步按钮缓存，事件与 poll 使用同一状态；`selection_trigger.swift` 内重演按下→轮询→松开→立即轮询。`--old-release-cache` 稳定失败，现实现通过；已进 test.sh。 | PASS（确定性接线回归）；物理拖选待验。 |
| AX 抑制诊断分支被提前 guard 排除，虽然不会误发，但缺少拒收记录 | guard 只判断 selected，复制策略开启时实际记录 `ax_selection_suppressed`。当前安装运行日志已出现该事件。 | PASS（实测日志）；不等于复制成功。 |
| 菜单快捷键 modifier 属性拼错且缺失被当成0 | 改用本机 SDK 定义的 `AXMenuItemCmdModifiers`；未知 mask 不选中。 | 构建 PASS；真实 Copy 菜单调用待验。 |
| 快照读取期间的并发复制可能被覆盖 | 全部类型读取后复核计数；发 Copy 前再次校验基线，变化即拒绝且保留新内容。 | 单测 PASS；移除发出前保护的反事实变体稳定失败，见 clipboard_counterfactual.json。 |
| 取词完成前丢失前台，或读到文字后才取消，可能仍交付 | 取消条件包含目标前台；清理后再次判断取消。 | 确定性取消断言 PASS；切应用实机待验。 |
| 正常退出没有等待在途事务清理 | applicationShouldTerminate 返回 terminateLater，失效当前事务并等待串行队列完成，再允许退出。 | 构建 PASS；实际在途退出待验。 |
| NSPasteboard.writeObjects 失败仍可能因为计数前进而被报恢复成功 | 写入失败返回失败标记，事务记录 restore_failed、不交付文本。 | 注入恢复失败单测 PASS；正常类型字节恢复仍 PASS。 |

`zsh scripts/test.sh` 全部通过。日志中两行 FAIL 分别是旧鼠标缓存、旧前台门控的预期反事实失败，脚本整体 exit=0。`zsh scripts/build.sh` 通过。最终候选 SHA-256：`1929c3ed7bd0b3e1cab04c83a45bbf3ce9ae353ed3b545751658999e679f5533`。

当前验收：T02–T05/T09 的离线范围继续 PASS；T01、T06、T07、T08 真实行为与 T04 实际退出仍 BLOCKED/NOT VERIFIED。自动解释暂时 OFF，提示词保持用户音标版。下一步仅需完整的物理拖选事件链，再继续原书复制对照、两轮全屏往返、真实 Gemini 与窗口覆盖测试。不得沿用旧版回答或静态窗口层级宣称这些项目通过。

最终安装核验（2026-09-19）：1929c3ed… 与 build 完全一致，运行记录确认辅助功能 true、复制探测开关 true、自动解释 false；用户保存提示词逐字不变。证据：`evidence/books_selection_copy_and_focus/run_20260919_takeover/final_candidate.json` 与 `final_runtime.jsonl`。图书留在原书前台，尚待物理划词；本轮未产生 AI 回答。
