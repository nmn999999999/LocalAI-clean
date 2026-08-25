# LocalAI — iOS 本地 AI 聊天（GGUF · 液态玻璃）

完全离线运行的 iOS AI 聊天应用：

- **GGUF 模型本地推理**（llama.cpp / Metal GPU 加速，经 [LLM.swift](https://github.com/eastriverlee/LLM.swift)）
- **文本聊天**：多轮对话、流式输出、历史记录持久化
- **图片输入**：PhotosPicker 选图发送给多模态模型
- **Agent 工具调用**：计算器 / 时间 / UUID / 字数统计 / 文本转换，自动循环执行
- **模型管理**：内置 HuggingFace 目录下载、自定义 URL 下载、从「文件」导入自行下载的 `.gguf`
- **原生 UI**：SwiftUI + iOS 26 Liquid Glass（标签栏 / 按钮 / 输入栏玻璃效果）

## 环境要求

| 项 | 要求 |
|---|---|
| Xcode | 26.0+ |
| iOS 部署目标 | 27.0（液态玻璃 + 新 API） |
| 真机 | A15 及以上芯片体验最佳；≥6GB 内存设备建议 ≤3B 参数 Q4 模型 |
| 模拟器 | 可运行 UI，但无 Metal 加速，推理极慢 |

## 快速开始

### 方式 A：GitHub Actions 云端打包（Windows 无需 Mac）✅

> Swift/iOS 26 SDK 只存在于 macOS，本机无法编译。
> 本仓库已内置 `.github/workflows/build-ipa.yml`，用免费 macOS 云构建器产出 IPA：

```text
1. Fork / 推送本仓库到 GitHub
2. 仓库页 → Actions → "Build IPA" → Run workflow
3. 等待 ~5-10 分钟（首次需编译 llama.cpp，较慢）
4. 运行详情页 Artifacts → 下载 localai-ipa
   └── localai-unsigned.ipa（未签名）
5. Windows 上安装 Sideloadly（https://sideloadly.io）
   - 数据线连接 iPhone
   - 拖入 localai-unsigned.ipa
   - 输入你的 Apple ID → Start
   （7 天有效，免费账号；AltStore 同理）
```

**自动签名（可选）**：在仓库 Settings → Secrets 配置

| Secret | 说明 |
|---|---|
| `P12_BASE64` | 发布证书 base64（`base64 -w0 cert.p12`） |
| `P12_PASSWORD` | 导出证书时设置的密码 |
| `MOBILEPROVISION_BASE64` | 描述文件 base64 |
| `SIGN_IDENTITY` | 如 `Apple Distribution: 你的名字 (TEAMID)` |

配置后每次构建会额外产出 **localai-signed.ipa**，可直接通过 TrollStore /
企业签分发安装。

**第三方签名（公益签 / 企业签）**：`localai-unsigned.ipa` 可被任意证书签名。
上传到公益签渠道用其共享企业证书签出即可安装（免 Apple ID、无 7 天限制）。

> ⚠️ 共享证书存在随时掉签风险；请只让渠道签你上传的原始包，
> 警惕"已修改版"，必要时核对 SHA256 防止被替换为夹带广告的二次打包。

#### 实测可用渠道（2026-08-25 二次验证）

| 渠道 | 地址 | 状态 |
|---|---|---|
| ⭐ **免费证书汇总页** | `eqishare.com/certshare.html` | **当天更新（260825）**，链接需在页面底部评论任意内容后解锁 |
| 轻松签在线签名 | `sign.p12z.com/esign` | 🟢 配合上面证书签 IPA |
| 快易签 | `s.kyq1.cn` | 定制版内置测试证书 |
| 水果助手 | `dz.p12zs.cn` | 在线定制，支持 iOS26+ |
| ~~路灯 P12 系统~~ | ~~`udid.hccld.com`~~ | ❌ 已被撤销（2026-08 报告） |

> 掉签轮换规律：公共共享证书约每 1-4 周换一批；
> `certshare.html` 是最稳定的"新货入口"，B站搜「后厂村路灯 免费证书」有配套教程。

以上均为第三方公益/灰色渠道，时效性极强，仅作学习用途；
长期稳定方案仍是 Apple 开发者账号或爱思助手/Sideloadly 自签。

### 方式 B：本地 XcodeGen（有 Mac 时）

```bash
brew install xcodegen
cd LocalAI
xcodegen generate     # 生成 LocalAI.xcodeproj
open LocalAI.xcodeproj
```

### 方式 C：手动创建

1. Xcode → File → New → Project → **iOS App**
   - Product Name: `LocalAI`，Interface: **SwiftUI**，Language: Swift
   - Minimum Deployment: **iOS 27.0**
2. 删除模板生成的 `ContentView.swift` 与 `LocalAIApp.swift`
3. 将本仓库的 `LocalAI/` 文件夹拖入项目（勾选 Copy items if needed + Create groups）
4. File → Add Package Dependencies… 添加：
   ```
   https://github.com/eastriverlee/LLM.swift   (from: 0.14.0)
   ```
   选择产品 **LLM** 加入 App target
5. Target → Build Settings → 搜索 *Interop*：
   - **C++ and Objective-C Interoperability → C++/Objective-C++**（llama.cpp 必需）

## 使用流程

1. 「模型」页 → 选择推荐模型下载，或点右上角 **导入** 从「文件」App 导入自己下载的 `.gguf`
2. 点击 **加载**（首次加载大模型较慢，属正常现象）
3. 回到「聊天」页即可对话：
   - 📷 发送图片（需多模态模型，如 Gemma 3）
   - 🪄 开启 Agent 模式让模型调用工具
   - 「设置」页可调 temperature / top-k / top-p / 上下文长度与系统提示词

## 项目结构

```
LocalAI/
├── App/            入口 + 液态玻璃 TabView
├── Data/           ChatMessage / AIModelInfo / 工具定义
├── Services/       LLMService(引擎门面) LlamaSwiftEngine ModelManager ChatStore AgentService SettingsStorage
├── Views/
│   ├── Chat/       聊天页 / 消息气泡 / 会话列表
│   ├── ModelsTab/  模型下载与导入
│   └── Settings/   参数设置
└── Utilities/      GlassComponents（glassEffect 封装）
```

## 关键实现说明

- **液态玻璃标签栏**：iOS 26+ 用新 SDK 构建时 `TabView` 自动获得悬浮玻璃材质，
  另通过 `.tabBarMinimizeBehavior(.onScrollDown)` 在滚动时最小化。
- **自绘玻璃组件**：输入栏与 Agent 步骤条使用 `GlassEffectContainer` +
  `.glassEffect(.regular.interactive(), in: .capsule)`，按钮用 `.buttonStyle(.glass)`。
- **引擎隔离**：所有推理经 `LLMEngine` 协议封装；未添加 LLM.swift 时编译进
  `EchoEngine` 演示模式，保证工程开箱可运行。
- **工具调用解析**：向系统提示注入工具目录，容错解析模型输出的
  `{"name":..., "arguments":{...}}` JSON（含围栏代码块），最多循环 4 轮。

## 常见问题

| 现象 | 处理 |
|---|---|
| 加载后闪退 / OOM | 换更小量化（Q4_K_M→Q4_0）或 ≤2B 模型 |
| 模拟器卡死 | 用真机；模拟器无 GPU 加速 |
| 编译报 llama.cpp 头文件错误 | 未开启 C++/ObjC 互操作，见快速开始第 5 步 |
| SPM 解析失败（版本不存在） | 将 project.yml 中 `from: 0.14.0` 改为 LLM.swift 最新 release 版本号 |
| LLM.swift API 编译报错 | 库迭代较快，若 `preprocess/getCompletion` 签名有变，仅需调整 `LlamaSwiftEngine.swift` 单文件 |

## License

MIT
