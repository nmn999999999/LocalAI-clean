import Foundation

// MARK: - JS 插件模型（manifest.json 结构）

/// 插件清单：模块元信息（每个模块一个文件夹，位于 Documents/Modules/<id>/）
struct PluginManifest: Codable, Sendable {
    var id: String
    var name: String
    var version: String
    var description: String
    var author: String?
    /// 最低 App 版本（如 "0.3.36"）；低于则提示升级 App
    var minAppVersion: String?

    init(
        id: String,
        name: String,
        version: String,
        description: String,
        author: String? = nil,
        minAppVersion: String? = nil
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.description = description
        self.author = author
        self.minAppVersion = minAppVersion
    }
}

/// 插件工具定义（由 tools.js 里 registerTool() 注册，App 读取后转成 AgentToolDefinition）
struct PluginToolDef: Codable, Sendable {
    var name: String
    var description: String
    var parameters: [String: PluginParam]

    init(name: String, description: String, parameters: [String: PluginParam] = [:]) {
        self.name = name
        self.description = description
        self.parameters = parameters
    }
}

struct PluginParam: Codable, Sendable {
    var type: String
    var description: String

    init(type: String = "string", description: String = "") {
        self.type = type
        self.description = description
    }
}

/// 远程模块索引条目（modules/index.json）
struct ModuleIndexEntry: Codable, Sendable, Identifiable {
    var id: String
    var name: String
    var version: String
    var description: String
    var author: String?
    var minAppVersion: String?
    /// 各文件的下载地址
    var files: ModuleFiles

    struct ModuleFiles: Codable, Sendable {
        var manifest: String
        var tools: String
    }
}

struct ModuleIndex: Codable, Sendable {
    var modules: [ModuleIndexEntry]
}

/// 模块更新状态（UI 用）
struct ModuleUpdate: Identifiable, Sendable {
    let entry: ModuleIndexEntry
    var id: String { entry.id }
    /// nil = 未安装；非 nil = 已安装版本
    let installedVersion: String?
    var hasUpdate: Bool { installedVersion != entry.version }
}
