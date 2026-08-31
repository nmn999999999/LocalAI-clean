import Foundation

/// 嵌入式 Shell 沙箱(iOS 限定在 app 沙盒内的受限 shell)
/// 不依赖真实 `/bin/sh` —— iOS 没有 shell 二进制可调用。本沙箱:
/// - 解析简单 shell 命令(支持 `;` 串联 / `|` 管道 / `>` `>>` 重定向 / `&&` `||` 链)
/// - 路径解析限定在 `appHome/shellbox/` 子树下,任何命令访问越界路径一律转回沙箱根
/// - 内置 18 个核心命令(文件/文本/系统)
/// - 通配符 `*` `?` 在参数展开时支持
///
/// 用法:`ShellSandbox.run("ls -l *.txt | head -5")` 即可串起命令链。
enum ShellSandbox {

    /// 沙箱根目录:app 沙盒下独立子目录,跟其它模块隔离
    static let sandboxRoot: String = {
        let docs = NSHomeDirectory() + "/Documents"
        let root = docs + "/shellbox"
        try? FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
        return root
    }()

    /// 当前工作目录(每次 process 重置;AgentService 跨调用可保留)
    nonisolated(unsafe) static var cwd: String = sandboxRoot

    /// 简单会话环境(export 写入的变量)
    nonisolated(unsafe) static var env: [String: String] = [
        "HOME": sandboxRoot,
        "USER": "mobile",
        "PWD": sandboxRoot,
        "SHELL": "LumenAI-SandboxShell",
        "PATH": "/bin:/usr/bin"  // 虚拟 PATH,本沙箱内置命令等价于"在 PATH 中"
    ]

    /// 命令历史(v0.3.19:history 命令读取;重复命令去重,上限 200)
    nonisolated(unsafe) static var history: [String] = []

    /// 同步入口:执行一条 shell 命令字符串,返回标准输出
    static func run(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        // 支持 && 和 || 链(简单优先匹配)
        let segments = splitByChaining(trimmed)
        var output = ""
        var lastExit = 0
        for seg in segments {
            let (cond, body) = seg
            // 0=success, !=0=fail
            let shouldRun: Bool
            switch cond {
            case .none:    shouldRun = true
            case .and:     shouldRun = (lastExit == 0)
            case .or:      shouldRun = (lastExit != 0)
            }
            if shouldRun {
                let res = execSegment(body)
                output += res.text
                lastExit = res.exitCode
            }
        }
        return output
    }

    private enum ChainCond { case none, and, or }

    /// 切分 `cmd1 && cmd2 || cmd3`:在 "&&" 和 "||" 处断开,保留连接符。
    private static func splitByChaining(_ s: String) -> [(ChainCond, String)] {
        var out: [(ChainCond, String)] = []
        var current = ""
        var pending: ChainCond = .none
        var i = s.startIndex
        while i < s.endIndex {
            // 检查 &&
            if s[i...].hasPrefix("&&") {
                out.append((pending, current.trimmingCharacters(in: .whitespaces)))
                current = ""
                pending = .and
                i = s.index(i, offsetBy: 2)
                continue
            }
            if s[i...].hasPrefix("||") {
                out.append((pending, current.trimmingCharacters(in: .whitespaces)))
                current = ""
                pending = .or
                i = s.index(i, offsetBy: 2)
                continue
            }
            current.append(s[i])
            i = s.index(after: i)
        }
        if !current.trimmingCharacters(in: .whitespaces).isEmpty {
            out.append((pending, current.trimmingCharacters(in: .whitespaces)))
        }
        return out
    }

    /// 执行一段 `cmd1 ; cmd2 ; cmd3`(按顺序,失败也继续)
    private static func execSegment(_ seg: String) -> (text: String, exitCode: Int) {
        // 先 tokenize 让 ; 和 | 提前分离,然后按 ; 切分执行(每段走 executeSubPart 处理 | 与 重定向)
        let tokens = tokenize(seg)
        guard !tokens.isEmpty else { return ("", 0) }
        // 按 ; 切分
        var segments: [[String]] = [[]]
        for t in tokens {
            if t == ";" {
                segments.append([])
            } else {
                segments[segments.count - 1].append(t)
            }
        }
        var lastText = ""
        var lastExit = 0
        for s in segments where !s.isEmpty {
            let r = executePipeline(s)
            lastText = r.text
            lastExit = r.exitCode
        }
        return (lastText, lastExit)
    }

    /// 处理一段形如 `cmd1 | cmd2 | cmd3`(单段内可能有重定向 `>` `>>`)
    private static func executePipeline(_ tokens: [String]) -> (text: String, exitCode: Int) {
        // tokens 已被 tokenize:遇到 > 或 >> 后跟文件名识别为重定向
        // 简化:把整个 pipeline 当若干 subCommand 串接(每个 | 切)
        var groups: [[String]] = [[]]
        for t in tokens {
            if t == "|" {
                groups.append([])
            } else {
                groups[groups.count - 1].append(t)
            }
        }
        var current = ""
        var exitCode = 0
        for (idx, g) in groups.enumerated() where !g.isEmpty {
            let r = executeSingle(g, stdin: (idx == 0 ? "" : current))
            current = r.text
            exitCode = r.exitCode
        }
        return (current, exitCode)
    }

    /// 单条命令:处理 `>` `>>` 重定向
    private static func executeSingle(_ tokens: [String], stdin: String) -> (text: String, exitCode: Int) {
        // 寻找 > / >>
        var argv = tokens
        var redirect: (path: String, append: Bool)? = nil
        if let rIdx = argv.firstIndex(where: { $0 == ">" || $0 == ">>" }),
           rIdx + 1 < argv.count {
            redirect = (argv[rIdx + 1], argv[rIdx] == ">>")
            argv.removeSubrange(rIdx..<min(rIdx + 2, argv.count))
        }
        let result = dispatch(tokens: argv, stdin: stdin)
        if let rd = redirect {
            let resolved = resolvePath(rd.path)
            do {
                if rd.append {
                    let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: resolved))
                    try handle.seekToEnd()
                    if let data = result.text.data(using: .utf8) {
                        try handle.write(contentsOf: data)
                    }
                    try handle.close()
                } else {
                    try (result.text).write(toFile: resolved, atomically: true, encoding: .utf8)
                }
            } catch {
                return (result.text + "（重定向到 \(resolved) 失败: \(error.localizedDescription)）", 1)
            }
        }
        return result
    }

    /// 真正分派:从已 tokenize 的 argv 数组展开通配符,调用对应 builtin
    private static func dispatch(tokens: [String], stdin: String) -> (text: String, exitCode: Int) {
        // 取出环境变量 $VAR 替换(只支持 $FOO, 不支持 ${FOO})
        let expanded = tokens.map { expandEnvVars($0) }
        guard let cmd = expanded.first, !cmd.isEmpty else { return ("", 0) }
        var args = Array(expanded.dropFirst())

        // 展开通配符 * ?
        args = args.flatMap { arg -> [String] in
            if arg.contains("*") || arg.contains("?") {
                let matches = globExpand(arg)
                return matches.isEmpty ? [arg] : matches
            }
            return [arg]
        }

        return execBuiltin(cmd, args: args, stdin: stdin)
    }

    /// 内置命令分派
    private static func execBuiltin(_ cmd: String, args: [String], stdin: String) -> (text: String, exitCode: Int) {
        // 记录 history(重复命令去重,上限 200)
        if !cmd.isEmpty && cmd != "history" {
            history.append(cmd + (args.isEmpty ? "" : " " + args.joined(separator: " ")))
            if history.count > 200 { history.removeFirst(history.count - 200) }
        }
        switch cmd {
        case "ls":       return lsCmd(args)
        case "cat":      return catCmd(args, stdin: stdin)
        case "pwd":      return (cwd + "\n", 0)
        case "echo":     return (args.joined(separator: " ") + "\n", 0)
        case "mkdir":    return mkdirCmd(args)
        case "rm":       return rmCmd(args)
        case "cp":       return cpCmd(args)
        case "mv":       return mvCmd(args)
        case "head":     return headTailCmd(args, tail: false, stdin: stdin)
        case "tail":     return tailCmd(args, stdin: stdin)
        case "wc":       return wcCmd(args, stdin: stdin)
        case "grep":     return grepCmd(args, stdin: stdin)
        case "sort":     return sortCmd(args, stdin: stdin)
        case "uniq":     return uniqCmd(args, stdin: stdin)
        case "date":     return (formatDate() + "\n", 0)
        case "whoami":   return ("mobile\n", 0)
        case "env":      return (env.map { "\($0.key)=\($0.value)" }.joined(separator: "\n") + "\n", 0)
        case "export":   return exportCmd(args)
        case "cd":       return cdCmd(args)
        case "stat":     return statCmd(args)
        case "true":     return ("", 0)
        case "false":    return ("", 1)
        // v0.3.19 新增 POSIX 化命令
        case "sed":      return sedCmd(args, stdin: stdin)
        case "awk":      return awkCmd(args, stdin: stdin)
        case "find":     return findCmd(args)
        case "history":  return historyCmd(args)
        case "tr":       return trCmd(args, stdin: stdin)
        case "cut":      return cutCmd(args, stdin: stdin)
        case "touch":    return touchCmd(args)
        case "tee":      return teeCmd(args, stdin: stdin)
        case "basename": return basenameCmd(args)
        case "dirname":  return dirnameCmd(args)
        case "du":       return duCmd(args)
        case "lz4":      return lz4Cmd(args, stdin: stdin)
        case "clear":    return ("", 0)
        case "help", "--help", "-h":
            return (helpText(), 0)
        default:
            return ("未知命令: \(cmd)\n(输入 help 查看支持列表)\n", 127)
        }
    }

    // MARK: - lz4 (LZ4 压缩/解压, 内置纯 Swift 块编解码器)

    private static func lz4Cmd(_ args: [String], stdin: String) -> (text: String, exitCode: Int) {
        guard let flag = args.first else { return (lz4Help(), 2) }
        switch flag {
        case "-i":
            // 内存压缩演示:生成一段可压缩文本,演示 LZ4.Box 内存容器
            var sample = ""
            for i in 0..<400 {
                sample += "LumenAI 会话 #\(i) | 用户: 帮我压缩这段数据 | 助手: LZ4 内存压缩演示内容。"
            }
            let box = LZ4.Box(Data(sample.utf8))
            let pct = String(format: "%.1f%%", (1 - Double(box.compressed.count) / Double(box.originalSize)) * 100)
            let ratio = String(format: "%.2fx", Double(box.originalSize) / Double(max(box.compressed.count, 1)))
            return ("""
            内存压缩演示 (LZ4.Box):
              原文 \(box.originalSize)B → 压缩后 \(box.compressed.count)B
              节省 \(box.savedBytes)B, 压缩率 \(pct) (\(ratio))
            """, 0)

        case "-c", "-d":
            let compress = flag == "-c"
            let srcArg = args.count >= 2 ? args[1] : nil
            let dstArg = args.count >= 3 ? args[2] : nil
            // 输入:文件或 stdin
            var input = Data()
            var fromStdin = false
            if let srcRaw = srcArg {
                let p = resolvePath(srcRaw)
                guard let d = FileManager.default.contents(atPath: p) else {
                    return ("lz4: 无法读取 \(srcRaw)\n", 1)
                }
                input = d
            } else if !stdin.isEmpty {
                input = Data(stdin.utf8)
                fromStdin = true
            } else {
                return ("lz4: 缺少输入(文件参数或 stdin)\n", 2)
            }
            let result: Data
            var stats: String
            if compress {
                result = LZ4.compress(input)
                let r = String(format: "%.2fx", Double(input.count) / Double(max(result.count, 1)))
                stats = "压缩: \(input.count)B → \(result.count)B (\(r))"
            } else {
                guard let d = LZ4.decompress(input) else {
                    return ("lz4: 解压失败(输入不是有效的 LZ4 块)\n", 1)
                }
                result = d
                stats = "解压: \(input.count)B → \(d.count)B"
            }
            // 输出路径:显式 dst > 默认(压缩=.lz4 后缀;解压=去 .lz4 后缀)
            let dst: String
            if let dstRaw = dstArg {
                dst = resolvePath(dstRaw)
            } else if fromStdin {
                dst = resolvePath(compress ? "stdin.lz4" : "stdin.out")
            } else if compress {
                dst = resolvePath(srcArg! + ".lz4")
            } else {
                let s = srcArg!
                dst = resolvePath(s.hasSuffix(".lz4") ? String(s.dropLast(4)) : s + ".out")
            }
            do {
                try result.write(to: URL(fileURLWithPath: dst))
                return (stats + " → \(dst)\n", 0)
            } catch {
                return ("lz4: 写入 \(dst) 失败: \(error.localizedDescription)\n", 1)
            }

        case "-v":
            guard args.count >= 2 else { return ("lz4: 缺少文件参数\n", 2) }
            let p = resolvePath(args[1])
            guard let d = FileManager.default.contents(atPath: p) else {
                return ("lz4: 无法读取 \(args[1])\n", 1)
            }
            let c = LZ4.compress(d)
            let r = d.count > 0 ? String(format: "%.2fx", Double(d.count) / Double(max(c.count, 1))) : "-"
            return ("\(args[1]): \(d.count)B → LZ4 \(c.count)B (\(r))\n", 0)

        default:
            return (lz4Help(), 2)
        }
    }

    private static func lz4Help() -> String {
        return """
        lz4: LZ4 压缩/解压(内置纯 Swift LZ4 块编解码器, 无外部依赖)
          用法:
            lz4 -c <src> [dst]   压缩文件(默认 dst=src+.lz4)
            lz4 -d <src> [dst]   解压文件(默认去掉 .lz4 后缀)
            lz4 -c [dst]         压缩 stdin(管道输入)
            lz4 -v <file>        查看压缩统计
            lz4 -i               内存压缩演示(LZ4.Box)
        """
    }

    // MARK: - 工具方法

    /// 把 `~/foo` 解析为 sandboxRoot/foo;把相对路径解析为 cwd 下
    private static func resolvePath(_ raw: String) -> String {
        if raw == "~" { return sandboxRoot }
        if raw.hasPrefix("~/") {
            return sandboxRoot + String(raw.dropFirst(2))
        }
        if raw.hasPrefix("/") {
            // 绝对路径也限制在 sandboxRoot:越界路径重映射到 sandboxRoot
            if raw.hasPrefix(sandboxRoot) { return raw }
            // 拒绝越界并落到 sandboxRoot
            return sandboxRoot + raw
        }
        return (cwd as NSString).appendingPathComponent(raw)
    }

    /// `$FOO` 和 `$` 全部展开为 env 中的值(找不到则原样保留)
    private static func expandEnvVars(_ s: String) -> String {
        var out = s
        // 先展开 $FOO
        let pattern = #"\$([A-Za-z_][A-Za-z0-9_]*)"#
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let matches = regex.matches(in: out, range: NSRange(location: 0, length: (out as NSString).length)).reversed()
            for m in matches {
                guard let r = Range(m.range, in: out), r.lowerBound < out.endIndex else { continue }
                var name = ""
                if m.numberOfRanges > 1, let nameR = Range(m.range(at: 1), in: out) {
                    name = String(out[nameR])
                }
                if let val = env[name] {
                    out.replaceSubrange(r, with: val)
                }
            }
        }
        // 展开 ~ 引用
        out = out.replacingOccurrences(of: "~", with: sandboxRoot)
        return out
    }

    /// 极简 tokenize:支持 "双引号" 与 '单引号';`;`、`<`、`>`、`|` 单独成 token;
/// `&&`、`||` 也单独成 token。其余按空白切分。
    private static func tokenize(_ s: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inQuote: Character? = nil
        var i = s.startIndex
        while i < s.endIndex {
            let ch = s[i]
            // 检测 `&&` 和 `||` 优先
            if inQuote == nil, i < s.index(s.endIndex, offsetBy: -1, limitedBy: s.startIndex) ?? s.endIndex {
                // 简化检测:在 i 处向前看 2 字符
                let next = s.index(after: i)
                if next < s.endIndex {
                    let two = "\(s[i])\(s[next])"
                    if two == "&&" || two == "||" {
                        if !current.isEmpty { result.append(current); current = "" }
                        result.append(two)
                        i = s.index(after: next)
                        continue
                    }
                }
            }
            if let q = inQuote {
                if ch == q {
                    inQuote = nil
                    if !current.isEmpty { result.append(current); current = "" }
                } else {
                    current.append(ch)
                }
            } else if ch == "\"" || ch == "'" {
                inQuote = ch
            } else if ch.isWhitespace || ch == ";" || ch == "|" || ch == "<" {
                // ;、|、< 单独作 token
                if ch == ";" || ch == "|" || ch == "<" {
                    if !current.isEmpty { result.append(current); current = "" }
                    result.append(String(ch))
                } else {
                    if !current.isEmpty {
                        result.append(current)
                        current = ""
                    }
                }
            } else if ch == ">" {
                // > 与 >> 都识别为单一 token
                if !current.isEmpty { result.append(current); current = "" }
                let next = s.index(after: i)
                if next < s.endIndex && s[next] == ">" {
                    result.append(">>")
                    i = s.index(after: next)
                    continue
                } else {
                    result.append(">")
                }
            } else {
                current.append(ch)
            }
            i = s.index(after: i)
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    /// 简单 glob 展开:对传入 pattern(可含通配符)列出 sandboxRoot/cwd 下匹配的文件名。
    private static func globExpand(_ pattern: String) -> [String] {
        // 只在 sandboxRoot 内 glob
        let baseDir = (cwd as NSString).appendingPathComponent("")
        let regex = globToRegex(pattern)
        guard let r = try? NSRegularExpression(pattern: regex) else { return [] }
        var matches: [String] = []
        let fm = FileManager.default
        if let entries = try? fm.contentsOfDirectory(atPath: baseDir) {
            for e in entries {
                let full = NSRange(location: 0, length: (e as NSString).length)
                if r.firstMatch(in: e, range: full) != nil {
                    matches.append(e)
                }
            }
        }
        return matches
    }

    /// 把 glob 模式转成正则
    private static func globToRegex(_ p: String) -> String {
        var out = "^"
        for ch in p {
            switch ch {
            case "*": out += ".*"
            case "?": out += "."
            case ".", "+", "(", ")", "[", "]", "{", "}", "|", "^", "$", "\\":
                out += "\\\(ch)"
            default: out += String(ch)
            }
        }
        out += "$"
        return out
    }

    private static func formatDate() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss zzz"
        return f.string(from: Date())
    }

    private static func helpText() -> String {
        return """
        LumenAI Shell 沙箱命令列表 (v0.3.19 POSIX 扩展)
        ------------------
        文件/目录:
          ls [-l|-a] [path]       列出文件
          cat <file...>           输出文件内容(支持 stdin)
          mkdir [-p] <dir>        创建目录
          rm [-r] <path>          删除文件或目录
          cp <src> <dst>          复制
          mv <src> <dst>          移动
          touch <file>            创建空文件 / 更新时间戳
          find [-name PAT] [dir]  递归查找(按名称匹配;省略 -name 列出全部)
          du [-h] [path]          目录/文件占用空间
          pwd                     当前工作目录
          cd <dir>                切换(默认回 sandboxRoot)
          stat <path>             文件元数据
          basename <path>         取文件名部分
          dirname <path>          取目录部分

        文本:
          head [-n N] [file]      前 N 行(默认 10)
          tail [-n N] [file]      后 N 行(默认 10)
          wc [-l|-w|-c] [file]    行/词/字符数
          grep [-i] <pattern>     包含 pattern 的行
          sort [-r|-u]            排序(支持 stdin)
          uniq                    去重(相邻)
          sed 's/旧/新/[g]' [file] 文本替换(支持 stdin)
          awk '{print $1,$2}'     字段处理($1..$n,默认空格分隔)
          tr <set1> <set2>        字符替换/删除
          cut -d: -f1 <file>      按分隔符取字段

        系统:
          echo <args...>          回显
          date                    当前日期时间
          whoami                  当前用户名
          env                     列出环境变量
          export K=V              设置环境变量
          history                 查看命令历史
          tee <file>              输出同时写入文件
          true / false            始终成功 / 失败
          clear                   清屏(占位)
          lz4 -c/-d <src> [dst]   LZ4 压缩/解压(内置纯 Swift 实现)
          lz4 -i                  内存压缩演示 / lz4 -v <file> 压缩统计
          help                    本帮助

        语法:
          ; 顺序执行  && 成功才继续  || 失败才继续
          | 管道     > / >> 重定向
          ~/path    沙盒根目录下路径
          $VAR      展开已 export 的变量
          * ?       通配符展开到当前目录文件
        """
    }

    // MARK: - builtin 实现

    private static func lsCmd(_ args: [String]) -> (text: String, exitCode: Int) {
        var detailed = false
        var all = false
        var target = cwd
        for a in args {
            switch a {
            case "-l": detailed = true
            case "-a": all = true
            case "-la", "-al": detailed = true; all = true
            default: target = resolvePath(a)
            }
        }
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: target) else {
            return ("ls: 无法访问 \(target)\n", 1)
        }
        var lines: [String] = []
        var display = entries
        if !all { display = display.filter { !$0.hasPrefix(".") } }
        for e in display.sorted() {
            let p = (target as NSString).appendingPathComponent(e)
            if detailed {
                let attrs = (try? fm.attributesOfItem(atPath: p)) ?? [:]
                let size = (attrs[.size] as? Int) ?? 0
                let mtime = (attrs[.modificationDate] as? Date) ?? Date()
                let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm"; f.locale = Locale(identifier: "en_US_POSIX")
                lines.append(String(format: "%8d  %@  %@", size, f.string(from: mtime), e))
            } else {
                lines.append(e)
            }
        }
        return (lines.joined(separator: "\n") + "\n", 0)
    }

    private static func catCmd(_ args: [String], stdin: String) -> (text: String, exitCode: Int) {
        if args.isEmpty {
            return (stdin, stdin.isEmpty ? 1 : 0)
        }
        var out = ""
        for f in args {
            let p = resolvePath(f)
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: p)) else {
                return ("cat: \(f): 无法读取\n", 1)
            }
            out += String(data: data, encoding: .utf8) ?? ""
        }
        return (out, 0)
    }

    private static func mkdirCmd(_ args: [String]) -> (text: String, exitCode: Int) {
        let recursive = args.contains("-p")
        let paths = args.filter { $0 != "-p" }.map { resolvePath($0) }
        for p in paths {
            do {
                if recursive {
                    try FileManager.default.createDirectory(atPath: p, withIntermediateDirectories: true)
                } else {
                    try FileManager.default.createDirectory(atPath: p, withIntermediateDirectories: false)
                }
            } catch {
                return ("mkdir: \(p): \(error.localizedDescription)\n", 1)
            }
        }
        return ("", 0)
    }

    private static func rmCmd(_ args: [String]) -> (text: String, exitCode: Int) {
        let recursive = args.contains("-r") || args.contains("-rf") || args.contains("-fr")
        let paths = args.filter { !($0.hasPrefix("-")) }.map { resolvePath($0) }
        let fm = FileManager.default
        for p in paths {
            // 安全:禁止删除沙盒根
            if p == sandboxRoot || p == NSHomeDirectory() {
                return ("rm: 拒绝删除沙盒根目录 \(p)\n", 1)
            }
            do {
                let isDir = (try? fm.attributesOfItem(atPath: p)[.type] as? FileAttributeType) == .typeDirectory
                if isDir {
                    if recursive {
                        try fm.removeItem(atPath: p)
                    } else {
                        return ("rm: \(p): 是目录(需要 -r)\n", 1)
                    }
                } else {
                    try fm.removeItem(atPath: p)
                }
            } catch {
                return ("rm: \(p): \(error.localizedDescription)\n", 1)
            }
        }
        return ("", 0)
    }

    private static func cpCmd(_ args: [String]) -> (text: String, exitCode: Int) {
        guard args.count >= 2 else { return ("cp: 需要 src dst 两个参数\n", 1) }
        let src = resolvePath(args[0])
        let dst = resolvePath(args[1])
        let fm = FileManager.default
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: dst, isDirectory: &isDir), isDir.boolValue {
            // 复制到目录内:dst/basename(src)
            let base = (src as NSString).lastPathComponent
            let final = (dst as NSString).appendingPathComponent(base)
            do { try fm.copyItem(atPath: src, toPath: final) } catch {
                return ("cp: \(error.localizedDescription)\n", 1)
            }
        } else {
            do { try fm.copyItem(atPath: src, toPath: dst) } catch {
                return ("cp: \(error.localizedDescription)\n", 1)
            }
        }
        return ("", 0)
    }

    private static func mvCmd(_ args: [String]) -> (text: String, exitCode: Int) {
        guard args.count >= 2 else { return ("mv: 需要 src dst 两个参数\n", 1) }
        let src = resolvePath(args[0])
        let dst = resolvePath(args[1])
        let fm = FileManager.default
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: dst, isDirectory: &isDir), isDir.boolValue {
            let base = (src as NSString).lastPathComponent
            let final = (dst as NSString).appendingPathComponent(base)
            do { try fm.moveItem(atPath: src, toPath: final) } catch {
                return ("mv: \(error.localizedDescription)\n", 1)
            }
        } else {
            do { try fm.moveItem(atPath: src, toPath: dst) } catch {
                return ("mv: \(error.localizedDescription)\n", 1)
            }
        }
        return ("", 0)
    }

    private static func headTailCmd(_ args: [String], tail: Bool, stdin: String) -> (text: String, exitCode: Int) {
        // 解析 [-n N] [file...]
        var n = 10
        var files: [String] = []
        var i = 0
        while i < args.count {
            if args[i] == "-n", i + 1 < args.count, let v = Int(args[i+1]) {
                n = v; i += 2
            } else if args[i].hasPrefix("-n") {
                if let v = Int(String(args[i].dropFirst(2))) { n = v }
                i += 1
            } else {
                files.append(args[i]); i += 1
            }
        }
        // 来源:优先 file,否则 stdin
        var text: String = ""
        if !files.isEmpty {
            let p = resolvePath(files[0])
            text = (try? String(contentsOfFile: p, encoding: .utf8)) ?? ""
        } else {
            text = stdin
        }
        let lines = text.components(separatedBy: "\n")
        let picked: [String] = tail ? Array(lines.suffix(n)) : Array(lines.prefix(n))
        return (picked.joined(separator: "\n") + "\n", 0)
    }

    // MARK: - v0.3.19 POSIX 化新增命令

    /// tail 独立(支持 stdin 管道,当 stdin 有内容且无文件参数时作用在 stdin 上)
    private static func tailCmd(_ args: [String], stdin: String) -> (text: String, exitCode: Int) {
        return headTailCmd(args, tail: true, stdin: stdin)
    }

    /// sed 文本替换:支持 `s/旧/新/[g]` 与 `d`(删除匹配行)
    private static func sedCmd(_ args: [String], stdin: String) -> (text: String, exitCode: Int) {
        guard let expr = args.first else { return ("sed: 缺少表达式\n", 1) }
        let files = Array(args.dropFirst())
        var text = stdin
        if !files.isEmpty {
            text = (try? String(contentsOfFile: resolvePath(files[0]), encoding: .utf8)) ?? ""
        }
        var lines = text.components(separatedBy: "\n")

        // 匹配 s/pattern/repl/[g]
        if expr.hasPrefix("s/") {
            // 解析 s/pat/repl/[flags] — 支持转义 \/
            var rest = expr.dropFirst(2)
            var pattern = ""
            var replacement = ""
            var current: String = ""
            var inPattern = true
            while let ch = rest.popFirst() {
                if ch == "/" {
                    if inPattern {
                        pattern = current
                        current = ""
                        inPattern = false
                    } else {
                        replacement = current
                        current = ""
                        break
                    }
                } else if ch == "\\", rest.first == "/" {
                    current.append("/")
                    rest.popFirst()
                } else {
                    current.append(ch)
                }
            }
            if pattern.isEmpty && replacement.isEmpty && !current.isEmpty {
                replacement = current
            }
            let global = rest.contains("g")
            let ignoreCase = rest.contains("i")
            // 用 NSRegularExpression 支持 \d \w 等
            var regex: NSRegularExpression?
            if ignoreCase {
                regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            } else {
                regex = try? NSRegularExpression(pattern: pattern)
            }
            if regex == nil { regex = try? NSRegularExpression(pattern: NSRegularExpression.escapedPattern(for: pattern)) }
            var out: [String] = []
            for line in lines {
                if let re = regex {
                    let ns = line as NSString
                    let range = NSRange(location: 0, length: ns.length)
                    if global {
                        out.append(re.stringByReplacingMatches(in: line, range: range, withTemplate: replacement))
                    } else if let m = re.firstMatch(in: line, range: range) {
                        var newLine = (line as NSString).replacingCharacters(in: m.range, with: replacement)
                        // 只替换第一个
                        out.append(newLine)
                    } else {
                        out.append(line)
                    }
                } else {
                    if global {
                        out.append(line.replacingOccurrences(of: pattern, with: replacement))
                    } else if line.contains(pattern) {
                        if let r = line.range(of: pattern) {
                            out.append(line.replacingCharacters(in: r, with: replacement))
                        } else { out.append(line) }
                    } else {
                        out.append(line)
                    }
                }
            }
            return (out.joined(separator: "\n") + "\n", 0)
        }

        // 匹配 /pattern/d — 删除匹配行
        if expr.hasPrefix("/"), expr.hasSuffix("/d") {
            let pattern = String(expr.dropFirst().dropLast(2))
            var regex: NSRegularExpression?
            regex = try? NSRegularExpression(pattern: pattern)
            var out: [String] = []
            for line in lines {
                let ns = line as NSString
                let full = NSRange(location: 0, length: ns.length)
                if let re = regex, re.firstMatch(in: line, range: full) == nil {
                    out.append(line)
                } else if !line.contains(pattern) {
                    out.append(line)
                }
            }
            return (out.joined(separator: "\n") + "\n", 0)
        }
        return ("sed: 不支持的表达式 \(expr)(支持 s/旧/新/g 与 /pattern/d)\n", 1)
    }

    /// awk 字段处理:支持 `{print $1,$2}`、`{print $NF}`、`-F<分隔符>`
    private static func awkCmd(_ args: [String], stdin: String) -> (text: String, exitCode: Int) {
        var fs = " "
        var files: [String] = []
        var program = ""
        for a in args {
            if a.hasPrefix("-F"), a.count > 2 {
                fs = String(a.dropFirst(2))
            } else if a.hasPrefix("{") || a.hasPrefix("print") {
                program = a
            } else if !a.hasPrefix("-") {
                files.append(a)
            }
        }
        if program.isEmpty { return ("awk: 缺少程序\n", 1) }
        var text = stdin
        if !files.isEmpty {
            text = (try? String(contentsOfFile: resolvePath(files[0]), encoding: .utf8)) ?? ""
        }
        var out: [String] = []
        for rawLine in text.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            var fields = line.components(separatedBy: fs).map { $0.trimmingCharacters(in: .whitespaces) }
            // 特殊:awk 默认空白分隔(1+ 空白),空字段剔除
            if fs == " " { fields = line.split(whereSeparator: { $0.isWhitespace }).map(String.init) }
            // 构建变量替换:$1..$n, $NF, $0
            var result = program
            result = result.replacingOccurrences(of: "$0", with: line)
            result = result.replacingOccurrences(of: "$NF", with: fields.last ?? "")
            for (i, f) in fields.enumerated() {
                result = result.replacingOccurrences(of: "$\(i + 1)", with: f)
            }
            // 执行 print 表达式
            if result.contains("print") {
                let body = result.replacingOccurrences(of: "print", with: "")
                var cleaned = body
                    .replacingOccurrences(of: "{", with: "")
                    .replacingOccurrences(of: "}", with: "")
                    .trimmingCharacters(in: .whitespaces)
                // $n 替换完可能残留裸字段名 → 直接按原样输出
                if cleaned.hasPrefix(",") { cleaned = String(cleaned.dropFirst()) }
                if cleaned.hasPrefix(";") { cleaned = String(cleaned.dropFirst()) }
                out.append(cleaned.isEmpty ? line : cleaned)
            } else {
                out.append(result)
            }
        }
        return (out.joined(separator: "\n") + "\n", 0)
    }

    /// find 递归查找:find [dir] [-name PATTERN]
    private static func findCmd(_ args: [String]) -> (text: String, exitCode: Int) {
        var dir = cwd
        var pattern: String?
        var i = 0
        while i < args.count {
            if args[i] == "-name", i + 1 < args.count {
                pattern = args[i + 1]
                i += 2
            } else if !args[i].hasPrefix("-") {
                dir = resolvePath(args[i])
                i += 1
            } else {
                i += 1
            }
        }
        let fm = FileManager.default
        var results: [String] = []
        // 递归遍历(限制深度 6 防止海量输出)
        func walk(_ path: String, depth: Int) {
            guard depth <= 6 else { return }
            guard let entries = try? fm.contentsOfDirectory(atPath: path) else { return }
            for e in entries.sorted() {
                let full = (path as NSString).appendingPathComponent(e)
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: full, isDirectory: &isDir) {
                    // 名称匹配
                    if let pat = pattern {
                        if matchesGlob(e, pattern: pat) {
                            results.append(relativePath(full))
                        }
                    } else {
                        results.append(relativePath(full))
                    }
                    if isDir.boolValue {
                        walk(full, depth: depth + 1)
                    }
                }
            }
        }
        walk(dir, depth: 0)
        return (results.joined(separator: "\n") + (results.isEmpty ? "" : "\n"), 0)
    }

    /// history 命令
    private static func historyCmd(_ args: [String]) -> (text: String, exitCode: Int) {
        let limit = args.first.flatMap { Int($0) } ?? 20
        let recent = history.suffix(limit)
        var out = ""
        var idx = max(0, history.count - recent.count)
        for h in recent {
            out += "\(idx)  \(h)\n"
            idx += 1
        }
        return (out, 0)
    }

    /// tr 字符替换/删除:tr 'ab' 'AB'(替换) tr -d 'x'(删除)
    private static func trCmd(_ args: [String], stdin: String) -> (text: String, exitCode: Int) {
        var deleteMode = false
        var sets: [String] = []
        for a in args {
            if a == "-d" { deleteMode = true }
            else { sets.append(a) }
        }
        var text = stdin
        if sets.count == 2, !deleteMode {
            // 替换
            let from = sets[0], to = sets[1]
            var out = ""
            for ch in text {
                if let idx = from.firstIndex(of: ch) {
                    let offset = from.distance(from: from.startIndex, to: idx)
                    let targetIdx = to.index(to.startIndex, offsetBy: min(offset, to.count - 1))
                    out.append(to[targetIdx])
                } else {
                    out.append(ch)
                }
            }
            return (out + "\n", 0)
        } else if deleteMode, let set = sets.first {
            var out = ""
            for ch in text where !set.contains(ch) {
                out.append(ch)
            }
            return (out + "\n", 0)
        }
        return ("tr: 用法 tr 'set1' 'set2' 或 tr -d 'set'\n", 1)
    }

    /// cut 按分隔符取字段:cut -d: -f1,3 <file>
    private static func cutCmd(_ args: [String], stdin: String) -> (text: String, exitCode: Int) {
        var delimiter = "\t"
        var fields: Set<Int> = []
        var files: [String] = []
        var i = 0
        while i < args.count {
            if args[i] == "-d", i + 1 < args.count {
                delimiter = args[i + 1]; i += 2
            } else if args[i] == "-f", i + 1 < args.count {
                for part in args[i + 1].split(separator: ",") {
                    if let n = Int(part) { fields.insert(n) }
                }
                i += 2
            } else if !args[i].hasPrefix("-") {
                files.append(args[i]); i += 1
            } else {
                i += 1
            }
        }
        var text = stdin
        if !files.isEmpty {
            text = (try? String(contentsOfFile: resolvePath(files[0]), encoding: .utf8)) ?? ""
        }
        if fields.isEmpty { fields = [1] }
        var out: [String] = []
        for rawLine in text.components(separatedBy: "\n") {
            guard !rawLine.isEmpty else { continue }
            let parts = rawLine.components(separatedBy: delimiter)
            let picked = fields.sorted().compactMap { n in
                n >= 1 && n <= parts.count ? parts[n - 1] : nil
            }
            out.append(picked.joined(separator: delimiter))
        }
        return (out.joined(separator: "\n") + "\n", 0)
    }

    /// touch 创建空文件 / 更新时间戳
    private static func touchCmd(_ args: [String]) -> (text: String, exitCode: Int) {
        for f in args {
            let p = resolvePath(f)
            if FileManager.default.fileExists(atPath: p) {
                do {
                    try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: p)
                } catch { return ("touch: \(f): \(error.localizedDescription)\n", 1) }
            } else {
                if !FileManager.default.createFile(atPath: p, contents: nil) {
                    return ("touch: \(f): 创建失败\n", 1)
                }
            }
        }
        return ("", 0)
    }

    /// tee 输出同时写入文件
    private static func teeCmd(_ args: [String], stdin: String) -> (text: String, exitCode: Int) {
        var files: [String] = []
        for a in args where !a.hasPrefix("-") {
            files.append(a)
        }
        for f in files {
            do {
                try stdin.write(toFile: resolvePath(f), atomically: true, encoding: .utf8)
            } catch {
                return (stdin + "\n(tee: 写入 \(f) 失败: \(error.localizedDescription))", 1)
            }
        }
        return (stdin, 0)
    }

    /// basename:取路径最后一段
    private static func basenameCmd(_ args: [String]) -> (text: String, exitCode: Int) {
        guard let p = args.first else { return ("basename: 缺少参数\n", 1) }
        return ((p as NSString).lastPathComponent + "\n", 0)
    }

    /// dirname:取目录部分
    private static func dirnameCmd(_ args: [String]) -> (text: String, exitCode: Int) {
        guard let p = args.first else { return ("dirname: 缺少参数\n", 1) }
        let dir = (p as NSString).deletingLastPathComponent
        return ((dir.isEmpty ? "." : dir) + "\n", 0)
    }

    /// du 目录/文件占用空间
    private static func duCmd(_ args: [String]) -> (text: String, exitCode: Int) {
        var humanReadable = false
        var target = cwd
        for a in args {
            if a == "-h" || a == "-sh" { humanReadable = true }
            else if a == "-s" { /* 忽略 */ }
            else if !a.hasPrefix("-") { target = resolvePath(a) }
        }
        let fm = FileManager.default
        var total: Int64 = 0
        func sizeOf(_ path: String) -> Int64 {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: path, isDirectory: &isDir) else { return 0 }
            var size: Int64 = 0
            if isDir.boolValue {
                if let entries = try? fm.contentsOfDirectory(atPath: path) {
                    for e in entries {
                        size += sizeOf((path as NSString).appendingPathComponent(e))
                    }
                }
            } else {
                size = (try? fm.attributesOfItem(atPath: path)[.size] as? Int64) ?? 0
            }
            return size
        }
        total = sizeOf(target)
        let label: String
        if humanReadable {
            label = ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
        } else {
            label = "\(total) bytes"
        }
        return ("\(label)\t\(relativePath(target))\n", 0)
    }

    /// glob 匹配辅助
    private static func matchesGlob(_ name: String, pattern: String) -> Bool {
        let regexStr = globToRegex(pattern)
        guard let re = try? NSRegularExpression(pattern: regexStr) else { return name == pattern }
        let ns = name as NSString
        return re.firstMatch(in: name, range: NSRange(location: 0, length: ns.length)) != nil
    }

    /// 相对路径显示:把 sandboxRoot 前缀替换为 ~
    private static func relativePath(_ path: String) -> String {
        if path.hasPrefix(sandboxRoot) {
            return "~/" + String(path.dropFirst(sandboxRoot.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        return path
    }

    private static func wcCmd(_ args: [String], stdin: String) -> (text: String, exitCode: Int) {
        var showLines = true; var showWords = true; var showChars = true
        var files: [String] = []
        for a in args {
            switch a {
            case "-l": showWords = false; showChars = false
            case "-w": showLines = false; showChars = false
            case "-c": showLines = false; showWords = false
            default: files.append(a)
            }
        }
        var text = stdin
        if !files.isEmpty {
            text = (try? String(contentsOfFile: resolvePath(files[0]), encoding: .utf8)) ?? ""
        }
        let lineCount = text.isEmpty ? 0 : text.components(separatedBy: "\n").count
        let wordCount = text.split(whereSeparator: { $0.isWhitespace }).count
        let charCount = text.count
        var parts: [String] = []
        if showLines { parts.append("\(lineCount)") }
        if showWords { parts.append("\(wordCount)") }
        if showChars { parts.append("\(charCount)") }
        let label = files.first ?? ""
        return (parts.joined(separator: " ") + " " + label + "\n", 0)
    }

    private static func grepCmd(_ args: [String], stdin: String) -> (text: String, exitCode: Int) {
        var ignoreCase = false
        var pattern = ""
        var files: [String] = []
        for a in args {
            if a == "-i" { ignoreCase = true }
            else if pattern.isEmpty { pattern = a }
            else { files.append(a) }
        }
        if pattern.isEmpty { return ("grep: 缺少 pattern\n", 1) }
        var text = stdin
        if !files.isEmpty {
            text = (try? String(contentsOfFile: resolvePath(files[0]), encoding: .utf8)) ?? ""
        }
        var hits: [String] = []
        for line in text.components(separatedBy: "\n") {
            let matches = ignoreCase
                ? line.lowercased().contains(pattern.lowercased())
                : line.contains(pattern)
            if matches { hits.append(line) }
        }
        return (hits.joined(separator: "\n") + "\n", hits.isEmpty ? 1 : 0)
    }

    private static func sortCmd(_ args: [String], stdin: String) -> (text: String, exitCode: Int) {
        let reverse = args.contains("-r")
        let unique  = args.contains("-u")
        let files = args.filter { !$0.hasPrefix("-") }
        var text = stdin
        if !files.isEmpty {
            text = (try? String(contentsOfFile: resolvePath(files[0]), encoding: .utf8)) ?? ""
        }
        var lines = text.components(separatedBy: "\n").filter { !$0.isEmpty || true }
        lines.sort()
        if reverse { lines.reverse() }
        if unique {
            var seen: [String] = []
            for l in lines where !seen.contains(l) { seen.append(l) }
            lines = seen
        }
        return (lines.joined(separator: "\n") + "\n", 0)
    }

    private static func uniqCmd(_ args: [String], stdin: String) -> (text: String, exitCode: Int) {
        let files = args.filter { !$0.hasPrefix("-") }
        var text = stdin
        if !files.isEmpty {
            text = (try? String(contentsOfFile: resolvePath(files[0]), encoding: .utf8)) ?? ""
        }
        var last = ""
        var out: [String] = []
        for l in text.components(separatedBy: "\n") where l != last {
            out.append(l); last = l
        }
        return (out.joined(separator: "\n") + "\n", 0)
    }

    private static func exportCmd(_ args: [String]) -> (text: String, exitCode: Int) {
        var changed = false
        for a in args {
            if let eq = a.firstIndex(of: "=") {
                let k = String(a[..<eq])
                let v = String(a[a.index(after: eq)...])
                env[k] = v
                changed = true
            }
        }
        return ("", changed ? 0 : 1)
    }

    private static func cdCmd(_ args: [String]) -> (text: String, exitCode: Int) {
        let target = args.first ?? "~"
        let p = resolvePath(target)
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: p, isDirectory: &isDir), isDir.boolValue {
            cwd = p
            env["PWD"] = p
            return ("", 0)
        } else {
            return ("cd: \(target): 不是目录\n", 1)
        }
    }

    private static func statCmd(_ args: [String]) -> (text: String, exitCode: Int) {
        guard let f = args.first else { return ("stat: 缺少文件\n", 1) }
        let p = resolvePath(f)
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: p) else {
            return ("stat: 无法访问 \(p)\n", 1)
        }
        let size = (attrs[.size] as? Int) ?? 0
        let mtime = (attrs[.modificationDate] as? Date).map { String(describing: $0) } ?? "?"
        let isDir = (attrs[.type] as? FileAttributeType) == .typeDirectory
        return ("文件: \(p)\n大小: \(size) 字节\n修改时间: \(mtime)\n类型: \(isDir ? "目录" : "文件")\n", 0)
    }

    /// 重置沙箱(测试用):cwd 回 root、env 不动
    static func reset() {
        cwd = sandboxRoot
        env["PWD"] = sandboxRoot
    }
}
