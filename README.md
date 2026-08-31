# LumenAI ✨

> **玻璃质感的本地 AI 聊天 · 完全离线可用 · 插件化可扩展**
> 原生 SwiftUI + iOS 26 Liquid Glass 打造，GGUF 本地推理 + 多 Provider 云端对话，App 内即可更新功能模块。

[![GitHub release](https://img.shields.io/badge/release-v0.3.47-blue)](https://github.com/nmn999999999/LumenAI/releases/latest)
[![License](https://img.shields.io/badge/license-MIT-green)](#license)
[![Platform](https://img.shields.io/badge/platform-iOS%2026+-black)]()

---

## 🚀 为什么是 LumenAI？

| | |
|---|---|
| 🧊 **液态玻璃 UI** | iOS 26 Liquid Glass 标签栏 / 卡片 / 输入栏，原生 SwiftUI，丝滑流畅 |
| 🔒 **本地推理** | llama.cpp + Metal GPU 加速，模型完全离线，数据不出设备 |
| ☁️ **云端随时切** | OpenAI / Gemini / Claude 多 Provider 流式对话，本地云端一键切换 |
| 🧩 **插件化** | **不换底包更新功能**：JS 插件 + 远程设置界面 + 模块市场，App 内一键装/更/卸 |
| 🤖 **Agent 模式** | 工具调用循环：计算 / 搜索 / 联网 / SSH / 沙盒 Shell / MCP，多轮思考自动执行 |
| 🌐 **多语言** | 中英双语界面，语音输入（ASR）+ 朗读（TTS） |
| 📦 **数据自由** | 备份 / 恢复 / S3 云备份 / QR 分享 / 灰度更新 |

---

## ✨ 功能总览

### 聊天
- 多轮对话 · 流式输出 · 思考块折叠（DeepSeek-R1 / Qwen3）
- Markdown 渲染（代码块 / 表格 / 公式样式）· 消息操作（重生成 / 编辑 / 删除 / 朗读）
- 图片输入（多模态模型）· AI 自动标题 · 全库/会话内搜索

### Agent 智能体
- 30+ 内置工具：计算器 / 时间 / 单位换算 / 进制 / 颜色 / 密码 / JSON / 网页搜索 / **SSH 远程执行** / **沙盒 Shell** / LZ4 / JWT 解码…
- MCP 协议接入外部工具服务器 · JS 插件扩展新工具
- 工具调用前**用户授权**（SSH / 网络 / MCP 默认需批准）

### 插件系统（不换包更新功能）
- 模块 = manifest.json + tools.js（JavaScriptCore 纯计算沙箱）
- **远程设置界面**：插件下发的配置卡片直接在设置页渲染，改配置不换包
- 模块市场：字符串 / 天气 / 汇率 / JSON / 颜色 / 随机 / 时间日期工具
- 灰度发布：按设备分桶小比例推送，稳定后全量

### 模型
- GGUF 目录下载（国内镜像）· 自定义 URL / 文件导入 · KV 缓存量化 · Metal 自动加速
- 小模型友好：Agent 模式限云端 / ≥3B 模型，自动适配提示词策略

---

## 📥 安装

1. 从 [Releases](https://github.com/nmn999999999/LumenAI/releases/latest) 下载 `LumenAI-*.ipa`
2. 用 **Sideloadly / AltStore / 全能签** 自签安装（免费 Apple ID 7 天有效）
3. 打开 App → 模型页下载 GGUF 模型 → 开始对话

> 或 [Fork 仓库](https://github.com/nmn999999999/LumenAI/fork) 走 GitHub Actions 云端打包

---

## 🏗️ 架构

```
LumenAI/
├── App/            # 入口 + 液态玻璃 TabView
├── Data/           # 模型 / 消息 / 工具定义 / 插件模型
├── Services/
│   ├── LLMService / LlamaSwiftEngine   # 推理引擎门面（本地 + 云端路由）
│   ├── Plugin/                          # JS 插件引擎 + 远程 UI + 模块市场
│   ├── MCP/                             # streamable HTTP MCP 客户端
│   ├── Cloud/                           # OpenAI / Gemini / Claude SSE 解码
│   └── …                               # ASR / TTS / S3 / 备份 / 搜索 / 更新
├── Views/          # 聊天 / 模型 / 服务 / 设置 / 插件
└── Utilities/      # 液态玻璃组件 / 本地化 / QR
```

**引擎隔离**：所有推理走 `LLMEngine` 协议，本地 GGUF 与云端 API 自动路由，互不干扰。

---

## 🔄 更新方式

- **App 本体**：设置页检查更新（GitHub Release + 灰度索引）
- **功能模块**：服务页 → 模块市场，App 内一键更新（不换包）
- **灰度发布**：`update/index.json` 配置比例，按设备稳定分桶

---

## 🧪 开发

```bash
brew install xcodegen
xcodegen generate   # 生成 LumenAI.xcodeproj
open LumenAI.xcodeproj
```

- 需要 Xcode 26+ / iOS 26 SDK / C++-ObjC 互操作
- 推理依赖 `llama.xcframework` 与 `ssh.xcframework`（由构建脚本产出）

---

## 📄 License

MIT
