# 模型速度和英文遵循实测

2026-09-20，本文件前半为真实模型 API 比较；后半追加用户确认交互方案后的实施验收。产品合同见 [PRD.md](PRD.md)，显示生命周期见 [RFC.md](RFC.md)。

## 测试合同

- 三个网关 ID：`gemini-3.7-flash`、`gemini-3.5-flash`、`deepseek-v4-flash`。4.1 仅列出 `deepseek-v4.1-flash-max`，用户明确排除后未调用。
- 每个模型相同五组：bulldozer、fragile、you’re liable to、The truth is down there somewhere, but it’s fragile.、can I run it by you?。
- 从 UserDefaults 读取用户当前保存的完整 Prompt；编译并执行实际 `ReadingContext.swift` 和 `ReadingPreferences.swift` 获取匹配结果和 system prompt。当前模板要求简单英文、单词提供音标及常见意思、短语或句子解释加新例句，不使用标题/列表/Markdown/中文。
- 对 `you’re liable to`，实际匹配器发现书中多处同表达，按生产逻辑不附上下文；其余四组使用所在段落及前后文。没有为测试另造更有利的提示词。
- 使用生产消息结构，`stream=true`、`max_tokens=1800`，不覆盖 temperature 或 reasoning 参数。Python urllib 直接访问 LAN 网关；不包括选区捕获、窗口渲染开销。90 秒总期限；超时/截断/流中断算失败，不静默重试。
- 15 次串行调用，每组轮换模型顺序，无预热。正文首字时间从请求开始到首个非空白 `delta.content`；推理字段不算正文。完整时间截至 `[DONE]` 并关闭响应。
- 人工逐条检查完整回答是否英文、单词是否提供 IPA、短语/句子是否解释含义及给同表达例句；格式遵循与语言遵循分开评价。

运行命令（会产生模型费用）：

```sh
python3 scripts/benchmark_models.py --run --output evidence/model_benchmark_20260920
```

证据保存在本机、Git 忽略的 [evidence/model_benchmark_20260920/](../../evidence/model_benchmark_20260920/)：`inputs.json` 为逐字提示词/上下文/源码指纹，`results.jsonl` 和逐次 JSON 保存时间、完整回答、结束原因及返回的模型 ID，逐次 `.sse.jsonl` 保存带接收时间的流。密钥仅在内存，不记录鉴权头；目录 0700、文件 0600。复跑需使用新的输出目录，避免覆盖证据。

## 当前结果

15/15 调用完整成功，均收到 `[DONE]`，`finish_reason=stop`，返回模型 ID 与请求一致；没有重试、超时或截断。4.1 Max 调用次数为零。

### 速度汇总

单位：秒。统计以五次中位数为主，同时保留范围；首字特指用户能看到的英文正文。

| 模型 | 首字中位数 | 完整中位数 | 首字范围 | 完整范围 | 英文 |
| --- | ---: | ---: | --- | --- | --- |
| gemini-3.7-flash | 2.73 | 3.14 | 2.19–3.07 | 2.57–3.40 | 5/5 |
| gemini-3.5-flash | 5.09 | 5.57 | 4.10–5.78 | 4.38–6.36 | 5/5 |
| deepseek-v4-flash | 6.42 | 7.32 | 2.72–9.88 | 4.02–10.29 | 5/5 |

Gemini 3.7 Flash 在五组的正文首字、完整时间均最快。本次五组下建议继续使用 3.7 Flash；3.5 更长、较慢，DeepSeek V4 波动较大。此为当前 LAN 网关、当前 Prompt、这五组输入的一轮结果，不能推断所有时段/地区/文本的普遍性能或模型真身。网关未返回 usage/cache 命中元数据，缓存和上游负载影响无法排除。

### 五组逐项比较

每格为“正文首字 / 完整回答”，秒。

| 选区 | Gemini 3.7 | Gemini 3.5 | DeepSeek V4 |
| --- | ---: | ---: | ---: |
| bulldozer | 3.07 / 3.40 | 5.78 / 6.16 | 9.88 / 10.29 |
| fragile | 2.97 / 3.35 | 5.09 / 5.57 | 8.71 / 9.23 |
| you’re liable to | 2.19 / 2.57 | 4.10 / 4.38 | 6.42 / 7.32 |
| The truth is down there somewhere, but it’s fragile. | 2.55 / 2.86 | 5.48 / 6.36 | 2.72 / 4.02 |
| can I run it by you? | 2.73 / 3.14 | 4.22 / 4.50 | 3.70 / 4.60 |

### 逐条正文人工检查

- `gemini-3.7-flash`：英文 5/5；两段 5/5；两组单词均含 IPA；三组短语/句子均解释含义并给出新例句。平均约 58 词。
- `gemini-3.5-flash`：英文 5/5；两段 5/5；两组单词均含 IPA；三组短语/句子均解释含义并给出新例句。平均约 79 词，较 3.7 冗长。
- `deepseek-v4-flash`：英文 5/5；两段 3/5：bulldozer 一段，fragile 三段；两组单词均含 IPA；三组短语/句子均有释义与例句，但常加 New example 等引导语。truth 一组还延展了原文考古比喻，直接程度稍弱。单词分支与模板总开头的“两段”存在语义张力，因此区分语言通过与严格格式偏差，不把单词缺例句直接判为错误。

DeepSeek V4 的五次 SSE 均含 reasoning_content，先于正文；当前 App 不显示该字段。本测试将这段等待计入首字时间，没有把推理首包当成回答出现，也没有人为改成关闭思考的不同配置。

人工检查确认三模型均无中文正文、无 Markdown 标题/项目列表；检查音标是否提供，不把该检查当作词典级 IPA 正确性验证。五组英文通过不构成所有输入稳定遵循的保证。

完整原始正文：[answers.md](../../evidence/model_benchmark_20260920/answers.md)；数值：[timings.csv](../../evidence/model_benchmark_20260920/timings.csv)；汇总与人工检查：[summary.json](../../evidence/model_benchmark_20260920/summary.json)。

### 边界

以上模型比较为 API 层 PASS，不代表 Books UI/全屏/选区链路验收；未切换生产模型。随后交互实现状态见下节。

## 收起交互实施验收（2026-09-20）

用户随后确认实现原建议，新增顶部可勾选的 15 秒收起。本节初次验收二进制 SHA-256：`511a5671e58ac1b50e18c3ad73161d303ecdebec3ab8cd42665deb72a406a178`；build 与安装版逐字相同，运行日志 buildID 一致。辅助功能授权通过原生系统设置恢复，运行 `accessibilityTrusted=true`。自动解释与 Copy 开关维持 true，用户 Prompt 逐字保持，模型配置未修改。计时复选框默认 false，测试后恢复 false。当前反侧定位增量见后续章节。

### 自动化回归与构建：PASS

`zsh scripts/test.sh` 整体退出 0，新增 `tests/reading_panel.swift` 已接入实际入口，编译真正 BookAsk 窗口与 ReadingPanelController。检查窗口实际可见性、事件返回同一对象、旧计时器/旧点击隔离、15 秒截止、取消勾选、交互取消、下一次重新计时、500 点宽按钮不截断，以及隐藏后草稿/对话/选区/request generation 不变。

回归来自用户“点 Books 没收起”的真实失败：offscreen AppKit 窗口出现后把外部点击交给实际 Controller，直接断言 `panel.isVisible=false`。反事实 `--old-no-outside-dismiss` 移除旧版缺失的处理，确定失败于 `clicking Books must actively hide the reading panel`，入口将该失败作为预期，证明回归可区分旧行为。它是组件回归，不等同于 OS 全局事件和真实 Books 鼠标集成测试。

既有剪贴板恢复/竞态、选区触发、横滚限制、词本和诊断检查均通过。构建无编译警告。没有因为应用尚未显示数据而伪造书中选区或固定模型回答。

### 最终安装版原生 UI 验收

| 项目 | 结果与直接证据 |
| --- | --- |
| 顶部勾选项、固定尺寸 | PASS。原生 AX 初始复选框 0，点击变 1；截图 500×539 内自动解释、15秒、词本、编辑提示词完整可见。 |
| 真实 15 秒超时 | PASS。UI 勾选后 scheduled UTC 03:22:20.253，timeout UTC 03:22:35.261，单调时钟间隔 15.008 秒，visibleAfter=false。此路径是“已显示时勾选”，新划词弹出的端到端计时仍待真实鼠标覆盖。 |
| 正在输入不会自动消失 | PASS。勾选重新计时后，在真实输入框键入草稿；03:23:28.890 记录 panel_interaction 取消计时，超过15秒后草稿仍在。测试草稿随后清除。 |
| Esc | PASS。原生 pressKey(Escape) 后日志 03:28:24.332 reason=escape、visibleAfter=false。 |
| 焦点离开 | PASS（已覆盖系统设置）。打开系统设置时记录 focus_left_panel，visibleAfter=false。 |
| Books 真实鼠标点击/拖选链路 | BLOCKED 于控制工具能力。Books CUA 点击、拖动改变了界面，但当前运行未收到对应 books_mouse_event/global mouse，因此不能据此断言实际新词弹出或 Books 点击收起通过；已发一次异步请求等待用户物理操作反馈。 |
| 收起时仍在生成、完成入词本且不重弹 | 源码/组件覆盖隐藏不取消任务，结束不调用showWindow且只有可见key窗口可恢复输入焦点；本轮真实 Books＋正在生成的完整UI场景未覆盖。 |
| 普通窗口/原生全屏分别完整验收 | 未覆盖，不能把计时与组件通过当作全屏或取词兼容性修复。 |

注意：CUA 在本应用没有显示窗口时，下一次 getAXState 可能引发 macOS reopen 并重新显示。日志明确记为 reason=reopen；确认隐藏以之前的 `window_dismissed.visibleAfter=false` 为准，不能把工具重新打开误判成应用定时弹回。

### 证据与剩余工作

本机证据目录 [popup_dismissal_20260920](../../evidence/popup_dismissal_20260920/)；源码/应用基线在 baseline/ 与 previous.app，构建与回归为 build_final.log、tests_final.log，运行关联为 runtime.jsonl，原生UI审阅为 ui_verification.json，安装/设置校验为 verification.json。修改文件及证据扫描没有实际 API Key。

此阶段为已安装候选，组件/计时/Esc验收通过；当时真实 Books 物理鼠标链路待用户反馈，不宣称完整E2E通过。此阶段未加入自动换边。后续用户确认与增量验收如下。

## 划词反侧定位与用户实机验收（2026-09-20）

当前安装版 SHA-256 `9ecd66c8ec83bc259165bcdde0e29662f67474c2808cf7cf34125da55a21e2fe`，与 build 一致；运行 ID `8EECD19D-2807-469A-88B5-88EE13A9B11E`，辅助功能 true。配置文件、用户 Prompt、自动解释、Copy、15秒选项均与本增量前一致。新增鼠标松开位置快照、Books 窗口中线判断、所选屏幕反侧定位；组件/全套回归与构建退出 0，无编译警告。

新增测试覆盖偏移 Books 窗口（不能误用屏幕中线）、左右两个方向、窗口边界缺失回退、负坐标外接屏及 Quartz/AppKit 转换；实际 BookAsk.finishCopyCapture 验证旧请求晚到/失败不得换位置，同词新手势换边仍保留草稿和请求 generation、不另起付费请求。

用户按真实划词试用后回复 **“it works”**。同一安装版运行日志提供以下对应证据，弥补之前 CUA 无法触发真实鼠标事件的缺口：

| 实际行为 | 直接证据（UTC） | 结果 |
| --- | --- | --- |
| Books 右半边划词 → 左上角 | 03:45:57.272 mouse-up x=1310.516，Books frame `{{0,0},{1728,1084}}`；captureID `BA5A9986-0947-4CDF-8F17-001D52450361`，接受151字符；03:45:57.686 panelFrame `{{0,545},{500,539}}`，scheduled/presented 的位置快照完全一致 | PASS |
| Books 左半边划词 → 右上角 | 03:46:03.723 mouse-up x=438.293，同一Books边界；captureID `B7D3A74C-C8DF-4063-A64C-7D64F5D0DA3B`，接受76字符；03:46:04.087 panelFrame `{{1228,545},{500,539}}`，位置快照一致 | PASS |
| 点回 Books 收起 | 首次窗口03:45:59.083记录 outside_click，source=global_mouse，foregroundApp=com.apple.iBooksX，visibleAfter=false | PASS |
| 收起后仍完成回答、不重新弹出 | 首个请求6.233秒完成，answer在03:46:03.921；完成前已隐藏，日志无完成导致的window_presented；之后的弹出关联第二个新captureID | PASS |
| 两次真实模型回答 | 两次请求gemini-3.7-flash，完成6.233秒/2.737秒，正文均英文；sampleID/requestID关联完整 | PASS |

当前已通过用户日常实机换边、Books外部点击、后台回答完成的验收。不能据此宣称原生全屏往返、实际多显示器和所有选区边界都已覆盖；多屏为组件坐标测试，当前实机只有一块屏幕。新划词启用15秒的完整物理操作未单独覆盖，计时与开关已有上一安装版原生UI和当前回归覆盖。

本地私有证据：[opposite_selection_20260920](../../evidence/opposite_selection_20260920/)：`baseline/`、`previous.app`、`baseline.json`、`implementation.diff`、`build.log`、`tests.log`、`runtime.jsonl`、`verification.json`。用户确认和两次采集/显示/回答链路存入verification，原始词句与回答留在本机，凭据扫描无泄露。
