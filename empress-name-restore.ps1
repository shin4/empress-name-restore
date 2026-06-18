#Requires -Version 5.1
<#
.SYNOPSIS
    《女王的游戏：盛世天下》女帝篇 — 和谐人名还原工具
.DESCRIPTION
    自动识别游戏目录，将被和谐的唐朝历史人名还原为原名。
    所有替换均为等字节(UTF-8)二进制替换，不会破坏protobuf结构。
.NOTES
    作者: shin4
    仓库: https://github.com/shin4/empress-name-restore
#>

# ============================================================
# 编码设置 (确保中文正常显示)
# ============================================================
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# ============================================================
# 辅助函数 (必须在使用前定义)
# ============================================================

function Write-ColorLine {
    param([string]$Text, [ConsoleColor]$Color = "White")
    Write-Host $Text -ForegroundColor $Color
}

# ============================================================
# 替换映射表 (从 name_mapping.json 读取)
# ============================================================
$MappingFile = Join-Path $PSScriptRoot "name_mapping.json"
if (-not (Test-Path -LiteralPath $MappingFile)) {
    Write-ColorLine "[错误] 未找到 name_mapping.json" Red
    Read-Host "按回车退出"
    exit 1
}
$MappingJson = Get-Content -LiteralPath $MappingFile -Raw -Encoding UTF8 | ConvertFrom-Json
$NameMapping = @()
foreach ($entry in $MappingJson.replacements) {
    $h = @{ From = $entry.from; To = $entry.to; Desc = $entry.desc }
    if ($entry.fromTrad) { $h.FromTrad = $entry.fromTrad }
    if ($entry.toTrad)   { $h.ToTrad = $entry.toTrad }
    $NameMapping += $h
}
Write-Host "[映射] 已从 name_mapping.json 加载 $($NameMapping.Count) 对替换规则"

# ============================================================
# 辅助函数
# ============================================================

function Find-GameDirectory {
    <#
    .SYNOPSIS
        自动搜索游戏安装目录
    #>
    $gameFolderName = "roadtoempress2"
    $candidates = @()

    # 1. 从 Steam 注册表获取安装路径
    $steamPaths = @()
    $regPaths = @(
        "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam",
        "HKLM:\SOFTWARE\Valve\Steam",
        "HKCU:\SOFTWARE\Valve\Steam"
    )
    foreach ($rp in $regPaths) {
        try {
            $val = (Get-ItemProperty -Path $rp -Name "InstallPath" -ErrorAction SilentlyContinue).InstallPath
            if ($val -and [System.IO.Path]::IsPathRooted($val)) { $steamPaths += $val }
        } catch {}
    }

    # 2. 常见默认路径
    $defaultPaths = @(
        "C:\Program Files (x86)\Steam",
        "C:\Program Files\Steam",
        "D:\Steam",
        "D:\SteamLibrary",
        "E:\Steam",
        "E:\SteamLibrary"
    )
    foreach ($dp in $defaultPaths) {
        if (Test-Path -LiteralPath $dp) { $steamPaths += $dp }
    }
    $steamPaths = $steamPaths | Select-Object -Unique

    # 3. 解析 libraryfolders.vdf 获取额外库路径
    foreach ($sp in $steamPaths) {
        $vdfPath = Join-Path $sp "steamapps\libraryfolders.vdf"
        if (Test-Path -LiteralPath $vdfPath) {
            try {
                $vdfContent = Get-Content -LiteralPath $vdfPath -Raw -Encoding UTF8
                $pathMatches = [regex]::Matches($vdfContent, '"path"\s+"([^"]+)"')
                foreach ($m in $pathMatches) {
                    $libPath = $m.Groups[1].Value -replace '\\\\', '\'
                    if ([System.IO.Path]::IsPathRooted($libPath) -and (Test-Path -LiteralPath $libPath)) {
                        $steamPaths += $libPath
                    }
                }
            } catch {}
        }
    }
    $steamPaths = $steamPaths | Select-Object -Unique

    # 4. 在所有 Steam 路径中搜索游戏目录
    foreach ($sp in $steamPaths) {
        $gamePath = Join-Path $sp "steamapps\common\$gameFolderName"
        if (Test-Path -LiteralPath $gamePath) {
            $cfgCheck = Join-Path $gamePath "Data\StreamingAssets\res\main\cfg\data"
            if (Test-Path -LiteralPath $cfgCheck) { $candidates += $gamePath }
        }
    }

    # 5. 搜索当前脚本所在目录的父级
    if ($PSScriptRoot) {
        $scriptParent = Split-Path $PSScriptRoot -Parent
        if ($scriptParent -and [System.IO.Path]::IsPathRooted($scriptParent)) {
            $testPath = Join-Path $scriptParent "Data\StreamingAssets\res\main\cfg\data"
            if (Test-Path -LiteralPath $testPath) { $candidates += $scriptParent }
        }
    }

    $candidates = @($candidates | Select-Object -Unique)
    return $candidates
}

function Get-CfgDataPath {
    param([string]$GameDir)
    return Join-Path $GameDir "Data\StreamingAssets\res\main\cfg\data"
}

# ============================================================
# 核心功能
# ============================================================

function Invoke-ReplaceNames {
    param([string]$CfgPath)

    $backupDir = Join-Path $CfgPath "_backup_original"

    # 1. 备份
    if (-not (Test-Path -LiteralPath $backupDir)) {
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
        $allPbin = Get-ChildItem -LiteralPath $CfgPath -Filter "*.pbin" -File
        foreach ($f in $allPbin) {
            Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $backupDir $f.Name) -Force
        }
        Write-ColorLine "[备份] 已备份 $($allPbin.Count) 个原始文件到 _backup_original" Green
    } else {
        Write-ColorLine "[备份] 备份已存在，跳过" Yellow
    }

    # 2. Build byte pairs
    # pairsSimp: from→to (non-zh_TW) or from→toTrad (zh_TW)
    # pairsTrad: fromTrad→to (non-zh_TW) or fromTrad→toTrad (zh_TW)
    $pairsSimp = @()
    $pairsTrad = @()

    foreach ($entry in $NameMapping) {
        $fromBuf = [System.Text.Encoding]::UTF8.GetBytes($entry.From)
        $toBuf   = [System.Text.Encoding]::UTF8.GetBytes($entry.To)
        if ($fromBuf.Length -ne $toBuf.Length) {
            Write-ColorLine "[错误] $($entry.Desc): 字节数不等，跳过" Red
            continue
        }

        # Simplified target (for non-zh_TW) or Traditional target (for zh_TW)
        if ($entry.ToTrad) {
            $toTradBuf = [System.Text.Encoding]::UTF8.GetBytes($entry.ToTrad)
            if ($fromBuf.Length -ne $toTradBuf.Length) {
                Write-ColorLine "[错误] $($entry.Desc): 繁简目标字节数不等，跳过" Red
                continue
            }
            $pairsSimp += @{ FromBuf = $fromBuf; ToBuf = $toBuf; ToTradBuf = $toTradBuf; Desc = $entry.Desc }
        } else {
            $pairsSimp += @{ FromBuf = $fromBuf; ToBuf = $toBuf; ToTradBuf = $null; Desc = $entry.Desc }
        }

        # Traditional source (for ALL files, shared files also contain 繁体)
        if ($entry.FromTrad) {
            $fromTradBuf = [System.Text.Encoding]::UTF8.GetBytes($entry.FromTrad)
            $targetBuf = $toBuf
            $targetTradBuf = if ($entry.ToTrad) { $toTradBuf } else { $null }
            if ($fromTradBuf.Length -eq $toBuf.Length) {
                $pairsTrad += @{ FromBuf = $fromTradBuf; ToBuf = $toBuf; ToTradBuf = $targetTradBuf; Desc = $entry.Desc }
            }
        }
    }

    # 3. 扫描 TextClient*.pbin 文件 — 纯字节操作
    $textFiles = Get-ChildItem -LiteralPath $CfgPath -Filter "TextClient*.pbin" -File
    $totalReplacements = 0
    $totalFilesModified = 0

    Write-Host ""
    Write-ColorLine "--- 开始替换 ---" Cyan

    foreach ($file in $textFiles) {
        $data = [System.IO.File]::ReadAllBytes($file.FullName)
        $fileReplacements = 0
        $isTrad = $file.Name -match 'zh_TW'

        # Build active pairs: simplified + traditional, with correct targets
        $activePairs = @()
        foreach ($p in $pairsSimp) {
            if ($isTrad -and $p.ToTradBuf) {
                $activePairs += @{ FromBuf = $p.FromBuf; ToBuf = $p.ToTradBuf; Desc = $p.Desc }
            } else {
                $activePairs += @{ FromBuf = $p.FromBuf; ToBuf = $p.ToBuf; Desc = $p.Desc }
            }
        }
        foreach ($p in $pairsTrad) {
            if ($isTrad -and $p.ToTradBuf) {
                $activePairs += @{ FromBuf = $p.FromBuf; ToBuf = $p.ToTradBuf; Desc = $p.Desc }
            } else {
                $activePairs += @{ FromBuf = $p.FromBuf; ToBuf = $p.ToBuf; Desc = $p.Desc }
            }
        }

        foreach ($p in $activePairs) {
            $fromLen = $p.FromBuf.Length
            $firstByte = $p.FromBuf[0]

            $i = [Array]::IndexOf($data, $firstByte, 0)
            while ($i -ge 0 -and $i -le $data.Length - $fromLen) {
                $found = $true
                for ($j = 1; $j -lt $fromLen; $j++) {
                    if ($data[$i + $j] -ne $p.FromBuf[$j]) { $found = $false; break }
                }
                if ($found) {
                    [Array]::Copy($p.ToBuf, 0, $data, $i, $fromLen)
                    $fileReplacements++
                    $totalReplacements++
                    $i = [Array]::IndexOf($data, $firstByte, $i + $fromLen)
                } else {
                    $i = [Array]::IndexOf($data, $firstByte, $i + 1)
                }
            }
        }

        if ($fileReplacements -gt 0) {
            [System.IO.File]::WriteAllBytes($file.FullName, $data)
            $totalFilesModified++
            Write-ColorLine "[修改] $($file.Name): $fileReplacements 处" White
        }
    }

    Write-Host ""
    Write-ColorLine "=== 替换完成 ===" Green
    Write-ColorLine "修改文件: $totalFilesModified 个" Green
    Write-ColorLine "替换总数: $totalReplacements 处" Green
}

function Invoke-VerifyNames {
    param([string]$CfgPath)

    Write-ColorLine "--- 验证替换结果 ---" Cyan
    Write-Host ""

    $textFiles = Get-ChildItem -LiteralPath $CfgPath -Filter "TextClient*.pbin" -File

    # Initialize counters
    $fromCounts = @{}    # simplified source
    $fromTradCounts = @{} # traditional source
    $toCounts = @{}      # target (simplified + traditional combined)
    foreach ($entry in $NameMapping) {
        $fromCounts[$entry.From] = 0
        $toCounts[$entry.To] = 0
        if ($entry.FromTrad) { $fromTradCounts[$entry.FromTrad] = 0 }
        if ($entry.ToTrad)   { $toCounts[$entry.ToTrad] = 0 }
    }

    # Single pass: read each file once, count all names via .NET regex
    $fileCount = 0
    foreach ($file in $textFiles) {
        $fileCount++
        Write-Host "`r  Scanning file $fileCount/$($textFiles.Count)..." -NoNewline

        $text = [System.IO.File]::ReadAllText($file.FullName, [System.Text.Encoding]::UTF8)

        foreach ($entry in $NameMapping) {
            $fromCounts[$entry.From] += ([regex]::Matches($text, [regex]::Escape($entry.From))).Count
            $toCounts[$entry.To]     += ([regex]::Matches($text, [regex]::Escape($entry.To))).Count
            if ($entry.FromTrad) {
                $fromTradCounts[$entry.FromTrad] += ([regex]::Matches($text, [regex]::Escape($entry.FromTrad))).Count
            }
            if ($entry.ToTrad) {
                $toCounts[$entry.ToTrad] += ([regex]::Matches($text, [regex]::Escape($entry.ToTrad))).Count
            }
        }
    }
    Write-Host "`r                                            "

    # Print results
    $header = "{0,-16} {1,-8} {2,-8} {3,-8}" -f "说明", "旧名残留", "新名出现", "状态"
    Write-ColorLine $header Cyan
    Write-ColorLine ("-" * 60) DarkGray

    $allPassed = $true
    foreach ($entry in $NameMapping) {
        $fc = $fromCounts[$entry.From]
        $ftc = if ($entry.FromTrad) { $fromTradCounts[$entry.FromTrad] } else { 0 }
        $totalOld = $fc + $ftc
        $tc = $toCounts[$entry.To]
        if ($entry.ToTrad) { $tc += $toCounts[$entry.ToTrad] }

        $tradNote = if ($entry.FromTrad) { "+" } else { "" }
        $status = if ($totalOld -eq 0) { "OK" } else { "FAIL($totalOld)"; $allPassed = $false }
        $statusColor = if ($totalOld -eq 0) { "Green" } else { "Red" }

        $line = "{0,-16} {1,-8} {2,-8} " -f $entry.Desc, "$totalOld$tradNote", $tc
        Write-Host $line -NoNewline
        Write-ColorLine $status $statusColor
    }

    Write-ColorLine ("-" * 60) DarkGray
    Write-Host ""
    if ($allPassed) {
        Write-ColorLine "全部通过! 旧名已全部替换为历史原名（简体+繁体）。" Green
    } else {
        Write-ColorLine "存在未完成的替换，请重新运行替换。" Red
    }
}

function Invoke-RestoreNames {
    param([string]$CfgPath)

    $backupDir = Join-Path $CfgPath "_backup_original"

    if (-not (Test-Path -LiteralPath $backupDir)) {
        Write-ColorLine "[错误] 备份目录不存在，无法还原" Red
        return
    }

    $backupFiles = Get-ChildItem -LiteralPath $backupDir -Filter "*.pbin" -File
    $restored = 0

    foreach ($f in $backupFiles) {
        $src = $f.FullName
        $dst = Join-Path $CfgPath $f.Name
        Copy-Item -LiteralPath $src -Destination $dst -Force
        $restored++
    }

    Write-ColorLine "[还原] 已恢复 $restored 个文件到原始状态" Green
}

# ============================================================
# 字幕替换功能
# ============================================================

function Get-SrtFiles {
    param([string]$Dir)
    $files = @()
    if (-not (Test-Path -LiteralPath $Dir)) { return $files }
    $items = Get-ChildItem -LiteralPath $Dir -Recurse -Filter "*.srt" -File
    return $items.FullName
}

function Invoke-ReplaceSubtitles {
    param([string]$GameDir)

    $srtDir = Join-Path $GameDir "Data\StreamingAssets\res\main\SSTX2\Global\srt"
    $backupDir = Join-Path $srtDir "_backup_subtitles"

    if (-not (Test-Path -LiteralPath $srtDir)) {
        Write-ColorLine "[错误] 未找到字幕目录: $srtDir" Red
        return
    }

    # 1. Backup
    if (-not (Test-Path -LiteralPath $backupDir)) {
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
        $langs = @('zh_TW', 'zh_GL')
        $totalFiles = 0

        foreach ($lang in $langs) {
            $langDir = Join-Path $srtDir $lang
            if (-not (Test-Path -LiteralPath $langDir)) { continue }

            $backupLangDir = Join-Path $backupDir $lang
            New-Item -ItemType Directory -Path $backupLangDir -Force | Out-Null

            $files = Get-SrtFiles -Dir $langDir
            foreach ($file in $files) {
                $relativePath = $file.Substring($langDir.Length + 1)
                $backupFile = Join-Path $backupLangDir $relativePath
                $backupSubDir = Split-Path $backupFile -Parent
                if (-not (Test-Path -LiteralPath $backupSubDir)) {
                    New-Item -ItemType Directory -Path $backupSubDir -Force | Out-Null
                }
                Copy-Item -LiteralPath $file -Destination $backupFile -Force
                $totalFiles++
            }
        }
        Write-ColorLine "[备份] 已备份 $totalFiles 个字幕文件到 _backup_subtitles" Green
    } else {
        Write-ColorLine "[备份] 备份已存在，跳过" Yellow
    }

    # 2. Build pairs
    $simpPairs = @()
    $tradPairs = @()
    $simpPairsNoTrad = @()  # entries without fromTrad (same form in zh_TW)

    foreach ($entry in $NameMapping) {
        $simpPairs += @{ From = $entry.From; To = $entry.To; Desc = $entry.Desc }
        if ($entry.FromTrad) {
            $toTrad = if ($entry.ToTrad) { $entry.ToTrad } else { $entry.To }
            $tradPairs += @{ From = $entry.FromTrad; To = $toTrad; Desc = $entry.Desc }
        } else {
            $simpPairsNoTrad += @{ From = $entry.From; To = $entry.To; Desc = $entry.Desc }
        }
    }

    # 3. Process files
    # zh_TW: tradPairs (繁体源→繁体目标) + simpPairsNoTrad (无繁体变体，简繁同形)
    # zh_GL: simpPairs (简体源→简体目标)
    $langConfigs = @(
        @{ Dir = 'zh_TW'; Pairs = ($tradPairs + $simpPairsNoTrad); Name = '繁体' },
        @{ Dir = 'zh_GL'; Pairs = $simpPairs; Name = '简体' }
    )

    $totalReplacements = 0
    $totalFilesModified = 0

    Write-Host ""
    Write-ColorLine "--- 开始替换字幕 ---" Cyan

    foreach ($langCfg in $langConfigs) {
        $langDir = Join-Path $srtDir $langCfg.Dir
        if (-not (Test-Path -LiteralPath $langDir)) {
            Write-ColorLine "[跳过] $($langCfg.Dir) 目录不存在" Yellow
            continue
        }

        $files = Get-SrtFiles -Dir $langDir
        $langReplacements = 0
        $langFilesModified = 0

        foreach ($file in $files) {
            $content = [System.IO.File]::ReadAllText($file, [System.Text.Encoding]::UTF8)
            $newContent = $content
            $fileReplacements = 0

            foreach ($pair in $langCfg.Pairs) {
                $escaped = [regex]::Escape($pair.From)
                $count = ([regex]::Matches($newContent, $escaped)).Count
                if ($count -gt 0) {
                    $newContent = $newContent -replace $escaped, $pair.To
                    $fileReplacements += $count
                }
            }

            if ($fileReplacements -gt 0) {
                [System.IO.File]::WriteAllText($file, $newContent, [System.Text.Encoding]::UTF8)
                $langReplacements += $fileReplacements
                $langFilesModified++
                $totalReplacements += $fileReplacements
                $totalFilesModified++
            }
        }

        Write-ColorLine "[修改] $($langCfg.Dir) ($($langCfg.Name)): $langFilesModified 个文件, $langReplacements 处替换" White
    }

    Write-Host ""
    Write-ColorLine "=== 字幕替换完成 ===" Green
    Write-ColorLine "修改文件: $totalFilesModified 个" Green
    Write-ColorLine "替换总数: $totalReplacements 处" Green
}

function Invoke-VerifySubtitles {
    param([string]$GameDir)

    $srtDir = Join-Path $GameDir "Data\StreamingAssets\res\main\SSTX2\Global\srt"

    if (-not (Test-Path -LiteralPath $srtDir)) {
        Write-ColorLine "[错误] 未找到字幕目录" Red
        return
    }

    Write-ColorLine "--- 验证字幕替换结果 ---" Cyan
    Write-Host ""

    # Build pairs
    $simpPairs = @()
    $tradPairs = @()
    $simpPairsNoTrad = @()

    foreach ($entry in $NameMapping) {
        $simpPairs += @{ From = $entry.From; To = $entry.To; Desc = $entry.Desc }
        if ($entry.FromTrad) {
            $toTrad = if ($entry.ToTrad) { $entry.ToTrad } else { $entry.To }
            $tradPairs += @{ From = $entry.FromTrad; To = $toTrad; Desc = $entry.Desc }
        } else {
            $simpPairsNoTrad += @{ From = $entry.From; To = $entry.To; Desc = $entry.Desc }
        }
    }

    $zhGLFiles = Get-SrtFiles -Dir (Join-Path $srtDir 'zh_GL')
    $zhTWFiles = Get-SrtFiles -Dir (Join-Path $srtDir 'zh_TW')

    Write-Host "zh_GL 字幕文件: $($zhGLFiles.Count) 个"
    Write-Host "zh_TW 字幕文件: $($zhTWFiles.Count) 个"
    Write-Host ""

    $allPassed = $true

    # Check zh_GL
    foreach ($pair in $simpPairs) {
        $fromCount = 0
        foreach ($file in $zhGLFiles) {
            $content = [System.IO.File]::ReadAllText($file, [System.Text.Encoding]::UTF8)
            $fromCount += ([regex]::Matches($content, [regex]::Escape($pair.From))).Count
        }
        $status = if ($fromCount -eq 0) { "OK" } else { "FAIL($fromCount)"; $allPassed = $false }
        $statusColor = if ($fromCount -eq 0) { "Green" } else { "Red" }
        $line = "{0,-16} {1,-8} {2,-8} " -f $pair.Desc, "zh_GL", $fromCount
        Write-Host $line -NoNewline
        Write-ColorLine $status $statusColor
    }

    # Check zh_TW
    foreach ($pair in ($tradPairs + $simpPairsNoTrad)) {
        $fromCount = 0
        foreach ($file in $zhTWFiles) {
            $content = [System.IO.File]::ReadAllText($file, [System.Text.Encoding]::UTF8)
            $fromCount += ([regex]::Matches($content, [regex]::Escape($pair.From))).Count
        }
        $status = if ($fromCount -eq 0) { "OK" } else { "FAIL($fromCount)"; $allPassed = $false }
        $statusColor = if ($fromCount -eq 0) { "Green" } else { "Red" }
        $line = "{0,-16} {1,-8} {2,-8} " -f $pair.Desc, "zh_TW", $fromCount
        Write-Host $line -NoNewline
        Write-ColorLine $status $statusColor
    }

    Write-Host ""
    if ($allPassed) {
        Write-ColorLine "全部通过! 字幕旧名已全部替换。" Green
    } else {
        Write-ColorLine "存在未完成的替换，请重新运行字幕替换。" Red
    }
}

function Invoke-RestoreSubtitles {
    param([string]$GameDir)

    $srtDir = Join-Path $GameDir "Data\StreamingAssets\res\main\SSTX2\Global\srt"
    $backupDir = Join-Path $srtDir "_backup_subtitles"

    if (-not (Test-Path -LiteralPath $backupDir)) {
        Write-ColorLine "[错误] 备份目录不存在，无法还原" Red
        return
    }

    $langs = @('zh_TW', 'zh_GL')
    $restored = 0

    foreach ($lang in $langs) {
        $backupLangDir = Join-Path $backupDir $lang
        if (-not (Test-Path -LiteralPath $backupLangDir)) { continue }

        $langDir = Join-Path $srtDir $lang
        $files = Get-SrtFiles -Dir $backupLangDir

        foreach ($file in $files) {
            $relativePath = $file.Substring($backupLangDir.Length + 1)
            $dstFile = Join-Path $langDir $relativePath
            $dstDir = Split-Path $dstFile -Parent
            if (-not (Test-Path -LiteralPath $dstDir)) {
                New-Item -ItemType Directory -Path $dstDir -Force | Out-Null
            }
            Copy-Item -LiteralPath $file -Destination $dstFile -Force
            $restored++
        }
    }

    Write-ColorLine "[还原] 已恢复 $restored 个字幕文件到原始状态" Green
}

# ============================================================
# 自动更新
# ============================================================

$RepoUrl = "https://github.com/shin4/empress-name-restore"
$RawBaseUrl = "https://raw.githubusercontent.com/shin4/empress-name-restore/master"
$LocalVersionFile = Join-Path $PSScriptRoot "VERSION"

function Get-LocalVersion {
    if (Test-Path -LiteralPath $LocalVersionFile) {
        return (Get-Content -LiteralPath $LocalVersionFile -Raw -Encoding UTF8).Trim()
    }
    return "0.0"
}

function Compare-Version {
    param([string]$V1, [string]$V2)
    $parts1 = $V1.Split('.') | ForEach-Object { [int]$_ }
    $parts2 = $V2.Split('.') | ForEach-Object { [int]$_ }
    $len = [Math]::Max($parts1.Count, $parts2.Count)
    for ($i = 0; $i -lt $len; $i++) {
        $a = if ($i -lt $parts1.Count) { $parts1[$i] } else { 0 }
        $b = if ($i -lt $parts2.Count) { $parts2[$i] } else { 0 }
        if ($a -gt $b) { return 1 }
        if ($a -lt $b) { return -1 }
    }
    return 0
}

function Check-Update {
    param([bool]$Silent = $false)

    $localVer = Get-LocalVersion

    try {
        $remoteVer = (Invoke-WebRequest -Uri "$RawBaseUrl/VERSION" -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop).Content.Trim()
    } catch {
        if (-not $Silent) {
            Write-ColorLine "[更新] 无法检查更新（网络不可用）" Yellow
        }
        return
    }

    $cmp = Compare-Version -V1 $remoteVer -V2 $localVer
    if ($cmp -le 0) {
        if (-not $Silent) {
            Write-ColorLine "[更新] 当前已是最新版本 v$localVer" Green
        }
        return
    }

    Write-ColorLine "[更新] 发现新版本 v$remoteVer (当前 v$localVer)" Yellow
    $choice = Read-Host "是否下载更新？(Y/N)"
    if ($choice -ne "Y" -and $choice -ne "y") {
        Write-Host "已跳过更新"
        return
    }

    # 下载 ZIP
    $zipUrl = "$RepoUrl/archive/refs/heads/master.zip"
    $tempZip = Join-Path $env:TEMP "empress-name-restore-update.zip"
    $tempDir = Join-Path $env:TEMP "empress-name-restore-update"

    Write-Host "正在下载..."
    try {
        Invoke-WebRequest -Uri $zipUrl -OutFile $tempZip -UseBasicParsing -TimeoutSec 60 -ErrorAction Stop
    } catch {
        Write-ColorLine "[错误] 下载失败: $($_.Exception.Message)" Red
        Write-Host "请手动下载: $RepoUrl"
        return
    }

    # 解压
    Write-Host "正在解压..."
    if (Test-Path -LiteralPath $tempDir) { Remove-Item -LiteralPath $tempDir -Recurse -Force }
    Expand-Archive -Path $tempZip -DestinationPath $tempDir -Force

    # 找到解压后的子目录（GitHub ZIP 会有一层 empress-name-restore-master/）
    $extractedDir = Get-ChildItem -LiteralPath $tempDir -Directory | Select-Object -First 1
    if (-not $extractedDir) {
        Write-ColorLine "[错误] 解压失败" Red
        return
    }

    # 复制文件覆盖本地（跳过备份目录和 .git）
    $skipDirs = @("_backup_original", "_backup_subtitles", ".git")
    $copied = 0
    Get-ChildItem -LiteralPath $extractedDir.FullName -Recurse -File | ForEach-Object {
        $relativePath = $_.FullName.Substring($extractedDir.FullName.Length + 1)
        $skip = $false
        foreach ($sd in $skipDirs) {
            if ($relativePath -like "$sd*") { $skip = $true; break }
        }
        if (-not $skip) {
            $destPath = Join-Path $PSScriptRoot $relativePath
            $destDir = Split-Path $destPath -Parent
            if (-not (Test-Path -LiteralPath $destDir)) {
                New-Item -ItemType Directory -Path $destDir -Force | Out-Null
            }
            Copy-Item -LiteralPath $_.FullName -Destination $destPath -Force
            $copied++
        }
    }

    # 清理临时文件
    Remove-Item -LiteralPath $tempZip -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue

    Write-ColorLine "[更新] 更新完成！已更新 $copied 个文件" Green
    Write-ColorLine "[更新] 请重新启动本工具以使用新版本" Yellow
    Write-Host ""
    Read-Host "按回车退出"
    exit 0
}

# ============================================================
# 主程序
# ============================================================

$host.UI.RawUI.WindowTitle = "女帝篇 — 和谐人名还原工具"

Write-Host ""
Write-ColorLine "============================================" Cyan
Write-ColorLine "  《女王的游戏：盛世天下》女帝篇" Cyan
Write-ColorLine "      和谐人名还原工具 v3.9" Cyan
Write-ColorLine "============================================" Cyan
Write-Host ""

# 启动时自动检查更新（静默模式，不打扰正常流程）
Check-Update -Silent $true

# 自动搜索游戏目录
Write-ColorLine "正在搜索游戏目录..." Yellow
$gameDirs = @(Find-GameDirectory)

if ($gameDirs.Count -eq 0) {
    Write-ColorLine "[错误] 未找到游戏目录" Red
    Write-Host ""
    Write-Host "请将本工具放在游戏根目录下，或手动输入路径："
    Write-Host ""
    $manualPath = Read-Host "输入游戏目录路径 (留空退出)"
    if ($manualPath -and (Test-Path -LiteralPath $manualPath)) {
        $cfgPath = Get-CfgDataPath $manualPath
        if (Test-Path -LiteralPath $cfgPath) {
            $gameDirs = @($manualPath)
        } else {
            Write-ColorLine "[错误] 路径无效，未找到 cfg\data 目录" Red
            Read-Host "按回车退出"
            exit 1
        }
    } else {
        exit 0
    }
}

# 选择游戏目录
$gameDir = $gameDirs[0]
if ($gameDirs.Count -gt 1) {
    Write-Host "找到多个游戏目录，请选择："
    Write-Host ""
    for ($i = 0; $i -lt $gameDirs.Count; $i++) {
        Write-Host "  [$($i + 1)] $($gameDirs[$i])"
    }
    Write-Host ""
    $choice = Read-Host "请输入编号 (默认 1)"
    $idx = if ($choice) { [int]$choice - 1 } else { 0 }
    if ($idx -lt 0 -or $idx -ge $gameDirs.Count) { $idx = 0 }
    $gameDir = $gameDirs[$idx]
}

$cfgPath = Get-CfgDataPath $gameDir

Write-ColorLine "[游戏目录] $gameDir" Green
Write-ColorLine "[数据目录] $cfgPath" Green
Write-Host ""

# 菜单循环
while ($true) {
    Write-ColorLine "---------- 功能菜单 ----------" Cyan
    Write-Host ""
    Write-Host "  [1] 一键替换（人名 + 字幕）"
    Write-Host "  [2] 一键验证（人名 + 字幕）"
    Write-Host "  [3] 一键还原（人名 + 字幕）"
    Write-Host "  [4] 启动内存补丁（字幕实时替换）"
    Write-Host "  [5] 检查更新"
    Write-Host "  [6] 退出"
    Write-Host ""
    $action = Read-Host "请选择操作 (1-6)"

    switch ($action) {
        "1" {
            Write-Host ""
            Invoke-ReplaceNames -CfgPath $cfgPath
            Write-Host ""
            Invoke-ReplaceSubtitles -GameDir $gameDir
            Write-Host ""
        }
        "2" {
            Write-Host ""
            Invoke-VerifyNames -CfgPath $cfgPath
            Write-Host ""
            Invoke-VerifySubtitles -GameDir $gameDir
            Write-Host ""
        }
        "3" {
            Write-Host ""
            $confirm = Read-Host "确认还原为游戏原始版本？(Y/N)"
            if ($confirm -eq "Y" -or $confirm -eq "y") {
                Invoke-RestoreNames -CfgPath $cfgPath
                Write-Host ""
                Invoke-RestoreSubtitles -GameDir $gameDir
            } else {
                Write-Host "已取消"
            }
            Write-Host ""
        }
        "4" {
            Write-Host ""
            # 查找 memory_patch.exe
            $patchExe = $null
            $candidates = @(
                (Join-Path $PSScriptRoot "release\memory_patch.exe"),
                (Join-Path $PSScriptRoot "memory_patch.exe")
            )
            foreach ($c in $candidates) {
                if (Test-Path -LiteralPath $c) { $patchExe = $c; break }
            }
            if ($patchExe) {
                Write-ColorLine "[启动] $patchExe" Green
                Write-ColorLine "  需要管理员权限，游戏需已在运行中" Yellow
                Write-ColorLine "  按 Ctrl+C 退出补丁" Yellow
                Write-Host ""
                Start-Process -FilePath $patchExe -Verb RunAs -Wait
            } else {
                Write-ColorLine "[错误] 未找到 memory_patch.exe" Red
                Write-Host "  请将 release\ 目录与本工具放在同一文件夹下"
                Write-Host "  或从 GitHub 下载: https://github.com/shin4/empress-name-restore"
            }
            Write-Host ""
        }
        "5" {
            Write-Host ""
            Check-Update -Silent $false
            Write-Host ""
        }
        "6" {
            Write-Host ""
            Write-ColorLine "再见!" Cyan
            Write-Host ""
            exit 0
        }
        default {
            Write-ColorLine "无效输入，请输入 1-6" Yellow
            Write-Host ""
        }
    }
}
