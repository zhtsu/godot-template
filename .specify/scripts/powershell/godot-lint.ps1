<#
.SYNOPSIS
    godot-template 静态规则校验（宪法 I / II / III / IV 的可执行版本）。

.DESCRIPTION
    这是"宽松档"实现：只扫 .gd 文件，不扫 .tscn/.tres。
    原因：.tscn 里的 ext_resource path="res://..." 与 script="res://..." 是引擎自己写死的，
    过滤器无法区分"合规的资源引用"与"散落硬编码"，硬扫会全是误报。

    规则配置在 .specify/godot-lint.json（非受管文件，可自由改）。
    违规存量记录在 .specify/godot-lint-baseline.json（只提示，不清零也不阻断）。

    error 级违规会让退出码为 1；warn 级只提示。
    本脚本是只读的：不写任何文件（-WriteBaseline 除外）。

.PARAMETER Json
    输出机器可读的 JSON（Findings / Summary / ExitCode 三个字段）。

.PARAMETER Quiet
    不回显人类可读报告（与 -Json 组合时只输出 JSON）。

.PARAMETER UpdateBaseline
    把当前所有违规写回 .specify/godot-lint-baseline.json（人工确认存量后使用）。

.PARAMETER ListRules
    列出当前生效的规则与配置文件路径，然后退出。

.EXAMPLE
    # 人工/agent 平时这么用
    .specify/scripts/powershell/godot-lint.ps1

.EXAMPLE
    # /speckit-godot-lint 技能用这个
    .specify/scripts/powershell/godot-lint.ps1 -Json
#>
[CmdletBinding()]
param(
    [switch]$Json,
    [switch]$Quiet,
    [switch]$UpdateBaseline,
    [switch]$ListRules
)

$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$configPath = Join-Path $repoRoot '.specify/godot-lint.json'
$baselinePath = Join-Path $repoRoot '.specify/godot-lint-baseline.json'

if ($ListRules) {
    Write-Host "config : $configPath"
    Write-Host "baseline: $baselinePath"
    if (Test-Path $configPath) {
        $cfg = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($p in $cfg.PSObject.Properties) {
            if ($p.Name -eq '_comment' -or $p.Name -eq 'tools' -or $p.Name -eq 'godot') { continue }
            $sev = $null
            if ($p.Value -is [PSCustomObject]) {
                $sevProp = $p.Value.PSObject.Properties['severity']
                if ($sevProp) { $sev = $sevProp.Value }
            }
            Write-Host ("  {0,-14} severity={1}" -f $p.Name, $sev)
        }
    } else {
        Write-Host "配置缺失，脚本会用内置默认值。"
    }
    exit 0
}

if (-not (Test-Path $configPath)) {
    Write-Host "ERROR: 找不到规则配置 $configPath" -ForegroundColor Red
    exit 2
}
$cfg = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json

# --- 小工具 ---------------------------------------------------------------

function Get-Cfg {
    param([string]$Section, [string]$Property, $Default)
    $secProp = $cfg.PSObject.Properties[$Section]
    if (-not $secProp -or $null -eq $secProp.Value) { return $Default }
    $prop = $secProp.Value.PSObject.Properties[$Property]
    if (-not $prop -or $null -eq $prop.Value) { return $Default }
    return $prop.Value
}

$script:Findings = New-Object System.Collections.ArrayList

function Add-Finding {
    param(
        [Parameter(Mandatory)][string]$Rule,
        [Parameter(Mandatory)][string]$Severity,
        [Parameter(Mandatory)][string]$Message,
        [string]$File = '',
        [int]$Line = 0,
        [string]$Snippet = ''
    )
    [void]$script:Findings.Add([PSCustomObject]@{
        Rule    = $Rule
        Severity = $Severity
        File    = $File
        Line    = $Line
        Message = $Message
        Snippet = $Snippet.Trim()
    })
}

# 注释行判定：宽松档只跳过"整行是注释"的行（# / ## / ; 开头），
# 不做行内注释剥离（否则 '#' 出现在字符串里会误判）。
function Test-IsCommentLine {
    param([string]$Text)
    $t = $Text.TrimStart()
    return ($t.StartsWith('#') -or $t.StartsWith(';'))
}

function Get-ScanFiles {
    param([string[]]$Dirs, [string[]]$Extensions)
    $out = @()
    foreach ($d in $Dirs) {
        $full = Join-Path $repoRoot $d
        if (-not (Test-Path $full)) { continue }
        $files = if ($Extensions -contains '.gd') {
            Get-ChildItem -LiteralPath $full -Recurse -File -Filter '*.gd'
        } else {
            Get-ChildItem -LiteralPath $full -Recurse -File
        }
        foreach ($f in $files) {
            if ($f.FullName -like '*\addons\*' -or $f.FullName -like '*\.godot\*') { continue }
            $ext = $f.Extension.ToLower()
            if ($Extensions -and ($Extensions -notcontains $ext)) { continue }
            $out += $f
        }
    }
    return ($out | Sort-Object -Property FullName -Unique)
}

function Get-RelPath {
    param([string]$FullName)
    return $FullName.Substring($repoRoot.Length).TrimStart('\', '/') -replace '\\', '/'
}

# --- 规则 1: 路径集中化（宪法 I）-----------------------------------------
function Invoke-PathRule {
    $dirs = @(Get-Cfg 'paths' 'files' @('core', 'entry', 'ui', 'save_data'))
    $allow = @(Get-Cfg 'paths' 'allow' @('core/paths.gd'))
    $sev = [string](Get-Cfg 'paths' 'severity' 'error')
    foreach ($f in (Get-ScanFiles -Dirs $dirs -Extensions @('.gd'))) {
        $rel = Get-RelPath $f.FullName
        if ($allow -contains $rel) { continue }
        $lines = Get-Content -LiteralPath $f.FullName -Encoding UTF8
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $line = $lines[$i]
            if (Test-IsCommentLine $line) { continue }
            if ($line -notmatch '"res://') { continue }
            Add-Finding -Rule 'paths' -Severity $sev -File $rel -Line ($i + 1) -Snippet $line `
                -Message 'res:// 字面量只允许出现在 core/paths.gd（宪法 I）'
        }
    }
}

# --- 规则 2: 事件名集中化（宪法 I）--------------------------------------
function Invoke-EventRule {
    $dirs = @(Get-Cfg 'events' 'files' @('core', 'entry', 'ui', 'save_data'))
    $allow = @(Get-Cfg 'events' 'allow' @('core/events.gd'))
    $names = @(Get-Cfg 'events' 'names' @())
    $sev = [string](Get-Cfg 'events' 'severity' 'error')
    if ($names.Count -eq 0) { return }
    $pattern = '"(' + (($names | ForEach-Object { [regex]::Escape($_) }) -join '|') + ')"'
    foreach ($f in (Get-ScanFiles -Dirs $dirs -Extensions @('.gd'))) {
        $rel = Get-RelPath $f.FullName
        if ($allow -contains $rel) { continue }
        $lines = Get-Content -LiteralPath $f.FullName -Encoding UTF8
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $line = $lines[$i]
            if (Test-IsCommentLine $line) { continue }
            if ($line -match $pattern) {
                Add-Finding -Rule 'events' -Severity $sev -File $rel -Line ($i + 1) -Snippet $line `
                    -Message ("事件名字符串 '" + $Matches[1] + "' 只能出现在 core/events.gd（宪法 I）")
            }
        }
    }
}

# --- 规则 3: UI 不得绕过 ui_root（宪法 II）------------------------------
function Invoke-UiBypassRule {
    $dirs = @(Get-Cfg 'ui_bypass' 'files' @('ui'))
    $patterns = @(Get-Cfg 'ui_bypass' 'patterns' @('\.instantiate\s*\(', '\.queue_free\s*\('))
    $sev = [string](Get-Cfg 'ui_bypass' 'severity' 'error')
    if ($patterns.Count -eq 0) { return }
    foreach ($f in (Get-ScanFiles -Dirs $dirs -Extensions @('.gd'))) {
        $rel = Get-RelPath $f.FullName
        $lines = Get-Content -LiteralPath $f.FullName -Encoding UTF8
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $line = $lines[$i]
            if (Test-IsCommentLine $line) { continue }
            foreach ($p in $patterns) {
                if ($line -match $p) {
                    Add-Finding -Rule 'ui_bypass' -Severity $sev -File $rel -Line ($i + 1) -Snippet $line `
                        -Message '界面生命周期必须经 Events.OPEN_UI / CLOSE_UI 交给 core/ui_root.gd（宪法 II）'
                    break
                }
            }
        }
    }
}

# --- 规则 4: 禁止长节点路径（宪法 技术约束）-----------------------------
function Invoke-SceneTreeRule {
    $dirs = @(Get-Cfg 'scene_tree' 'files' @('core', 'entry', 'ui', 'save_data'))
    $sev = [string](Get-Cfg 'scene_tree' 'severity' 'warn')
    $pattern = '\$[A-Za-z_][A-Za-z0-9_]*\s*/|get_node\s*\(\s*"(?!\.)(?!%)(?!\*)[^"]*[/][^"]*"'
    foreach ($f in (Get-ScanFiles -Dirs $dirs -Extensions @('.gd'))) {
        $rel = Get-RelPath $f.FullName
        $lines = Get-Content -LiteralPath $f.FullName -Encoding UTF8
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $line = $lines[$i]
            if (Test-IsCommentLine $line) { continue }
            if ($line -match $pattern) {
                Add-Finding -Rule 'scene_tree' -Severity $sev -File $rel -Line ($i + 1) -Snippet $line `
                    -Message '长节点路径易碎（改名只在运行时才报错），新代码请用 %唯一名 或 @export'
            }
        }
    }
}

# --- 规则 5: 翻译键三处同步 + orphan（宪法 IV）--------------------------
function Get-PoKeys {
    param([string]$FullPath)
    $keys = New-Object System.Collections.ArrayList
    if (-not (Test-Path $FullPath)) { return @() }
    foreach ($line in (Get-Content -LiteralPath $FullPath -Encoding UTF8)) {
        if ($line -match '^msgid\s+"(.+)"\s*$') { [void]$keys.Add($Matches[1]) }
    }
    return $keys.ToArray()
}

function Invoke-LocaleRule {
    $po = Get-Cfg 'locale' 'poFiles' $null
    if (-not $po) { return }
    $sev = [string](Get-Cfg 'locale' 'severity' 'error')
    $orphanSev = [string](Get-Cfg 'locale' 'orphanSeverity' 'warn')
    $prefix = [string](Get-Cfg 'locale' 'keyPrefix' 'ui.')
    $orphanBaseline = [int](Get-Cfg 'locale' 'orphanBaseline' 0)

    $sets = @{}
    foreach ($p in $po.PSObject.Properties) {
        $rel = $p.Value
        $keys = @(Get-PoKeys (Join-Path $repoRoot $rel))
        $sets[$p.Name] = [PSCustomObject]@{ Path = $rel; Keys = $keys }
    }

    # 5a) 三处 key 集合必须相等
    $names = @($sets.Keys)
    for ($a = 0; $a -lt $names.Count; $a++) {
        for ($b = $a + 1; $b -lt $names.Count; $b++) {
            $na = $names[$a]; $nb = $names[$b]
            $onlyA = @($sets[$na].Keys | Where-Object { $_ -notin $sets[$nb].Keys })
            $onlyB = @($sets[$nb].Keys | Where-Object { $_ -notin $sets[$na].Keys })
            foreach ($k in $onlyA) {
                Add-Finding -Rule 'locale_sync' -Severity $sev -File $sets[$na].Path `
                    -Message ("key '{0}' 只存在于 {1}，缺少于 {2}（宪法 IV）" -f $k, $na, $nb)
            }
            foreach ($k in $onlyB) {
                Add-Finding -Rule 'locale_sync' -Severity $sev -File $sets[$nb].Path `
                    -Message ("key '{0}' 只存在于 {1}，缺少于 {2}（宪法 IV）" -f $k, $nb, $na)
            }
        }
    }

    # 5b) orphan：三处都有但项目里没引用
    $allKeys = @($sets[$names[0]].Keys)
    $used = New-Object 'System.Collections.Generic.HashSet[string]'
    $refFiles = @()
    $refFiles += Get-ScanFiles -Dirs @('core', 'entry', 'ui', 'save_data') -Extensions @('.gd')
    $refFiles += Get-ScanFiles -Dirs @('core', 'entry', 'ui') -Extensions @('.tscn')
    foreach ($f in $refFiles) {
        $text = [System.IO.File]::ReadAllText($f.FullName, [System.Text.Encoding]::UTF8)
        foreach ($m in [regex]::Matches($text, '"(' + [regex]::Escape($prefix) + '[^"]+)"')) {
            [void]$used.Add($m.Groups[1].Value)
        }
    }
    $orphans = @($allKeys | Where-Object { $prefix -and $_.StartsWith($prefix) -and -not $used.Contains($_) })
    if ($orphans.Count -gt $orphanBaseline) {
        Add-Finding -Rule 'locale_orphan' -Severity $orphanSev -File $sets[$names[0]].Path `
            -Message ("orphan key {0} 个，超过基线 {1} 个：{2}（新增了没被引用的 key？）" -f $orphans.Count, $orphanBaseline, ($orphans -join ', '))
    }
}

# --- 规则 6: 存档分段字段类型（宪法 III）-------------------------------
function Invoke-SaveDataRule {
    $dir = [string](Get-Cfg 'save_data' 'dir' 'save_data')
    $forbidden = @(Get-Cfg 'save_data' 'forbiddenTypes' @('Object', 'Callable', 'Signal', 'RID'))
    $sev = [string](Get-Cfg 'save_data' 'severity' 'error')
    if ($forbidden.Count -eq 0) { return }
    $dirFull = Join-Path $repoRoot $dir
    if (-not (Test-Path $dirFull)) { return }

    $typeAlt = ($forbidden | ForEach-Object { [regex]::Escape($_) }) -join '|'
    # 只看类型标注：[const|var|static var] name: Type  或  func f() -> Type
    $declPattern = '(?i)(?:\b(?:const|var|static\s+var)\s+[A-Za-z_][A-Za-z0-9_]*\s*:\s*|\b[A-Za-z_][A-Za-z0-9_]*\s*\([^)]*\)\s*->\s*)(' + $typeAlt + ')\b'
    $arrayPattern = '(?i)Array\s*\[\s*(' + $typeAlt + ')\s*\]'

    foreach ($f in (Get-ChildItem -LiteralPath $dirFull -Recurse -File -Filter '*.gd')) {
        $rel = Get-RelPath $f.FullName
        $lines = Get-Content -LiteralPath $f.FullName -Encoding UTF8
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $line = $lines[$i]
            if (Test-IsCommentLine $line) { continue }
            $hit = $null
            if ($line -match $declPattern) { $hit = $Matches[1] }
            elseif ($line -match $arrayPattern) { $hit = $Matches[1] }
            if ($hit) {
                Add-Finding -Rule 'save_data_type' -Severity $sev -File $rel -Line ($i + 1) -Snippet $line `
                    -Message ("存档分段不得标注 '{0}' 类型：to_dict() 会静默跳过它（宪法 III）" -f $hit)
            }
        }
    }

    # 6b) 结构版本提示：save_data/ 下若有非基类文件比 save_data.gd 更新，提醒核对 version
    $rootFile = Join-Path $dirFull 'save_data.gd'
    if (Test-Path $rootFile) {
        $rootTime = (Get-Item -LiteralPath $rootFile).LastWriteTimeUtc
        $newer = @(Get-ChildItem -LiteralPath $dirFull -File -Filter '*.gd' |
            Where-Object { $_.Name -notin @('save_data.gd', 'save_section.gd') -and $_.LastWriteTimeUtc -gt $rootTime })
        if ($newer.Count -gt 0) {
            Add-Finding -Rule 'save_data_version' -Severity 'warn' -File (Get-RelPath $rootFile) `
                -Message ("以下分段类比 save_data.gd 新：{0}；若动了字段结构，请确认 SaveData.version 已 +1 且 migrate() 有对应分支" -f (($newer | ForEach-Object { $_.Name }) -join ', '))
        }
    }
}

# --- 规则 7: 仓库根的临时/探针脚本 --------------------------------------
# 宪法原则 VII 允许只读的 git 查询，所以这里用 `git ls-files` 判断跟踪状态
# （比手工解析 .gitignore 准确）。若 git 不可用则退化为纯文件系统判定，
# 只过滤 .gitignore 里的字面模式，并在报告里说明降级。
function Get-IgnorePatterns {
    param([string]$RepoRoot)
    $patterns = New-Object System.Collections.ArrayList
    foreach ($name in @('.gitignore', '.specify/.gitignore')) {
        $p = Join-Path $RepoRoot $name
        if (-not (Test-Path $p)) { continue }
        foreach ($line in (Get-Content -LiteralPath $p -Encoding UTF8)) {
            $t = $line.Trim()
            if ($t.Length -eq 0) { continue }
            if ($t.StartsWith('#')) { continue }
            if ($t.StartsWith('!')) { continue }   # 反向规则一律忽略，宁可多报
            [void]$patterns.Add($t)
        }
    }
    return $patterns.ToArray()
}

function Test-IgnoredByPattern {
    param([string]$RelPath, [string[]]$Patterns)
    $rel = $RelPath -replace '\\', '/'
    foreach ($pat in $Patterns) {
        $p = $pat.TrimEnd('/')
        if ($p.Length -eq 0) { continue }
        $anchored = $p.StartsWith('/')
        if ($anchored) { $p = $p.Substring(1) }
        $hasSlash = $p.Contains('/')
        $regex = '^' + [regex]::Escape($p).Replace('\*', '[^/]*').Replace('\?', '[^/]') + '$'
        if ($anchored -or $hasSlash) {
            if ($rel -match $regex) { return $true }
        } else {
            foreach ($seg in ($rel -split '/')) {
                if ($seg -match $regex) { return $true }
            }
        }
    }
    return $false
}

function Get-TrackedFiles {
    param([string]$RepoRoot)
    try {
        $out = @(& git -C $RepoRoot ls-files 2>$null)
        if ($LASTEXITCODE -eq 0) { return @($out | ForEach-Object { $_ -replace '\\', '/' }) }
    } catch { }
    return $null      # null = git 不可用
}

function Invoke-TempFileRule {
    $tracked = Get-TrackedFiles -RepoRoot $repoRoot
    $usingGit = ($null -ne $tracked)
    $trackedSet = New-Object 'System.Collections.Generic.HashSet[string]'
    if ($usingGit) { foreach ($t in $tracked) { [void]$trackedSet.Add($t) } }
    $patterns = @(Get-IgnorePatterns -RepoRoot $repoRoot)

    $candidates = @(Get-ChildItem -LiteralPath $repoRoot -File -Filter '_*.gd' -ErrorAction SilentlyContinue)
    foreach ($c in $candidates) {
        $rel = Get-RelPath $c.FullName
        if ($usingGit) {
            if ($trackedSet.Contains($rel)) {
                Add-Finding -Rule 'temp_files' -Severity 'warn' -File $rel `
                    -Message '已跟踪的探针/临时脚本：确认它是有意提交的示例，否则请删除并提交（MUST NOT 由 agent 自行 git rm）'
            } else {
                Add-Finding -Rule 'temp_files' -Severity 'warn' -File $rel `
                    -Message '未跟踪的一次性探针/临时脚本，交付前必须删除（宪法 V）'
            }
        } else {
            if (Test-IgnoredByPattern -RelPath $rel -Patterns $patterns) { continue }
            Add-Finding -Rule 'temp_files' -Severity 'warn' -File $rel `
                -Message '仓库根的探针/临时脚本（git 不可用，已降级为 .gitignore 字面匹配），交付前请删除（宪法 V）'
        }
    }
}

# --- 执行 -----------------------------------------------------------------
Invoke-PathRule
Invoke-EventRule
Invoke-UiBypassRule
Invoke-SceneTreeRule
Invoke-LocaleRule
Invoke-SaveDataRule
Invoke-TempFileRule

$errors = @($script:Findings | Where-Object { $_.Severity -eq 'error' })
$warns = @($script:Findings | Where-Object { $_.Severity -eq 'warn' })
$exitCode = if ($errors.Count -gt 0) { 1 } else { 0 }

# 存量基线（只做提示）
$baselineCount = 0
if (Test-Path $baselinePath) {
    try {
        $b = Get-Content -LiteralPath $baselinePath -Raw -Encoding UTF8 | ConvertFrom-Json
        $baselineCount = @($b.Findings).Count
    } catch { $baselineCount = 0 }
}

if ($UpdateBaseline) {
    $payload = [PSCustomObject]@{
        _comment = 'godot-lint.ps1 -UpdateBaseline 生成。记录规则上线时的违规存量，仅供对比，不阻断也不清零。'
        generated_at = (Get-Date).ToString('s')
        godot = [string](Get-Cfg 'godot' 'executable' '')
        Findings = $script:Findings
    }
    $payload | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $baselinePath -Encoding UTF8
    Write-Host "已写入基线：$baselinePath（$($script:Findings.Count) 条）"
}

if ($Json) {
    [PSCustomObject]@{
        Config       = '.specify/godot-lint.json'
        BaselinePath = '.specify/godot-lint-baseline.json'
        BaselineSize = $baselineCount
        ErrorCount   = $errors.Count
        WarnCount    = $warns.Count
        ExitCode     = $exitCode
        Findings     = $script:Findings
    } | ConvertTo-Json -Depth 6
    exit $exitCode
}

if (-not $Quiet) {
    Write-Host ''
    Write-Host '=== godot-lint（宽松档：只扫 .gd）===' -ForegroundColor Cyan
    Write-Host "仓库: $repoRoot"
    if ($script:Findings.Count -eq 0) {
        Write-Host '没有发现违规。' -ForegroundColor Green
    } else {
        foreach ($f in $script:Findings) {
            $color = if ($f.Severity -eq 'error') { 'Red' } else { 'Yellow' }
            $loc = if ($f.Line -gt 0) { "{0}:{1}" -f $f.File, $f.Line } else { $f.File }
            Write-Host ("[{0}] {1}  {2}" -f $f.Severity.ToUpper(), $f.Rule, $loc) -ForegroundColor $color
            Write-Host ("        {0}" -f $f.Message)
            if ($f.Snippet) { Write-Host ("        > {0}" -f $f.Snippet) -ForegroundColor DarkGray }
        }
    }
    Write-Host ''
    Write-Host ("error={0}  warn={1}  存量基线={2} 条" -f $errors.Count, $warns.Count, $baselineCount)
    if ($errors.Count -gt 0) {
        Write-Host '有 error 级违规：违反宪法硬规则，必须修（或按宪法 Governance 走豁免流程）。' -ForegroundColor Red
    } else {
        Write-Host '无 error 级违规。warn 是存量/建议，不阻断。' -ForegroundColor Green
    }
    Write-Host ''
}

exit $exitCode
