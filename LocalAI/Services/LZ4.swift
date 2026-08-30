import Foundation

/// 纯 Swift 实现的 LZ4 块格式编解码器（无外部依赖）。
///
/// 遵循 LZ4 block format 公开规范（https://github.com/lz4/lz4/blob/dev/doc/lz4_Block_format.md），
/// 可与系统 Compression 框架（COMPRESSION_LZ4）及其它 LZ4 实现互操作。
///
/// 用途：
/// - 会话存档 / 备份的 LZ4 压缩持久化（BackupService）
/// - 沙盒 shell 的 `lz4` 命令（ShellSandbox）
/// - 内存中大数据块的压缩暂存（LZ4.Box）
public enum LZ4 {

    public static let maxOffset = 65535

    // MARK: - 压缩

    public static func compress(_ src: Data) -> Data {
        let n = src.count
        guard n > 0 else { return Data() }
        var out: [UInt8] = []
        out.reserveCapacity(n + n / 8 + 64)

        var table = [Int32](repeating: -1, count: 1 << 16)  // 4 字节序列 hash → 最近位置
        var litStart = 0
        var i = 0
        // LZ4 规范硬约束（供标准解码器安全解码）：
        // - MFLIMIT=12：只在距块尾 ≥12 字节处搜索匹配（解码器 wild-copy 安全余量）
        // - LASTLITERALS=5：最后 5 字节必须是字面量，块必须以纯字面量序列收尾
        //   （参考解码器在 match 后会继续读下一个 token，块尾是 match 会越界）
        let mflimit = n - 12
        let lastLimit = n - 5

        while i < n {
            var matchPos = -1
            var matchLen = 0
            if i < mflimit && i + 4 <= n {
                let h = hash4(src, i)
                let cand = Int(table[h])
                table[h] = Int32(i)
                if cand >= 0 && i - cand <= maxOffset {
                    let len = matchLenAt(src, cand, i, n)
                    if len >= 4 {
                        matchPos = cand
                        matchLen = len
                    }
                }
            }
            if matchLen < 4 {
                i += 1
                continue
            }
            // 匹配不得覆盖最后 5 字节（保证块以纯字面量序列收尾）
            if i + matchLen > lastLimit {
                matchLen = lastLimit - i
                if matchLen < 4 {
                    i += 1
                    continue
                }
            }
            emitSeq(&out, src: src, litStart: litStart, ll: i - litStart,
                    offset: i - matchPos, ml: matchLen)
            // 为匹配段内的位置也更新哈希表，提升后续命中（起点是匹配段起点 i）
            var j = i
            let end = i + matchLen
            while j < end && j + 4 <= n {
                table[hash4(src, j)] = Int32(j)
                j += 1
            }
            i += matchLen
            litStart = i
        }
        let tail = n - litStart
        if tail > 0 {
            emitLiteralsOnly(&out, src: src, litStart: litStart, ll: tail)
        }
        return Data(out)
    }

    // MARK: - 解压

    public static func decompress(_ src: Data) -> Data? {
        let n = src.count
        guard n > 0 else { return Data() }
        var out: [UInt8] = []
        out.reserveCapacity(n * 3)
        var i = 0

        while i < n {
            let token = src[i]; i += 1
            var ll = Int(token >> 4)
            if ll == 15 {
                while true {
                    guard i < n else { return nil }
                    let b = src[i]; i += 1
                    ll += Int(b)
                    if b < 255 { break }
                }
            }
            guard i + ll <= n else { return nil }
            if ll > 0 {
                out.append(contentsOf: src[i..<(i + ll)])
                i += ll
            }
            if i >= n { break }  // 最后一个序列只含字面量

            guard i + 2 <= n else { return nil }
            let off = Int(src[i]) | (Int(src[i + 1]) << 8)
            i += 2
            guard off > 0, off <= out.count else { return nil }

            var ml = Int(token & 0x0F) + 4
            if (token & 0x0F) == 15 {
                while true {
                    guard i < n else { return nil }
                    let b = src[i]; i += 1
                    ml += Int(b)
                    if b < 255 { break }
                }
            }
            // 重叠复制安全：每写一个字节，后续读取位置随之增长
            let base = out.count - off
            for k in 0..<ml {
                out.append(out[base + k])
            }
        }
        return Data(out)
    }

    // MARK: - 内存压缩容器

    /// 内存中的 LZ4 压缩数据容器：构造时压缩，访问时解压。
    /// 适合把不常用的较大数据块（长文本、日志、历史）压缩暂存在内存。
    public struct Box: Sendable {
        public let compressed: Data
        public let originalSize: Int

        public init(_ data: Data) {
            originalSize = data.count
            compressed = LZ4.compress(data)
        }

        public var decompressed: Data {
            LZ4.decompress(compressed) ?? Data()
        }

        public var compressionRatio: Double {
            originalSize > 0 ? Double(originalSize) / Double(max(compressed.count, 1)) : 1.0
        }

        public var savedBytes: Int { originalSize - compressed.count }
    }

    // MARK: - 内部实现

    private static func hash4(_ src: Data, _ i: Int) -> Int {
        let v = UInt32(src[i]) << 24 | UInt32(src[i + 1]) << 16
            | UInt32(src[i + 2]) << 8 | UInt32(src[i + 3])
        return Int((v &* 2654435761) >> 16) & 0xFFFF
    }

    private static func matchLenAt(_ src: Data, _ p: Int, _ i: Int, _ n: Int) -> Int {
        var len = 0
        while p + len < n && i + len < n && src[p + len] == src[i + len] {
            len += 1
        }
        return len
    }

    private static func emitSeq(_ out: inout [UInt8], src: Data,
                                litStart: Int, ll: Int, offset: Int, ml: Int) {
        var token: UInt8 = 0
        var llr = ll
        if llr >= 15 { token |= 15 << 4 } else { token |= UInt8(llr) << 4 }
        var mlr = ml - 4
        if mlr >= 15 { token |= 15 } else { token |= UInt8(mlr) }
        out.append(token)
        if llr >= 15 {
            llr -= 15
            while llr >= 255 { out.append(255); llr -= 255 }
            out.append(UInt8(llr))
        }
        out.append(contentsOf: src[litStart..<(litStart + ll)])
        out.append(UInt8(offset & 0xFF))
        out.append(UInt8((offset >> 8) & 0xFF))
        if mlr >= 15 {
            mlr -= 15
            while mlr >= 255 { out.append(255); mlr -= 255 }
            out.append(UInt8(mlr))
        }
    }

    private static func emitLiteralsOnly(_ out: inout [UInt8], src: Data,
                                         litStart: Int, ll: Int) {
        var token: UInt8 = 0
        var llr = ll
        if llr >= 15 { token |= 15 << 4 } else { token |= UInt8(llr) << 4 }
        out.append(token)
        if llr >= 15 {
            llr -= 15
            while llr >= 255 { out.append(255); llr -= 255 }
            out.append(UInt8(llr))
        }
        out.append(contentsOf: src[litStart..<(litStart + ll)])
    }
}
