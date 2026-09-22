---
name: "speckit-godot-verify"
description: "Verify a godot-template change in the real Godot engine: run headless smoke with baseline diff, instantiate the touched scene, run disposable probe scripts, and record command-plus-output evidence. Use instead of claiming 'it looks correct'."
compatibility: "Requires Godot 4.7.x (not on PATH by default), PowerShell 7, and the godot-template repo layout."
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

执行宪法原则 V（"改动必须经引擎运行验证"，NON-NEGOTIABLE）。本技能存在的唯一理由：
**Godot 对场景文件里的未知属性、部分类型错误保持静默**，所以"跑起来没报错""代码看起来对"
都不构成正确性证据。验证必须产生**命令 + 原始输出 + 判据结论**三元组。

## Pre-Execution Checks

**Extension hooks**: 若 `.specify/extensions.yml` 存在，按 `hooks.before_verify` 处理；
YAML 无法解析时**不要静默跳过**，告知用户解析失败并说明未检查任何 hook。无该文件时静默继续。

**先确认工具链可用**（不要假设 `godot` 在 PATH 上 —— 它**不在**）：

```powershell
# 脚本会自己按这个顺序找：-Godot > $env:GODOT > .specify/godot-lint.json 的 godot.executable
#   > C:\portable\Godot\<ver>\*_console.exe > PATH
.specify/scripts/powershell/verify-engine.ps1 -NoBaseline
```

找不到可执行文件时脚本会打印三种指定方式后以退出码 2 结束。把这句话原样转达给用户，
**不要**自己去装 Godot 或猜路径。

## Execution Steps

### 1. 先跑静态门禁

```powershell
.specify/scripts/powershell/godot-lint.ps1 -Json
```

有 error 级违规就先修，再进引擎验证 —— 静态能抓的错没必要花一次引擎运行。
（规则清单与"宽松档"边界见 `/speckit-godot-lint`。）

### 2. 主场景冒烟 + 基线 diff

```powershell
.specify/scripts/powershell/verify-engine.ps1
```

脚本做三件关键的事，**不要绕开它手工跑 `--quit-after`**：

1. 归一化引擎输出（剥 ANSI 转义、抹平时戳/泄漏计数/版本 hash）；
2. 与 `.specify/godot-verify-baseline.json` 逐行 diff，只把**新增**的 ERROR/WARNING 算作回归；
3. 退出码：有新增回归或任一 Godot 调用非 0 → 1。

**为什么不能写"退出码 0 且没有 ERROR"**：主场景基线本身稳定输出 5 行 ERROR/WARNING
（日志文件写不了、证书库读不到、ObjectDB 泄漏、资源残留），而 Godot 的**退出码仍然是 0**。
这条判据既不可执行也不可证伪，所以必须换成"与基线 diff"。

首次在某台机器上跑会报"基线不存在"：**人工确认输出正常后**再执行 `-UpdateBaseline` 登记。
基线是机器相关的（首次运行是否有 `options.sav` 会影响启动日志），换机器或存档状态大变后要重登。

### 3. 直接实例化被改动的场景

```powershell
.specify/scripts/powershell/verify-engine.ps1 -Scenario res://ui/<screen>/<screen>.tscn
```

这一步最容易抓到节点路径与属性名错误。`.tscn` 里不存在的属性会被**静默忽略**，
所以"没报错"不能证明属性名对 —— 怀疑时用 `--doctool` 导出 `doc/classes/*.xml` 核对。

### 4. 写一次性探针脚本做行为断言

```powershell
# 探针文件名按用户故事区分，避免多个故事互相覆盖
#   res://_probe_us1.gd   extends SceneTree
.specify/scripts/powershell/verify-engine.ps1 -Probe res://_probe_us1.gd
```

写探针的硬性要求：

- `extends SceneTree`；`SceneTree` 初始化阶段挂的节点此时还没 `_ready`，
  **涉及节点的断言必须等 ≥2 帧**再查。
- 断言要打**可判定的输出**（成功/失败各一行，带实际值），不要只 `print` 状态。
- **先写验证手段并观察到失败，再写实现**（红 → 绿）。先绿后补的验证证明不了什么。
- 新增或改名了 `class_name` 时，先跑一次 `--import` 让全局类缓存刷新：

  ```powershell
  & $godot --headless --path . --import
  ```

- 探针**必须删除**；交付前用 `git status`（只读查询，宪法原则 VII 允许）或 `godot-lint.ps1` 的
  `temp_files` 规则确认没有 `_*` 残留。

### 5. 写证据

把三元组落盘到 `specs/<NNN>-<feature>/verification.md`（不存在则创建），每条一行：

```markdown
| 判据 | 命令 | 原始输出要点 | 结论 |
|---|---|---|---|
| US1 打开设置界面后进入 ui_dict | `verify-engine.ps1 -Scenario res://ui/options/options.tscn` | 输出无新增 ERROR/WARNING | PASS |
| US1 关闭后条目被清除 | `verify-engine.ps1 -Probe res://_probe_us1.gd` | `ui_dict has 0 entries after CLOSE_UI` | PASS |
```

**禁止**把"已实现""已通过""看起来正确"写进结论栏。判据栏要能追到 spec.md 的 FR/SC 或
tasks.md 的任务 id。

### 6. 清理并复述残留风险

- 删除全部探针脚本与临时资源；
- `git status`（只读）确认只剩预期改动；MUST NOT 自行提交或暂存；
- 报告里明确写出**没有被验证覆盖到的东西**（例如"暂停菜单在无手柄环境下未测"），
  这比笼统的"验证通过"有用得多。

## 什么算验证完成

一份改动只有同时满足下列条件才算完成：

- [ ] `godot-lint.ps1` 无 error 级违规
- [ ] `verify-engine.ps1`（主场景冒烟）退出码 0，且无基线之外的新 ERROR/WARNING
- [ ] 改动的场景/脚本走过"被真实实例化"的路径（而不是只读了一遍代码）
- [ ] 每条 FR/SC 都有对应判据，且判据是引擎可观测的
- [ ] 一次性探针已删除，`git status`（只读）干净
- [ ] 已知基线噪声**没有**被当作本次回归（例如 10 ObjectDB leaked 是基线自带）

## Operating Constraints

- **不要改 `addons/godot_core_system/`** 来让验证通过。框架层是冻结的；确需修改要单独走规格与理由。
- **只读的 git 查询随便用**（`git status` / `diff` / `log` / `ls-files` 等），但**不许改变仓库状态**：
  `git add` / `commit` / `checkout` / `stash` / `clean` 等一律不许（宪法原则 VII，NON-NEGOTIABLE）。
  需要提交时在报告里写出建议的命令与原因，由人类执行。
- **不要用 `-UpdateNoise` 掩盖真实回归**。它的用途只是登记"已人工确认与本功能无关"的噪声行；
  登记前必须能解释那一行**为什么**与本功能无关。
- **不要为了让判据变绿而放宽规则**（改 lint 配置的 `severity`、删基线行、改断言）。这类调整
  要么有明确理由并写进报告，要么就是在作弊。
- 引擎在 headless 下退出时会有基线噪声；**不要把基线噪声当成新问题反复"修复"**，
  也不要因为看到 ERROR 字样就断定失败 —— 先看 diff。
