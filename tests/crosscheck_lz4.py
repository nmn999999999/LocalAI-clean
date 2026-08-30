#!/usr/bin/env python3
"""LZ4.swift 与 liblz4 参考实现（python-lz4 的 lz4.block，标准 LZ4 block 格式）双向交叉验证。

用法: python3 tests/crosscheck_lz4.py /tmp/test_lz4

方向1: 我们压缩 → liblz4 解压（证明我们的编码器产出标准 block）
方向2: liblz4 压缩 → 我们解压（证明我们的解码器理解标准 block）
"""
import subprocess, sys, os, tempfile
import lz4.block

BIN = sys.argv[1]
tmp = tempfile.mkdtemp()


def run(args):
    r = subprocess.run(args, capture_output=True)
    if r.returncode != 0:
        raise RuntimeError(f"{' '.join(args)} 失败: {r.stderr.decode(errors='replace')}")
    return r


def our_compress(data: bytes) -> bytes:
    i = os.path.join(tmp, "in.bin"); o = os.path.join(tmp, "out.lz4")
    with open(i, "wb") as f: f.write(data)
    run([BIN, "encode", i, o])
    with open(o, "rb") as f: return f.read()


def our_decompress(data: bytes) -> bytes:
    i = os.path.join(tmp, "in.lz4"); o = os.path.join(tmp, "out.bin")
    with open(i, "wb") as f: f.write(data)
    run([BIN, "decode", i, o])
    with open(o, "rb") as f: return f.read()


def rng(n, seed):
    out = bytearray(); s = seed
    for _ in range(n):
        s = (s * 6364136223846793005 + 1442695040888963407) & 0xFFFFFFFFFFFFFFFF
        out.append((s >> 33) & 0xFF)
    return bytes(out)


def text(n, seed):
    chars = b"abcdefghijklmnopqrstuvwxyz 0123456789,.!?\n"
    out = bytearray(); s = seed
    for _ in range(n):
        s = (s * 6364136223846793005 + 1442695040888963407) & 0xFFFFFFFFFFFFFFFF
        out.append(chars[(s >> 33) % len(chars)])
    return bytes(out)


datasets = [
    ("重复模式100KB", b"A" * 100_000),
    ("文本300KB", text(300_000, 123)),
    ("文本1MB", text(1_048_576, 55)),
    ("随机256KB", rng(262_144, 42)),
    ("交替重复128KB", bytes(i % 64 for i in range(131_072))),
    ("小数据17B", b"hello lz4 world!"),
    ("会话JSON模拟1MB", (b'{"role":"user","content":"message ' + b"0" * 20 + b'"}\n') * 20000),
    ("中文混合文本", text(200_000, 7) + "这是一段中文测试内容。".encode() * 500),
]

fails = 0
print("== 方向1: 我们压缩 → liblz4 解压 ==")
for name, data in datasets:
    c = our_compress(data)
    try:
        d = lz4.block.decompress(c, uncompressed_size=len(data))
        ok = d == data
    except Exception as e:
        ok = False; d = str(e)
    ratio = f"{len(data) / max(len(c), 1):.2f}x"
    mark = "✓" if ok else "✗"
    print(f"  {mark} {name}: {len(data)}→{len(c)} ({ratio})")
    if not ok:
        fails += 1
        print(f"      失败: {d if isinstance(d, str) else '内容不一致'}")

print("== 方向2: liblz4 压缩 → 我们解压 ==")
for name, data in datasets:
    c = lz4.block.compress(data, store_size=False)
    try:
        d = our_decompress(c)
        ok = d == data
    except Exception as e:
        ok = False; d = str(e)
    mark = "✓" if ok else "✗"
    print(f"  {mark} {name}: {len(data)}→{len(c)}")
    if not ok:
        fails += 1
        print(f"      失败: {d if isinstance(d, str) else '内容不一致'}")

print()
if fails == 0:
    print("✅ 与 liblz4 参考实现双向交叉验证全部通过 —— LZ4 block 格式标准合规")
else:
    print(f"❌ {fails} 项交叉验证失败")
sys.exit(1 if fails else 0)
