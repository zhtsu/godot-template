---
name: "speckit-godot-lint"
description: "Run godot-template's static rule checks (constitution principles I/II/III/IV) against the current working tree before or after implementation, and report violations with file:line evidence."
compatibility: "Requires the godot-template repo layout and PowerShell 7 (pwsh). Reads .specify/godot-lint.json."
metadata:
  author: "godot-template"
  source: "project-local skill (not managed by spec-kit; safe to edit)"
---

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Goal

把宪法里"只能靠人眼"的静态规则变成可执行检查，并给出 `file:line` 证据。

**规则清单不在本文件重复**（避免两处漂移）：唯一权威是 `.specify/godot-lint.json`，
值都是明文，直接读它。速记：`paths` / `events` / `ui_bypass` / `locale_sync` / `save_data_type`
是 **error**（违反宪法，必须修）；`scene_tree` / `locale_orphan` / `save_data_version` / `temp_files`
是 **warn**（存量或建议，不阻断）。

**注意这是"宽松档"**：只扫 `.gd` 文件，**不扫 `.tscn`/`.tres`**。`.tscn` 里的
`ext_resource path="res://..."` 与 `script="res://..."` 是引擎自己写死的，静态文本无法区分
"合规资源引用"与"散落硬编码"，硬扫只会产生满屏误报。所以场景层的路径违规由 `/speckit-godot-verify`
的引擎运行来兜底，而不是靠 grep。

## Pre-Execution Checks

**Extension hooks**: 若 `.specify/extensions.yml` 存在，按其中 `hooks.before_lint` 的条目处理
（`enabled: false` 的跳过；带非空 `condition` 的跳过并留给 HookExecutor）。
YAML 无法解析时**不要静默跳过**：明确告知用户读取失败（含解析错误），并说明未检查任何 hook。
无该文件或无 hook 时静默继续。

## Execution Steps

1. **确认工作目录是仓库根**。脚本用 `$PSScriptRoot` 推导仓库根，所以不依赖 cwd；
   但 `temp_files` 规则只扫仓库根，用 `git status` 或 `Get-ChildItem` 核对残留时请确保 cwd 正确。
   不确定时可以用只读命令确认：`git rev-parse --show-toplevel`（宪法原则 VII 允许只读查询）。

2. **跑 lint（机器可读）**：

   ```powershell
   .specify/scripts/powershell/godot-lint.ps1 -Json
   ```

   输出是一个 JSON 对象：`Config` / `BaselinePath` / `BaselineSize` / `ErrorCount` / `WarnCount` /
   `ExitCode` / `Findings[]`（每项含 `Rule` / `Severity` / `File` / `Line` / `Message` / `Snippet`）。
   退出码：有 error 级违规时为 1，否则 0。

3. **报告**。按 `Rule` 分组，逐条给出 `file:line` 与代码片段。必须区分两件事：

   - **error 级**：违反宪法硬规则，MUST 修。不要用"这是存量"当借口 —— 存量已登记在
     `.specify/godot-lint-baseline.json`，不在里面的 error 就是本次新增的。
   - **warn 级**：存量或建议。**不要**顺手"修好"它们：本仓库的 3 处长节点路径与 5 个 orphan key
     是 `AGENTS.md` 明确列为"已知未完成事项"的存量，属于本次范围外。只有当用户明确要求时才动。

4. **与基线对比**（可选）：`.specify/godot-lint-baseline.json` 记录了规则上线时的违规存量。
   如果本次 findings 比基线**多了**条目，在报告里单独列出"新增违规"。
   基线是**只提示**的：它不清零、不阻断，也不是"允许保留"的免罪符。

5. **判定新增规则是否要调**。若某条规则在本仓库产生了明显误报（例如把合规代码判成违规）：
   - 优先改 `.specify/godot-lint.json`（加 `allow`、收窄 `files`、把 `severity` 降为 `warn`），
     并在报告里说明理由；
   - 若改的是脚本本体 `.specify/scripts/powershell/godot-lint.ps1`，同样要说明理由 ——
     这两个文件都**不是** spec-kit 受管文件，改它们不会被 `specify integration status` 记为 modified。

6. **收尾**：确认本次运行没有留下任何临时文件（lint 本身只读，不写文件，`-UpdateBaseline` 除外）。
   若用了 `-UpdateBaseline`，必须明确告知用户库存量已被改写。

## 什么时候该跑

- `/speckit-plan` 之后：把 plan.md 的 Constitution Check 从"声称 PASS"变成"有证据"。
- `/speckit-tasks` 之后、`/speckit-implement` 之前：确认起点是干净的。
- `/speckit-implement` 每个任务组之后：尽早发现散落字面量。
- `/speckit-analyze`：把 findings 作为一条独立证据来源。
- 提交前：与 `/speckit-godot-verify` 一起作为提交门禁。

## Operating Constraints

- **不要修改 `addons/godot_core_system/`**：脚本文本扫描会跳过 `addons/` 与 `.godot/`，
  这是刻意的。发现框架层违规时报告但不改。
- **不要批量重写存量违规**：`warn` 是存量，改它们会污染本次改动的 diff。
- **报告要可复现**：给出的是命令 + 原始输出，不是"我检查过了"。
- 规则判定以 `.specify/godot-lint.json` 的**当前内容**为准；报告里引用规则时要复述其阈值，
  避免用户以为规则和报告不一致。
