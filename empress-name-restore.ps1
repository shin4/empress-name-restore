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
# 替换映射表
# ============================================================
$NameMapping = @(
    @{ From = "伍元照"; To = "武则天"; ToTrad = "武則天"; Desc = "女主角本名" },
    @{ From = "伍媚娘"; To = "武媚娘"; Desc = "女主角封号" },
    @{ From = "伍士彟"; To = "武士彟"; Desc = "武则天之父" },
    @{ From = "伍士渊"; To = "武士彟"; Desc = "武则天之父(异写)" },
    @{ From = "伍元庆"; To = "武元庆"; ToTrad = "武元慶"; Desc = "武则天大哥" },
    @{ From = "伍元爽"; To = "武元爽"; Desc = "武则天二哥" },
    @{ From = "伍元顺"; To = "武元顺"; ToTrad = "武元順"; Desc = "武则天长姐" },
    @{ From = "礼治";   To = "李治";   FromTrad = "禮治";   Desc = "唐高宗" },
    @{ From = "礼世民"; To = "李世民"; FromTrad = "禮世民"; Desc = "唐太宗" },
    @{ From = "礼泰";   To = "李泰";   FromTrad = "禮泰";   Desc = "魏王" },
    @{ From = "礼弘";   To = "李弘";   FromTrad = "禮弘";   Desc = "太子" },
    @{ From = "礼贤";   To = "李贤";   FromTrad = "禮賢";   ToTrad = "李賢"; Desc = "章怀太子" },
    @{ From = "礼显";   To = "李显";   FromTrad = "禮顯";   ToTrad = "李顯"; Desc = "唐中宗" },
    @{ From = "礼旦";   To = "李旦";   FromTrad = "禮旦";   Desc = "唐睿宗" },
    @{ From = "礼勣";   To = "李勣";   FromTrad = "禮勣";   Desc = "凌烟阁功臣" },
    @{ From = "礼敬业"; To = "徐敬业"; FromTrad = "禮敬業"; ToTrad = "徐敬業"; Desc = "起兵反武之人" },
    @{ From = "高扬";   To = "高阳";   FromTrad = "高揚";   ToTrad = "高陽"; Desc = "高阳公主" },
    @{ From = "上官宜"; To = "上官仪"; ToTrad = "上官儀"; Desc = "太子太傅" },
    @{ From = "楚遂良"; To = "褚遂良"; Desc = "宰相" },
    @{ From = "丘神绩"; To = "丘神勣"; FromTrad = "丘神績"; Desc = "将领" },
    @{ From = "狄任介"; To = "狄仁杰"; ToTrad = "狄仁傑"; Desc = "朝臣" },
    @{ From = "盛朝";   To = "唐朝";   Desc = "国号" },
    @{ From = "盛安";   To = "长安";   ToTrad = "長安"; Desc = "首都" },
    @{ From = "伍氏";   To = "武氏";   Desc = "武氏家族(宗族)" },
    @{ From = "礼氏";   To = "李氏";   FromTrad = "禮氏"; Desc = "李唐皇族(宗族)" },
    @{ From = "伍周";   To = "武周";   Desc = "武周朝代" }
)

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

function Write-ColorLine {
    param([string]$Text, [ConsoleColor]$Color = "White")
    Write-Host $Text -ForegroundColor $Color
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
# 主程序
# ============================================================

$host.UI.RawUI.WindowTitle = "女帝篇 — 和谐人名还原工具"

Write-Host ""
Write-ColorLine "============================================" Cyan
Write-ColorLine "  《女王的游戏：盛世天下》女帝篇" Cyan
Write-ColorLine "      和谐人名还原工具 v1.5" Cyan
Write-ColorLine "============================================" Cyan
Write-Host ""

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
    Write-Host "  [1] 替换人名（还原历史原名）"
    Write-Host "  [2] 验证替换结果"
    Write-Host "  [3] 还原为游戏原始版本"
    Write-Host "  [4] 退出"
    Write-Host ""
    $action = Read-Host "请选择操作 (1-4)"

    switch ($action) {
        "1" {
            Write-Host ""
            Invoke-ReplaceNames -CfgPath $cfgPath
            Write-Host ""
        }
        "2" {
            Write-Host ""
            Invoke-VerifyNames -CfgPath $cfgPath
            Write-Host ""
        }
        "3" {
            Write-Host ""
            $confirm = Read-Host "确认还原为游戏原始版本？(Y/N)"
            if ($confirm -eq "Y" -or $confirm -eq "y") {
                Invoke-RestoreNames -CfgPath $cfgPath
            } else {
                Write-Host "已取消"
            }
            Write-Host ""
        }
        "4" {
            Write-Host ""
            Write-ColorLine "再见!" Cyan
            Write-Host ""
            exit 0
        }
        default {
            Write-ColorLine "无效输入，请输入 1-4" Yellow
            Write-Host ""
        }
    }
}
