#!/usr/bin/env python3
from pathlib import Path
import json
import sys

preview = sys.argv[2] == "--preview"
note = """读书提问 0.2.6

把「读书提问.app」拖入旁边的 Applications 文件夹，再从应用程序打开。
无需安装开发工具、运行脚本、注册账户或导入整本书。

首次使用：
1. 按使用指南，在系统设置的「隐私与安全性 → 辅助功能」中开启读书提问。
2. 打开 Apple Books，划选一个词或短句，点鼠标旁的「问 AI」。
3. 阅读解释，或继续输入问题。勾选「划词弹窗」后，划词即可显示浮窗。

菜单栏的「书问」可以重新打开窗口、词本和使用指南。
不需要按快捷键；关闭「划词弹窗」时，不点击「问 AI」就不会读取选区或发送给模型。
提问会将选区、问题与本轮对话发送到配置的模型服务；读取选区会临时复制并恢复剪贴板。
历史、词本与诊断保存在本机的 ~/Library/Application Support/BookAsk。
模型未配置、Key 失效、额度用完或网络不可用时，应用会显示错误。

构建目标：macOS 12 或更新版本，Apple Silicon 和 Intel。
包内包含两种架构；实际兼容性仍需在目标系统验证。
"""
if preview:
    note += """
这是未公证的内部预览包，不等同于已通过 Apple 验证的正式发行版。
首次打开可能被 macOS 拦截。确认来源后，可按 Apple 指引在系统设置中选择「仍要打开」：
https://support.apple.com/102445
无需关闭系统整体安全保护。

"""
profile = json.loads(Path(sys.argv[3]).read_text())
note += "\n此包使用公共试用服务，调用失败时会直接显示错误。\n" if profile.get("apiKey") else "\n此包未配置模型服务和试用 Key；划词后会显示服务未配置的错误。\n"
Path(sys.argv[1]).write_text(note, encoding="utf-8")
