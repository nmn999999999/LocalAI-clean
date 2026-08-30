# kelivo 功能复现说明（LocalAI iOS 原生版）

> 项目：[Chevey339/kelivo](https://github.com/Chevey339/kelivo)（Flutter LLM Chat Client，约 1900 commits）
> 复现载体：本仓库的 **LocalAI** iOS 原生工程（SwiftUI + iOS 26 液态玻璃）
> 日期：2026-08-28 ｜ 版本对照：kelivo 1.2.4+68

## 一、总体思路

kelivo 是 Flutter 跨端 LLM 聊天客户端，核心价值是「**多 Provider + 流式 + 可配置**」。
本地工程原本只有「本地 GGUF 推理 + 单端点 OpenAI 兼容 API 模式」。
本次复现采用**原生 Swift 重写其功能层**，架构一一对应：

| kelivo（Flutter） | 本工程（Swift） |
|---|---|
| `StreamChunkDecoder`（Claude/Google/ChatCompletions/Responses 四解码器） | `CloudChatClient`（openAI / gemini / claude 三协议 SSE 解码器） |
| Provider 模型 + multi-key load balancing | `ChatProvider` + `ProviderStore.nextKey()` 轮换 |
| Custom Requests（自定义请求头/体） | `ChatProvider.headers` + `extraBody` 合并 |
| Custom Assistants | `AIAssistant` + `AssistantStore`（绑定 Provider/模型/温度） |
| gpt_markdown 渲染 | `MarkdownRenderer`（块级+内联，代码块/表格/LaTeX 样式/列表/引用） |
| Web Search（Bing/DDG 等） | 复用 `SearchService` + 发送前注入上下文 |
| Prompt Variables | `PromptVariableResolver`（{model} {provider} {date} {time} {datetime}） |
| QR Code Sharing | `QRCodeGenerator`（CIQRCode 生成/识别）+ `ProviderShareCodec` |
| Data Backup / Restore | `BackupService`（会话+Provider+助手 整体导出/恢复） |
| Voice / TTS Providers | `TTSService`（系统 AVSpeechSynthesizer + OpenAI 兼容网络 TTS） |
| MCP 支持 | `MCPClient`（streamable HTTP + JSON-RPC）+ `MCPService`（服务器管理/工具发现）+ Agent 工具目录 |
| ASR 语音输入 | `ASRService`（SFSpeechRecognizer 中英听写，输入栏麦克风按钮） |
| World Book / Memory / Instruction Injection | `PersonaStore`（世界观/长期记忆/指令，注入系统提示词）+ `PersonaView` |
| S3 备份 | `S3Client`（纯 Swift AWS SigV4 PUT/GET）+ 设置页上传/恢复 |
| Keep Screen On | 设置开关 + 生成时 `isIdleTimerDisabled` |
| 多语言（中/英） | `L10n` 词条表 + 设置页语言切换 |
| 消息操作（重新生成/编辑/删除/朗读） | `MessageBubble` 上下文菜单 + `ChatView` 动作 |

## 二、新增/改动文件清单

```
新增（第一批：多 Provider 核心）：
  LocalAI/Data/ChatProvider.swift             Provider 模型（类型/多Key/请求头/模型表）
  LocalAI/Data/AIAssistant.swift              自定义助手模型
  LocalAI/Services/ProviderStore.swift        Provider 存储（内置种子 + 旧设置迁移 + 轮换）
  LocalAI/Services/AssistantStore.swift       助手存储
  LocalAI/Services/Cloud/CloudChatClient.swift 三协议流式客户端（核心）
  LocalAI/Services/TTSService.swift           朗读服务
  LocalAI/Services/BackupService.swift        备份/恢复 + 系统分享 + 文件选择
  LocalAI/Services/PromptVariableResolver.swift 提示词变量
  LocalAI/Utilities/QRCodeGenerator.swift     QR 生成/识别 + Provider 导入导出编解码
  LocalAI/Utilities/Localization.swift        中英词条表
  LocalAI/Views/Chat/MarkdownRenderer.swift   Markdown 块级解析与渲染
  LocalAI/Views/Providers/ProvidersView.swift 服务页（Provider/助手/备份/QR）
  LocalAI/Views/Providers/ProviderEditSheet.swift
  LocalAI/Views/Providers/AssistantEditSheet.swift

新增（第二批：MCP / ASR / 人格 / S3 / 常亮）：
  LocalAI/Services/MCP/MCPClient.swift        MCP streamable HTTP + JSON-RPC 客户端
  LocalAI/Services/MCP/MCPService.swift       MCP 服务器管理 + Agent 工具目录
  LocalAI/Views/Providers/MCPServerEditSheet.swift  MCP 服务器编辑 + 工具调用测试
  LocalAI/Services/ASRService.swift           语音输入（SFSpeechRecognizer）
  LocalAI/Services/PersonaStore.swift         世界观/记忆/指令 存储与注入
  LocalAI/Views/Settings/PersonaView.swift    人格与记忆编辑页
  LocalAI/Services/S3Client.swift             纯 Swift AWS SigV4 S3 客户端

改动：
  LocalAI/Data/AIModelInfo.swift       ModelSettings 增加 14 个字段（搜索/TTS/语言/常亮/人格/S3，旧存档兼容）
  LocalAI/Services/LLMService.swift    新增云路由（hasCloudSelection/streamCloud/completeCloud/makeCloudMessages）
  LocalAI/Services/ChatStore.swift     新增 restoreFromBackup
  LocalAI/Services/AgentService.swift  工具分发支持 MCP（内置未命中 → MCPService）
  LocalAI/Views/Chat/ChatView.swift    模型/助手选择、联网搜索、语音输入、消息操作、人格注入、屏幕常亮
  LocalAI/Views/Chat/MessageBubble.swift Markdown 渲染 + 操作菜单
  LocalAI/Settings/SettingsView.swift  语言/朗读/联网搜索/变量/常亮/人格入口/S3 卡片
  LocalAI/App/MainTabView.swift        新增「服务」Tab
  project.yml                          新增语音识别/麦克风权限描述（Info.plist）
```

## 三、功能对照（已复现 ✅ / 说明 ⏳）

| kelivo 功能 | 状态 | 说明 |
|---|---|---|
| 多 Provider（OpenAI/Gemini/Claude/兼容） | ✅ | 三种协议流式 SSE 解码，内置 8 个 Provider 种子 |
| 多 Key 负载均衡 | ✅ | 逗号分隔多 Key，请求轮换 |
| 自定义请求头/请求体 | ✅ | 编辑表单 JSON 输入，body 合并时保护核心字段 |
| 自定义助手 | ✅ | 名称/emoji/系统提示词/绑定 Provider+模型/温度覆盖 |
| Markdown 渲染 | ✅ | 标题/加粗/斜体/行内代码/代码块(复制)/表格/列表/引用/分隔线/LaTeX 样式 |
| 多模态图片输入 | ✅ | 原有 PhotosPicker + 云协议 base64 编码 |
| 流式输出 + 思考块 | ✅ | 三种协议流式；DeepSeek reasoning_content → `<think>` 块 |
| 提示词变量 | ✅ | 系统提示词与用户输入均可使用 5 个变量 |
| Web 搜索 | ✅ | 输入栏开关 + 设置自动搜索；Bing→DDG→维基 链路 |
| QR 分享/导入 | ✅ | 导出 QR（分享/复制文本）；相册扫码导入 |
| 数据备份/恢复 | ✅ | 导出含会话+Provider+助手；恢复前二次确认 |
| TTS 朗读 | ✅ | 系统 TTS + 网络 TTS（OpenAI 兼容 /audio/speech），气泡菜单朗读 |
| **MCP 工具协议** | ✅ | streamable HTTP + JSON-RPC（initialize/tools/list/call）；服务页管理/连接/工具列表/调用测试；工具注入 Agent 目录由对话循环执行（本地与云端模型通用） |
| **ASR 语音输入** | ✅ | SFSpeechRecognizer 中英听写，输入栏麦克风按钮实时转写（权限描述已加） |
| **世界观 / 记忆 / 指令注入** | ✅ | 设置页「人格与记忆」管理三类条目，按开关注入系统提示词 |
| **S3 备份** | ✅ | 纯 Swift AWS SigV4（PUT/GET），兼容 MinIO/COS/OSS；设置页一键上传/恢复 |
| **生成时保持屏幕常亮** | ✅ | 设置开关 + 生成期间 isIdleTimerDisabled |
| 中英双语 | ✅ | 设置切换；新界面全量词条，旧界面中文为主 |
| 重新生成/编辑/删除 | ✅ | 长按消息气泡菜单 |
| 对话搜索 | ✅ | 原有全库/会话内搜索 |
| 后台生成/系统托盘 | ⏳ | 桌面端特性；iOS 已用屏幕常亮替代 |
| 世界观自动记忆抽取 | ⏳ | 手动维护 + 注入已实现；模型自动总结提炼记忆未做（可后续加 pipeline） |

## 四、构建与运行

```bash
brew install xcodegen        # 若未安装
xcodegen generate            # 重新生成 LocalAI.xcodeproj（新增文件自动纳入）
open LocalAI.xcodeproj       # 选择真机运行
```

- 云端对话：**「服务」页** → 添加/选择 Provider → 填 API Key → 聊天页右上角选「Provider · 模型」
- 旧版设置里的 API 端点/密钥/模型会在首次启动时自动迁移为一个「自定义 API（旧设置）」Provider
- 本地 GGUF 对话与原有 Agent 工具模式不受影响（未选中云 Provider 时自动走本地）

## 五、工程说明

- 编译验证：`xcodebuild -project LocalAI.xcodeproj -scheme LocalAI -destination 'generic/platform=iOS' build CODE_SIGNING_ALLOWED=NO`
- xcframework（llama/ssh）仅含真机 arm64 切片，模拟器构建需自行补切片
- 密钥仅存本机（Documents/UserDefaults），备份导出时包含 Provider 配置，注意保管
