# AGENTS.md

## Critical: Binary File Handling

.pbin files are **protobuf binary**, not plain text. They contain mixed binary data (field tags, varints) and UTF-8 strings.

**NEVER** do `ReadAllText(UTF8)` → modify string → `UTF8.GetBytes()` → `WriteAllBytes()`. The round-trip corrupts invalid UTF-8 bytes into U+FFFD (EF BF BD), destroying the file structure and crashing the game.

**Always** use pure byte operations:
- Node.js: `Buffer.indexOf()` / `Buffer.copy()`
- PowerShell: `[Array]::IndexOf()` / `[Array]::Copy()`

## Single Source of Truth

`name_mapping.json` is the **only** file to edit when adding/modifying replacements. Both `replace_names.js` and `empress-name-restore.ps1` read from it at runtime.

Fields per entry:
- `from` / `to` — required, must be equal UTF-8 byte length
- `fromTrad` — optional, Traditional Chinese source (for zh_TW files)
- `toTrad` — optional, Traditional Chinese target (for zh_TW files)

## Traditional Chinese (zh_TW)

- zh_TW files use 繁体字形: 禮治 (not 礼治), 高揚 (not 高扬)
- Chapter files (`chapter*.pbin`) are **shared across all locales** — they contain both simplified and traditional forms
- The scripts detect `zh_TW` in filename to switch target glyphs (`to` vs `toTrad`)
- Traditional source (`fromTrad`) replacements apply to **all** files, not just zh_TW

## File Architecture

Game data: `<steam>/steamapps/common/roadtoempress2/Data/StreamingAssets/res/main/cfg/data/`

| File pattern | Count | Type | Editable |
|---|---|---|---|
| `TextClient*.pbin` | 80 | Plaintext protobuf | Yes |
| `CharacterConfig.pbin` etc. | 44 | AES encrypted | No |

Only `TextClient*.pbin` files contain display text (names, dialogue). Config files store ID references only.

Subtitle files (encrypted `.k` format):

| Path | Format | Editable |
|---|---|---|
| `bundle/editordata_s2/*.json.k` | TBUAESv1 (AES encrypted) | No — key unknown |

Game loads subtitles from `.k` files at runtime (not from `.srt` files). The memory patch (`memory_patch.py`) replaces names directly in the game process memory after decryption.

## 内存补丁 (memory_patch.py)

The game encrypts subtitle files with AES (TBUAESv1 format, key unknown). The `.srt` files on disk are not read at runtime. To fix names in subtitles, `memory_patch.py` patches the game's memory directly.

### How it works

1. Opens the game process via `OpenProcess` (requires admin)
2. Enumerates virtual memory regions via `VirtualQueryEx`
3. Reads `MEM_PRIVATE` + `PAGE_READWRITE` regions via `ReadProcessMemory`
4. Searches for UTF-8 byte patterns (e.g. `礼治` = `E7 A4 BC E6 B2 BB`)
5. Validates context is valid UTF-8 text (not binary data)
6. Writes modified data back via `WriteProcessMemory`
7. Polls every 3 seconds to catch newly loaded chapter subtitles

### Critical: MEMORY_BASIC_INFORMATION on x64

The struct must be **48 bytes** on x64 Windows. Using wrong field types causes field offset misalignment — `State`, `Protect`, `Type` read garbage values, causing writes to wrong memory regions and game crashes.

```python
# CORRECT (48 bytes on x64)
class MEMORY_BASIC_INFORMATION(ctypes.Structure):
    _fields_ = [
        ("BaseAddress", ctypes.c_void_p),        # 8 bytes
        ("AllocationBase", ctypes.c_void_p),      # 8 bytes
        ("AllocationProtect", ctypes.c_ulong),    # 4 bytes
        ("PartitionId", ctypes.c_ushort),          # 2 bytes
        ("_pad", ctypes.c_ushort),                 # 2 bytes
        ("RegionSize", ctypes.c_size_t),           # 8 bytes
        ("State", ctypes.c_ulong),                # 4 bytes
        ("Protect", ctypes.c_ulong),              # 4 bytes
        ("Type", ctypes.c_ulong),                 # 4 bytes
        ("_pad2", ctypes.c_ulong),                # 4 bytes
    ]

# WRONG (56 bytes — causes crashes!)
# Do NOT use c_ulonglong for State/Protect/Type
```

### Subtitle data location

Subtitles are loaded into large `MEM_PRIVATE/READWRITE` regions (32MB+). The scan filter must allow regions up to 50MB.

## PyInstaller Packaging

`memory_patch.py` can be packaged as a standalone `.exe`:

```bash
pip install pyinstaller
pyinstaller --onefile --uac-admin --add-data "name_mapping.json;." --name memory_patch memory_patch.py
```

- `--onefile`: single exe output
- `--uac-admin`: auto-request admin privileges on launch
- `--add-data`: bundle `name_mapping.json` inside the exe

At runtime, the script checks `sys.frozen` to find `name_mapping.json` next to the `.exe` first, falling back to `sys._MEIPASS` (PyInstaller temp dir).

Build script: `build.bat`

## PS1 Encoding

`empress-name-restore.ps1` **must** be saved as UTF-8 with BOM. Without BOM, cmd.exe reads it as GBK and Chinese characters become garbled parser errors.

## Path Assumptions

- JS scripts (`replace_names.js` etc.) expect `__dirname` to be `roadtoempress2/tools/` — they resolve game data via `path.join(__dirname, '..', 'Data', ...)`
- PS script auto-detects Steam paths via registry + `libraryfolders.vdf`
- Backup goes to `cfg/data/_backup_original/`

## No Build/Test

This repo has no build step for the main tools, no tests, no lint. Verification is manual: run `node verify_names.js` or PS menu option 2. All 18 replacement pairs should show `旧名残留: 0`.

The `.exe` requires a one-time build step via `build.bat` or `pyinstaller` (see PyInstaller Packaging section above).
