# 读书提问项目

本项目仅本地私人使用。保留 Apple Books、原书和已有中文脚注。除用户模型 API 外软件免费。

- `src/` 放 Swift 应用；`scripts/` 放 Python 3 标准库工具与 shell 入口；`tests/` 放离线测试。
- 构建使用本机 Swift / AppKit，不依赖付费服务或额外包。
- 每个实施阶段更新 `docs/working.md`。仅在获得提交授权后分阶段 commit；禁止添加远端或发布。
- 密钥从既有私有凭据读取，配置仅保存 locator。不得输出、复制入源码或提交密钥。
- 测试通过需包含 Apple Books 内真实拖选、系统入口传递选区、Gemini Flash 实际回答和可继续追问的 UI 证据。
- 不用伪选区或固定回答冒充 E2E。API smoke test 与真正 UI 验收分别记录。
- 不改服务器、Books 数据库、输入法、豆包或其他全局快捷键。仅安装本项目用户级应用和服务入口。
