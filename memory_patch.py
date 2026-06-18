#!/usr/bin/env python3
"""
运行时内存字幕替换脚本
实时轮询模式：后台常驻，每 3 秒扫描一次游戏内存并替换字幕文本
支持 PyInstaller 打包为 .exe
"""
import ctypes
import ctypes.wintypes
import json
import os
import subprocess
import sys
import time

# Windows API 常量
PROCESS_VM_READ = 0x0010
PROCESS_VM_WRITE = 0x0020
PROCESS_VM_OPERATION = 0x0008
PROCESS_QUERY_INFORMATION = 0x0400

MEM_COMMIT = 0x1000
MEM_PRIVATE = 0x20000
MEM_IMAGE = 0x1000000
MEM_MAPPED = 0x40000

PAGE_READWRITE = 0x04
PAGE_WRITECOPY = 0x08
PAGE_EXECUTE_READWRITE = 0x40

kernel32 = ctypes.WinDLL('kernel32', use_last_error=True)

SCAN_INTERVAL = 3  # 扫描间隔（秒）


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
    ]  # Total: 48 bytes (x64)


def load_mapping():
    """加载替换映射表，同时生成 UTF-8 和 UTF-16LE 替换对"""
    if getattr(sys, 'frozen', False):
        exe_dir = os.path.dirname(sys.executable)
        mapping_file = os.path.join(exe_dir, 'name_mapping.json')
        if not os.path.exists(mapping_file):
            mapping_file = os.path.join(sys._MEIPASS, 'name_mapping.json')
    else:
        script_dir = os.path.dirname(os.path.abspath(__file__))
        mapping_file = os.path.join(script_dir, 'name_mapping.json')

    if not os.path.exists(mapping_file):
        print("[错误] 未找到 name_mapping.json")
        sys.exit(1)

    print(f"  映射文件: {mapping_file}")
    with open(mapping_file, 'r', encoding='utf-8-sig') as f:
        data = json.load(f)

    pairs = []
    for entry in data['replacements']:
        from_s = entry['from']
        to_s = entry['to']

        # UTF-8 对
        from_utf8 = from_s.encode('utf-8')
        to_utf8 = to_s.encode('utf-8')
        if len(from_utf8) == len(to_utf8):
            pairs.append((from_utf8, to_utf8, f"{from_s}->{to_s}", 'utf8'))
        else:
            print(f"  [跳过] {from_s} -> {to_s} (UTF-8 字节数不等)")

        # UTF-16LE 对（Unity/IL2CPP 原生字符串编码）
        from_utf16 = from_s.encode('utf-16-le')
        to_utf16 = to_s.encode('utf-16-le')
        if len(from_utf16) == len(to_utf16):
            pairs.append((from_utf16, to_utf16, f"{from_s}->{to_s}", 'utf16'))
        else:
            print(f"  [跳过] {from_s} -> {to_s} (UTF-16LE 字节数不等)")

    utf8_count = sum(1 for p in pairs if p[3] == 'utf8')
    utf16_count = sum(1 for p in pairs if p[3] == 'utf16')
    print(f"  UTF-8: {utf8_count} 对, UTF-16LE: {utf16_count} 对")

    return pairs


def is_valid_utf8_context(data, offset, match_len, context_size=50):
    """检查匹配位置周围的上下文是否像有效的 UTF-8 文本"""
    start = max(0, offset - context_size)
    end = min(len(data), offset + match_len + context_size)
    context = data[start:end]

    non_text_count = 0
    for b in context:
        if b < 0x20 and b not in (0x0A, 0x0D, 0x09):
            non_text_count += 1

    if non_text_count > len(context) * 0.3:
        return False

    try:
        context.decode('utf-8', errors='strict')
        return True
    except UnicodeDecodeError:
        try:
            local_start = max(0, offset - 10)
            local_end = min(len(data), offset + match_len + 10)
            data[local_start:local_end].decode('utf-8', errors='strict')
            return True
        except UnicodeDecodeError:
            return False


def is_valid_utf16le_context(data, offset, match_len, context_size=60):
    """检查匹配位置是否像有效的 UTF-16LE 文本（2字节对齐 + CJK/ASCII 范围）"""
    # UTF-16LE 要求 2 字节对齐
    if offset % 2 != 0:
        return False

    # 检查周围 16-bit code units 是否在合理范围
    check_start = max(0, offset - context_size)
    check_end = min(len(data), offset + match_len + context_size)
    # 对齐到 2 字节边界
    check_start = check_start + (check_start % 2)
    check_end = check_end - (check_end % 2)

    if check_end - check_start < 4:
        return False

    code_units = []
    for i in range(check_start, check_end - 1, 2):
        code_unit = data[i] | (data[i + 1] << 8)
        code_units.append(code_unit)

    # 统计有效 code unit 比例
    valid = 0
    for cu in code_units:
        # ASCII (0x0020-0x007E), CJK (0x4E00-0x9FFF), CJK 扩展,
        # 常用标点 (0x3000-0x303F), 全角 (0xFF00-0xFFEF)
        # 或者 0x0000 (null terminator)
        if cu == 0x0000:
            valid += 1
        elif 0x0020 <= cu <= 0x007E:
            valid += 1
        elif 0x3000 <= cu <= 0x303F:
            valid += 1
        elif 0x4E00 <= cu <= 0x9FFF:
            valid += 1
        elif 0xFF00 <= cu <= 0xFFEF:
            valid += 1
        elif 0x2000 <= cu <= 0x206F:
            valid += 1  # 通用标点
        elif 0xFE30 <= cu <= 0xFE4F:
            valid += 1  # CJK 兼容形式

    return valid >= len(code_units) * 0.7


def scan_and_replace(pid, pairs):
    """扫描内存并替换（安全模式）"""
    h_process = kernel32.OpenProcess(
        PROCESS_VM_READ | PROCESS_VM_WRITE | PROCESS_VM_OPERATION | PROCESS_QUERY_INFORMATION,
        False, pid
    )

    if not h_process:
        print(f"[错误] 无法打开进程 {pid}，错误码: {ctypes.get_last_error()}")
        print("请以管理员权限运行此脚本")
        return None

    total_replacements = 0
    total_regions = 0
    details = []
    total_write_ok = 0
    total_write_fail = 0
    total_verified = 0

    addr = ctypes.c_ulonglong(0)
    mbi = MEMORY_BASIC_INFORMATION()
    mbi_size = ctypes.sizeof(mbi)

    scanned = 0
    skipped = 0

    while addr.value < 0x7FFFFFFFFFFF:
        ret = kernel32.VirtualQueryEx(h_process, addr, ctypes.byref(mbi), mbi_size)
        if ret == 0:
            addr.value += 0x1000
            continue

        base = mbi.BaseAddress if mbi.BaseAddress else 0
        region_size = mbi.RegionSize if mbi.RegionSize else 0

        if region_size == 0:
            addr.value += 0x1000
            continue

        if (mbi.State == MEM_COMMIT and
                mbi.Type == MEM_PRIVATE and
                mbi.Protect in (PAGE_READWRITE, PAGE_WRITECOPY, PAGE_EXECUTE_READWRITE)):

            if region_size < 256 or region_size > 50 * 1024 * 1024:
                skipped += 1
                addr.value = base + region_size
                continue

            try:
                buffer = ctypes.create_string_buffer(region_size)
                bytes_read = ctypes.c_size_t(0)

                if kernel32.ReadProcessMemory(
                    h_process, ctypes.c_void_p(base),
                    buffer, region_size, ctypes.byref(bytes_read)
                ):
                    data = bytearray(buffer.raw[:bytes_read.value])
                    region_replacements = 0
                    # 收集需要写入的 (偏移量, 新字节) 列表
                    patches = []

                    for from_buf, to_buf, desc, encoding in pairs:
                        idx = 0
                        while True:
                            idx = data.find(from_buf, idx)
                            if idx == -1:
                                break
                            if encoding == 'utf16':
                                valid = is_valid_utf16le_context(data, idx, len(from_buf))
                            else:
                                valid = is_valid_utf8_context(data, idx, len(from_buf))
                            if valid:
                                patches.append((idx, bytes(to_buf)))
                                region_replacements += 1
                                total_replacements += 1
                            idx += len(from_buf)

                    # 只写入被修改的字节，不回写整个区域
                    for offset, new_bytes in patches:
                        write_buf = ctypes.create_string_buffer(new_bytes)
                        bytes_written = ctypes.c_size_t(0)
                        ret = kernel32.WriteProcessMemory(
                            h_process, ctypes.c_void_p(base + offset),
                            write_buf, len(new_bytes), ctypes.byref(bytes_written)
                        )
                        if ret and bytes_written.value == len(new_bytes):
                            total_write_ok += 1
                            # 读回验证
                            verify_buf = ctypes.create_string_buffer(len(new_bytes))
                            verify_read = ctypes.c_size_t(0)
                            kernel32.ReadProcessMemory(
                                h_process, ctypes.c_void_p(base + offset),
                                verify_buf, len(new_bytes), ctypes.byref(verify_read)
                            )
                            if verify_buf.raw[:len(new_bytes)] == new_bytes:
                                total_verified += 1
                        else:
                            total_write_fail += 1
                    if patches:
                        total_regions += 1
                        details.append((hex(base), region_replacements))

                scanned += 1
            except Exception:
                pass

        addr.value = base + region_size

    kernel32.CloseHandle(h_process)

    return total_replacements, total_regions, details, scanned, total_write_ok, total_write_fail, total_verified


def find_game_process():
    """查找游戏进程，返回 PID 或 None"""
    try:
        result = subprocess.run(
            ['tasklist', '/FI', 'IMAGENAME eq sstx2.exe', '/FO', 'CSV', '/NH'],
            capture_output=True, text=True, timeout=10
        )
        for line in result.stdout.strip().split('\n'):
            if 'sstx2.exe' in line:
                parts = line.split(',')
                if len(parts) >= 2:
                    return int(parts[1].strip('"'))
    except Exception:
        pass
    return None


def main():
    print("=" * 50)
    print("  女帝篇 字幕还原补丁 v1.0")
    print("  运行时内存替换 | Ctrl+C 退出")
    print("=" * 50)

    # 加载映射
    print("\n[1/2] 加载映射表...")
    pairs = load_mapping()
    print(f"  加载了 {len(pairs)} 个替换对 (UTF-8 + UTF-16LE)")

    # 等待游戏进程
    print("\n[2/2] 等待游戏进程...")
    pid = find_game_process()
    if not pid:
        print("  等待游戏启动...")
        while True:
            time.sleep(2)
            pid = find_game_process()
            if pid:
                break

    print(f"  找到游戏进程: PID {pid}")
    print(f"\n开始实时替换 (每 {SCAN_INTERVAL} 秒扫描一次)")
    print("-" * 50)

    scan_count = 0
    total_replacements = 0

    try:
        while True:
            # 检查游戏是否还在运行
            current_pid = find_game_process()
            if current_pid is None:
                print(f"\n\n游戏已退出")
                break
            if current_pid != pid:
                print(f"\n\n游戏进程已重启 (PID {pid} -> {current_pid})")
                pid = current_pid
                print(f"  继续监控新进程: PID {pid}")

            scan_count += 1
            result = scan_and_replace(pid, pairs)

            if result is None:
                print(f"\n\n无法访问进程，请确认管理员权限")
                break

            replacements, regions, details, scanned, ws, wf, vf = result
            total_replacements += replacements

            if replacements > 0:
                detail_str = ", ".join(f"{a}({c}处)" for a, c in details)
                print(f"  [#{scan_count}] {replacements} 处替换 | 写入:{ws} 失败:{wf} 验证:{vf} | {detail_str} | 累计 {total_replacements}")
            else:
                # 无变化时覆盖同一行，避免刷屏
                sys.stdout.write(f"\r  [#{scan_count}] 无变化 | 累计 {total_replacements} 处替换")
                sys.stdout.flush()

            time.sleep(SCAN_INTERVAL)

    except KeyboardInterrupt:
        pass

    print(f"\n\n{'=' * 50}")
    print(f"  总扫描: {scan_count} 次")
    print(f"  总替换: {total_replacements} 处")
    print(f"{'=' * 50}")


if __name__ == "__main__":
    main()
