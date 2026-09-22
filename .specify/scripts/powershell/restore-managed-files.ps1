<#
.SYNOPSIS
    把 spec-kit 受管文件恢复成 manifest 记录的原始内容（逐字节一致）。

.DESCRIPTION
    用途：受管文件被误改后（agent 手滑、编辑器改行尾、`specify init --force` 之外的写入），
    让 `specify integration status` 重新回到 Modified managed files: 0。

    为什么不能简单"把多加的行删掉"：行尾与末尾换行也必须一致。
    本仓库的 .gitattributes 是 `* text=auto eol=lf`，但**已安装的受管文件并不都符合它**
    （实测 .specify/.gitignore 是 383 字节且带末尾换行）。手工编辑极易差几个字节，
    而 manifest 校验的是 sha256，差一个字节就报 modified。
    所以本脚本不猜：它枚举几种常见行尾/末尾换行组合，逐一算 sha256，命中才算恢复。

    脚本只读 manifest、只写命中的那个文件；不做任何猜测性写入。
    找不到匹配组合时会明确报告并保持文件不动。

.PARAMETER File
    要恢复的受管文件路径（相对仓库根）。缺省则检查全部受管文件并只报告漂移。

.PARAMETER All
    恢复全部漂移的受管文件。

.EXAMPLE
    # 只看有没有漂移
    .specify/scripts/powershell/restore-managed-files.ps1

.EXAMPLE
    # 恢复一个文件
    .specify/scripts/powershell/restore-managed-files.ps1 -File .specify/.gitignore
#>
[CmdletBinding()]
param(
    [string]$File,
    [switch]$All
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$manifests = @(
    Join-Path $repoRoot '.specify/integrations/dsh.manifest.json'
    Join-Path $repoRoot '.specify/integrations/speckit.manifest.json'
)

# 汇总所有受管文件及其期望哈希
$expected = @{}
foreach ($m in $manifests) {
    if (-not (Test-Path $m)) { continue }
    $j = Get-Content -LiteralPath $m -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($p in $j.files.PSObject.Properties) {
        $expected[$p.Name.Replace('\', '/')] = $p.Value
    }
}

function Get-Drifted {
    $out = @()
    foreach ($rel in $expected.Keys) {
        $full = Join-Path $repoRoot $rel
        if (-not (Test-Path $full)) { $out += [PSCustomObject]@{ Rel = $rel; Reason = 'MISSING' }; continue }
        $h = (Get-FileHash $full -Algorithm SHA256).Hash.ToLower()
        if ($h -ne $expected[$rel]) { $out += [PSCustomObject]@{ Rel = $rel; Reason = 'MODIFIED' } }
    }
    return $out
}

function Find-MatchingBytes {
    param([string]$Target, [string]$Want)

    # 先按行拆，再重组出常见形态，逐一比对 sha256
    $text = $Target.Replace("`r`n", "`n").Replace("`r", "`n")
    $hasTrailing = $text.EndsWith("`n")
    $core = $text.TrimEnd("`n")
    $lines = $core -split "`n"

    $variants = [ordered]@{}
    $variants['LF+末尾LF'] = (($lines -join "`n") + "`n")
    $variants['LF无末尾'] = ($lines -join "`n")
    $variants['LF+末尾LF+LF'] = (($lines -join "`n") + "`n`n")
    $variants['CRLF+末尾CRLF'] = (($lines -join "`r`n") + "`r`n")
    $variants['CRLF无末尾'] = ($lines -join "`r`n")

    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("restore-managed-" + [guid]::NewGuid().ToString('N'))
    try {
        foreach ($k in $variants.Keys) {
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($variants[$k])
            [System.IO.File]::WriteAllBytes($tmp, $bytes)
            $h = (Get-FileHash $tmp -Algorithm SHA256).Hash.ToLower()
            if ($h -eq $Want) {
                return [PSCustomObject]@{ Bytes = $bytes; Variant = $k; Length = $bytes.Length }
            }
        }
    } finally {
        if (Test-Path $tmp) { Remove-Item $tmp -Force }
    }
    return $null
}

$drifted = Get-Drifted
if ($drifted.Count -eq 0) {
    Write-Host '受管文件无漂移（Modified/Missing 均为 0）。' -ForegroundColor Green
    exit 0
}

Write-Host ("发现 {0} 个受管文件漂移：" -f $drifted.Count) -ForegroundColor Yellow
foreach ($d in $drifted) { Write-Host ("  [{0}] {1}" -f $d.Reason, $d.Rel) }

$targets = @()
if ($File) { $targets = @($File.Replace('\', '/')) }
elseif ($All) { $targets = @($drifted | ForEach-Object { $_.Rel }) }
else {
    Write-Host ''
    Write-Host '未指定 -File 或 -All，只做报告。要恢复请加 -File <路径> 或 -All。'
    Write-Host '提示：受管文件本就不该手改；定制一律写 .specify/templates/overrides/。'
    exit 1
}

$failed = 0
foreach ($rel in $targets) {
    if (-not $expected.ContainsKey($rel)) {
        Write-Host ("跳过 {0}：不在任何 manifest 里（不是受管文件）" -f $rel) -ForegroundColor DarkYellow
        continue
    }
    $full = Join-Path $repoRoot $rel
    $cur = [System.IO.File]::ReadAllText($full, [System.Text.Encoding]::UTF8)
    $match = Find-MatchingBytes -Target $cur -Want $expected[$rel]
    if (-not $match) {
        Write-Host ("无法恢复 {0}：内容与 manifest 记录的版本不一致，且不在已知行尾变体范围内。" -f $rel) -ForegroundColor Red
        Write-Host '  这说明它有实质内容改动（不只是行尾/换行差异）。请从上游重新获取，或人工比对。'
        $failed++
        continue
    }
    [System.IO.File]::WriteAllBytes($full, $match.Bytes)
    $h = (Get-FileHash $full -Algorithm SHA256).Hash.ToLower()
    if ($h -eq $expected[$rel]) {
        Write-Host ("已恢复 {0}（{1}，{2} 字节）" -f $rel, $match.Variant, $match.Length) -ForegroundColor Green
    } else {
        Write-Host ("恢复 {0} 后哈希仍不匹配，已中止" -f $rel) -ForegroundColor Red
        $failed++
    }
}

Write-Host ''
$after = Get-Drifted
if ($after.Count -eq 0) {
    Write-Host '复查：受管文件无漂移。' -ForegroundColor Green
    exit 0
} else {
    Write-Host ("复查：仍有 {0} 个漂移" -f $after.Count) -ForegroundColor Yellow
    exit 1
}
