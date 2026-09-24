<#
.SYNOPSIS
    godot-template 引擎验证：跑 headless 冒烟，并与已登记基线逐行比对。

.DESCRIPTION
    为什么不用"退出码 0 且没有 ERROR"当判据：本工程的本机冒烟**稳定**输出 5 行噪声
    （user:// 日志写不了 ×2、证书库读不到、ObjectDB 泄漏、资源残留），而 Godot 退出码仍是 0。
    所以判据是"**相对基线无新增行**"。

    基线是**机器相关**的（user:// 下有没有存档会影响启动日志）。换机器、或存档状态大变之后，
    用 -UpdateBaseline 重新登记，并在提交信息/说明里写清为什么变。

.PARAMETER Godot
    Godot 可执行文件路径。缺省按 -Godot > $env:GODOT > 常见安装路径 > PATH 查找。
    注意：要用 *_console.exe 才拿得到 stdout。

.PARAMETER Project
    Godot 工程目录，默认 <仓库根>/godot-template。

.PARAMETER Frames
    冒烟跑多少帧后退出（默认 5）。

.PARAMETER Probe
    额外跑一个一次性探针脚本（如 res://_probe.gd）。只报告退出码与问题行，不参与基线 diff。

.PARAMETER Scenario
    额外把一个场景当主场景跑（如 res://ui/options/options.tscn）。同上不参与 diff。

.PARAMETER UpdateBaseline
    按本次输出重新登记基线（人工确认这些行"正常"之后才用）。

.PARAMETER NoBaseline
    跳过基线比对，只报告原始问题行（第一次摸底用）。

.EXAMPLE
    pwsh scripts/verify-engine.ps1
    pwsh scripts/verify-engine.ps1 -Scenario res://ui/options/options.tscn -Probe res://_probe.gd
    pwsh scripts/verify-engine.ps1 -UpdateBaseline
#>
[CmdletBinding()]
param(
    [string]$Godot,
    [string]$Project,
    [int]$Frames = 5,
    [string]$Probe,
    [string]$Scenario,
    [switch]$UpdateBaseline,
    [switch]$NoBaseline
)

$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if (-not $Project) { $Project = Join-Path $repoRoot 'godot-template' }
$baselinePath = Join-Path $PSScriptRoot 'engine-baseline.json'

if (-not (Test-Path (Join-Path $Project 'project.godot'))) {
    Write-Host "ERROR: $Project 下没有 project.godot；用 -Project 指定工程目录。" -ForegroundColor Red
    exit 2
}

# --- 定位引擎 -------------------------------------------------------------
function Resolve-GodotExe {
    param([string]$Explicit)
    $candidates = New-Object System.Collections.ArrayList
    if ($Explicit) { [void]$candidates.Add($Explicit) }
    if ($env:GODOT) { [void]$candidates.Add($env:GODOT) }
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
    Write-Host 'ERROR: 找不到 Godot 可执行文件。用 -Godot <路径>、$env:GODOT 指定。' -ForegroundColor Red
    Write-Host '  提示：本仓库不假设 godot 在 PATH 上，且要用 *_console.exe。'
    exit 2
}

$version = (& $godotExe --version 2>&1 | Select-Object -First 1)
Write-Host "Godot: $godotExe"
Write-Host "version: $version"
Write-Host "project: $Project"

# --- 输出归一化 -----------------------------------------------------------
function Get-NormalizedLines {
    param([string[]]$Raw)
    $out = New-Object System.Collections.ArrayList
    foreach ($line in $Raw) {
        if ($null -eq $line) { continue }
        $t = [string]$line
        if ($t.Trim().Length -eq 0) { continue }
        $t = $t -replace "`e\[[0-9;]*m", ''
        $t = $t -replace "`e\[[0-9;]*[A-Za-z]", ''
        $t = $t -replace 'Godot Engine v[\d\.]+\.stable\.official\.[0-9a-f]+', 'Godot Engine v<version>'
        $t = $t -replace 'user://logs/godot[\dT:\-\.]*\.log', 'user://logs/godot<ts>.log'
        $t = $t -replace '\[\d{4}-\d{2}-\d{2}T[\d:\.]+\]', '[<ts>]'
        $t = $t -replace '^\s*WARNING:\s*\d+\s+ObjectDB instances were leaked at exit', 'WARNING: <n> ObjectDB instances were leaked at exit'
        $t = $t -replace '^\s*ERROR:\s*\d+\s+resources still in use at exit', 'ERROR: <n> resources still in use at exit'
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

# 1) 主场景冒烟（参与基线比对）
[void]$results.Add((Invoke-Godot -GodotArgs @('--headless', '--path', $Project, '--quit-after', "$Frames") `
            -Label "主场景冒烟（--quit-after $Frames）"))

# 2) 目标场景
if ($Scenario) {
    [void]$results.Add((Invoke-Godot -GodotArgs @('--headless', '--path', $Project, $Scenario, '--quit-after', '3') `
                -Label "场景实例化 $Scenario"))
}

# 3) 一次性探针
if ($Probe) {
    [void]$results.Add((Invoke-Godot -GodotArgs @('--headless', '--path', $Project, '--script', $Probe) `
                -Label "探针 $Probe"))
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
        if ($r.Label -like '探针*') {
            # 探针的价值就在它的断言输出，所以这里把它的普通输出也打出来
            # （问题行上面已经单独列过，这里跳过，避免重复刷屏）
            Write-Host '        --- 探针输出 ---' -ForegroundColor DarkGray
            $probeOut = @($r.Lines | Where-Object { $_ -notin $problems })
            foreach ($l in ($probeOut | Select-Object -First 150)) { Write-Host ("        {0}" -f $l) -ForegroundColor DarkGray }
        }
    }
}

$newProblems = @()
$missingProblems = @()
$baselineMissing = $false

if (-not $NoBaseline) {
    Write-Host ''
    Write-Host '=== 与基线 diff ===' -ForegroundColor Cyan
    if (-not (Test-Path -LiteralPath $baselinePath)) {
        Write-Host '基线不存在，本次视为初始登记。' -ForegroundColor Yellow
        $baselineMissing = $true
    } else {
        $baseline = Get-Content -LiteralPath $baselinePath -Raw -Encoding UTF8 | ConvertFrom-Json
        $baseProblems = @($baseline.ProblemLines)
        $baseLines = @($baseline.SmokeLines)
        $newProblems = @($smokeProblems | Where-Object { $_ -notin $baseProblems })
        $missingProblems = @($baseProblems | Where-Object { $_ -notin $smokeProblems })
        $newLines = @($smoke.Lines | Where-Object { $_ -notin $baseLines })

        if ($newProblems.Count -eq 0) {
            Write-Host ("无新增 ERROR/WARNING（基线 {0} 行）。" -f $baseProblems.Count) -ForegroundColor Green
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
        Write-Host ("基线: {0}（{1}）" -f $baselinePath, (Get-Item -LiteralPath $baselinePath).LastWriteTime.ToString('s'))
    }
}

if ($UpdateBaseline) {
    $payload = [PSCustomObject]@{
        _comment        = 'verify-engine.ps1 生成的引擎输出基线。机器相关：换机器或存档状态大变后请用 -UpdateBaseline 重登。'
        generated_at    = (Get-Date).ToString('s')
        godot           = $godotExe
        version         = $version
        project         = $Project
        frames          = $Frames
        ProblemLines    = @($smokeProblems)
        SmokeLines      = $smoke.Lines
    }
    $payload | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $baselinePath -Encoding UTF8
    Write-Host ("已写入基线：{0}（问题行 {1}）" -f $baselinePath, @($smokeProblems).Count) -ForegroundColor Yellow
}

Write-Host ''
$exitCode = 0
if ($results | Where-Object { $_.ExitCode -ne 0 }) { $exitCode = 1 }
if (-not $UpdateBaseline -and -not $NoBaseline) {
    if ($baselineMissing) {
        Write-Host '提示：基线还没登记。人工确认上面输出正常后执行 -UpdateBaseline。' -ForegroundColor Yellow
    } elseif ($newProblems.Count -gt 0) {
        $exitCode = 1
    }
}

if ($exitCode -eq 0) {
    Write-Host '验证通过：退出码 0，且没有基线之外的新 ERROR/WARNING。' -ForegroundColor Green
} else {
    Write-Host '验证未通过。上面带 + 的行是新增输出。' -ForegroundColor Red
}
Write-Host ''
exit $exitCode
