# Verification 证据台账

**Feature**: `001-core-save-refactor` | **Started**: 2026-09-23

> 按宪法原则 V，本文件只收录「命令 + 原始输出要点 + 判据结论」三元组。
> SCR-1 ~ SCR-10 的引擎证据由 T006 / T009 / T015 / T021 / T024 / T028 逐步追加；
> 本条（T007）是治理动作，不涉及 `.gd`，因此不需要引擎运行。

---

## T007 — 宪法原则 III 修订（治理动作，无引擎改动）

**判据**：「存档结构变更 MUST 提升结构版本号并提供迁移路径」这条 NON-NEGOTIABLE 要求 **MUST 保留**，
只允许追加**一次性**例外；版本号 MUST 按 Governance 调整；文档中 MUST NOT 再残留"MAJOR 级 / 永久放宽"的旧描述。

**用户裁定（本次对话原文）**：「T007 允许不兼容只允许这一次，宪法还是要在」

**命令 1**：`.specify/scripts/powershell/resolve-template.ps1 constitution-template -Json`

- 输出要点：解析成功，返回 core 版 `constitution-template`（该项目未对 constitution 模板做 override，
  故无项目层覆盖）；模板占位符形如 `[CONSTITUTION_VERSION]`、`[LAST_AMENDED_DATE]`。
- 结论：实际文档使用已填值的项目版本，修订后未引入任何未解释的占位符。

**命令 2**：`Select-String -Path .specify/memory/constitution.md -Pattern 'MUST 提升结构版本号'`

- 输出要点：命中 `:48`（原则 III 正文，原要求**原样保留**）；
  其余命中位于原则 III 的例外段落与（当时仍在的）头部 Sync Impact Report 中，属说明文字
  —— 该临时块已在收尾时删除，见 T034 节。
- 结论：原要求未被删除或改写 → 与"宪法还是要在"一致。

**命令 3**：`Select-String -Path .specify/memory/constitution.md -Pattern '^\*\*Version'`

- 输出要点：`**Version**: 1.4.0 | **Ratified**: 2026-09-23 | **Last Amended**: 2026-09-23`
- 结论：版本号已按 Governance 调整，级别 **MINOR**（1.3.1 → 1.4.0）。
  理由：未移除、未重定义任何原则，只新增**限定范围、一次性、可收回**的例外条款；
  原计划的 MAJOR 2.0.0 以"移除既有硬要求"为前提，该前提已由用户裁定撤销。

**命令 4**：`.specify/scripts/powershell/restore-managed-files.ps1`

- 输出要点：`受管文件无漂移（Modified/Missing 均为 0）。`
- 结论：本次只改项目自有文件（`.specify/memory/constitution.md` 不在 spec-kit manifest 内），
  未触碰任何受管文件。

**命令 5**：`git status --short`（只读查询，宪法原则 VII 允许）

- 输出要点：` M .gitignore`、`?? .dsh/`、`?? .specify/`、`?? AGENTS.md`、`?? specs/`、
  `?? _probe_us2.gd`（+`.uid`）。其中 `.gitignore` 的改动与 `_probe_us2.gd` 均为本功能此前步骤产生；
  本次新增变更文件为 `.specify/memory/constitution.md` 与 `specs/001-core-save-refactor/*`（游离于未跟踪目录内）。
- 结论：本次未产生新的临时文件；`_probe_us2.gd` 是 T004 的探针，按 T030 在交付前删除。

**例外使用情况**：本次**被使用**（用户裁定：`spec.md` `PR-002` 的契约是"结构变更 = 是"）——
变更内容为元数据独立成段 `meta`（`MetaSave`）并把 `SaveData.version` 由 1 提升到 2，
旧档策略为**显式拒绝**（见 `research.md` R4 与 `contracts/save-file-format.md` §5）。
该一次性例外**用尽**：此后任何存档结构变更 MUST 回到"提升版本 **并提供迁移路径**"的完整要求。
代码侧的落地与引擎证据见 T037 ~ T040（本文件后续章节补充）。

**已知影响（待 T040 用引擎证据确认）**：本机既有 `user://saves/options.sav` 是 v1 存档
（248 字节，2026-09-17 生成）。结构提升到 v2 后它会被显式拒绝，启动时按当前引擎状态重新播种设置，
因此主场景冒烟可能新增与"版本过旧 / 重新播种"相关的日志行。若出现，MUST 在 T040 的命令与结论中说明，
并由人类确认后用 `verify-engine.ps1 -UpdateBaseline` 重登基线（宪法原则 V）。

**附带的配置改动**：`.specify/godot-lint.json` 的 `save_data._comment` 已同步新策略
（改结构时 MUST 提升版本并声明策略：写迁移，或按已在本次用尽的一次性例外显式拒绝）。
该文件是**项目自有**非受管文件，改动不影响受管文件漂移检查（命令 4 已确认无漂移）。

**修订记录的去处（为什么可以删掉头部临时块）**：本次修订的可追溯记录在本文件 T007 节、
`tasks.md` 的 T007 块与 `AGENTS.md`「存档系统契约」条目里各存一份 —— 这正是原则 III 例外条款
自己要求记录的位置（"其授予与使用情况 MUST 记录在对应功能的 `specs/<NNN>-<feature>/` 与
`AGENTS.md` 的存档契约条目中"）。因此头部的 `Sync Impact Report` 临时块已按流程删除（见 T034 节）。

---

## T001 — 引擎输出基线在改动前无回归

**命令**：`.specify/scripts/powershell/verify-engine.ps1`

- 输出要点：
  ```
  Godot: C:\portable\Godot\4.7.2\Godot_v4.7.2-stable_win64_console.exe
  version: 4.7.2.stable.official.ed1daf0bf
  [WARN] 主场景冒烟（--quit-after 5）  exit=0  ERROR/WARNING 行=5
  无新增 ERROR/WARNING（基线 5 行）。
  基线路径: .specify/godot-verify-baseline.json（2026-09-23T00:56:08）
  验证通过：退出码 0，且没有基线之外的新 ERROR/WARNING。
  ```
- 结论：PASS —— 基线时间戳早于本功能任何代码改动，且当前无回归。

## T002 — 改动前 lint 起点

**命令**：`.specify/scripts/powershell/godot-lint.ps1`

- 输出要点：`error=0  warn=4  存量基线=0 条`。4 条 warn = 3 条 `scene_tree` 存量
  （`ui/main_menu/main_menu.gd:6`、`ui/options/options.gd:6`、`:7`）+ 1 条 `temp_files`
  （`_probe_us2.gd`，T004 的探针，按 T030 交付前删除）。
- 结论：`error=0`。**对照基准取"删除探针后 warn=3"**：实现期间探针在场会多一条 `temp_files` warn，
  它不计入 T032 的"不高于 3"判据。

## 环境限制（影响验证方式，必须记录）

本会话的文件沙箱是 `workspace-write`：**`user://` 目录的写入落在工作区之外，被拒绝**。
实测（一次性诊断脚本，已删除）：

```
DIAG make_dir_recursive_absolute("user://_probe_saves") -> 0     # 声称成功
DIAG dir_exists -> false                                          # 目录并不存在
DIAG open(tmp) -> <null> err=7                                    # ERR_FILE_CANT_OPEN
```

对照 `res://_probe_saves`：`make_dir_recursive_absolute -> 0`、`dir_exists -> true`、写入成功。

因此：所有探针把存档目录临时改到 `res://_probe_saves`（`ProjectSettings` 的
`godot_core_system/save_system/save_directory`，`SaveService._ready()` 读它），
并在退出前删除该目录。这也解释了基线里那两行 `Failed to open 'user://logs/...'` 噪声的成因。
AGENTS.md「存档系统契约」一节本就写明"测试时可临时改到 `res://` 下"，与本次做法一致。

## T003 / T004 / T005 — 三个探针（改动前编写）

| 探针 | 覆盖 | 说明 |
|---|---|---|
| `res://_probe_us1.gd` | SCR-1 / SCR-2a / SCR-2b / SCR-3 / SCR-4 / SCR-10 | 界面记账、存档往返、首启播种、列表与 payload、未知 ui_layer |
| `res://_probe_us2.gd` | SCR-5 | 事件 payload 四种形态（T004 已存在，本次复跑） |
| `res://_probe_us3.gd` | SCR-6a~e / SCR-7a / SCR-7b / SCR-8 / SCR-9 | 补丁类型校验、槽位安全、原子性、版本拒绝 |

三个探针共同约定：`extends SceneTree`；节点相关断言等 ≥2 帧；每条断言打 PASS/FAIL 一行带实际值；
`--script` 模式下 autoload 标识符 `CoreSystem` 在编译期不可用，一律经
`root.get_node_or_null("/root/CoreSystem")` 取（这也是 `_probe_us2.gd` 的既有写法）。

## T006 — 改动前的原始输出（重构后逐条对照的对照物）

**命令**：`& $godot --headless --path . --script res://_probe_us<N>.gd`（引擎路径见 AGENTS.md）

### `_probe_us1.gd`（改动前：PASS=12 FAIL=1）

```
[PASS] SCR-1 打开：ui_dict 含 res://ui/main_menu/main_menu.tscn 且实例在树内
[PASS] SCR-1 关闭：CLOSE_UI 后 ui_dict 已清除该路径（剩余 0 项）
[PASS] SCR-10 未知 ui_layer=999 → 实例入树且挂在 Middle 下（按 MIDDLE 处理）
[PASS] SCR-2a 文件头 4 字节 == GTSV（实际 'GTSV'）
[FAIL] SCR-2b v2 结构未生效：version=1 根键=["version","slot","saved_at","game_version","playtime"]
[PASS] SCR-2a 往返一致：playtime 写 123.5 → 读 123.5
[PASS] SCR-2a 往返一致：slot == 'probe_slot'
[PASS] SCR-3 首启播种：language == 引擎 locale（zh_CN）
[PASS] SCR-3 首启播种：resolution == (1152, 648)（引擎窗口 (0, 0)）
[PASS] SCR-4 回调收到数组本身（typeof=ARRAY，长度 1）
[PASS] SCR-4 存档列表排除设置档：slots=["probe_slot"]
[PASS] SCR-4 存档列表含游戏档 'probe_slot'
[PASS] SCR-4 payload[0] 不是嵌套数组（typeof=27）
--- 结果：PASS=12 FAIL=1 ---
```

- SCR-2b 的 FAIL 是**预期**的：v2 结构（元数据独立成段）是本次要做的变更，此刻尚未实施。
  它是"结构确实还没改"的可判定证据，也是 US4（T037~T040）完成后的对照点。
- SCR-3 的 `resolution` 断言按代码语义推导：headless 下引擎窗口为 `(0, 0)`，
  于是播种值应是 `OptionsSave.DEFAULT_RESOLUTION`（1152×648）——实测一致。

### `_probe_us2.gd`（改动前：PASS=4 FAIL=0）

```
[PASS] 非数组负载 → 1 个参数，typeof=Dictionary（对象本身）
[PASS] 单元素数组 ['x'] → 1 个参数，值为 'x'（数组已作为参数表，未嵌套）
[PASS] 多元素数组 ['a',7,true] → 展开为 3 个位置参数
[PASS] 空数组 [] → 0 个参数
--- 结果：PASS=4 FAIL=0 ---
```

- 结论（对应 research.md R1）：payload 契约**代码侧本来就正确**，缺陷只在文档描述。
  US2 因此不打补丁给代码，只修 `AGENTS.md` 硬规则 4（T008 已完成）并补 `core/events.gd` 注释（T012）。

### `_probe_us3.gd`（改动前：PASS=10 FAIL=6）

```
[PASS] SCR-8 非法槽位全部被拒（14/14 个请求，含空槽位读档）
[PASS] SCR-8 非法槽位未产生任何文件（存档目录为空）
[PASS] SCR-8 无路径穿越产物（res://evil.sav 等均不存在）
[FAIL] SCR-6a 不兼容字段被改写：playtime=0.0 typeof=3（期望 5.0）
[FAIL] SCR-6b 不兼容字段被改写：version=0 typeof=2（期望 1）
[PASS] SCR-6c 不兼容字段保持原值：resolution 仍是 Vector2i (1152, 648)
[PASS] SCR-6d 同批次合法字段仍生效：language == 'zh_CN'
[PASS] SCR-6e 无损互通被接受：playtime（int 7）→ 7.0
[PASS] SCR-9 写入后无 .tmp 残留（目录内容 ["probe_type.sav"]）
[PASS] SCR-9 正式存档文件存在：res://_probe_saves/probe_type.sav
[FAIL] SCR-7a-1 v1 旧档被接受（应当显式拒绝）：ok=true，slot='legacy_v1' playtime=777.0
[FAIL] SCR-7a-2 失败原因不可区分：''（笼统值为 '存档不存在 / 版本不兼容 / 读取失败'）
[FAIL] SCR-7a-3 出现半读入：playtime=777.0（哨兵 42.0）slot='legacy_v1'（哨兵 'before_legacy_load'）
[PASS] SCR-7b-1 高版本存档被拒绝（既有保护保持）：error='存档不存在 / 版本不兼容 / 读取失败'
[FAIL] SCR-7b-2 失败原因不可区分：'存档不存在 / 版本不兼容 / 读取失败'
[PASS] SCR-7b-3 无半读入：playtime 仍 42.0，slot 仍 'before_newer_load'
--- 结果：PASS=10 FAIL=6 ---
```

**改动前 FAIL 的 6 条，正是本次要修的三处缺陷**：

1. **SCR-6a / SCR-6b（apply_dict 无类型校验）**：坏类型补丁不是"被忽略"，而是**被静默改写**。
   一次性诊断脚本（已删除）的原始输出：
   ```
   DIAG playtime    typed=float     -> typeof=3 value=0.0     # 起点 5.0，"abc" → 0.0（丢数据）
   DIAG version     typed=int       -> typeof=2 value=0       # 起点 1，"x" → 0
   DIAG resolution  typed=Vector2i  -> typeof=6 value=(1152, 648)   # String → 静默忽略
   DIAG slot        typed=String    -> typeof=4 value=keep    # int → 静默忽略
   DIAG language    typed=String    -> typeof=4 value=en      # int → 静默忽略
   ```
   即：GDScript 的 `set()` 对"可转换"的坏类型**静默转换**（float←String → 0.0、int←String → 0），
   对"不可转换"的坏类型**静默忽略**；两种情况下都**没有任何告警**。
   这修正了 research.md R2 的初始描述（它以为是一律 `set()` 任意类型），缺陷本身成立且更隐蔽：
   **不兼容补丁会导致静默丢数据，且失败不可观测**（违反 FR-004 的"可观测告警"）。
2. **SCR-7a-1/2/3（版本策略）**：当前 `SaveData.version == 1`，于是 v1 文件被当成"同版本"直接读入 ——
   没有拒绝、没有可区分原因、并且**发生了半读入**（`playtime` 被覆盖成 777.0、`slot` 被改成 `legacy_v1`）。
3. **SCR-7b-2（失败原因不可区分）**：高版本存档确实被拒（既有保护成立），
   但 `error` 是笼统的 `存档不存在 / 版本不兼容 / 读取失败`，调用方无法区分"文件不存在"与"版本不兼容"。

**既有保护（改动前即通过，重构 MUST 保持）**：SCR-6c/6d/6e、SCR-8（3 条）、SCR-9（2 条）、SCR-7b-1/3。

---

## T009 / T010 — US1 复跑并与改动前逐条对照

**命令**：`& $godot --headless --path . --script res://_probe_us1.gd`

- 输出要点：改动前 `PASS=12 FAIL=1` → 全部工作完成后 `PASS=13 FAIL=0`。
- 逐条对照：改动前那 12 条 PASS **逐条一致**（SCR-1 打开/关闭、SCR-2a 文件头 + 往返、SCR-3 首启播种 ×2、
  SCR-4 ×4、SCR-10）；唯一差异是 **SCR-2b 由 FAIL 转 PASS** —— 那正是本次 US4 的交付内容
  （落盘根键 `["version","meta"]`、`version == 2`）。
- 结论：PASS。SCR-1 / SCR-2a / SCR-3 / SCR-4 / SCR-10 描述的都是**既有正确行为**，
  在未做任何实现改动时即成立，属防回归护栏（T010）。

## T011 — SCR-5 事件负载契约

**命令**：`& $godot --headless --path . --script res://_probe_us2.gd`

- 输出要点：`PASS=4 FAIL=0`，与改动前完全一致（非数组 → 1 个参数；`['x']` → 收到 `'x'` 本身；
  多元素数组 → 3 个位置参数；`[]` → 0 个参数）。**0 例嵌套数组**。
- 结论：PASS —— 与 research.md R1 一致：契约**代码侧本来就正确**，缺陷只在文档。

## T012 — `core/events.gd` 只补注释

- 改动内容：新增 payload 语义说明（四种形态 + "想传数组就直接传该数组" + 指向
  `contracts/event-payload-contract.md` 与探针），**未触碰任何 `const *_REQUEST/_FINISHED/_READY` 的值**。
- 证据：`git diff --stat` 显示 `core/events.gd | 13 +`（纯新增行，0 删除）；
  `godot-lint.ps1` 的 `events` 规则（error 级）通过；`_probe_us2.gd` 复跑仍 PASS=4。
- 结论：PASS。

## T013 — `push_event` 调用点核查

| 位置 | 写法 | 订阅者签名 | 判定 |
|---|---|---|---|
| `core/save_service.gd` `_emit()` | `push_event(event_name, result)` | `_on_*` 收单个 `Types.SaveResult` | 正确（非数组 → 单元素参数表） |
| `core/save_service.gd` `_do_save_list()` | `push_event(SAVE_LIST_READY, [saves])` | 探针 `_on_save_list_ready(saves: Array)` 收到**数组本身** | 正确（SCR-4 实测） |
| `core/ui_root.gd` | `subscribe_unique_script(OPEN_UI/CLOSE_UI, ...)` | `_open_ui(request)` / `_close_ui(path)` | 正确（SCR-1 实测） |
| `ui/options/options.gd:28` | `push_event(CLOSE_UI, Paths.UI_OPTIONS)` | `_close_ui(ui_path: String)` | 正确（String 非数组） |
| `ui/options/options.gd:42` | `push_event(SAVE_REQUEST, request)` | `_on_save_request(request)` | 正确 |
| `entry/main.gd:7`、`ui/main_menu/main_menu.gd:17` | `push_event(OPEN_UI, request)` | `_open_ui(request)` | 正确 |

- 结论：PASS —— 六处调用点全部与契约一致，**无需改代码**（与 research.md R1 的预期一致）。

## T014 / T015 / T016 / T021 — SCR-6：类型校验缺陷由失败转通过

**改动前（T015 记录，见上文 T006 节）**：`SCR-6a FAIL`（`playtime` 被 `"abc"` 静默写成 `0.0`）、
`SCR-6b FAIL`（`version` 被 `"x"` 静默写成 `0`）。

**T016 的改动**：`save_data/save_section.gd` 的 `apply_dict()` 增加逐字段类型兼容检查
（新增私有函数 `_is_patch_type_compatible()`），规则逐条对应 data-model.md §2.2：
同型接受、`int` ↔ `float` 互通接受、其余不兼容 → **拒绝该字段 + `push_warning` + 保持原值**。

**改动后**（同一探针原始输出）：

```
  [PASS] SCR-6a 不兼容字段保持原值：playtime 仍 5.0（未被 'abc' 写成 0.0）
  [PASS] SCR-6b 不兼容字段保持原值：version 仍 2（未被 'x' 写成 0）
  [PASS] SCR-6c 不兼容字段保持原值：resolution 仍是 Vector2i (1152, 648)
  [PASS] SCR-6d 同批次合法字段仍生效：language == 'zh_CN'
  [PASS] SCR-6e 无损互通被接受：playtime（int 7）→ 7.0
```

可观测告警（同一份输出的 WARNING 行，即 FR-004 要求的"可观测"）：

```
WARNING: [save_data.gd] 字段 'playtime' 类型不符：期望 float，补丁给的是 String，已拒绝该字段（保持原值 5.0）
WARNING: [save_data.gd] 字段 'version' 类型不符：期望 int，补丁给的是 String，已拒绝该字段（保持原值 1）
WARNING: [options_save.gd] 字段 'resolution' 类型不符：期望 Vector2i，补丁给的是 String，已拒绝该字段（保持原值 (1152, 648)）
```

- 结论：PASS —— SCR-6 五条全绿，且不变量成立（拒绝不清空原值、空补丁不改变字段、坏字段不阻断同批次合法字段）。

## T017 / T018 / T019 / T020 / T022 / T023 — 职责拆分（US3 主体）

**新增/改动**：

| 文件 | 行数 | 内容 |
|---|---|---|
| `core/save_storage.gd`（新） | 136 | **纯文件 IO**：`is_valid_slot` / `path_for` / `list_slots` / `make_slot` / `write`（原子写）/ `read`（魔数 / 长度 / 上限 / 解码）。全部 `static`，`save_dir` 由参数传入，**不持状态、不订阅事件、不持有 `SaveData`、无 `class_name`** |
| `core/options_applier.gd`（新） | 26 | **纯引擎状态应用**：语言 / 分辨率 / 全屏。`static`，不持状态、不订阅事件、不读存档、无 `class_name` |
| `core/save_service.gd`（改） | 463 → 361 | 只留"什么时候做"：事件订阅/退订、请求校验、任务队列（上限 16）、`save_data` 所有权、`_stamp`、`_payload_for`、`_prepare_load`、`_make_result`/`_emit`、设置档启动流程 |
| `core/paths.gd`（改） | +2 常量 | `SCRIPT_SAVE_STORAGE` / `SCRIPT_OPTIONS_APPLIER` —— 供 `preload` 引用（理由见 T035） |

**T020**：`_do_save()` 在 `apply_dict()` 之后、落盘之前调用一次 `save_data.validate_tree()`（research.md R2 的 B+C 组合）。
注释与 AGENTS.md 都写明了两者的语义分工：类型不兼容属"调用方写错"→ 告警 + 保持原值；
值不合理属"值不行"→ 由各分段 `validate()` 修正。**两者未合并成同一机制**。

**T022 命令与结果**：

- `.specify/scripts/powershell/verify-engine.ps1` → 主场景冒烟 `exit=0`、`无新增 ERROR/WARNING`（拆分后、v2 之前）。
- `.specify/scripts/powershell/verify-engine.ps1 -Scenario res://ui/options/options.tscn` → 两个步骤均 `exit=0`，
  各自 5 行已知噪声，`无新增 ERROR/WARNING`。
- 复跑两个探针：`_probe_us1.gd` `PASS=12 FAIL=1`（与改动前逐条一致）、
  `_probe_us3.gd` `PASS=12 FAIL=4`（与改动前相比只有 SCR-6a/6b 按 T016 的预期转 PASS）。
- 结论：PASS —— 拆分是**纯结构调整**，对外可观测行为未变。

**T023 依赖方向（人工审阅）**：`save_service` → `save_storage` / `options_applier` **单向**。
两个新模块内部**没有** `subscribe`、没有 `var` 状态字段、不认识 `Types`/`Events`，
`save_dir` 与 `OptionsSave` 都经参数传入。MUST NOT 反向依赖成立。

## T024 / T037–T040 — US4：`meta` 分段 + `version` 1 → 2 + 显式拒绝

**代码**：

- T037 `save_data/meta_save.gd`（新，24 行）：`class_name MetaSave extends SaveSection`，
  承载 `slot` / `saved_at` / `game_version` / `playtime` —— **既有字段搬家，未新增字段**。
- T038 `save_data/save_data.gd`（61 行）：`version` **1 → 2**；根上只留 `version` + `meta` + `options`；
  `metadata()` **仍返回原来那 5 个平铺键**（值取自 `meta`，FR-002）；`migrate()` **改为显式拒绝**（`return {}`）并说明理由。
- T039 `core/save_service.gd`：`_stamp()` / 写入失败回滚改到 `save_data.meta.*`；
  `_payload_for()` 统一用 `to_dict()`（设置档也是 v2 形状）；`_prepare_load()` 增加 `_load_reject_reason`，
  `_do_load()` 用**可区分**的原因填 `result.error`（FR-006）。

**命令 1**：`& $godot --headless --path . --import`（新增 `class_name MetaSave`，必须先重建全局类缓存）

- 输出要点：`update_scripts_classes ... [50%] MetaSave ... [DONE]`。
- 说明：该命令另有两条与本改动无关的 ERROR（`Unrecognized UID: uid://cc28skn5h7aup` 与
  `Cannot save file ...editor_settings-4.7.tres`——后者是 user:// 写入受沙箱限制，见上文"环境限制"）。

**命令 2/3**：两个探针（`--script`，v2 之后）

```
--- 结果：PASS=13 FAIL=0 ---   # _probe_us1.gd（SCR-2b 转 PASS）
--- 结果：PASS=16 FAIL=0 ---   # _probe_us3.gd
```

**SCR-7a / SCR-7b 原始输出**：

```
[PASS] SCR-7a-1 v1 旧档被拒绝：ok=false，error='存档结构版本 1 过旧，本版本不提供迁移（当前结构版本 2）'
[PASS] SCR-7a-2 失败原因可区分（非笼统）：'存档结构版本 1 过旧，本版本不提供迁移（当前结构版本 2）'
[PASS] SCR-7a-3 无半读入：playtime 仍 42.0，slot 仍 'before_legacy_load'
[PASS] SCR-7b-1 高版本存档被拒绝（既有保护保持）：error='存档结构版本 3 比当前程序 2 新，请用新版程序打开'
[PASS] SCR-7b-2 失败原因可区分（非笼统）：'存档结构版本 3 比当前程序 2 新，请用新版程序打开'
[PASS] SCR-7b-3 无半读入：playtime 仍 42.0，slot 仍 'before_newer_load'
```

- 结论：PASS —— v1 旧档被**显式拒绝**、原因**可区分**、**无半读入**；高版本存档的既有保护保持不变。

**本次刻意新增的行为（记录在案，避免被当成"顺手加的"）**：设置档**载入失败**时（版本过旧 / 损坏），
启动流程改为**按当前引擎状态播种**（原先只在"文件不存在"时播种），并打一条 WARNING。
理由：spec 的 Edge Case 要求"设置档存在但内容损坏 → 回落到默认值并告警，
MUST NOT 让界面显示与生效值不一致"；而 v2 起"v1 设置档被拒"成为常态，
若沿用旧逻辑就会出现"内存里是 `en` / 引擎实际是 `zh_CN`"的不一致。

**补丁路径变化（结构变更的必然结果）**：带元数据的补丁从 `{"playtime": 5}` 变为 `{"meta": {"playtime": 5}}`；
内存路径从 `save_data.slot` 变为 `save_data.meta.slot`。已写入 `AGENTS.md` 与契约 §2.1。

## T025 — 契约与最终代码一致

`contracts/save-file-format.md`：Version 2；§1 字节层不变 / 字典结构变更；§2.1 v2 结构表（含补丁路径行）；
§4 拒绝条件含"版本 < 程序（显式拒绝）"与"版本 > 程序"；§5.1 实际状态表（`version` = 2、`migrate()` = 显式拒绝、
对外 `metadata()` 键不变、设置档影响）；§5.2 例外**已被使用、已用尽**；§7 判据含 SCR-2（v2 结构）与 SCR-7a/7b。

## T026 — `AGENTS.md` 同步（PR-005）

- 「存档系统契约」：结构（`meta` 段）、纯文件 IO / 设置应用模块位置、**结构版本与兼容策略**
  （当前 2；改结构 MUST 声明"写迁移 / 显式拒绝"；MUST NOT 悄悄改；MUST NOT 半读入）、
  本次不兼容变更的完整记录（含补丁路径与内存路径变化、"例外已用尽"）、
  补丁类型校验（含"别指望 `set()` 兜底"的实测原因）、设置档回退。
- 「基线噪声」：新增"存档结构版本变更后的基线扰动"说明（成因 + 处理方式）。
- 「目录速查」：`core/` 补 `save_storage.gd` / `options_applier.gd`；`save_data/` 补 `meta_save.gd`。
- 「规格驱动开发」：宪法版本 1.3.1 → **1.4.0**，并注明原则 III 的一次性例外已被本功能用尽。
- 「已知未完成事项」：逐条复核，**无一条因本次改动而失效或需要更新**（main_menu 空按钮、5 个 orphan key、
  设置界面范围、游戏流程层、`project.godot` 缺项、存量 lint 基线均未被本次触碰）。

## T027 — `save_data.gd` 的 `version` / `migrate()` 复核

- `version` 的注释写明：版本历史（1 → 2 改了什么）、为什么是**不兼容**变更、
  变的是落盘形状与内存路径而**不是** `metadata()` 的对外键、以及"例外已在本次用尽"。
- `migrate()` 的注释写明：为什么本次选**显式拒绝**（三条理由）、以及**以后 MUST 写迁移**。
- 结论：与最终策略一致。本任务**有实际改动**（不是"已复核、不改"）。

## T028 — 判据汇总

| 判据 | 结论 | 证据位置 |
|---|---|---|
| SCR-1 界面开关记账 | PASS | T009 节 |
| SCR-2a 往返 + `GTSV` | PASS | T006 / T009 节 |
| SCR-2b v2 结构生效 | PASS（改动前 FAIL，属预期） | T009 / T024 节 |
| SCR-3 首启播种 = 引擎状态 | PASS | T006 / T009 节 |
| SCR-4 列表排除设置档 + payload 是数组本身 | PASS | T006 / T009 节 |
| SCR-5 payload 四种形态、0 例嵌套数组 | PASS | T011 节 |
| SCR-6a~e 类型校验 + 可观测告警 | PASS（改动前 6a/6b FAIL） | T014–T021 节 |
| SCR-7a v1 旧档显式拒绝 / 可区分 / 无半读入 | PASS（改动前 FAIL） | T024 节 |
| SCR-7b 高版本拒绝 + 可区分 | PASS（改动前 7b-2 FAIL） | T024 节 |
| SCR-8 槽位安全 / 无路径穿越 | PASS（既有保护） | T006 节 |
| SCR-9 原子写 / 无 `.tmp` 残留 | PASS（既有保护） | T006 节 |
| SCR-10 未知 `ui_layer` 仍入树 | PASS | T009 节 |

## T029 / T030 / T031 — 收尾核对

- **T030**：探针已删除（`res://_probe_us1.gd` / `us2` / `us3` 及各自 `.uid`）；
  `Get-ChildItem -Filter "_*"` 无输出。
- **T031**：`git status --short`（只读）显示改动文件恰好是本次范围内的 6 个既有文件 + 3 个新文件，
  无 `_*` 残留、无意外文件；**未执行任何改变仓库状态的 git 操作**。
- **T029**：见 T026 节的「已知未完成事项」复核结论。

## T032 — 静态门禁（收尾）

**命令**：`.specify/scripts/powershell/godot-lint.ps1`

- 输出要点：`error=0  warn=3  存量基线=0 条`（3 条全部是 `scene_tree` 存量：
  `ui/main_menu/main_menu.gd:6`、`ui/options/options.gd:6`、`:7`）。
- 结论：PASS —— `error=0`，warn 数**不高于** T002 记录的存量 3 条（实现期间多出的
  `temp_files` warn 随探针删除而消失；`save_data_version` warn 未触发）。

## T033 — 主场景冒烟（收尾）

**命令**：`.specify/scripts/powershell/verify-engine.ps1`

- 首次（登记前）输出要点：`新增 7 行` —— 逐行确认全部由**本次契约变更**引起，且都不是缺陷：
  ```
  + WARNING: [SaveService] 存档版本 1 较旧（当前 2），尝试迁移后载入
  + WARNING: [SaveData] 存档结构版本 1 过旧（v1 元数据平铺 → v2 meta 分段），本版本不提供迁移，拒绝载入
  + ERROR:   [SaveService] 存档结构版本 1 过旧，本版本不提供迁移（当前结构版本 2）
  + WARNING: [SaveService] 设置档无法载入，按首次运行处理：以当前引擎状态作为设置默认值
  （+ 3 行 push_warning / logger 的栈帧行）
  ```
  成因：本机遗留的 `user://saves/options.sav` 是 **v1** 存档，v2 起按设计**显式拒绝**并回退播种。
- **基线变更（宪法原则 V 要求说明）**：用 `verify-engine.ps1 -UpdateNoise` 把这 4 行登记为
  **已确认的基线行**（基线从 5 行 → 11 行）。这不是把回归"洗白"：这些行是"本机带着 v1 存档"这一
  机器状态下的**确定性输出**，已在 `AGENTS.md` 的基线噪声一节写明成因与撤销方式。
- **复跑**：`无新增 ERROR/WARNING（基线 11 行）`，`验证通过：退出码 0`。
- **可选的更干净基线**：删除本机那个 v1 `options.sav`（或让设置界面把它重写成 v2）后，
  这 4 行会消失，届时用 `-UpdateBaseline` 重登即可回到 5 行基线 —— 该文件在 `user://` 下，
  **超出本会话的文件沙箱**，需人类执行。

## T034 — 宪法修订落地核对

- `.specify/memory/constitution.md`：`**Version**: 1.4.0`；原则 III 的
  「存档结构变更 MUST 提升结构版本号并提供迁移路径」**原文保留**，例外条款写明"一次性、不可延期、
  不可当作先例、模板发布或出现真实用户后 MUST 收回"；例外状态已更新为**由本功能使用（用尽）**。
- 头部 `Sync Impact Report` 注释块**已删除**（宪法文件现从 `# godot-template 项目宪法` 直接开始；
  `Select-String 'Sync Impact Report|临时材料'` 命中 0 行，文件 210 → 193 行）。
  删除是安全的：修订记录已在 T007 节、`tasks.md` T007 块与 `AGENTS.md` 存档契约条目中各存一份。

## T035 — "未越界"复核

**确认未被改动**：`res://core/types.gd`、`res://core/ui_root.gd`、`res://save_data/options_save.gd`、
`res://locale/*`、`res://ui/**`、`res://entry/**`、`res://addons/**`
（依据：`git status --short` + `git diff --stat`，无这些路径）。

**唯一例外：`res://core/paths.gd`（+2 个常量）**，举证：宪法原则 I 规定「所有 `res://` 路径 MUST 只在
`core/paths.gd` 中定义」，且 `godot-lint.ps1` 的 `paths` 规则把其他 .gd 里的 `"res://"` 字面量判为 **error**。
本次拆分出的两个模块刻意不加 `class_name`，只能用路径引用，因此路径常量**必须**落在 `paths.gd`。
计划里"本功能不改 `paths.gd`"的假设与宪法冲突，按宪法优先处理（改动仅新增 2 行常量，未改动既有常量）。

## T036 — 与规格的一致性复核

手工逐项复核（不另起 agent），结论：

- `spec.md`：US1（基线可复现）→ 三探针 + 逐条对照；US2（payload 契约）→ 文档修正 + SCR-5；
  US3（类型校验 + 职责拆分）→ SCR-6 + 两个新模块 + `validate_tree()`；US4（版本策略 + 一次不兼容变更）
  → `meta` 段、`version` 2、显式拒绝、SCR-7a/7b。**无未落地的功能需求**。
- `plan.md` / `data-model.md` / `contracts/` / `quickstart.md`：与最终代码一致（本文件已逐条记录）。
- **记录在案的偏差**（都不是缺口，而是过程事实）：
  1. `research.md` R4 的初稿结论（"不变更结构"）被用户裁定撤销，已保留撤销记录；
  2. `_probe_us3.gd` 在 v2 之后需要同步改内部字段路径与补丁路径（`meta.*`），
     因此它"改动前输出"的对照点以 **SCR-2b / 7a 的 FAIL** 为准，而不是逐字节相同的输出；
  3. 计划里"不改 `core/paths.gd`"与宪法 I 冲突，已按宪法处理（见 T035）；
  4. 设置档回退行为是本次刻意新增（见 T024 节末尾）。
- 探针已删除，`_*` 无残留。
