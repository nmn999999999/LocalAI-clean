import Foundation
import Compression

// LZ4.swift 的单元验证：
// 1. roundtrip：压缩→解压 == 原数据（多类型数据）
// 2. 与系统 Compression 框架（COMPRESSION_LZ4）交叉验证 block 格式互操作
// 3. 随机数据 fuzz
// 4. 压缩率报告

var failures = 0
func check(_ name: String, _ cond: Bool, _ extra: String = "") {
    if cond { print("  ✓ \(name)") }
    else { failures += 1; print("  ✗ \(name) \(extra)") }
}

func randomBytes(_ n: Int, seed: UInt64) -> Data {
    var rng = seed
    var out = Data(capacity: n)
    for _ in 0..<n {
        rng = rng &* 6364136223846793005 &+ 1442695040888963407
        out.append(UInt8((rng >> 33) & 0xFF))
    }
    return out
}

func randomText(_ n: Int, seed: UInt64) -> Data {
    var rng = seed
    let chars = Array("abcdefghijklmnopqrstuvwxyz 0123456789,.!?（中文测试内容）".utf8)
    var out = Data(capacity: n)
    for _ in 0..<n {
        rng = rng &* 6364136223846793005 &+ 1442695040888963407
        out.append(chars[Int(rng % UInt64(chars.count))])
    }
    return out
}

// ── CLI 模式（供 liblz4 参考实现交叉验证驱动）──
// 用法: test_lz4 encode <in> <out>  |  test_lz4 decode <in> <out>
if CommandLine.arguments.count >= 4 {
    let mode = CommandLine.arguments[1]
    let inPath = CommandLine.arguments[2]
    let outPath = CommandLine.arguments[3]
    guard let input = FileManager.default.contents(atPath: inPath) else {
        FileHandle.standardError.write(Data("无法读取 \(inPath)\n".utf8)); exit(2)
    }
    switch mode {
    case "encode":
        try! LZ4.compress(input).write(to: URL(fileURLWithPath: outPath))
    case "decode":
        guard let out = LZ4.decompress(input) else {
            FileHandle.standardError.write(Data("解压失败\n".utf8)); exit(3)
        }
        try! out.write(to: URL(fileURLWithPath: outPath))
    default:
        FileHandle.standardError.write(Data("未知模式 \(mode)\n".utf8)); exit(2)
    }
    exit(0)
}

print("== 1. roundtrip ==")
let datasets: [(String, Data)] = [
    ("空数据", Data()),
    ("单字节", Data([0x42])),
    ("重复模式(100KB)", Data(repeating: 0x41, count: 100_000)),
    ("重复文本(200KB)", randomText(200_000, seed: 7)),
    ("随机二进制(64KB)", randomBytes(65536, seed: 42)),
    ("随机二进制(1MB)", randomBytes(1_048_576, seed: 99)),
    ("交替重复(128KB)", Data((0..<131072).map { UInt8($0 % 64) })),
    ("会话JSON模拟(500KB)", Data(randomText(524_288, seed: 3))),
]
for (name, data) in datasets {
    let c = LZ4.compress(data)
    let d = LZ4.decompress(c)
    let ratio = data.count > 0 ? String(format: "%.2fx", Double(data.count) / Double(max(c.count, 1))) : "-"
    check("\(name) 压缩\(ratio) (\(data.count)→\(c.count))",
          d == data, "roundtrip 不一致! 原\(data.count) 解\(d?.count ?? -1)")
}

print("== 2. 与 liblz4 参考实现交叉验证 ==")
// 说明：Apple 的 COMPRESSION_LZ4 输出带 12 字节私有帧头（magic "bv41"+尺寸字段），
// 且对不可压数据用存储模式，不是标准 LZ4 block 格式，无法直接互操作。
// 标准合规性改用 liblz4 参考实现验证（Python lz4.block，即标准 LZ4 block 格式）：
//   tests/crosscheck_lz4.py <test_lz4二进制>  —— 双向交叉验证
print("  → 运行: python3 tests/crosscheck_lz4.py /tmp/test_lz4")
print("  → 同时验证 CLI 模式: encode/decode <in> <out>")

print("== 3. fuzz（随机小块，1000 轮） ==")
var fuzzOK = true
for round in 0..<1000 {
    let size = Int.random(in: 0...4096)
    let mode = round % 4
    let data: Data
    switch mode {
    case 0: data = randomBytes(size, seed: UInt64(round + 1))
    case 1: data = randomText(size, seed: UInt64(round + 1))
    case 2: data = Data(repeating: UInt8(round % 256), count: size)
    default: data = Data((0..<size).map { UInt8(($0 * 7 + round) % 251) })
    }
    let c = LZ4.compress(data)
    let d = LZ4.decompress(c)
    if d != data { fuzzOK = false; print("  第\(round)轮失败 size=\(size)"); break }
}
check("1000 轮 fuzz 全部通过", fuzzOK)

print("== 4. 大块重复数据（重叠匹配路径） ==")
let big = Data(repeating: UInt8(0xEE), count: 2_000_000)
let bc = LZ4.compress(big)
let bd = LZ4.decompress(bc)
check("2MB 全重复数据 roundtrip", bd == big, "失败 \(bd?.count ?? -1)")
print("  2MB 重复 → \(bc.count)B（offset=1 重叠复制路径）")

print("== 5. LZ4.Box 内存容器 ==")
let box = LZ4.Box(randomText(1_000_000, seed: 5))
print("  1MB 文本: 内存占用 \(box.compressed.count)B（节省 \(box.savedBytes)B, \(String(format: "%.2f%%", (1 - Double(box.compressed.count)/1_000_000) * 100))）")
check("Box 解压还原", box.decompressed.count == 1_000_000)

print()
if failures == 0 { print("✅ 全部测试通过") } else { print("❌ \(failures) 项失败") }
exit(failures == 0 ? 0 : 1)
