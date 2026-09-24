<#
.SYNOPSIS
    godot-template 静态规则门禁。

.DESCRIPTION
    把项目里几条"靠人记"的约定变成可执行检查。error 级违规会让退出码非 0。

    error 级（违反约定，必须修）：
      paths           `res://` 字面量只允许出现在 core/paths.gd
      events          事件名字符串只允许出现在 core/events.gd
      ui_bypass       ui/ 下不得直接 instantiate() / queue_free()（界面生命周期交给 UiRoot）
      save_data_type  save_data/ 下分段字段不得使用 Object / Callable / Signal / RID 等类型
      locale          en.po / zh_CN.po / texts.pot 三处 msgid 集合必须完全一致

    warn 级（存量或建议，不阻断）：
      scene_tree      长节点路径（$A/B 或 get_node("A/B")）易碎，新代码请用 %唯一名 或 @export
      locale_orphan   三处都有、但 core/entry/ui/save_data 的 .gd/.tscn 里没人引用的 key
      temp_files      仓库里的临时脚本（`_*.gd` 等），交付前必须删除

.PARAMETER Project
    Godot 工程目录，默认 <仓库根>/godot-template。

.EXAMPLE
    pwsh scripts/godot-lint.ps1
#>
[CmdletBinding()]
param(
    [string]$Project
)

$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if (-not $Project) { $Project = Join-Path $repoRoot 'godot-template' }
if (-not (Test-Path (Join-Path $Project 'project.godot'))) {
    Write-Host "ERROR: $Project 下没有 project.godot；用 -Project 指定工程目录。" -ForegroundColor Red
    exit 2
}

# --- 可调配置 -------------------------------------------------------------
$scanDirs = @('core', 'entry', 'ui', 'save_data', 'game')      # 只扫项目层，不扫 addons/
$pathsAllow = @('core/paths.gd')
$eventsAllow = @('core/events.gd')
$eventNames = @(
    'open_ui', 'close_ui',
    'start_game', 'return_to_title', 'pause_toggle',
    'save_request', 'load_request', 'delete_save_request', 'save_list_request',
    'save_finished', 'load_finished', 'delete_save_finished', 'save_list_ready'
)
$forbiddenTypes = @('Object', 'Node', 'NodePath', 'Resource', 'Callable', 'Signal', 'RID')
$localeFiles = [ordered]@{
    en    = 'locale/en.po'
    zh_CN = 'locale/zh_CN.po'
    pot   = 'locale/texts.pot'
}
$orphanBaseline = 0   # 存量 orphan 数；清理后请一起调低

# --- 工具函数 -------------------------------------------------------------
$findings = New-Object System.Collections.ArrayList

function Add-Finding {
    param([string]$Rule, [string]$Severity, [string]$File, [int]$Line, [string]$Snippet, [string]$Message)
    [void]$findings.Add([PSCustomObject]@{
            Rule = $Rule; Severity = $Severity; File = $File
            Line = $Line; Snippet = $Snippet; Message = $Message
        })
}

function Get-ScanFiles {
    param([string[]]$Dirs, [string[]]$Extensions)
    $out = New-Object System.Collections.ArrayList
    foreach ($d in $Dirs) {
        $full = Join-Path $Project $d
        if (-not (Test-Path -LiteralPath $full)) { continue }
        foreach ($f in Get-ChildItem -LiteralPath $full -Recurse -File) {
            if ($Extensions -notcontains $f.Extension) { continue }
            [void]$out.Add($f)
        }
    }
    return ($out | Sort-Object -Property FullName -Unique)
}

function Get-RelPath {
    param([string]$FullName)
    return ($FullName.Substring($repoRoot.Length).TrimStart('\', '/') -replace '\\', '/')
}

# 规则里的 allow 列表按"工程相对路径"写（如 core/paths.gd），
# 这样工程挪目录（godot-template/ 改名或换层）也不用改配置。
function Get-ProjectRelPath {
    param([string]$FullName)
    return ($FullName.Substring($Project.Length).TrimStart('\', '/') -replace '\\', '/')
}

function Test-IsCommentLine {
    param([string]$Line)
    return $Line.TrimStart().StartsWith('#')
}

function Get-MsgIds {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    $ids = New-Object System.Collections.ArrayList
    foreach ($line in (Get-Content -LiteralPath $Path -Encoding UTF8)) {
        if ($line -match '^msgid\s+"(.+)"') { [void]$ids.Add($matches[1]) }
    }
    return $ids
}

# --- 规则 1: res:// 路径集中 ---------------------------------------------
foreach ($f in (Get-ScanFiles -Dirs $scanDirs -Extensions @('.gd'))) {
    $rel = Get-RelPath $f.FullName
    $prel = Get-ProjectRelPath $f.FullName
    if ($pathsAllow -contains $prel) { continue }
    $lines = Get-Content -LiteralPath $f.FullName -Encoding UTF8
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if (Test-IsCommentLine $lines[$i]) { continue }
        if ($lines[$i] -notmatch '"res://') { continue }
        Add-Finding -Rule 'paths' -Severity 'error' -File $rel -Line ($i + 1) -Snippet $lines[$i].Trim() `
            -Message "res:// 字面量只允许出现在 core/paths.gd（把路径加到 Paths 里再引用）"
    }
}

# --- 规则 2: 事件名集中 ---------------------------------------------------
$eventPattern = '"(' + (($eventNames | ForEach-Object { [regex]::Escape($_) }) -join '|') + ')"'
foreach ($f in (Get-ScanFiles -Dirs $scanDirs -Extensions @('.gd'))) {
    $rel = Get-RelPath $f.FullName
    $prel = Get-ProjectRelPath $f.FullName
    if ($eventsAllow -contains $prel) { continue }
    $lines = Get-Content -LiteralPath $f.FullName -Encoding UTF8
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if (Test-IsCommentLine $lines[$i]) { continue }
        if ($lines[$i] -match $eventPattern) {
            Add-Finding -Rule 'events' -Severity 'error' -File $rel -Line ($i + 1) -Snippet $lines[$i].Trim() `
                -Message "事件名字符串 '$($matches[1])' 只能出现在 core/events.gd（用 Events.XXX 引用）"
        }
    }
}

# --- 规则 3: UI 不得绕过 UiRoot ------------------------------------------
foreach ($f in (Get-ScanFiles -Dirs @('ui') -Extensions @('.gd'))) {
    $rel = Get-RelPath $f.FullName
    $lines = Get-Content -LiteralPath $f.FullName -Encoding UTF8
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if (Test-IsCommentLine $lines[$i]) { continue }
        if ($lines[$i] -match '\.instantiate\s*\(|\.queue_free\s*\(') {
            Add-Finding -Rule 'ui_bypass' -Severity 'error' -File $rel -Line ($i + 1) -Snippet $lines[$i].Trim() `
                -Message "界面生命周期必须经 Events.OPEN_UI / CLOSE_UI 交给 core/ui_root.gd"
        }
    }
}

# --- 规则 4: save_data 只允许基础类型 ------------------------------------
$typePattern = '(:|->)\s*(' + (($forbiddenTypes | ForEach-Object { [regex]::Escape($_) }) -join '|') + ')\b'
foreach ($f in (Get-ScanFiles -Dirs @('save_data') -Extensions @('.gd'))) {
    $rel = Get-RelPath $f.FullName
    $lines = Get-Content -LiteralPath $f.FullName -Encoding UTF8
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if (Test-IsCommentLine $lines[$i]) { continue }
        if ($lines[$i] -match $typePattern) {
            Add-Finding -Rule 'save_data_type' -Severity 'error' -File $rel -Line ($i + 1) -Snippet $lines[$i].Trim() `
                -Message "分段字段不能是 $($matches[2])：纯数据存档存不了它（写进去只会静默丢数据）"
        }
    }
}

# --- 规则 5: 翻译 key 三处一致 + orphan ----------------------------------
$ids = [ordered]@{}
foreach ($k in $localeFiles.Keys) {
    $ids[$k] = @(Get-MsgIds (Join-Path $Project $localeFiles[$k]))
}
$allIds = @($ids.Values | ForEach-Object { $_ } | Sort-Object -Unique)
foreach ($id in $allIds) {
    $missing = @($ids.Keys | Where-Object { $ids[$_] -notcontains $id })
    if ($missing.Count -gt 0) {
        Add-Finding -Rule 'locale' -Severity 'error' -File 'locale/' -Line 0 -Snippet $id `
            -Message "key '$id' 缺在：$($missing -join ', ')（三处必须同步）"
    }
}

$referenceBlob = (Get-ScanFiles -Dirs $scanDirs -Extensions @('.gd', '.tscn') |
    ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8 }) -join "`n"
$orphans = @($ids['en'] | Where-Object { -not $referenceBlob.Contains($_) })
foreach ($id in $orphans) {
    Add-Finding -Rule 'locale_orphan' -Severity 'warn' -File 'locale/en.po' -Line 0 -Snippet $id `
        -Message "key '$id' 三处都有但没人引用（清理，或补上使用点）"
}
if ($orphans.Count -gt $orphanBaseline) {
    Add-Finding -Rule 'locale_orphan' -Severity 'warn' -File 'locale/' -Line 0 -Snippet "$($orphans.Count) 个" `
        -Message "orphan 数（$($orphans.Count)）超过基线 $orphanBaseline"
}

# --- 规则 6: 长节点路径（warn） ------------------------------------------
$sceneTreePattern = '\$[A-Za-z_][A-Za-z0-9_]*\s*/|get_node\s*\(\s*"(?!\.)(?!%)(?!\*)[^"]*[/][^"]*"'
foreach ($f in (Get-ScanFiles -Dirs $scanDirs -Extensions @('.gd'))) {
    $rel = Get-RelPath $f.FullName
    $lines = Get-Content -LiteralPath $f.FullName -Encoding UTF8
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if (Test-IsCommentLine $lines[$i]) { continue }
        if ($lines[$i] -match $sceneTreePattern) {
            Add-Finding -Rule 'scene_tree' -Severity 'warn' -File $rel -Line ($i + 1) -Snippet $lines[$i].Trim() `
                -Message "长节点路径易碎（改名只在运行时才报错），新代码请用 %唯一名 或 @export"
        }
    }
}

# --- 规则 7: 临时文件残留（warn） ----------------------------------------
foreach ($f in (Get-ChildItem -LiteralPath $Project -Recurse -File -Force)) {
    if ($f.FullName -match '\\\.godot\\|\\addons\\') { continue }
    if ($f.Name -match '^_' -and $f.Extension -in @('.gd', '.tscn', '.tres', '.tmp')) {
        Add-Finding -Rule 'temp_files' -Severity 'warn' -File (Get-RelPath $f.FullName) -Line 0 -Snippet $f.Name `
            -Message "临时脚本/资源，交付前必须删除"
    }
}

# --- 报告 -----------------------------------------------------------------
$errors = @($findings | Where-Object { $_.Severity -eq 'error' })
$warns = @($findings | Where-Object { $_.Severity -eq 'warn' })

Write-Host ''
Write-Host '=== godot-lint（静态规则门禁）===' -ForegroundColor Cyan
Write-Host "工程: $Project"
foreach ($f in ($findings | Sort-Object @{Expression = { if ($_.Severity -eq 'error') { 0 } else { 1 } } }, Rule, File, Line)) {
    $color = if ($f.Severity -eq 'error') { 'Red' } else { 'DarkYellow' }
    $tag = $f.Severity.ToUpper()
    $where = if ($f.Line -gt 0) { "$($f.File):$($f.Line)" } else { $f.File }
    Write-Host ("[{0}] {1,-14} {2}" -f $tag, $f.Rule, $where) -ForegroundColor $color
    if ($f.Snippet) { Write-Host ("        > {0}" -f $f.Snippet) -ForegroundColor DarkGray }
    Write-Host ("        {0}" -f $f.Message) -ForegroundColor DarkGray
}

Write-Host ''
Write-Host ("error={0}  warn={1}" -f $errors.Count, $warns.Count)
if ($errors.Count -eq 0) {
    Write-Host '无 error 级违规。warn 是存量/建议，不阻断。' -ForegroundColor Green
} else {
    Write-Host '有 error 级违规，必须修。' -ForegroundColor Red
}
Write-Host ''
exit ($(if ($errors.Count -gt 0) { 1 } else { 0 }))
