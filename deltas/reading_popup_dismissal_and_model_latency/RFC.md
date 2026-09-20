# 浮窗显示生命周期

本轮产品合同见 [PRD](PRD.md)。不修改取词复制事务、模型调用参数、提示词和词本数据格式。

## 实现

- `ReadingPanelController` 拥有浮窗的本地/全局点击监听和一次性计时器。全局点击监听覆盖 Books 仍为前台时的非激活浮窗；本地监听覆盖词本等同应用其他窗口。事件继续交给原目标，仅本窗口 Esc 被消费。
- 使用 `orderOut` 隐藏，保留选区、消息、编辑内容和网络任务；Esc/关闭按钮共用此路径。窗口失去键盘焦点也收起，子窗口/附属 sheet 保留。下一轮事件队列的焦点回调绑定 presentationID，不能关闭新展示。
- 顶部复选框存 `autoDismissAfter15Seconds`，缺省 false。新选区显示创建新的 presentationID，并在勾选时调度 common-mode Timer 15 秒。关闭、操作或换词取消旧计时；回调同时核对 ID、开关、截止时间、可见性，抵御已入队的旧回调。
- 点击/键入/滚动浮窗取消本次计时；菜单显式恢复、启动恢复不自动计时。当前已显示窗口刚勾选时从当下开始计时。
- 同词通过真实 Copy 捕获重新选择后，仅 showWindow(reason: repeat_selection)，不调用 receive/ask、不清空草稿。AX 轮询不能进入该恢复分支。
- 模型结束时仅在可见且为 key window 的情况下恢复输入焦点。完成回答始终走既有 history 写入，不因隐藏再次调用 showWindow。
- 不新建权限种类或全局快捷键。旧有辅助功能授权只因 ad-hoc 构建变更按已有流程刷新。

## 诊断

每次展示沿用 `window_presented`；新增 `window_dismissed`（reason、presentationID、visibleAfter、sincePresentationSeconds；外部点击还带输入时间与前台 app ID）、`window_auto_hide_scheduled`（deadlineUptime、delaySeconds）、`window_auto_hide_cancelled` 和 `auto_dismiss_changed`。继续使用既有 session/sample/request/run 关联、轮换和密钥脱敏。

## 划词反侧定位

`ReadingPanelPlacement` 在既有 Books 全局 mouse-up 监听中取得该事件的 CGEvent 坐标，不读取等待结束后的实时鼠标。将 Quartz 全局坐标转换为 AppKit 坐标，确定屏幕 ID；通过 WindowServer 的屏幕内普通层级窗口边界，选择同一 Books PID 且包含该点的第一个窗口。仅用边界，不读取其他应用正文、标题或新申请权限；边界缺失时使用该屏幕。

以参考矩形中线确定另一侧，将鼠标坐标、原始事件时间、参考矩形/来源、屏幕 ID 和方向构成不可变值。该值随 captureID 通过 settle delay 与复制队列；finishCopyCapture 先检查当前 captureID，只有接受的文字才提交位置。相同文字的新手势同样提交新位置但保留对话。showWindow 在对应屏幕 visibleFrame 的顶部左/右角定位；若该显示器已断开，回退当前可用显示器并沿用方向。

`copy_capture_scheduled` 与 `window_presented` 新增 `placement`，可对照 mouseUpPoint、eventTimestamp、referenceFrame、referenceSource、displayID、side 与实际 panelFrame。后续模型流或完成回调不重新读取鼠标、不移动窗口。

## 回滚

安装前本地 `evidence/popup_dismissal_20260920/previous.app` 备份为 2097b5a5…；源码快照在 baseline/，指纹 baseline.json。回退应用需正常退出后恢复该目录，再核对辅助功能状态。没有提交、远端或服务器改动。

反侧定位增量的直接基线为 511a5671…，备份在 `evidence/opposite_selection_20260920/previous.app`，源码与设置指纹在同目录 baseline/、baseline.json、preferences_before.plist。
