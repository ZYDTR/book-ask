# 验证

- 离线：EPUB 脚注排除；引号与空白归一；唯一、重复、找不到与跨段选区；Swift 编译。
- 布局回归：使用生产 NSTextView / NSScrollView 组件在离屏 AppKit 窗口中按 610 → 500 → 1000 → 1500 → 500 → 610 点调整宽度；分别替换短文本和长文本模拟流式更新。检查中英文及无空格长 URL 不越界、文档与视口等宽、水平滚动约束为 0、长文仍可竖向延伸。修复前稳定失败（多出 540 点），修复后通过；已接入 scripts/test.sh。
- 网络：现有凭据调用真实 Gemini Flash，保存去密响应，不等于 E2E。
- E2E：Computer Use 在 Apple Books 原书划选，不使用 ⌘C/粘贴；自动出现提问窗口；发送问题；核对实际回答、追问、上下文 ID 和返回原页。
- 门控：未授权不读取，只处理 Books 的新选区；自动解释关闭时继续带入真实选区，但无 request_started 或 answer；开启时新选区自动发送可编辑模板，编辑模板和切换开启本身不产生请求。
- 持久化与尺寸：通过原生编辑器修改模板、关闭开关，退出后重新启动仍保留；临时缩放后重新启动恢复 500 × 539 点。
- 新版真实验收：默认英文简短解释与同表达例句；关闭自动解释后只显示原文；手动追问可回复；重新开启后使用保存的模板；回归原文/回答/模板均不横滚。
- 秘密：源码、文档、日志、证据均不含实际 Key，配置仅存 locator。

最新真实状态见 working.md。不用伪选区或固定响应冒充 UI 验收。

## 选区不弹出回归（2026-09-18）

- 证据：诊断版连续读到真实 `bulldozer`（9 字符），但 booksInForeground=false，旧门控丢弃所有结果；见私有 evidence/selection_recovery_e2e.json。
- tests/selection_trigger.swift 直接断言新 Books 选区即使焦点在别处也能触发，启动旧选区、重复选区、瞬时空读取、鼠标拖动、读取未完成与 Books 重启均不误触发。固定时钟输入，无 sleep；已接入 scripts/test.sh。
- 反事实：同一测试加 --old-foreground-gate 稳定在新选区触发断言失败；正式实现通过。该测试保护触发判断，不冒充 macOS 实机 UI 测试。
- 最终安装版真实 AX 选区 → 自动回答、追问、关闭只带入原文均通过；原文截图与原生窗口核对。Computer Use 原始 drag 未可靠创建选区，使用 selectText/原生右键选择得到真实书内高亮；随后另观察到前台 Books 的 pieces 选区自动回答，非 Agent 当次选择。不同 macOS Space 的全屏前置与长时间后台休眠仍需实机持续使用观察。

## 全屏往返兼容性（2026-09-18）

**FAIL / 未解决。** 真实步骤：普通窗口重新开书 → fragile 真实选区和 API 回答成功 → Books 菜单进入全屏 → 退出全屏 → 右键选中 bulldozer → 画面有选区，AX 返回空值且所有 rangeLength 为 0，没有新请求。用户也确认全屏内和退出后都不弹出。详见 evidence/fullscreen_investigation.json。

既有 scripts/test.sh 的 PASS 只覆盖 EPUB、上下文、稳定选区触发与横向滚动，不覆盖 Books 的 AX 提供方在全屏切换后的行为。禁止把设置了窗口 collectionBehavior 或 mock selectedText 的单元测试写成该 bug 已通过。临时恢复为关闭阅读窗口并从继续阅读重新打开；这也不是全屏修复。

## 词本（2026-09-18）

PASS：tests/wordbook.swift 覆盖同书合并、跨书分离、会话交错、自动解释与追问、取消、尾行截断及搜索；tests/wordbook_layout.swift 覆盖真实内容视图 59pt 收缩回归与三种宽度。均接入 scripts/test.sh。原生按钮、搜索/无结果、旧解释/追问、新 shovel 真实选区和答案入词本通过；去密证据 evidence/wordbook_ui_e2e.json。

## 持续诊断（2026-09-18）

`tests/diagnostic_log.swift`：30 个完整预触发样本、样本/请求关联、毫秒时间、递归密钥脱敏、0600、3 份小容量测试轮换、incident 保存，已接入 scripts/test.sh。全部通过。`tests/selection_trigger.swift` 补充新手势必须重新等待稳定及可读决策。

真实错误与正确结果已分别保留：同一 location=29/length=9 在旧节点给出 er, forci，重开书页后节点正文恢复并给出 bulldozer。两者的范围几何字段都是零，不能作为正确性 oracle。本轮不声明该错位已有自动化修复；用户截图与 Books AX 不一致是目前的真实失败语义。
