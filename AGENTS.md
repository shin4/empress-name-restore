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

## PS1 Encoding

`empress-name-restore.ps1` **must** be saved as UTF-8 with BOM. Without BOM, cmd.exe reads it as GBK and Chinese characters become garbled parser errors.

## Path Assumptions

- JS scripts (`replace_names.js` etc.) expect `__dirname` to be `roadtoempress2/tools/` — they resolve game data via `path.join(__dirname, '..', 'Data', ...)`
- PS script auto-detects Steam paths via registry + `libraryfolders.vdf`
- Backup goes to `cfg/data/_backup_original/`

## No Build/Test

This repo has no build step, no tests, no lint. Verification is manual: run `node verify_names.js` or PS menu option 2. All 18 replacement pairs should show `旧名残留: 0`.
