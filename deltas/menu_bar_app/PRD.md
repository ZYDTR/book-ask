# 菜单栏常驻，移除 Dock 图标

2026-09-20 用户确认去掉程序坞中的应用图标，保留顶部「书问」作为显示浮窗、词本、自动解释、授权、诊断与退出入口。另提出大幅重做 UI 的可行性讨论，视觉重做尚未定稿，不包含在本次代码改动中。

## 行为和实现边界

- 使用 macOS accessory 应用模式，运行时不在 Dock 显示应用图标；Info.plist 标记 LSUIElement，避免启动时短暂出现普通应用图标。
- 浮窗、词本仍可交互和输入；保留划词反侧出现、区域外点击/Esc收起、可勾选15秒计时、自动解释、原Prompt、模型与本机历史。
- 沿用现有菜单栏入口，不修改取词、剪贴板事务、API、数据格式、窗口外观或全局快捷键。
- 启动日志记录实际 activationPolicy 和 LSUIElement，区分配置与运行结果。

## 验证与回滚

构建与既有回归检查窗口行为；安装版确认 accessory 实际生效、顶部菜单可打开词本/浮窗、输入可编辑，核对原权限及设置。真实 Books 新手势自动解释另以运行日志和实际操作验证，不能用启动成功代替。

本次基线为 main@8ea90000d3645d14e0de0221b8bd159c66087dec，工作区干净。安装基线9ecd66c8…备份在本机 `evidence/menu_bar_app_20260920/previous.app`；回退时正常退出应用，恢复该包并核对原辅助功能授权。代码提交历史可独立用于恢复源码。

## 当前验收

- `scripts/test.sh` 与 `scripts/build.sh` 均退出0；既有反事实测试预期失败仍正确触发。未为两项声明式设置增加镜像测试。
- 安装二进制 `8b9947a996b53084f1eb2a95dc8b71d4908c7797682ab223e668bc140595c177` 与 build 一致。安装包 LSUIElement=true，真实运行日志 window_policy activationPolicy=1（accessory）、isUIElement=true、普通窗口level=0、joinsAllSpaces=false。
- Prompt、自动解释、Copy、15秒选项及模型配置与基线一致。
- macOS 重新绑定原辅助功能权限时出现触控ID验证。已请用户本人完成；此时划词权限与最终UI验收仍待完成，不把运行策略检查当作完整划词通过。
- 证据位于本机 `evidence/menu_bar_app_20260920/` 的build.log、tests.log、runtime.jsonl、verification.json；未改模型调用或发送测试请求。

后续：用户已完成该次系统验证。随后纸感UI增量继承本变更，最新安装版dd14c629…已恢复原辅助功能，实际运行accessory/LSUIElement正确；输入、词本和收起的原生验证统一见 [paper_reading_ui TEST](../paper_reading_ui/TEST.md)。
