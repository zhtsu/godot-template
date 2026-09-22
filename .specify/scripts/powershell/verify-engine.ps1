<#
.SYNOPSIS
    godot-template 引擎验证：跑 headless 冒烟，并与已登记基线逐行比对。

.DESCRIPTION
    宪法原则 V 要求"非平凡改动 MUST 在真实 Godot 引擎中运行验证"。本脚本把这件事变成一条命令，
    并解决两个现实问题：

    1) `godot` 不在 PATH 上 —— 本脚本按 -Godot > $env:GODOT > 配置 > 常见安装路径 > PATH 的顺序查找，
       找不到就明确报错，而不是让调用方对着 CommandNotFoundException 猜。
    2) 引擎输出里有一批**每次都会出现**的噪声（且退出码仍是 0）—— 所以"退出码为 0 且没有 ERROR"
       从来不是一个可执行的判据。本脚本把输出归一化后与基线 diff，只把**新增**行算作回归。

    已知基线噪声（首次运行会自动登记）：
      - Failed to open 'user://logs/godot*.log' / Failed to open log file for writing
      - Failed to read the root certificate store
      - N ObjectDB instances were leaked at exit
      - N resources still in use at exit
    其中 ObjectDB / resources 的**数量**会被归一化（env 差异），但该行本身参与 diff：
    如果某次运行完全不出现泄漏行，会提示但没有 ERROR 时不算失败。

    基线是**机器相关**的（首次运行是否有 options.sav 会影响启动日志），
    换机器或存档状态大变后请用 -UpdateBaseline 重登。

.PARAMETER Godot
    Godot 可执行文件路径。缺省按上述顺序自动查找。

.PARAMETER Frames
    headless 冒烟跑多少帧后退出（默认 5，与 AGENTS.md 基线一致）。

.PARAMETER Probe
    额外跑一个一次性探针脚本（如 res://_probe.gd）。探针只报告退出码与 ERROR/WARNING，不参与基线 diff。

.PARAMETER Scenario
    额外把一个场景当主场景跑（如 res://ui/options/options.tscn）。同理不参与基线 diff。

.PARAMETER UpdateBaseline
    重新登记基线（人工确认当前输出是"正常"之后再用）。

.PARAMETER UpdateNoise
    把本次输出里出现、但基线中没有的 ERROR/WARNING 行追加进基线（用于登记"已确认无关"的噪声）。
    与 -UpdateBaseline 的区别：-UpdateBaseline 覆盖整份基线，-UpdateNoise 只追加噪声行。

.PARAMETER NoBaseline
    跳过基线 diff，只报告原始输出与 ERROR/WARNING 计数（用于第一次摸底）。

.EXAMPLE
    # 最常用：改完代码跑这个
    .specify/scripts/powershell/verify-engine.ps1

.EXAMPLE
    # 同时验证目标场景与探针
    .specify/scripts/powershell/verify-engine.ps1 -Scenario res://ui/options/options.tscn -Probe res://_probe.gd

.EXAMPLE
    # 第一次在某台机器上摸底
    .specify/scripts/powershell/verify-engine.ps1 -NoBaseline
#>
[CmdletBinding()]
param(
    [string]$Godot,
    [int]$Frames = 5,
    [string]$Probe,
    [string]$Scenario,
    [switch]$UpdateBaseline,
    [switch]$UpdateNoise,
    [switch]$NoBaseline
)

$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$configPath = Join-Path $repoRoot '.specify/godot-lint.json'
$baselinePath = Join-Path $repoRoot '.specify/godot-verify-baseline.json'

# --- 定位 Godot -----------------------------------------------------------
function Resolve-GodotExe {
    param([string]$Explicit)

    $candidates = New-Object System.Collections.ArrayList
    if ($Explicit) { [void]$candidates.Add($Explicit) }
    if ($env:GODOT) { [void]$candidates.Add($env:GODOT) }

    if (Test-Path $configPath) {
        try {
            $cfg = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $p = $cfg.PSObject.Properties['godot']
            if ($p) {
                $ep = $p.Value.PSObject.Properties['executable']
                if ($ep -and $ep.Value) { [void]$candidates.Add([string]$ep.Value) }
            }
        } catch { }
    }

    [void]$candidates.Add('C:\portable\Godot\4.7.2\Godot_v4.7.2-stable_win64_console.exe')
    foreach ($pattern in @(
        'C:\portable\Godot\*\Godot_v*_console.exe',
        "$env:LOCALAPPDATA\Programs\Godot\*\Godot_v*_console.exe",
        "$env:USERPROFILE\scoop\apps\godot\current\*.exe"
    )) {
        $found = @(Get-ChildItem -Path $pattern -ErrorAction SilentlyContinue | Sort-Object Name -Descending)
        if ($found.Count -gt 0) { [void]$candidates.Add($found[0].FullName) }
    }

    $onPath = Get-Command godot -ErrorAction SilentlyContinue
    if ($onPath) { [void]$candidates.Add($onPath.Source) }

    foreach ($c in $candidates) {
        if ($c -and (Test-Path -LiteralPath $c -PathType Leaf)) { return (Resolve-Path -LiteralPath $c).Path }
    }
    return $null
}

$godotExe = Resolve-GodotExe -Explicit $Godot
if (-not $godotExe) {
    Write-Host 'ERROR: 找不到 Godot 可执行文件。' -ForegroundColor Red
    Write-Host '  用 -Godot <路径> 指定，或设置 $env:GODOT，或在 .specify/godot-lint.json 的 godot.executable 里配置。'
    Write-Host '  注意：本仓库不假设 `godot` 在 PATH 上。'
    exit 2
}

$version = (& $godotExe --version 2>&1 | Select-Object -First 1)
Write-Host "Godot: $godotExe"
Write-Host "version: $version"
Write-Host "repo: $repoRoot"

# --- 输出归一化 -----------------------------------------------------------
# 把每次都会变的片段抹平成占位符，只留下"结构性"的行。
function Get-NormalizedLines {
    param([string[]]$Raw)

    $out = New-Object System.Collections.ArrayList
    foreach ($line in $Raw) {
        if ($null -eq $line) { continue }
        $t = [string]$line
        if ($t.Trim().Length -eq 0) { continue }

        # 输出里带 ANSI 颜色转义（例如日志前缀的 RGB 序列）。必须剥掉：
        # 这类序列在不同终端/管道下可能出现也可能不出现，留着会让 diff 虚假失配。
        $t = $t -replace "`e\[[0-9;]*m", ''
        $t = $t -replace "`e\[[0-9;]*[A-Za-z]", ''

        # Godot 启动横幅带 git hash，版本号本身固定但换 4.7.x 会变 → 归一化
        $t = $t -replace 'Godot Engine v[\d\.]+\.stable\.official\.[0-9a-f]+', 'Godot Engine v<version>'

        # user:// 日志路径与时间戳
        $t = $t -replace "user://logs/godot[\dT:\-\.]*\.log", 'user://logs/godot<ts>.log'
        $t = $t -replace '\[\d{4}-\d{2}-\d{2}T[\d:\.]+\]', '[<ts>]'

        # 泄漏计数是环境相关的（节点/资源数量随存档状态变），归一化数字
        $t = $t -replace '^\s*WARNING:\s*\d+\s+ObjectDB instances were leaked at exit', 'WARNING: <n> ObjectDB instances were leaked at exit'
        $t = $t -replace '^\s*ERROR:\s*\d+\s+resources still in use at exit', 'ERROR: <n> resources still in use at exit'

        # 行号 / 栈帧地址
        $t = $t -replace '0x[0-9a-fA-F]{6,}', '0x<addr>'

        [void]$out.Add($t.TrimEnd())
    }
    return $out.ToArray()
}

function Get-ProblemLines {
    param([string[]]$Lines)
    return @($Lines | Where-Object { $_ -match '(?i)(^|\s)(ERROR|WARNING|SCRIPT ERROR|Parse Error)' })
}

function Invoke-Godot {
    param([string[]]$GodotArgs, [string]$Label)
    Write-Host ''
    Write-Host "--- $Label ---" -ForegroundColor Cyan
    Write-Host ("& `"$godotExe`" " + ($GodotArgs -join ' ')) -ForegroundColor DarkGray
    $raw = & $godotExe @GodotArgs 2>&1
    $code = $LASTEXITCODE
    $lines = Get-NormalizedLines -Raw @($raw | ForEach-Object { [string]$_ })
    return [PSCustomObject]@{ Label = $Label; ExitCode = $code; Lines = $lines }
}

$results = New-Object System.Collections.ArrayList

# 1) 主场景冒烟（参与基线 diff）
[void]$results.Add((Invoke-Godot -GodotArgs @('--headless', '--path', $repoRoot, '--quit-after', "$Frames") -Label "主场景冒烟（--quit-after $Frames）"))

# 2) 目标场景直接实例化
if ($Scenario) {
    [void]$results.Add((Invoke-Godot -GodotArgs @('--headless', '--path', $repoRoot, $Scenario, '--quit-after', '3') -Label "场景实例化 $Scenario"))
}

# 3) 一次性探针
if ($Probe) {
    [void]$results.Add((Invoke-Godot -GodotArgs @('--headless', '--path', $repoRoot, '--script', $Probe) -Label "探针 $Probe"))
}

# --- 报告 -----------------------------------------------------------------
$smoke = $results[0]
$smokeProblems = Get-ProblemLines -Lines $smoke.Lines

Write-Host ''
Write-Host '=== 各步骤结果 ===' -ForegroundColor Cyan
foreach ($r in $results) {
    $problems = Get-ProblemLines -Lines $r.Lines
    $flag = if ($r.ExitCode -ne 0) { 'FAIL' } elseif ($problems.Count -gt 0) { 'WARN' } else { 'OK' }
    Write-Host ("[{0}] {1}  exit={2}  ERROR/WARNING 行={3}" -f $flag, $r.Label, $r.ExitCode, $problems.Count)
    if ($r.Label -ne $smoke.Label) {
        foreach ($p in $problems) { Write-Host ("        {0}" -f $p) -ForegroundColor DarkYellow }
    }
}

$newProblems = @()
$missingProblems = @()
$baselineProblemCount = 0
$baselineMissing = $false

if (-not $NoBaseline) {
    Write-Host ''
    Write-Host '=== 与基线 diff ===' -ForegroundColor Cyan
    if (-not (Test-Path $baselinePath)) {
        Write-Host '基线不存在，本次视为初始登记。' -ForegroundColor Yellow
        $baselineMissing = $true
    } else {
        $baseline = Get-Content -LiteralPath $baselinePath -Raw -Encoding UTF8 | ConvertFrom-Json
        $baseProblems = @($baseline.SmokeProblems)
        $baseLines = @($baseline.SmokeLines)
        $baselineProblemCount = $baseProblems.Count

        $newProblems = @($smokeProblems | Where-Object { $_ -notin $baseProblems })
        $missingProblems = @($baseProblems | Where-Object { $_ -notin $smokeProblems })
        $newLines = @($smoke.Lines | Where-Object { $_ -notin $baseLines })

        if ($newProblems.Count -eq 0) {
            Write-Host ("无新增 ERROR/WARNING（基线 {0} 行）。" -f $baselineProblemCount) -ForegroundColor Green
        } else {
            Write-Host ("新增 {0} 行（很可能是本次改动引入的回归）：" -f $newProblems.Count) -ForegroundColor Red
            foreach ($p in $newProblems) { Write-Host ("  + {0}" -f $p) -ForegroundColor Red }
        }
        if ($missingProblems.Count -gt 0) {
            Write-Host ("基线里有、本次没有的 {0} 行（修好了？还是路径没跑到？）：" -f $missingProblems.Count) -ForegroundColor DarkYellow
            foreach ($p in $missingProblems) { Write-Host ("  - {0}" -f $p) -ForegroundColor DarkYellow }
        }
        if ($newLines.Count -gt 0 -and $newProblems.Count -eq 0) {
            Write-Host '非 ERROR/WARNING 的新增输出行（通常是 print/日志，确认是否预期）：' -ForegroundColor DarkGray
            foreach ($l in ($newLines | Select-Object -First 20)) { Write-Host ("  + {0}" -f $l) -ForegroundColor DarkGray }
        }
        Write-Host ("基线路径: {0}（{1}）" -f $baselinePath, (Get-Item -LiteralPath $baselinePath).LastWriteTime.ToString('s'))
    }
}

if ($UpdateBaseline -or $UpdateNoise) {
    $payloadLines = if ($UpdateNoise -and (Test-Path $baselinePath)) {
        $b = Get-Content -LiteralPath $baselinePath -Raw -Encoding UTF8 | ConvertFrom-Json
        @($b.SmokeProblems) + @($newProblems) | Select-Object -Unique
    } else {
        $smokeProblems
    }
    $payload = [PSCustomObject]@{
        _comment = 'verify-engine.ps1 生成的引擎输出基线。机器相关：换机器或存档状态大变后请用 -UpdateBaseline 重登。'
        generated_at = (Get-Date).ToString('s')
        godot = $godotExe
        version = $version
        frames = $Frames
        SmokeProblems = @($payloadLines)
        SmokeLines = $smoke.Lines
    }
    $payload | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $baselinePath -Encoding UTF8
    Write-Host ("已写入基线：{0}（噪声行 {1}）" -f $baselinePath, @($payloadLines).Count) -ForegroundColor Yellow
}

Write-Host ''
$exitCode = 0
if ($results | Where-Object { $_.ExitCode -ne 0 }) { $exitCode = 1 }
if ($UpdateBaseline -or $UpdateNoise) {
    # 本次就是来登记基线的，不要再提示去登记
    Write-Host '基线已按本次输出登记。若确认这些行是环境噪声，下次运行应报"无新增 ERROR/WARNING"。' -ForegroundColor Yellow
} elseif (-not $NoBaseline) {
    if ($baselineMissing) {
        Write-Host '提示：这是第一次运行，基线未登记。请人工确认上面输出正常后执行 -UpdateBaseline。' -ForegroundColor Yellow
    } elseif ($newProblems.Count -gt 0) {
        $exitCode = 1
    }
}

if ($exitCode -eq 0) {
    Write-Host '验证通过：退出码 0，且没有基线之外的新 ERROR/WARNING。' -ForegroundColor Green
} else {
    Write-Host '验证未通过。上面带 + 的行是新增输出；确认无关后可用 -UpdateNoise 登记为噪声。' -ForegroundColor Red
}
Write-Host ''
exit $exitCode
