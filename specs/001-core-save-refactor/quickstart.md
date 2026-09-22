# Quickstart: core/ 与 save_data/ 审查重构的验证剧本

**Feature**: `001-core-save-refactor` | **Date**: 2026-09-23

本文件是**验证/运行指南**，不是实现说明。实现细节见 `plan.md` 与 `tasks.md`；
字段与校验规则见 `data-model.md`；格式与负载契约见 `contracts/`。

---

## 0. 前置条件

| 项 | 值 |
|---|---|
| 引擎 | Godot **4.7.2.stable**，路径 `C:\portable\Godot\4.7.2\Godot_v4.7.2-stable_win64_console.exe` |
| Shell | PowerShell 7（`pwsh`） |
| 工作目录 | 仓库根（本例为 `C:\repos\godot-template`） |
| 关键前提 | **`godot` 不在 PATH 上** —— 两个脚本会自己定位引擎，不要写裸 `godot` |

> **FR-001 已满足**：引擎输出基线已于 2026-09-23（改动前）采集并验证为"无新增 ERROR/WARNING"。
> 基线文件：`.specify/godot-verify-baseline.json`。若它被重新登记，本剧本的"无回归"判据失效，MUST 重采。

---

## 1. 每次改动后都跑这两条

```powershell
# 1) 静态门禁（宪法 I/II/III/IV 的可执行版本；宽松档只扫 .gd）
.specify/scripts/powershell/godot-lint.ps1

# 2) 引擎验证：主场景冒烟 + 与已登记基线逐行 diff（含回归验证）
.specify/scripts/powershell/verify-engine.ps1
```

**通过标准**：

- `godot-lint`：`error=0`。`warn` 数量 MUST NOT 高于改动前（改动前基线为 3 条 `scene_tree`）。
- `verify-engine`：退出码 **0**，且报告"**无新增 ERROR/WARNING**"。

**常见误读**：主场景基线本身稳定输出 5 行 ERROR/WARNING（日志文件写不了 ×2、证书库读不到、
ObjectDB 泄漏、资源残留），**而退出码仍是 0**。因此判据 MUST NOT 写成"退出码 0 且没有 ERROR"，
MUST 写成"相对基线无新增行"。看到 ERROR 字样不等于失败，先看 diff。

---

## 2. 涉及场景与探针的验证

```powershell
# 本次新增 class_name（MetaSave）→ 首次运行前 MUST 先重建全局类缓存
& "C:\portable\Godot\4.7.2\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --import

# 目标场景直接实例化（本次范围为 core/ 与 save_data/，通常不需要；保留以备回归）
.specify/scripts/powershell/verify-engine.ps1 -Scenario res://ui/options/options.tscn

# 按用户故事编号的探针（实现阶段编写，交付前删除）
.specify/scripts/powershell/verify-engine.ps1 -Probe res://_probe_us1.gd
.specify/scripts/powershell/verify-engine.ps1 -Probe res://_probe_us2.gd
.specify/scripts/powershell/verify-engine.ps1 -Probe res://_probe_us3.gd
```

探针约定：`extends SceneTree`；**涉及节点的断言必须等 ≥2 帧**（初始化阶段挂的节点此时还没 `_ready`）；
断言要打**可判定的输出**（成功/失败各一行，带实际值）。

---

## 3. 验证场景清单（expected outcomes）

每条都要给出"命令 + 原始输出要点 + 结论"，写入 `specs/001-core-save-refactor/verification.md`。

| ID | 覆盖 | 探针 | 期望观察 | 对应 |
|---|---|---|---|---|
| SCR-1 | 界面开关记账 | `_probe_us1.gd` | `OPEN_UI` 后 `ui_dict` 含该路径且节点在树内；`CLOSE_UI` 后条目被清除、节点被释放 | SC-002 |
| SCR-2 | 存档往返 | `_probe_us1.gd` | 写入后文件首 4 字节 == `GTSV`；重新载入后逐字段值与写入前一致；落盘根键为 `version` / `meta`（+ `options`）且 `version == 2` | SC-003 |
| SCR-3 | 设置首启播种 | `_probe_us1.gd` | 无 `options.sav` 时，内存中的设置值 == 当前引擎状态（`TranslationServer.get_locale()` / 窗口尺寸） | SC-002 |
| SCR-4 | 列表与 payload | `_probe_us1.gd` | 列表不含 `options` 槽位；`SAVE_LIST_READY` 回调收到的是**数组本身**，`typeof == TYPE_ARRAY` 且 `received[0]` 不是 `Array` | SC-002 / SC-006 |
| SCR-5 | 负载契约 | `_probe_us2.gd` | 非数组负载 → 收到该对象本身；数组负载 → 收到该数组本身；多元素数组 → 按位置收到各元素。**0 例嵌套数组** | SC-006 |
| SCR-6 | 补丁类型校验 | `_probe_us3.gd` | 类型错误的补丁：目标字段**保持原值**且有告警；随后用正确类型补丁：写入成功 | FR-004 |
| SCR-7a | 旧档拒绝（本次变更） | `_probe_us3.gd` | 构造 v1 旧档（`version == 1`、平铺元数据）→ `ok == false` 且 `error` 可区分（结构版本过旧 / 不提供迁移）；**无半读入** | SC-004 / FR-006 |
| SCR-7b | 高版本拒绝（既有保护） | `_probe_us3.gd` | 构造 `version` 高于当前的存档 → `ok == false` 且 `error` 可区分；**无半读入** | SC-004 / FR-006 |
| SCR-8 | 槽位安全 | `_probe_us3.gd` | 含 `..` / `/` / `\` / 以 `.` 开头的槽位一律被拒；存档目录外无任何文件被创建或读取 | FR-007 |
| SCR-9 | 写入原子性 | `_probe_us3.gd` | 成功写入后目录中**无 `.tmp` 残留**；正式文件完整可读 | FR-007 |
| SCR-10 | 未知 UI 层级 | `_probe_us1.gd` | `ui_layer` 传未知值时：告警 + 实例仍被挂入 MIDDLE（**不出现"已实例化但不入树"**） | FR-002 |

**断言集规模**：10 条 ≥ spec 的 `SC-002` 要求的 8 条。

---

## 4. 判定与故障处理

| 现象 | 含义 | 处理 |
|---|---|---|
| `verify-engine` 报"新增 N 行" | 很可能是本次改动引入的回归 | 看 `+` 开头的行；与本功能无关且确认是噪声时才用 `-UpdateNoise` 登记 |
| `godot-lint` 出现 error | 违反宪法硬规则 | 必须修；不要用改 `severity` 的方式绕过 |
| 探针断言失败但 lint/冒烟通过 | 行为确实变了，或被改动的路径没被实例化 | 先确认探针本身写对了（≥2 帧、断言可判定），再判定为回归 |
| 出现 `SCRIPT ERROR: Parse Error` | GDScript 语法/缩进错误（本仓库用 **tab** 缩进） | 修；注意 `.gd` 里混用空格会直接 Parse Error |
| 新增了 `class_name` 后报找不到类 | 全局类缓存过期 | 先跑一次 `--import`：`& "C:\portable\Godot\4.7.2\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --import` |

> 本计划**刻意不新增 `class_name`**，因此预期不需要 `--import`。若实现阶段新增了，MUST 先 `--import`。

---

## 5. 收尾

```powershell
# 删除全部一次性探针（本仓库约定：仓库根 _*.gd 不得残留）
Remove-Item res://_probe_us1.gd, res://_probe_us2.gd, res://_probe_us3.gd -ErrorAction SilentlyContinue
# 实际路径为仓库根下的 _probe_us<N>.gd

# 用只读查询确认残留（宪法原则 VII 允许只读）
git status

# 静态门禁也会扫仓库根的 _*.gd 并告警（temp_files 规则）
.specify/scripts/powershell/godot-lint.ps1
```

**MUST NOT 自行 `git add` / `git commit`。** 需要提交时，在报告里给出建议的命令与原因，由人类执行。

---

## 6. 完成标准汇总

- [ ] `godot-lint.ps1`：`error=0`，`warn` 不高于 3
- [ ] `verify-engine.ps1`：退出码 0 且无新增 ERROR/WARNING
- [ ] SCR-1 ~ SCR-10（含 SCR-7a / SCR-7b）逐条有"命令 + 输出要点 + 结论"记录
- [ ] 探针脚本已删除，`git status`（只读）确认无 `_*` 残留
- [ ] `AGENTS.md` 硬规则 4 已修正（不再是"数组要再包一层"）
- [ ] 宪法原则 III 的修订已记录（**MINOR：1.3.1 → 1.4.0** —— 原要求保留 + 一次性例外，理由可追溯）
- [ ] `verification.md` 已落盘
