#!/usr/bin/env python3
"""
IL2CPP String 布局探测脚本（只读，绝对安全）。

目的：验证内存补丁的"对象锚定"方案所依赖的核心假设——
    游戏内字幕字符串在内存中符合 IL2CPP System.String 的标准布局，
    即 [klass(8) monitor(8) length(int32) chars[](UTF-16LE)]，
    从而可以用 length 字段 + klass 指针 一致性 来确定性地判定
    "某个匹配位置是否落在真实字符串对象内"，彻底摆脱邻居/比例的两难。

工作方式：
    1. 用 name_mapping.json 里的 UTF-16LE 模式（和谐前的"伍元照/礼治"等）
       在游戏内存里搜索匹配位置。
    2. 对每个匹配位置，反向枚举 8 字节对齐的候选对象头 base，
       在多种布局假设下读取 length 字段，检验 pattern 是否落在 chars[] 范围内。
    3. 统计每种假设下的"自洽匹配数"，以及 candidate klass 指针的频次。
       真 String klass 会被成百上千个字符串引用（高频）；
       噪声 klass 各不相同（频次 1）。频次分布会直接告诉我们哪种假设是对的。

只使用 ReadProcessMemory，绝不写入。
"""
import ctypes
import json
import os
import subprocess
import sys
from collections import Counter

# ---- Windows API ----
PROCESS_VM_READ = 0x0010
PROCESS_QUERY_INFORMATION = 0x0400
MEM_COMMIT = 0x1000
MEM_PRIVATE = 0x20000
PAGE_READWRITE = 0x04
PAGE_WRITECOPY = 0x08
PAGE_EXECUTE_READWRITE = 0x40

kernel32 = ctypes.WinDLL('kernel32', use_last_error=True)


class MEMORY_BASIC_INFORMATION(ctypes.Structure):
    _fields_ = [
        ("BaseAddress", ctypes.c_void_p),
        ("AllocationBase", ctypes.c_void_p),
        ("AllocationProtect", ctypes.c_ulong),
        ("PartitionId", ctypes.c_ushort),
        ("_pad", ctypes.c_ushort),
        ("RegionSize", ctypes.c_size_t),
        ("State", ctypes.c_ulong),
        ("Protect", ctypes.c_ulong),
        ("Type", ctypes.c_ulong),
        ("_pad2", ctypes.c_ulong),
    ]


def find_game_pid():
    try:
        r = subprocess.run(
            ['tasklist', '/FI', 'IMAGENAME eq sstx2.exe', '/FO', 'CSV', '/NH'],
            capture_output=True, text=True, timeout=10
        )
        for line in r.stdout.strip().split('\n'):
            if 'sstx2.exe' in line:
                parts = line.split(',')
                if len(parts) >= 2:
                    return int(parts[1].strip('"'))
    except Exception:
        pass
    return None


def iter_regions(h_process):
    """枚举所有可读的 MEM_PRIVATE 提交区域，yield (base, size, raw_bytes)。"""
    addr = ctypes.c_ulonglong(0)
    mbi = MEMORY_BASIC_INFORMATION()
    sz = ctypes.sizeof(mbi)
    while addr.value < 0x7FFFFFFFFFFF:
        if kernel32.VirtualQueryEx(h_process, addr, ctypes.byref(mbi), sz) == 0:
            addr.value += 0x1000
            continue
        base = mbi.BaseAddress or 0
        rsize = mbi.RegionSize or 0
        if rsize == 0:
            addr.value += 0x1000
            continue
        if (mbi.State == MEM_COMMIT and mbi.Type == MEM_PRIVATE and
                mbi.Protect in (PAGE_READWRITE, PAGE_WRITECOPY, PAGE_EXECUTE_READWRITE) and
                256 <= rsize <= 50 * 1024 * 1024):
            buf = ctypes.create_string_buffer(rsize)
            n = ctypes.c_size_t(0)
            if kernel32.ReadProcessMemory(h_process, ctypes.c_void_p(base),
                                          buf, rsize, ctypes.byref(n)):
                yield base, n.value, buf.raw[:n.value]
        addr.value = base + rsize


def load_utf16_patterns():
    """加载映射表，返回 [(from_utf16_bytes, label), ...]"""
    here = os.path.dirname(os.path.abspath(__file__))
    with open(os.path.join(here, 'name_mapping.json'), 'r', encoding='utf-8-sig') as f:
        data = json.load(f)
    out = []
    for e in data['replacements']:
        f16 = e['from'].encode('utf-16-le')
        out.append((f16, e['from']))
    return out


# 多种布局假设。每种：(name, length_field_offset_in_object, object_header_size)
# 标准 IL2CPP：klass@0, monitor@8, length@0x10, chars@0x14
# 备选假设覆盖常见变体
LAYOUTS = [
    ("std_il2cpp_len@0x10_chars@0x14", 0x10, 0x14),
    ("variant_len@0x0c_chars@0x10",    0x0C, 0x10),
    ("variant_len@0x14_chars@0x18",    0x14, 0x18),
]


def check_layout(data, match_off, pat_len, len_off, chars_off, max_j=8192):
    """对单个匹配，在布局 (len_off, chars_off) 下反向找自洽的对象头。
    返回 (base, length, klass) 或 None。要求对象头 8 字节对齐。"""
    n_cu = pat_len // 2
    data_len = len(data)
    anchor = match_off - chars_off
    if anchor < 0:
        return None
    base = anchor - (anchor % 8)  # 第一个 <= anchor 的 8 对齐位置
    while base >= 0 and (match_off - chars_off - base) // 2 < max_j:
        # 读 length（int32 LE）
        if base + len_off + 4 > data_len:
            base -= 8
            continue
        length = int.from_bytes(data[base + len_off:base + len_off + 4], 'little', signed=True)
        if not (1 <= length <= 8192):
            base -= 8
            continue
        j = (match_off - chars_off - base) // 2
        if j + n_cu > length:
            base -= 8
            continue
        if base + chars_off + 2 * length > data_len:
            base -= 8
            continue
        # 读 klass（base 处 8 字节，应是合法用户态高位指针）
        klass = int.from_bytes(data[base:base + 8], 'little')
        if klass <= 0x10000 or klass >= 0x7FFFFFFFFFFF:
            base -= 8
            continue
        return base, length, klass
    return None


def main():
    print("=" * 60)
    print("  IL2CPP String 布局探测 (只读)")
    print("=" * 60)

    pid = find_game_pid()
    if not pid:
        print("[错误] 未找到 sstx2.exe，请先启动游戏")
        sys.exit(1)
    print(f"  游戏进程 PID: {pid}")

    h = kernel32.OpenProcess(PROCESS_VM_READ | PROCESS_QUERY_INFORMATION, False, pid)
    if not h:
        print(f"[错误] OpenProcess 失败，错误码 {ctypes.get_last_error()}")
        print("  请以管理员权限运行")
        sys.exit(1)

    patterns = load_utf16_patterns()
    print(f"  加载 {len(patterns)} 个 UTF-16LE 模式")
    print("  开始扫描内存（只读）...\n")

    # 统计
    # 每种布局：自洽匹配数、klass 频次、length 频次
    stats = {name: {"hits": 0, "klass": Counter(), "length": Counter(), "samples": []}
             for name, _, _ in LAYOUTS}
    raw_match_total = 0   # 所有区域里出现的模式匹配总数（含噪声）
    pattern_hit_counts = Counter()  # 每个模式被自洽命中的次数（用标准布局）

    for base, n, data in iter_regions(h):
        data_ba = bytearray(data)
        for pat, label in patterns:
            idx = 0
            while True:
                idx = data_ba.find(pat, idx)
                if idx == -1:
                    break
                raw_match_total += 1
                for name, len_off, chars_off in LAYOUTS:
                    res = check_layout(data_ba, idx, len(pat), len_off, chars_off)
                    if res is not None:
                        ob, length, klass = res
                        s = stats[name]
                        s["hits"] += 1
                        s["klass"][klass] += 1
                        s["length"][length] += 1
                        if name.startswith("std") and len(s["samples"]) < 8:
                            # 读回该字符串内容用于人工核对
                            try:
                                txt_off = ob + chars_off
                                raw = bytes(data_ba[txt_off:txt_off + 2 * length])
                                txt = raw.decode('utf-16-le', errors='replace')
                            except Exception:
                                txt = "<?>"
                            s["samples"].append((base + ob, length, klass, txt, label))
                        idx += len(pat)
                        break  # 同一布局下找到一个自洽头即可
                idx += len(pat) if not any(
                    False for _ in [0]) else len(pat)
                # 注意：上面 break 只跳出 LAYOUTS 循环；这里保证 idx 前进

    kernel32.CloseHandle(h)

    # ---- 输出 ----
    print("=" * 60)
    print("  扫描结果")
    print("=" * 60)
    print(f"  扫描到的原始模式匹配总数（含噪声）: {raw_match_total}\n")

    best = None
    best_score = -1
    for name, _, _ in LAYOUTS:
        s = stats[name]
        print("-" * 60)
        print(f"  布局假设: {name}")
        print(f"    自洽匹配数: {s['hits']}")
        if s["klass"]:
            top_klass = s["klass"].most_common(5)
            top_count = top_klass[0][1]
            distinct = len(s["klass"])
            print(f"    不同 klass 数: {distinct}")
            print(f"    klass 频次 Top5:")
            for k, c in top_klass:
                print(f"        0x{k:012X} : {c}")
            print(f"    Top1 klass 占比: {top_count / s['hits'] * 100:.1f}%  "
                  f"(真 String 应高度集中，>80%)")
            print(f"    length 范围: min={min(s['length'])} max={max(s['length'])} "
                  f"distinct={len(s['length'])}")
            # 评分：Top1 klass 集中度（真值应 >> 噪声）
            score = top_count / s['hits'] if s['hits'] else 0
            if score > best_score:
                best_score = score
                best = name
        else:
            print("    无自洽匹配")
        print()

    print("=" * 60)
    print("  样例字符串（标准布局假设下读回的实际文本）")
    print("=" * 60)
    std = stats[LAYOUTS[0][0]]
    for addr, length, klass, txt, label in std["samples"]:
        print(f"    @0x{addr:012X} len={length:<4} klass=0x{klass:012X}  "
              f"模式=[{label}]  文本=\"{txt}\"")

    print()
    print("=" * 60)
    print("  结论判定")
    print("=" * 60)
    if best and best_score > 0.5:
        print(f"  ✅ 布局 [{best}] 的 Top1 klass 集中度 = {best_score * 100:.1f}%")
        print(f"     高度集中说明：内存里的字幕字符串确实符合该 IL2CPP 布局。")
        print(f"     => 可以安全采用『length 字段 + klass 锚定』替换上下文比例判定。")
        print(f"     => 建议用 Top1 klass（见上）作为 string_klasses 集合。")
    else:
        print(f"  ⚠️  最高集中度仅 {best_score * 100:.1f}%（布局 {best}）")
        print(f"     没有任何布局假设表现出高频 klass 集中。可能：")
        print(f"       (a) 字幕不以 IL2CPP String 形式常驻（仅短时间存在/已被释放）")
        print(f"       (b) 游戏当前没加载到包含目标人名的字幕（请先在游戏内触发相关剧情）")
        print(f"       (c) 布局与所有假设都不符，需抓取 dump 进一步分析")
        print(f"     建议先在游戏内进入包含「伍元照/礼治/李世民」的章节再跑此脚本。")


if __name__ == "__main__":
    main()
