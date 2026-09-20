# 纸感界面验收

最新暗色续增量见末节；下文dd14c629…为浅色阶段的历史验收。

基线与代码绑定见索引。保留已安装8b9947a9…及现有未提交Dock改动，备份在本机 `evidence/paper_ui_20260920/`。

## 当前实现与构建

安装二进制 `dd14c629c1d858d1a93951782728e038141e1ce3952354847522c83b87f3e26f` 与 build 一致。`PaperTheme.swift` 提供原创原生纸张/颜料绘制和保留NSButton语义的控件；`ReadingWindow.swift` 将主浮窗布局从取词/请求逻辑中分离，词本使用同一主题和分层富文本。保留前一轮accessory/LSUIElement改动。没有引入外部图片、字体、依赖或新权限类别。

`scripts/build.sh`、`scripts/test.sh` 均退出0，无编译警告。既有反事实失败仍为预期。新增 `reading_visual_layout.swift` 已接入入口，使用真实窗口和明确隔离的排版样例验证500/640/900点、提示词开合、长中英文/无空格URL、开关文字完整、原文与回答不重叠，以及展开后仍有可阅读的回答区域。旧选区、剪贴板恢复/竞态、反侧位置、收起/计时、词本解析与布局、日志回归均通过。

## 最终安装版原生界面

| 项目 | 结果与直接观察 |
| --- | --- |
| 纸面主窗500×539 | PASS。CUA实际截图可见暖白纸底、淡黄原文底、浅蓝节标题、绿灰开关、珊瑚色发送；系统深色外观下仍使用这套经过排版检查的浅色纸面。 |
| 提示词 | PASS。点击编辑后显示完整用户现有Prompt，能竖向滚动；再次点击收起，正文/输入控件未遮挡。没有覆盖用户Prompt。 |
| 原生开关语义 | PASS。AX自动解释1→0→1，15秒0→1→0，日志状态一致；自绘外观未替换成失去语义的图片。 |
| 输入、收起 | PASS。输入实际草稿后AX可读取，随后清空；04:36:29.994Z Escape记录visibleAfter=false；打开词本/系统设置时焦点收起正常。 |
| 真实词本 | PASS。读取既有28项，搜索fragile得到6项，点开fragile显示IPA、三次划词与历史追问；无结果提示和清空恢复通过。原始历史未迁移。 |
| 运行策略和配置 | PASS。activationPolicy=1、isUIElement=true、level=0；原辅助功能已恢复true，自动解释/Copy保持true，15秒测试后恢复false；Prompt及config文件逐字不变。 |
| 本轮真实Books新划词与新回答 | 未验证。CUA的Books拖动不进入OS全局事件监视器；已请求用户物理划选，尚无本二进制的真实capture/request链路。不把组件样例或旧词本回答当作本轮新问答成功。 |

工具首次从主窗切到词本时，一次取AX返回failure；下一次读取已显示正确词本，后续搜索/选择/截图均正常，这是窗口切换时的观察瞬态，未出现应用异常。关键视觉观察来自当前安装版的原生截图；本地components PNG是同源码离屏绘制，不冒充原生截图或真实回答。

## 风格与证据

纸感Skill的R1–R6视觉自检通过；R7界面已检查，真实新划词链路仍待用户实际操作，整体记为部分未验证。逐项依据见本机 [review.md](../../evidence/paper_ui_20260920/review.md)。字体实际解析为`.NewYork-Regular`与`.AppleSystemUIFont`，来源为macOS系统；中文/IPA字符同时通过原生截图检查。

证据目录 [paper_ui_20260920](../../evidence/paper_ui_20260920/) 包含baseline副本、previous.app、build.log、tests.log、components/、fonts.txt、runtime.jsonl、verification.json。组件文本仅用于布局验证；用户Prompt/模型配置与原历史保持原样。原始证据Git忽略。

当前状态：界面重构已安装，视觉与控件自检完成；真实新划词待反馈，用户尚未确认视觉风格。全屏/物理多屏等旧验收边界不因换样式而扩大。

视觉组件渲染使用明确标记的样例，不写入用户history、不调用模型。真实Books验收另记，无法自动触发物理拖选时明确保留限制。

## 暗色续增量（2026-09-20，当前安装版）

当前二进制 `d1bb424be28e9baa2e939b462a117c7531661372938ae53cd0aa2eab4eea9418`，build与安装路径哈希一致；源码/旧包/偏好备份位于 `evidence/paper_dark_20260920/`。外观独立存储paperAppearance，默认system；应用菜单和「书问」菜单提供跟随系统/浅色纸面/暗色纸面。动态颜色保留在普通/富文本属性内，纸张缓存绑定实际外观，切换不重建对话。

- `scripts/build.sh` 与完整 `scripts/test.sh` 均退出0，无编译警告；日志中的旧行为反事实FAIL为原测试入口预期。
- 新增真实AppKit离屏绘制验证：暗→浅→暗像素与纸张缓存确实改变；system模式随测试进程外观改变，窗口无需重开；偏好通过隔离UserDefaults套件验证重读；草稿/提示词/回答/请求generation/session保留。原500/640/900点、长中英/URL、提示词开合、禁止横向滚动检查继续通过。
- `components/` 中浅暗回答、空白、暗色展开提示词、流式/错误样张仅是离屏视觉样例，不调用API、不写history。暗色正文与底色计算对比度12.48:1、次要文字6.86:1、发送文字5.7:1；这是指定纯色的数值辅助检查，实际可读性另看真实渲染。
- 原生CUA验收通过：主窗500×539实际截图核对暗色；菜单切浅色/暗色后输入草稿仍在；自定义提示词展开/收起保持原文；实际词本32项，搜索crate返回4项，切换前后的选中crate和IPA/历史回答都保持，文字随主题正确重绘。清空测试草稿与词本过滤，提示词恢复收起。
- 正常退出/重新启动后仍为dark；原生日志05:40:07.807Z的window_policy记录appearance=dark、darkPaper=true；首次无配置的启动记录system且darkPaper=true。原生菜单实际选中两种纸面，系统外观动态跟随在隔离AppKit进程内测试，未改用户系统设置。
- Prompt、autoExplain、autoDismiss和copyCapture偏好与开始前逐项相同；凭据全文件扫描通过，build/安装哈希相同。未提交/推送Git。
- **权限已恢复**：用户回复done，2026-09-20T05:50:17.203Z的selection_monitor_state为accessibilityTrusted=true，Books observer已重新挂接，读取循环已继续；当前安装二进制仍为d1bb424b…。证据见permission_restored.json。这是权限/监听恢复证据，不冒充本包新的选词/API成功。
- 当前暗色二进制的新Books物理划词/API链路尚未验证；组件样例、旧词本回答与旧二进制成功不能替代此项。未修改取词/剪贴板/模型策略。
