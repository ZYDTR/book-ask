# Delta 索引

控制面入口：[项目 README](../README.md)。本索引只管理本地 book_ask 的增量需求、执行绑定和下一步，长期文档归属由入口声明。已完成的 Delta 也保留在本目录。

| Delta | 状态 | 文档 | 唯一下一步 |
| --- | --- | --- | --- |
| `wordbook_exact_cache`：精确词条复用与清理 | 已安装；词本已清理，零请求回归通过 | [PRD](wordbook_exact_cache/PRD.md) · [RFC](wordbook_exact_cache/RFC.md) · [TEST](wordbook_exact_cache/TEST.md) | 等待真实Books重复划词核对；权限已恢复，当前二进制8189ef9d…。 |
| `paper_reading_ui`：纸感颜料界面重构 | 暗色已安装；主题/词本/重启通过，权限已恢复 | [PRD](paper_reading_ui/PRD.md) · [TEST](paper_reading_ui/TEST.md) | 本包真实划词待验证；权限与Books监听已恢复。当前二进制d1bb424b…。 |
| `menu_bar_app`：菜单栏常驻，移除 Dock 图标 | 已并入纸感版；原权限已恢复、输入/词本通过 | [需求 / 实现 / 验证](menu_bar_app/PRD.md) | 后续运行验收跟随paper_reading_ui，不重复建立验证记录。 |
| `reading_popup_dismissal_and_model_latency`：收起、划词反侧定位与模型比较 | 已安装；用户确认换边可用，日志核对两方向/Books点击/后台回答通过；测速完成 | [PRD](reading_popup_dismissal_and_model_latency/PRD.md) · [RFC](reading_popup_dismissal_and_model_latency/RFC.md) · [TEST](reading_popup_dismissal_and_model_latency/TEST.md) | 当前二进制9ecd66c8…；GitHub快照绑定见下节，TEST保留全屏/多屏等未覆盖边界。 |
| `reading_panel_top_right`：划词窗口固定右上角 | 已安装，启动/显式显示定位验证通过 | [PRD / 实施与验证](reading_panel_top_right/PRD.md) | 用户按日常阅读确认位置；模型列表已核对，保持 Gemini 3.7 Flash。 |
| `books_selection_copy_and_focus`：Books 自动复制取词与窗口前置 | 已安装；09-20 用户确认体验已很好，部分自动化全屏/竞态项目仍未覆盖 | [PRD](books_selection_copy_and_focus/PRD.md) · [RFC](books_selection_copy_and_focus/RFC.md) · [TEST](books_selection_copy_and_focus/TEST.md) | 保留未覆盖项的原记录；本轮新需求见右上角窗口 Delta。 |

## 当前执行绑定：books_selection_copy_and_focus

最新 `menu_bar_app` 执行绑定：代码/控制面均为 `/Users/zhengyidi/yage/context-infrastructure/adhoc_jobs/book_ask`，沿用当前工作目录，branch main，baseline HEAD `8ea90000d3645d14e0de0221b8bd159c66087dec`，开始时工作区干净。仅本地更新安装应用及本增量文件，验收结果见该 Delta；下表为历史取词任务基线。

| 项目 | 已核实值 |
| --- | --- |
| 控制面根目录 / 代码仓库 | `/Users/zhengyidi/yage/context-infrastructure/adhoc_jobs/book_ask` |
| 工作目录 | 同上，既有本地工作目录；未创建或切换 worktree |
| OpenCode Session 所属项目 | `/Users/zhengyidi/yage/context-infrastructure`；用户要求 Session 归属此项目。实际代码命令仍使用上面的 book_ask 工作目录。 |
| Branch / Base ref | `main`，unborn branch；没有可解析的 base commit |
| Baseline HEAD / Current HEAD | **不存在**。`git rev-parse --verify HEAD` 返回 128；不可伪造 SHA，也不能用已安装二进制哈希冒充 commit。 |
| Dirty state | 建档前 `.env.example`、`.gitignore`、`AGENTS.md`、`README.md`、`docs/`、`src/`、`scripts/`、`tests/` 共 32 个文件均 untracked；无 staged 或 tracked diff。本次仅补需求文档与入口。 |
| 远端 / 提交 | 无 remote，无 commit；本轮未获得也未执行提交、发布或部署授权 |
| 顶层 lessons.md | 不存在；已读取既有 `docs/working.md` 的 Lessons Learned 与精确相关故障记录，不新建第二份 lessons |
| 核验时间 | 2026-09-18 21:38:03 +08:00 |

由于仓库尚无提交，当前实现判断绑定本次核实的实际文件和以下内容指纹。它用于发现工作副本变化，不能替代 Git 历史或提供独立回滚能力。未来开始实现前重新核验；若后来获得提交授权，再补真实 baseline HEAD。

| 基线对象 | SHA-256 |
| --- | --- |
| `src/`、`scripts/`、`tests/` 合计 22 个非缓存文件的内容集合 | `cc4a3c710efd0a43a46e2ae608f230389747e7ed53dcc2dec971b165dd6ed38e` |
| `src/BooksSelection.swift` | `367520f881c3254d66cbdce682055497b8852b39b9294e3b595fe7c27fbe1e02` |
| `src/main.swift` | `8940c384a27725906e558d8c1b856d6ae194906eced2e5c894335d2d00f2317e` |
| `src/SelectionTrigger.swift` | `afb0521ed142d490dc0ebdb8d25a6c7c0d798d042e5850f69c3c96d84fb886f9` |
| `src/DiagnosticLog.swift` | `03ef65480046b88170ecd8b582e66fe7ed24be2f5190dbaf3a75126d216c7adb` |
| 现有安装版 `~/Applications/读书提问.app/Contents/MacOS/BookAsk` | `2fe559f6e4c48d966795b2694c05d9d0a339cb566f8869fe7bc47eeb4e2f96af` |

集合指纹算法：递归取上述三目录的普通文件，排除 `__pycache__`；按项目相对 POSIX 路径排序。每个文件生成 `路径 + NUL + 小写 SHA256 + LF`，连接为 UTF-8 字节后再次取 SHA-256。

所有实施与测试命令使用本索引绑定的工作目录。主 Agent 已完成文档链接检查和源码指纹核对，未改源码、构建或安装；后续实现和测试由获授权的 OpenCode Session 执行。

## OpenCode 交接

- 用户已明确要求创建一个 OpenCode Session 写代码、测试；只委派该任务，不授予继续创建 Agent/Session 的权限。
- 已核对 4096 服务 1.18.29 的实时配置：默认 `litellm/bailian-kimi-k3--max`；本次按用户点名的 High 显式指定 `litellm/bailian-kimi-k3--high`，不改全局配置。
- 服务当前无已连接 MCP。真实 Books 界面验收能力需执行者核实；工具缺失必须单独标 BLOCKED，不能把离线测试算作全屏/错词问题通过。候选代码可以先完成，启用新默认策略和最终修复结论必须等待实机证据。
- **当前 Session**：`ses_f4b19ce4effeVdKDzw0gAFGSTw`，标题「读书提问：自动复制取词与窗口前置 Delta 接手实现」，Session directory 为 `/Users/zhengyidi/yage/context-infrastructure`；创建成功，prompt_async 返回 204。已在 OpenCode 的 Yage Server → context-infrastructure 项目列表中找到并打开。
- 当前交接：[接手消息](../evidence/opencode_handoff_context_infrastructure_20260918/prompt.txt) · [派发回执](../evidence/opencode_handoff_context_infrastructure_20260918/dispatch.json) · [接手时文件指纹](../evidence/opencode_handoff_context_infrastructure_20260918/resume_point.json)。旧执行者新增 ClipboardCapture.swift、BooksCopy.swift，修改 ReadingPreferences.swift 与 main.swift，均作为未验收候选保留；尚无已确认的候选编译/测试通过结论。
- **旧 Session 已停止**：`ses_f4b31fd28ffekCHTnhUX9MzNRW` 原误建于 book_ask 子项目。按用户指示于 2026-09-18 22:21:23 +08:00 abort=true，服务确认 idle，UI 显示“已中断”。[停止回执](../evidence/opencode_handoff_20260918/stopped.json)。禁止重新启动造成并发写入。
- 完整交接消息：[prompt.txt](../evidence/opencode_handoff_20260918/prompt.txt)。派发回执：[dispatch.json](../evidence/opencode_handoff_20260918/dispatch.json)。它们是 Git 忽略的本地交接证据，不替代本索引与三份 Delta 文档。
- 两次 Session 的 `task` 权限均设为 deny，消息明确禁止再派生 Agent/Session。旧 Session 的[启动核验](../evidence/opencode_handoff_20260918/startup_check.json)仅为原交接证据；当前接手的启动检查保存于新交接目录，不代表实现或测试通过。


## 2026-09-19 接手状态

主 Agent 已按用户要求接手未完成测试；OpenCode 正确 Session 为 idle，旧错误 Session 未恢复。候选真实源码以 `evidence/books_selection_copy_and_focus/run_20260919_takeover/baseline.json` 及后续构建指纹为准。已修复事件/轮询重复递增手势版本、剪贴板快照竞态、取消与正常退出清理、恢复失败判定和菜单 modifier 属性；test.sh、构建及反事实检查通过。最终候选二进制 `1929c3ed…`。

候选已进入受控安装探测，复制开关临时开启、自动解释暂时关闭；源码默认复制仍 false。1309337a… 探测版已确认辅助功能 true，但 CUA 操作没有形成可核对的完整鼠标手势/复制链；正等待一次物理拖选。最终候选需再次核实授权和真实链路。详情与所有未验收项统一在本 Delta TEST，原安装包已本机备份；不宣称修复完成、不回灌长期合同。

最终安装核验（2026-09-19）：1929c3ed… 与 build 完全一致，运行记录确认辅助功能 true、复制探测开关 true、自动解释 false；用户保存提示词逐字不变。证据：`evidence/books_selection_copy_and_focus/run_20260919_takeover/final_candidate.json` 与 `final_runtime.jsonl`。图书留在原书前台，尚待物理划词；本轮未产生 AI 回答。

## reading_panel_top_right 执行绑定（2026-09-20）

控制面与代码仍为本地 book_ask；workdir `/Users/zhengyidi/yage/context-infrastructure/adhoc_jobs/book_ask`，branch main，HEAD 仍不存在，全仓 untracked，不创建 worktree 或提交。安装基线 `1929c3ed…`；main.swift 基线 `e0f3f193799d5a31ba00a86b8b87b6163c0cae8f3f4da9905476230e0447a30b`。用户本轮已确认现有体验很好，旧 Delta 的未覆盖自动验收项仍如实保留。当前唯一工作为新条目中的右上角位置及网关查询。

## reading_popup_dismissal_and_model_latency 执行绑定（2026-09-20）

同一控制面与工作目录，branch main，baseline/current HEAD 均不存在，全仓 untracked；没有切换 worktree、创建提交或派发其他执行者。`src/main.swift` 基线 SHA-256 `3950a0569624c03ca3507fce6328d55cd6332e382328fba883a9bc89be7fde4f`。测速阶段仅新增测速脚本、Delta 文档和本机调用证据；当时未修改 Swift 产品源码或安装包。其后用户已确认交互实现，执行基线及当前状态见续记和本 Delta TEST。当前模型及用户 Prompt 保持不变。

实施基线续记：用户已授权主 Agent 实现收起与勾选计时。安装基线 `2097b5a5…`，源码快照及逐文件指纹保存于 `evidence/popup_dismissal_20260920/baseline/`、`baseline.json`；原应用备份 `previous.app`。仓库仍 main/unborn/全 untracked。继续保持原 Prompt、Gemini 3.7 与取词策略。

反侧定位续记：按用户后续确认，以划词松开时鼠标在 Books 窗口的左右半边决定浮窗另一侧；不需要识别栏位。直接安装基线511a5671…，备份和源码指纹位于 `evidence/opposite_selection_20260920/`。9ecd66c8… 安装后用户实际测试回复“it works”，两方向及Books外部点击日志已核对，详情只在本Delta TEST维护。随后用户明确授权将当前版本提交并推送个人GitHub仓库；这项新授权取代此前未授权提交/远端的状态，推送绑定将在核验目标后续记。

## 个人 GitHub 快照绑定（2026-09-20）

用户确认当前版本可用后要求“用 Git 推到个人仓库”。已通过现有 gh 登录核对个人账号 `ZYDTR`，创建 [ZYDTR/book-ask](https://github.com/ZYDTR/book-ask)，GitHub 返回 private=true、viewerPermission=ADMIN。远端为 `https://github.com/ZYDTR/book-ask.git`，本地仍为同一独立仓库，推送分支 main，无合并请求、公开发布或部署。

这是首次提交整个当前项目：源代码、脚本、测试和同仓脚手架/Delta文档作为版本快照；书籍、配置/凭据、用户词本、原始日志、应用备份与构建产物均排除。此前各节的 unborn/无远端是历史基线，不再代表推送后的状态。当前 Git SHA 用 `git rev-parse HEAD`、远端用 `git rev-parse origin/main` 核验；安装二进制哈希仍独立记录，不充当 commit SHA。

preflight 与最终提交/远端一致性回执保存在本机 `evidence/github_push_20260920/`。本次按用户已接受的当前版本做私人版本保存；TEST 中没有实测的全屏/多显示器项目仍明确保留，不扩展验收结论。

## paper_reading_ui 执行绑定

控制面与代码目录 `/Users/zhengyidi/yage/context-infrastructure/adhoc_jobs/book_ask`，当前工作目录/main，HEAD `8ea90000d3645d14e0de0221b8bd159c66087dec`。进入时保留 menu_bar_app 尚未提交的 README/索引/working/Info.plist生成/启动策略改动和对应Delta；不创建worktree、不撤销旧改动。完整修改前副本、diff与安装包在 `evidence/paper_ui_20260920/`。视觉按用户指定Skill执行，最终结果回写本Delta TEST；未自动授权新一轮Git推送。

暗色续增量绑定：2026-09-20，同一目录/main/HEAD 8ea90000…；进入时保留浅色重构和Dock改动。dd14c629…安装包及修改前源码位于 `evidence/paper_dark_20260920/`。默认跟随系统，菜单三态切换，验证与未覆盖边界统一见paper_reading_ui TEST；未提交或推送。

## wordbook_exact_cache 执行绑定

2026-09-20，控制面/代码/工作目录均为 `/Users/zhengyidi/yage/context-infrastructure/adhoc_jobs/book_ask`，main，HEAD `8ea90000d3645d14e0de0221b8bd159c66087dec`。保留既有Dock/浅暗UI全部dirty改动；安装基线d1bb424b…，源码/旧包/历史备份在evidence/wordbook_exact_cache_20260920。没有新建worktree或派发Agent；本轮不提交/推送。

## 第二次Git快照授权（2026-09-20）

用户接受当前8189ef9d…版本并明确要求先推送，再实施同窗词本。当前目录/main，对端仍为个人私有 `ZYDTR/book-ask`，fetch后未落后origin/main；本次快照包括已确认的菜单栏、浅暗纸面、精确词条缓存、相应测试及同仓Delta导航。书籍/本地词本/凭据/原始证据不入Git。现有测试与构建结果绑定当前源码，无后续代码变更；最新未覆盖边界保留在TEST。推送回执位于evidence/github_push_20260920_v2。
