# LocalAI SwiftUI 代码审查报告

**审查依据**:SwiftUI Skills 包(基于 Xcode 26.1 内置 Apple 官方文档)
**引用文档**:
- `SwiftUI-Implementing-Liquid-Glass-Design.md`
- `SwiftUI-New-Toolbar-Features.md`
- `Swift-Concurrency-Updates.md`
- `SwiftData-Class-Inheritance.md` / `StoreKit-Updates.md`(按需)

---

## Blockers(阻塞级)

**无。** 未发现会导致崩溃、数据丢失或不可用的问题。

---

## Major(重要,建议修复)

### M1. 输入框用 `.background(.regularMaterial)` 而非 `.glassEffect`
**位置**:`ChatView.swift:410`
```swift
.background(.regularMaterial, in: .rect(cornerRadius: 22))
```
**文档依据**:Liquid Glass 文档 "Adding Liquid Glass to a View"——标准做法是 `.glassEffect(.regular, in: .rect(cornerRadius: 16.0))`;Material 背景**不参与** Liquid Glass 系统(无 reflection / tint / interactive 能力),与左右 `.glass` 按钮是两套视觉体系。

**背景**:v0.3.12 曾因输入框与发送键"玻璃糊在一起"改成 Material。但文档 Best Practices #3 明确:**玻璃合并距离由 `GlassEffectContainer(spacing:)` 控制,而不是换材质**。正确解法是容器 spacing 调大(或 `glassEffectUnion` 分组),让输入框回到玻璃体系且保持独立岛。

**建议**:
```swift
TextField(...)
    .glassEffect(.regular, in: .rect(cornerRadius: 22))
// 容器:GlassEffectContainer(spacing: 24) // 拉开独立岛边界
```
⚠️ 需实测 spacing 值,避免回归 v0.3.12 的"粘一起"。

### M2. 工具岛/步骤 chips 多玻璃无容器
**位置**:`ChatView.swift:337`(展开工具岛 HStack)、`ChatView.swift:301`(agentStepsBar 的 chips)

agentStepsBar 每个 chip 单独 `.glassEffect(.regular, in: .capsule)` 且**不在 `GlassEffectContainer` 内**;展开工具岛的 4 个 `.glass` 按钮也在主容器 `GlassEffectContainer(spacing: 12)` **之外**。

**文档依据**:Best Practices #1 "**Always use `GlassEffectContainer` when applying Liquid Glass to multiple views** for better performance and morphing effects."

**建议**:三层分别用容器包裹:
```swift
// 工具岛(输入栏上方)
GlassEffectContainer(spacing: 10) {
    HStack(spacing: 10) { /* 4 个 .glass 按钮 */ }
}
// agentStepsBar
GlassEffectContainer(spacing: 8) {
    HStack(spacing: 8) { /* ForEach chips */ }
}
```

### M3. 搜索用自定义悬浮条,未用系统 `.searchable`
**位置**:`ChatView.swift:64-66, 206-234`(`showSearch` + `searchBar`)

**文档依据**:Toolbar 文档 "Enhanced Search Integration"——iOS 上推荐 `.searchable($searchText).searchToolbarBehavior(.minimize)`,搜索字段**折叠成按钮,点击展开**,节省一条常驻行;且 `DefaultToolbarItem(kind: .search, placement:)` 可重定位搜索入口。

**建议**:用系统搜索替换自定义 searchBar:
```swift
NavigationStack {
    messageList
        .searchable($searchText, isPresented: $showSearch, placement: .toolbar)
        .searchToolbarBehavior(.minimize)
        .searchPresentationToolbarBehavior(.avoidHidingContent)
}
```
保留现有 200ms 防抖 + `chatStore.search` 逻辑,结果展示改为 overlay 列表。

---

## Minor(次要)

### m1. `MainTabView` 编译期判断与注释过时
**位置**:`MainTabView.swift:3, 28`
注释写 "iOS 27+ 使用 Xcode 27 SDK 构建",但 deployment target 是 26.0;`#if swift(>=27.0)` 用 Swift 语言版本判断系统特性,应改为 `#if swift(>=6.2)` 或直接以 SDK availability 为准。若 `tabBarMinimizeBehavior` 在 Xcode 26 SDK 可用,可去掉 guard。

### m2. ToolCallChip / ThinkSection 用 Material 而非玻璃
**位置**:`MessageBubble.swift:287, 320`
```swift
.background(.ultraThinMaterial, in: .rect(cornerRadius: 14))
```
与 M1 同理,建议 `.glassEffect(.regular, in: .rect(cornerRadius: 14))`,并让外层消息气泡统一玻璃容器。

### m3. 图标按钮缺 accessibilityLabel
**位置**:`ChatView.swift` 输入栏 `[+]`/照片/Agent/搜索/麦克风/发送,以及 `MessageBubble` 操作按钮全部是 icon-only。
**文档依据**:reviewer 检查点 "Accessibility and user-facing behavior"。VoiceOver 用户听到的将是图标名或空白。
**建议**:每个 icon-only Button 加 `.accessibilityLabel("添加工具")` 等。

### m4. 主题系统只作用于 tint,页面背景未跟随
**位置**:`AppTheme.swift` + `ChatView.swift:73`
`.background(Color(.systemGroupedBackground))` 硬编码系统色,AppTheme 提供的 `bubbleBackgroundLight/Dark` 没被页面引用。主题切换时只有强调色变化,背景不变,视觉割裂。
**建议**:页面背景改为 `theme.current.bubbleBackgroundLight/Dark`(按 colorScheme 自动选)。

### m5. 消息列表 `simultaneousGesture(TapGesture)` 影响 VoiceOver
**位置**:`ChatView.swift:173`
全局 TapGesture 收起键盘,与 VoiceOver 逐条浏览可能冲突。建议限制为 `.highPriorityGesture` 之外,或判断 `accessibilityVoiceOverEnabled` 时跳过。

---

## Concurrency 复核(对照 Swift 6.2 并发更新文档)

- ✅ **ASRService** 的 `nonisolated static` 授权 + `Task { @MainActor }` 单次回跳,符合文档 "isolated conformance" 思路(已根治 v0.3.7/9/10 三次 trap)。
- ✅ **AgentService.run()** 的 `appendStep` 全程在 @MainActor 上下文,`bridge` closure 捕获 @State 均合法。
- ✅ **pendingApproval continuation** 只在主线程 resume(alert 按钮/消失回调),无数据竞争。
- ⚠️ **ToolCallAccumulator** 用 `NSLock` + `@unchecked Sendable`,文档建议 prefer actor 隔离;但 streamSSE 的 onJSON 是 nonisolated 上下文,NSLock 是务实妥协,已在注释说明。

---

## 结论

| 级别 | 数量 | 关键项 |
|---|---|---|
| Blocker | 0 | — |
| Major | 3 | M1 输入框玻璃还原、M2 玻璃容器包裹、M3 系统搜索 |
| Minor | 5 | m1-m5 见上 |
| Concurrency | 复核通过 | 无新增风险 |

**优先建议**:M1(玻璃一致性,但需实测 spacing 防回归)→ M3(搜索体验)→ M2(容器性能)。
