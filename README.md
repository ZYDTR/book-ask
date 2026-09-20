# 读书提问

私人 Git 项目。保留 macOS 图书阅读器，在原书里划选文字就打开提问窗口，使用已有 LiteLLM 的 Gemini Flash。软件免费，仅消耗模型 API。个人私有仓库：[ZYDTR/book-ask](https://github.com/ZYDTR/book-ask)。书籍、密钥、阅读记录与原始诊断证据只存本机，不入库。

## 需求入口与文档归属

本 README 是 book_ask 的需求控制面入口，控制面与代码仓库均位于本目录，局部约束见 [AGENTS.md](AGENTS.md)。已有脚手架继续使用，不重新建项目。

- 唯一增量需求索引：[deltas/INDEX.md](deltas/INDEX.md)。需求状态、代码基线和下一步以该索引为准。
- 最新 Delta：[收起、划词反侧定位与模型比较](deltas/reading_popup_dismissal_and_model_latency/PRD.md)（已实现外部点击/15秒勾选收起、按鼠标松开位置反侧显示，用户确认换边可用；验收边界与真实 API 测速见其 TEST）；已有 [划词解释窗口固定在右上角](deltas/reading_panel_top_right/PRD.md) 与 [Books 自动复制取词与窗口前置](deltas/books_selection_copy_and_focus/PRD.md) 保留为历史增量，执行状态统一见索引。
- 既有长期文档仍在原位：[产品](docs/prd.md)、[架构](docs/rfc.md)、[测试](docs/test.md)、[提示词](docs/prompts.md)、[诊断](docs/diagnostics.md)。本次未回灌新的产品或技术结论；与当前代码或新要求的差异在 Delta 中说明。
- [docs/working.md](docs/working.md) 保留已有实施记录和 Lessons Learned；当前 Delta 的方案与验证只写入其 PRD/RFC/TEST，避免产生第二套状态。

本机当前安装已启用自动复制取词；全新配置的复制开关仍默认关闭，需完成本机选区/剪贴板验证后在本应用 UserDefaults 设置 `copyCaptureEnabled=true`。后续实现先从本入口进入索引核对执行绑定。`docs/` 保留此前阶段的长期文档，当前差异以 Delta 为准；只有用户明确授权回灌时才更新其产品与技术结论。

## 使用

1. 打开 `~/Applications/读书提问.app`。默认尺寸为用户选定的 **500 × 539 点**；临时缩放不会改变下次启动的默认大小。首次从菜单栏「书问 → 授权划词」开启辅助功能权限。
2. 「自动解释」默认开启。在 Apple Books 划选词语或句子，选区自动进入浮窗，并按上方提示词发送给 Gemini。
3. 关闭「自动解释」后，仍会带入选区，但不会自动调用模型。输入问题并回车或点「发送」；输入框留空时发送上方模板。
4. 提示词默认收起；点右上「编辑提示词」展开，编辑后自动保存，点「收起提示词」恢复阅读空间，下一次划选生效。开关状态也会保存，重启后尊重用户关闭的选择。
5. 点击浮窗区域外（包括图书）或按 Esc 收起，草稿和对话保留。顶部可勾选「15 秒后自动收起」，在浮窗内点击、输入或滚动会取消本次计时。同一选区支持连续追问，新选区开始新会话。「发送」在回答期间变成「停止」。关闭自动解释时，会取消正在生成的自动回答。

无需 ⌘C 或粘贴。没有「解释表达」「解释逻辑」「复制回答」「回到图书」按钮。相同选区不会反复弹窗或扣费；从菜单栏「书问 → 显示读书提问」可重新打开现有窗口。应用需保持运行，没有配置开机启动。

模板、原文和回答随窗口宽度自动换行，只允许竖向滚动。提示词全文见 [docs/prompts.md](docs/prompts.md)，实际验收状态见 [docs/working.md](docs/working.md)。

窗口使用普通层级。划选新内容时自动前置：鼠标松开位于 Books 窗口右半边时出现在屏幕左上角，左半边时出现在右上角；坐标随这次取词保存，后续移动鼠标不会改变方向。

## 权限与数据

辅助功能是 macOS 的较广权限。当前本机启用的 Copy 路径在 Books 真实划词后调用复制菜单，必要时向 Books 发送 ⌘C；事务期间读取选区并恢复原剪贴板，遇到用户更新剪贴板时保留新内容。非取词事务不持续监听剪贴板，不修改书籍。局部上下文来自本机已有 EPUB；不唯一或找不到时明确提示。

自动解释开启时划选会发送请求；关闭时仅在手动发送后调用。请求向用户配置的 LiteLLM 发送选区、匹配到的相邻段落、问题和本轮对话。配置位于 `~/.config/book-ask/config.json`。密钥从既有凭据文件按需读取，不复制到项目。私有记录位于 `~/Library/Application Support/BookAsk/history.jsonl`。

历史是追加写入的 JSONL（每行一个事件），用 `sessionID` 关联选区和问答：`selection_received` 保存选中文字与上下文 ID，`request_started` 保存实际提示词/问题及是否自动，`answer` 保存完整回答、问题、选区、模型、时间和轮次。取消、错误单独记录，不当作完整答案；关闭自动解释时仍记录收到的选区。目录权限 0700，历史文件权限 0600。

## 构建和测试

```sh
zsh scripts/test.sh
zsh scripts/build.sh
zsh scripts/install.sh
```

首次配置：`python3 scripts/prepare.py --epub <已有EPUB> --opencode-config <已有配置JSON> --auth-file <已有鉴权JSON>`。

`python3 scripts/smoke_api.py` 是会消耗 API 的网络测试，不等于图书 UI 验收。

开发注意：本地构建采用 ad-hoc 签名，重新编译后 macOS 可能保留旧签名授权，表现为开关已开启但新版本不能读取选区。需要通过系统设置重新添加当前安装文件并验证应用授权状态。每次交付必须验收最终安装的二进制，不能沿用旧版结果。

## 撤销

退出应用，将 `~/Applications/读书提问.app` 移至废纸篓，并撤销其辅助功能权限。项目数据在上述配置和记录目录中。原书、图书应用和原 API 配置不变。

## 结构

- `src/`：原生界面、选区检测、上下文匹配和模型调用。
- `scripts/`：配置、构建、安装和测试。
- `tests/`：离线回归。
- `docs/`：需求、架构、验收与工作记录。
- `evidence/`：本机真实调用证据，Git 忽略。

### Books 全屏验收边界

2026-09-18 的 AX 路径曾在原生全屏往返后停止提供真实选区；当前本机改用 Copy 路径，并已通过用户日常划词验证，但全屏往返尚未完成单独验收，不保证所有模式可用。原始故障见 docs/test.md，当前覆盖边界见最新 Delta TEST。

### 词本

点击主窗口右上角「词本」，即可查看已保存的词句、解释与后续追问。支持搜索词句/回答，同一本书的重复词句合并显示，最近划过的排在前面。数据直接来自 `~/Library/Application Support/BookAsk/history.jsonl`，查看词本不调用模型。

### 划词出错时

诊断日志现在默认持续开启，保存在 `~/Library/Application Support/BookAsk/diagnostics/`。在应用菜单或顶部「书问」菜单中选择「记录划词问题并打开日志」，即可保存当前现场并打开文件夹。持续日志约 60 MiB 轮换，单独保存的问题记录不受轮换影响，完整词本历史也不受影响。日志含选区和问答，只存本机并隐藏模型密钥。详细字段与排查步骤见 [docs/diagnostics.md](docs/diagnostics.md)。

2026-09-18 已记录 Books 画面高亮 bulldozer、AX 接口却提供另一段 er, forci 的错位。当前本机 Copy 路径不以错误 AX 内容兜底；历史故障及保留的验收边界见 Delta，不将日志功能本身等同于划词兼容性修复。
