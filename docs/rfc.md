# 架构

用户级 Swift/AppKit 应用。辅助功能 API 读取 Apple Books 选区，不使用剪贴板，不合成键盘事件。只在已授权、鼠标松开时检测 Books；自动解释开关不控制选区读取。后台队列读取 AXSelectedText，必要时读取 WebKit 的选中文字标记范围；Books 常聚焦容器，因此有带时间与节点上限的子树查找。

监听 Books 的选区与焦点通知，并用 common run-loop mode 的 350ms 定时器兜底。读取仅针对 Books，不依赖前台应用判断；实测原生选区已经改变时，前台判断仍可能为 false。启动或 Books 进程变化时，后台遗留选区只用作基线。SelectionTrigger 在新选区稳定至少 400ms 后显示窗口并聚焦输入框。Books 前台期间以 userInitiatedAllowingIdleSystemSleep 活动保持监听及时，离开即释放；系统仍可正常睡眠。同一选区不重复打开；Books 在切换焦点时可能临时返回空选区，因此空读取不清除最近已接收文本。新选区开启新对话，原选区对话可从菜单栏重新打开。上限 6000 字符。自动解释默认开启，接收到新选区后按当前模板调用模型；关闭时仅显示选区，手动发送后调用。切换为开启或编辑模板本身不会请求模型。模板为空时不自动发送。新选区会取消前一请求，以 generation ID 隔离旧响应。

浮窗支持全屏 Books 所在空间。直接点击图书继续阅读，移除回到图书和复制回答按钮。菜单栏与窗口中的自动解释开关同步；关闭会取消正在生成的自动请求。Services 接收方法作为兼容应用可选入口保留；本机 Books 不提供文本服务，不能用它验收。

窗口层级为 normal，collectionBehavior 为 moveToActiveSpace + fullScreenAuxiliary，取消 floating 与 canJoinAllSpaces。仅在收到新选区或用户打开窗口时前置；普通应用切换按正常层级排列。启动日志 window_policy 记录实际层级与是否加入所有桌面，方便核对安装版。

UserDefaults 保存自动解释开关与可编辑模板。模板编辑区每次启动默认收起；展开时在固定窗口内部调整高度，不改窗口尺寸，编辑即时保存。初次启用默认 on，保存过的 off 不会被覆盖。启动时保留已保存窗口位置，将外框尺寸设置为用户选定的 500 × 539 点。原文、提示词编辑器和回答共用只竖向滚动的 ReadingTextArea。

配置只保存 URL、model、既有凭据 locator 和上下文文件路径。离线解析已有 EPUB，排除词汇脚注，唯一匹配后附加同章节相邻段落。引用资料不能覆盖模型系统指令。

URLSession 异步 SSE 请求 LiteLLM Chat Completions；取消用 generation ID 丢弃旧响应；提前断流和长度截断不标成功。失败保留已完成会话。

本地日志目录 0700、文件 0600，记录选区、问题、实际回答、上下文 ID 与耗时，不记录密钥。常规监测记录权限、开关、Books 前台状态与观察器注册结果，不记录其他应用内容。selectionDiagnostics 默认关闭；调试开启时额外记录 Books 窗口标题、AX 错误码、访问节点数、选区长度与范围，不记录全文。

参考 Apple [辅助功能授权 API](https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions) 与 [选区属性](https://developer.apple.com/documentation/applicationservices/kaxselectedtextattribute)。
