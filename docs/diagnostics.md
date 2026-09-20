# 划词诊断

应用启动即持续记录，不依赖旧的 selectionDiagnostics 开关。诊断不会调用模型、上传日志或自动截屏。

## 位置与保留

- 持续日志：`~/Library/Application Support/BookAsk/diagnostics/diagnostic.jsonl`
- 轮换文件：`diagnostic.1.jsonl` 到 `diagnostic.5.jsonl`；每份约 10 MiB，持续部分约 60 MiB 上限。
- 菜单「读书提问 → 记录划词问题并打开日志」或顶部「书问」菜单的同名项：写入问题标记并将现有诊断复制到 `diagnostics/incidents/<问题ID>/`，随后 Finder 打开该目录。问题快照不参与持续日志轮换。
- 词本与完整问答继续保存在旁边的 `history.jsonl`，不参与轮换。
- 日志目录 0700、文件 0600。模型密钥登记后递归脱敏，Authorization/API key 等字段强制隐藏。日志包含所划文字、附近正文、问答和 Books 相关鼠标坐标，只保存在本机。

## 如何复盘

1. 按 `runID`、`buildID` 确定进程与实际二进制；`time` 精确到毫秒，`sequence` 给出本进程写入顺序，`uptime` 可比较间隔。
2. `capture_gate`、`books_mouse_event`、`mouse_state`、`books_window_mode`、`books_connection_refresh` 显示权限、鼠标状态、全屏状态和连接切换。
3. `selection_sample` 包含 `sampleID`、原始与清理后选区、读取耗时/是否完整、节点路径、节点所属进程、AXSelectedTextRange、AXStringForRange、节点自身文本相同范围的内容、附近正文、位置/大小。每 10 秒补一份树读取概要；API 不支持的属性保留错误码。
4. `trigger.decision` 表明为什么等待、忽略或接受。发生新鼠标手势会重新等待稳定；读取中手势变化则丢弃该次旧结果。
5. `selection_accepted` 前保存最近 30 次完整样本为 `selection_trace`，通过 `checkpointID` 关联；平时只落盘改变的样本与约 10 秒心跳，避免无意义膨胀。采样器仍约每 350ms 读取；鼠标拖动事件最多每 100ms 记录一次。
6. `selection_received → request_started → response_headers → first_content → answer/error/cancelled` 用 `sampleID`、`sessionID`、`requestID` 串联。请求同时记录真实 selection 与界面 displayedSelection、模型及上下文 ID；可区分读取错字、显示错字与请求串线。
7. `user_report` 同时保存当前界面选区、回答、最后读取结果和触发前样本。现场快照可在下一次构建前保留故障。

## 已复现的限制

2026-09-18 用户截图选中 bulldozer，历史却记录 er, forci。首次持续诊断构建在未重开 Books 前读到：AXStaticText 为下一段 `They are, in one way or another, forcing…`，范围 location=29、length=9，AXSelectedText、AXStringForRange 与 AXValue 子串都为 er, forci。Computer Use 的 AX 文字也与实际截图不一致。

关闭并重新打开书页后，同样 location=29、length=9 对应正文 `I see a lot of teams using a bulldozer…`，三个接口均返回 bulldozer，真实 API 回答成功。这是临时恢复，不是根因修复。正确与错误场景的 AXBoundsForRange 都为零、AXVisibleCharacterRange 都为零，不能靠这些零值贸然拒绝选区，也不能声称三个文本接口一致便证明画面一致。

该问题涉及 Books 提供的文字树和可见书页不一致，日志不能直接知道屏幕实际高亮了什么。用户截图仍是视觉真值。未实现自动截屏或 OCR，也未宣称全屏/错词兼容性已修复。
