# 自动复制取词与窗口生命周期

状态：主 Agent 已接手候选并补充保护（run_20260919_takeover）；源码复制策略默认关闭，当前受控实测临时开启、自动解释关闭，T01 尚未通过。产品行为由 [PRD](PRD.md) 拥有，代码与安装版基线见 [索引](../INDEX.md)。

## 当前代码与证据

- [BooksSelection.swift](../../src/BooksSelection.swift) 的 `text` / `inspect`：AXSelectedText 优先，TextMarker 作为另一读取方式，沿 Books 的事件、焦点和窗口子树查找。CFRange、AXStringForRange 和范围几何已进入诊断，不是尚未探索的新接口。
- [main.swift](../../src/main.swift) 的 `captureBooksSelection`：已有全局鼠标监听、AXObserver、350ms 轮询，`interactionRevision` 丢弃跨手势结果；不是纯轮询。`SelectionTrigger` 等待 400ms 稳定后调用 `receive`，再显示窗口与调用模型。
- `buildWindow` 当前使用普通层级、nonactivatingPanel、moveToActiveSpace/fullScreenAuxiliary/canJoinAllApplications；`showWindow` 调用 makeKeyAndOrderFront。全屏失败不能只归结为窗口层级。
- [诊断说明](../../docs/diagnostics.md) 与 [原始证据](../../evidence/selection_mismatch_20260918/diagnostics_e2e.json)：错误时三个文本结果一致但与画面不同；正确与错误场景的 AXBoundsForRange 均为零。跨接口一致不等于真实选区正确，零坐标也不是统一拒收依据。
- [全屏调查](../../evidence/fullscreen_investigation.json)：切换全屏后可见选区与 AX 空值冲突。当前没有复制路径的实机结果，不把相似 WebKit bug 或 DRM 推断视为已证明根因。
- 当前持续日志默认开启；旧 `docs/rfc.md` 的 selectionDiagnostics 默认关闭描述已经落后于实际代码。本轮只记录差异，不改写长期合同。

## 推荐取词路径

优先完成 [TEST](TEST.md) 的 T01：直接比较原书可见选区、AX 与 Books 复制结果。通过后再把 Books 的主输入切为复制结果，AX 保留为诊断和辅助信号。不能仅在 AX 为空时换路，否则非空错词仍会被接受。若执行环境缺少真实 UI 操作能力，可以先完成隔离的候选代码、测试与构建，把实机项记为 BLOCKED；T01 仍是启用新默认取词策略的前置条件，不把缺少工具当成通过。

调用顺序候选为：Books 可用的菜单 Copy 动作；仅在确认菜单途径不支持或未执行时，才改用定向的 ⌘C 事件。菜单动作超时并不证明没有执行，不能盲目叠加第二次复制。两条途径都使用系统通用剪贴板，不能称为私有剪贴板或零污染。

参考 [SelectedTextKit](https://github.com/tisfeng/SelectedTextKit) 的策略与剪贴板事务，以及 [Easydict Books 修复](https://github.com/tisfeng/Easydict/pull/996)。遵守项目现有无额外包约束，优先用已有 Swift/AppKit/ApplicationServices 做最小实现；本 Delta 不直接引入新依赖。参考代码如需复用，应保留适用许可证声明。

## 触发、取词与并发合同

1. 一次真实 Books 划选手势产生一个 `captureID`，绑定 Books PID、阅读窗口、手势修订号和开始时间。主要覆盖拖选与双击/三击选词。普通点击、滚动、启动遗留选区和仅有计时器 tick 不自动执行 Copy。
2. 350ms 轮询与 AX 通知可以继续观测、记录、协助稳定判断；不得每次轮询都复制，也不得让 AX 文本的变化绕过复制确认直接发送。
3. 复制动作有副作用：发出前必须确认 Books 仍是目标前台应用、阅读窗口未切换、鼠标已松开、手势仍有效。复制完成前不前置问答窗口。无法确认时取消本次动作，不能把快捷键发送给别的应用。
4. 这与旧只读 AX 前台门控缺陷不同：只读诊断可以观察后台 Books，副作用动作必须核验目标。需要用真实测试证明这项保护没有重新造成划词无法触发。
5. 同时只允许一笔复制事务。新手势、Books 重启、焦点/Space 改变使旧事务失效；旧事务仍负责必要清理，新事务等待清理结束。旧读取或旧模型流不得覆盖新选区。
6. 一次事务结束后，清理成功且选区可接受才进入 `receive`。相同选区沿用已有去重语义，不重复弹窗或扣费。结果未确定、目标已变、过长或为空时停止，不把旧剪贴板、旧 AX 文字或语言模型猜测作为兜底答案。

## 剪贴板事务

状态建议：`eligible → snapshot → copyIssued → captured → restoreOrPreserveNew → accepted / rejected`。取消也必须走清理。与模型请求 generation 分开管理取词 generation，避免网络取消打断剪贴板清理。

| 环节 | 合同 |
| --- | --- |
| Snapshot | 在内存保存全部项目、类型与数据，记录 changeCount；空剪贴板也是合法快照。数据延迟提供、读取失败或无法完整保存时拒绝动作。快照内容不持久化。 |
| Issue / Wait | 使用有上限的等待，不阻塞主线程；记录动作、PID/窗口、各阶段 changeCount 和耗时。没有发生新复制变化不能把原剪贴板误当选区。超时参数由 T01 测量后在本 RFC 补定。 |
| Validate | 组合手势、目标进程/窗口、焦点、时间与 changeCount 判断事务有效性。changeCount 本身不能证明写入者身份；有无法解释的变化时拒绝结果。不得声称这能提供系统级原子锁。 |
| Restore | 仅在剪贴板仍对应本事务结果、没有后来写入的证据时恢复全部原始项目；发现外部新内容就保留它。恢复前再次检查，恢复失败要记录并提示。 |
| Cleanup | 已发出 Copy 后的取消、正常退出、解析异常都执行受控清理；不在磁盘保存原剪贴板。强制结束、崩溃及系统外部竞争仍有无法彻底消除的窗口，不能保证恢复必达。 |

历史管理工具和通用剪贴板可能先观察到 Books 自己的复制；事后标记或恢复不提供撤销保证。不关闭 Handoff、不修改其他应用、也不照搬库里的系统音量修改来掩盖失败。

Books 可能添加引文和出处包装。只剥离实测证实的明确格式，保留正文标点与换行；不把任何出现 “Excerpt From” 的正文都裁掉，不用模型补全片段。包装无法确定时记录原因并拒绝自动请求。AX 与复制结果不一致时同时记录，采用通过验证的复制通道结果，不能因 AX 投票数量多而覆盖复制结果。

## 窗口合同

以 `captureID` 约束一次前置。优先保持普通窗口层级；若全屏必须临时提高层级，只在本次呈现期间使用，并在外部点击或离开本应用时恢复。降级检测不能只依赖 may-not-fire 的 resignKey；需要覆盖 nonactivatingPanel、Books 自己的选词弹窗及其他 Space 的实际事件。

外部点击必须原样送达目标应用，不拦截、不模拟补点、不清空本轮对话。答案增量、完成回调、取词轮询均不再执行 showWindow；再次主动打开窗口或真正的新选区才可前置。普通模式保留正常窗口可遮挡行为；全屏空间若不能跨应用叠放，应让出显示，返回时保留对话，不通过持续高层级强行留在屏幕上。

## 日志、实现边界与停止条件

在现有轮换日志中增加 `captureID`、`strategy`、Books PID/窗口与焦点、手势版本、各阶段时间/changeCount、快照项目/类型数量、恢复结果、拒收原因、AX/复制结果是否一致、前置及让出原因。保留 sample/session/request 关联。只记录本次有效 Books 选区及必要诊断，原剪贴板和竞争写入内容不得落日志或送模型。

主要涉及取词与触发、main.swift 的接收/呈现、诊断及相应测试；可拆最小的取词事务模块，保留现有问答、词本和历史格式的向后兼容。无需迁移历史或覆盖用户模板。

若 T01 实测否定复制能绕过故障，停止接入并把结论写回 TEST；若仅因工具缺失而待验，可继续上述隔离候选，不启用新的默认策略。不自动改成 OCR、自建阅读器或要求用户手动复制。若焦点、恢复或外部点击无法满足合同，保留明确失败状态，不标记修复完成。

后续候选安装前保留当前安装版作为回退点，不依赖目前不存在的 Git HEAD。回滚只恢复应用取词/窗口实现，保留配置、模板、词本、诊断和原书；旧版本本来就有的错位与全屏问题仍需如实说明。

## 实现偏差与实测待定（run_20260918a 回填）

- 模块落地为 `src/ClipboardCapture.swift`（事务/快照/包装剥离/决策）与 `src/BooksCopy.swift`（菜单 Copy 优先、定向 ⌘C 兜底、手势门控），接线在 `main.swift`；事务在串行 captureQueue 执行，新事务天然等待被失效的旧事务完成清理。
- 偏差 1：复制失败的「简短失败状态」只更新状态栏、不前置窗口——窗口前置严格限于真正的新选区与显式打开。
- 偏差 2：「阅读窗口未切换」未单独跟踪窗口 ID，由手势修订号 + Books PID + 前台性间接覆盖（切窗口必经鼠标/焦点事件）。
- 待定 1：超时参数沿用暂定值（settle 0.25s、poll 10ms、timeout 0.8s、上限 6000 字符），待 T01 实机测量后补定。
- 待定 2：中文引文包装（摘…此材料受版权保护。）为候选猜测；一次 Copy 是否恰好产生一个 changeCount 代际也未实测，若多于一个会被保守拒收（ambiguousWrites）。
- 待定 3：恢复操作本身 changeCount 可能前进 1–2（clearContents + write），实现按「前进即成功」判定，不按固定 +1。
- 已修复的旧候选缺陷：跨行选区包装正则不匹配换行导致全部误拒；取消/超时时已落盘的复制不恢复会遗留摘录；菜单键值大小写敏感。


## 2026-09-19 接手修订

事件与轮询共用 SelectionInteraction：鼠标事件在取出手势 revision 前同步按钮缓存，避免同一次 mouseUp 被 poll 再算一次。AX 在复制模式下继续仅诊断，抑制事件现在可达并记录。

快照读取后及发出 Copy 前复核 changeCount；目标前台丢失或读出后取消时清理并拒绝交付。正常退出使用 terminateLater 等待 captureQueue 清理，强制退出仍无恢复保证。NSPasteboard 写入失败单独记 restore_failed，不能凭计数前进判成功。菜单 mask 使用 SDK 的 AXMenuItemCmdModifiers，未知值拒绝。

主 Agent 的 T01 采用受控候选安装探测：内部复制开关临时 true、自动解释 false；这不是日常默认启用，不构成 T01 PASS。此前“未安装”只描述 09-18 OpenCode 的执行阶段。真实手势、包装、计数代际、前置让出和正常退出仍需最终安装版实测，见 TEST。
