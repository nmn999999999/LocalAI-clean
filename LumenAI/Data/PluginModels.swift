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
    /// 声明的权限：["network"]（联网，需授权）/ ["storage"]（模块本地存储）
    var permissions: [String]
    /// 远程设置界面（不换底包即可改变配置界面；JSON 声明式，App 渲染）
    var settingsUI: [RemoteUIGroup]?

    init(
        id: String,
        name: String,
        version: String,
        description: String,
        author: String? = nil,
        minAppVersion: String? = nil,
        permissions: [String] = [],
        settingsUI: [RemoteUIGroup]? = nil
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.description = description
        self.author = author
        self.minAppVersion = minAppVersion
        self.permissions = permissions
        self.settingsUI = settingsUI
    }

    // 旧存档/旧清单没有 permissions → 默认 []
    enum CodingKeys: String, CodingKey {
        case id, name, version, description, author, minAppVersion, permissions, settingsUI
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        version = try c.decode(String.self, forKey: .version)
        description = try c.decode(String.self, forKey: .description)
        author = try c.decodeIfPresent(String.self, forKey: .author)
        minAppVersion = try c.decodeIfPresent(String.self, forKey: .minAppVersion)
        permissions = try c.decodeIfPresent([String].self, forKey: .permissions) ?? []
        settingsUI = try c.decodeIfPresent([RemoteUIGroup].self, forKey: .settingsUI)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(version, forKey: .version)
        try c.encode(description, forKey: .description)
        try c.encodeIfPresent(author, forKey: .author)
        try c.encodeIfPresent(minAppVersion, forKey: .minAppVersion)
        try c.encode(permissions, forKey: .permissions)
        try c.encodeIfPresent(settingsUI, forKey: .settingsUI)
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
    var permissions: [String]?
    /// 模块灰度策略（可选）：命中灰度的设备才在市场看到该模块
    var gray: ModuleGrayPolicy?
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
