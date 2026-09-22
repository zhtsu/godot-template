---
description: "Task list for feature 001-core-save-refactor"
---

# Tasks: core/ 与 save_data/ 审查重构

**Input**: Design documents from `/specs/001-core-save-refactor/`

**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md, contracts/, quickstart.md

**Verification**: 本仓库没有单元测试框架。宪法原则 V 规定：非平凡改动 MUST 经真实引擎验证。因此每条用户故事都 MUST 包含"引擎验证"任务，且 MUST NOT 被当作可选项跳过。验证手段是 headless 引擎运行与一次性探针脚本，不是单元测试。

**命令与基线语义不在此重复**：见 `AGENTS.md` 的「验证」一节（唯一权威）与 plan.md 的 Verification Plan。
用仓库自带的 `.specify/scripts/powershell/godot-lint.ps1` 与 `verify-engine.ps1`，**不要写裸 `godot`**（它不在 PATH 上）。

**组织**: 任务按用户故事分组，使每条故事可独立实现、独立验证、独立交付。

**⚠️ 本功能的特殊性**：这是一次**重构**，头号约束是"除明确列为契约变更的项之外，行为不变"。
因此基线探针 MUST 在**任何实现改动之前**编写并运行（Phase 1），先记录"当前行为长什么样"——
否则事后无法区分"行为没变"与"不知道原来是什么样"。

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

所有路径都是仓库根下的 Godot 资源路径，任务描述里写 `res://` 全路径：

- 约定层：`res://core/`（`paths.gd` 路径常量、`events.gd` 事件名、`types.gd` 结构体、`options_data.gd` 候选值）
- 存档结构：`res://save_data/`（每分段一个类，继承 `SaveSection`；新分段还要在 `save_data.gd` 注册一行）
- 界面：`res://ui/<screen>/`（`<screen>.tscn` + `<screen>.gd`），打开/关闭只经事件
- 翻译：`res://locale/`（`en.po`、`zh_CN.po`、`texts.pot` 三处同步）
- 启动：`res://entry/`；框架层 `res://addons/godot_core_system/` MUST NOT 出现在任何任务的改动范围里
- 规格产物：`specs/001-core-save-refactor/`

**本功能不改动的文件**（出现在任何任务范围里即为越界）：`res://core/paths.gd`、`res://core/types.gd`、
`res://core/ui_root.gd`、`res://save_data/options_save.gd`、`res://locale/*`（三处）、`res://ui/**`、`res://entry/**`、`res://addons/**`。

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: 固化重构前的行为基线 —— 这是 FR-001 / VR-004 的硬要求，MUST 先于任何实现改动

- [X] T001 确认引擎输出基线已在改动前登记且当前无回归：跑 `.specify/scripts/powershell/verify-engine.ps1`，
      确认输出为"无新增 ERROR/WARNING"、退出码 0，基线文件为 `.specify/godot-verify-baseline.json`（时间戳应早于本功能任何代码改动）
- [X] T002 跑 `.specify/scripts/powershell/godot-lint.ps1` 记录改动前起点：`error=0`，`warn=3`（全部为 `scene_tree` 存量）。此数字是 T047 的对照基准
- [X] T003 [P] 编写基线探针 `res://_probe_us1.gd`（`extends SceneTree`），断言 SCR-1 / SCR-2 / SCR-3 / SCR-4 / SCR-10 五条。
      硬性要求：**涉及节点的断言 MUST 等 ≥2 帧**；断言 MUST 打可判定输出（成功/失败各一行，带实际值）。
      逐条断言：(SCR-1) `OPEN_UI` 后 `ui_dict` 含该路径且节点 `is_inside_tree()`，`CLOSE_UI` 后条目被清除；
      (SCR-2) 写入后文件首 4 字节 `== "GTSV"`，重新载入后逐字段值与写入前一致；
      (SCR-3) 无 `options.sav` 时内存设置值 `==` 当前引擎状态（`TranslationServer.get_locale()` / `DisplayServer.window_get_size()`）；
      (SCR-4) 存档列表不含 `"options"` 槽位，且 `SAVE_LIST_READY` 回调收到的是**数组本身**（`typeof == TYPE_ARRAY` 且 `received[0]` 不是 `Array`）；
      (SCR-10) `ui_layer` 传未知值时实例仍被挂入 MIDDLE（不出现"已实例化但不入树"）
- [X] T004 [P] 编写契约探针 `res://_probe_us2.gd`（`extends SceneTree`），断言 SCR-5 三条形态：
      非数组负载 → 订阅者收到**该对象本身**（`typeof` 与发送方一致）；数组负载 → 收到**该数组本身**且**不是嵌套数组**；
      多元素数组 → 按位置收到各元素。判据：三条全过，**0 例嵌套数组**
- [X] T005 [P] 编写存档探针 `res://_probe_us3.gd`（`extends SceneTree`），为 SCR-6/7/8/9 预先写好**结构**（断言内容可先留占位注释）。
      说明：SCR-6/SCR-7 的最终断言依赖 T019/T026/T038 之后的行为，此处只建立可运行骨架 + SCR-8/SCR-9（槽位安全、原子性）的完整断言
- [X] T006 运行三个探针并**如实记录改动前的原始输出**到 `specs/001-core-save-refactor/verification.md`：
      `.specify/scripts/powershell/verify-engine.ps1 -Probe res://_probe_us1.gd`（同样方式跑 us2 / us3）。
      **此步产出的输出是"重构后逐条一致"的对照物**（SC-002）。SCR-6/SCR-7a 此刻预期为**失败**
      （补丁类型缺陷、v1 旧档当前会被当成本版本读入）——保留失败输出，它证明缺陷真实存在

**Checkpoint**: 行为基线已固化。此后任何实现改动都必须以此为准做对比。

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: 治理与文档前提，未完成前不得动受影响代码

**⚠️ CRITICAL**: T007 是 US4 的前置项 —— US4 的交付物是"版本策略显式可查"，
其措辞 MUST 以 T007 定稿后的原则 III 为准（**本次裁定：原要求保留 + 只允许一次的不兼容例外**）；
T008 是 FR-003 的文档侧修复（已完成），其"存档契约同步"部分并入 T026

- [X] T007 修订 `.specify/memory/constitution.md` 的原则 III（**已完成**：v1.3.1 → **v1.4.0**）。
      人类裁定：允许不兼容**只允许这一次**，**宪法还是要保留** —— 因此**不移除**原要求，
      改为「原要求全部保留 + 追加一条一次性例外」：
      「模板尚未发布、不存在真实用户存档时，允许**一次**不兼容变更；迁移路径 MAY 省略，
      但 MUST 显式记录（改了什么 / 从哪个版本到哪个版本 / 为何允许不兼容），
      并 MUST 在『写迁移』与『显式拒绝』中声明其一，MUST NOT 出现半读入」。
      要求：(a) 保留"纯二进制 / 只允许基础类型 / 每段一类 / 原子写入 / 校验"等全部其余要求；
      (b) 例外 MUST NOT 延期、重复援引或当作先例，且 MUST 在模板发布或出现真实用户后通过一次专门修订收回；
      (c) 按 Governance 调整版本号——未移除、未重定义任何原则，属**新增限定范围的指引**，故为
      **MINOR 级修订**（1.3.1 → **1.4.0**；原计划的 MAJOR 2.0.0 以"移除既有硬要求"为前提，该前提已撤销）；
      (d) 例外**由本功能使用**（research.md R4：元数据独立成段 `meta`，`SaveData.version` 1 → 2，
      旧档策略 = 显式拒绝），用后即尽；该事实 MUST 在 `verification.md` 与 `AGENTS.md` 的存档契约条目中如实记录
- [X] T008 修正 `AGENTS.md` 硬规则 4 的反向描述（**已完成**：现行文本已改为"payload 就是订阅者的参数表"，
      并列出四种形态的实测结论；"数组时要再包一层是错的"）。
      原任务要求在此同时把 T007 的宪法变更同步进「存档系统契约」一节 —— 该同步**并入 T026**（PR-005），
      因为契约内容现在要一并描述本次 `version` 1 → 2 的不兼容变更，避免两处先后改出不一致

**Checkpoint**: 治理与文档一致，可以开始改动代码

---

## Phase 3: User Story 1 - 建立可复现的行为基线 (Priority: P1) 🎯 MVP

**Goal**: 交付"重构没改变行为"这一可判定能力本身 —— 基线 + 断言集 + 逐条对照结论

**Independent Test**: 复跑 T003/T004/T005 三个探针，逐条结论与 T006 记录的改动前输出一致；
且 `verify-engine.ps1` 报告无新增 ERROR/WARNING

### Verification for User Story 1 (MANDATORY - 引擎验证，非单元测试) ⚠️

- [X] T009 [US1] 复跑 `.specify/scripts/powershell/verify-engine.ps1 -Probe res://_probe_us1.gd`，
      与 T006 记录的改动前输出**逐条对照**，把差异（若有）写入 `verification.md`
- [X] T010 [US1] 确认 SCR-1 / SCR-2 / SCR-3 / SCR-4 / SCR-10 五条判据在**未做任何实现改动**时即成立
      （这五条描述的是既有正确行为，是防回归的护栏，不是待实现功能）

### Implementation for User Story 1

本故事**无生产代码改动** —— 它的交付物是验证能力本身。这是重构类功能的正常形态，不是遗漏。

**Checkpoint**: 行为基线可复现，MVP 达成（后续每条故事都靠它判定"没坏"）

---

## Phase 4: User Story 2 - 让事件 payload 契约自洽且可执行 (Priority: P2)

**Goal**: 契约的说明与实现一致，并被机械断言固化

**Independent Test**: SCR-5 三条形态全部通过，0 例嵌套数组（SC-006）

### Verification for User Story 2 (MANDATORY) ⚠️

- [X] T011 [US2] 运行 `.specify/scripts/powershell/verify-engine.ps1 -Probe res://_probe_us2.gd`，
      确认 SCR-5 三条判据通过（预期在 T008 修完文档后即通过——本故事的缺陷在文档而非代码，见 research.md R1）

### Implementation for User Story 2

- [X] T012 [P] [US2] 在 `res://core/events.gd` **仅补注释**：说明 payload 的真实形态
      （永远按参数表处理；非数组自动包成单元素；数组即参数表），并指向
      `specs/001-core-save-refactor/contracts/event-payload-contract.md`。
      **MUST NOT 改动任何 `const *_REQUEST/_FINISHED/_READY` 的值**（事件名属 FR-002 保护范围）
- [X] T013 [US2] 核查全部 `push_event` 调用点是否与该契约一致，把结论写入 `verification.md`。
      已知调用点：`res://core/save_service.gd`（`_emit` 与 `SAVE_LIST_READY` 发送处）、
      `res://entry/main.gd`、`res://ui/main_menu/main_menu.gd`。
      **预期结论：四处均正确，无需改代码**（research.md R1 已核实）——若发现不一致，MUST 先在 plan.md 记录再改

**Checkpoint**: 事件契约自洽且有断言保护

---

## Phase 5: User Story 3 - 消除校验缺陷并拆分职责 (Priority: P2/P3)

**Goal**: 补丁不再能静默写坏字段类型；`save_service.gd` 的七种职责变得可辨认

**Independent Test**: SCR-6（类型校验）通过；SCR-1~SCR-10 全绿；`save_service.gd` 的对外事件接口未变

### Verification for User Story 3 (MANDATORY) ⚠️

- [X] T014 [US3] 在 `res://_probe_us3.gd` 中补全 SCR-6 的断言，并**先运行确认它当前失败**
      （用类型错误的补丁，当前会被静默 `set()` 为错误类型）——保留失败输出作为"缺陷真实存在"的证据
- [X] T015 [US3] 运行 `.specify/scripts/powershell/verify-engine.ps1 -Probe res://_probe_us3.gd`，
      记录 SCR-6 失败、SCR-8/SCR-9 通过的起始状态

### Implementation for User Story 3

- [X] T016 [P] [US3] 在 `res://save_data/save_section.gd` 的 `apply_dict()` 中实现类型兼容校验（FR-004）。
      规则**逐条照 data-model.md §2.2 实现**：
      目标是 `SaveSection` 而补丁值不是 `Dictionary` → 拒绝该字段 + 告警（**保持现状**）；
      `int` ↔ `float`（无损）→ 接受；其余任意类型，`typeof` 不同 → **拒绝该字段**并 `push_warning`
      出「字段名 / 期望类型 / 实际类型」；`typeof` 相同 → 接受；未知字段 → 忽略 + 告警（**保持现状**）。
      不变量：拒绝 MUST NOT 清空或重置该字段（保持原值）；空补丁 MUST NOT 改变任何字段；
      一个坏字段 MUST NOT 阻止同批次其他合法字段被应用
- [X] T017 [P] [US3] 新建 `res://core/save_storage.gd`：承载**纯文件 IO** 职责。
      从 `res://core/save_service.gd` 迁出：路径拼接、槽位名过滤（拒绝空 / 以 `.` 开头 / 含
      `..` `/` `\` `:` `*` `?` `"` `<` `>` `|`）、文件大小上限（8 MiB）、魔数 `GTSV` 校验、
      `bytes_to_var` 解码、原子写（tmp → `DirAccess.rename_absolute`）。
      **约束**：`save_dir` 由参数传入（不持状态）；**不订阅事件**；**不持有 `SaveData`**；
      **不加 `class_name`**，用 `preload` 常量引用（与 `res://addons/godot_core_system/source/core_system.gd` 引用模块的方式一致），
      以避免污染全局类缓存与强制 `--import`
- [X] T018 [P] [US3] 新建 `res://core/options_applier.gd`：承载**纯引擎状态应用**职责。
      迁出 `_apply_options()` 的内容：`TranslationServer.set_locale`、全屏判定
      （`OptionsData.FULLSCREEN` == `Vector2i.ZERO`）、`DisplayServer.window_set_mode` / `window_set_size`。
      **约束**：纯函数式不持状态；不订阅事件；不读存档；不加 `class_name`
- [X] T019 [US3] 改造 `res://core/save_service.gd` 改为委派 T017/T018 的新模块，并**保留**：
      四个请求事件的订阅与退订、任务队列（`_jobs` / `_draining` / 一次 drain 上限 16 / 剩余下一帧）、
      `save_data` 所有权与 `SaveData.current` 赋值、`_stamp()` 元数据补齐、`_make_result()` / `_emit()`、
      设置档启动流程（`_options_ready()` / `_autoload_options()`）。
      **对外接口 MUST NOT 变**：事件名、请求/结果字段、`save_data` 共享单对象语义、读档为原地更新
- [X] T020 [US3] 在 `_do_save()` 的写入路径补一次 `save_data.validate_tree()`（research.md R2 的 B+C 组合），
      使范围/白名单类问题也在落盘前被兜住。注意语义差别：类型不兼容属"调用方写错"→ 告警并保持原值；
      范围不合理属"值不合理"→ 由既有 `validate()` 修正。两者 MUST NOT 合并成同一机制
- [X] T021 [US3] 复跑 `.specify/scripts/powershell/verify-engine.ps1 -Probe res://_probe_us3.gd`，
      确认 SCR-6 由失败转为通过，且 SCR-8/SCR-9 仍通过
- [X] T022 [US3] 跑 `.specify/scripts/powershell/verify-engine.ps1`（主场景冒烟）+ `-Scenario res://ui/options/options.tscn`，
      确认相对基线无新增 ERROR/WARNING
- [X] T023 [US3] 人工审阅依赖方向并把结论写入 `verification.md`：`save_service` → `save_storage` / `options_applier`
      MUST 单向；MUST NOT 出现反向依赖或新模块订阅事件（data-model.md §5.3）

**Checkpoint**: 校验缺陷已修，职责边界可辨认，对外行为不变

---

## Phase 6: User Story 4 - 用明确的分段版本策略取代"隐含兼容" (Priority: P3)

**Goal**: **执行并记录这一次**不兼容的存档结构变更 —— 元数据独立成段 `meta`、`SaveData.version` 1 → 2、
旧档策略为**显式拒绝**；并把"允许不兼容只允许这一次"的可追溯记录落到契约与 `AGENTS.md`。

**Independent Test**: SCR-7a/7b 通过（v1 旧档 → 明确拒绝、`error` 可区分、无半读入；`version` 高于程序 → 仍拒绝）；
且 `contracts/save-file-format.md` 与 `AGENTS.md` 能查到"改了什么 / 从哪个版本到哪个版本 / 为何允许不兼容"。

> **用户裁定（本次）**：`spec.md` 的 `PR-002` 写"结构变更 = 是"，因此本故事**真的做一次**不兼容结构变更
> （`research.md` R4 的初稿结论"不变更"已被撤销）。这**消耗掉**宪法原则 III 的一次性例外 ——
> 例外用尽后，后续任何结构变更 MUST 回到"提升版本 **并提供迁移路径**"的完整要求。
> **变更内容（不新增字段，只调整分段组织，符合 PR-001）**：根上的 `slot` / `saved_at` /
> `game_version` / `playtime` 移入新分段 `meta`（`MetaSave`）；对外 `metadata()` 仍返回**同一组平铺键**（FR-002）。
> **旧档策略 = 显式拒绝**（不是写迁移）：目标集合为空，写迁移无法被真实数据验证（research.md R4）。

### Verification for User Story 4 (MANDATORY) ⚠️

- [X] T024 [US4] 在 `res://_probe_us3.gd` 中补全 SCR-7a/7b 的两条断言并运行记录：
      (a) 构造 `version == 1` 的旧档（v1 平铺元数据）→ 载入 MUST `ok == false`、`error` MUST 可区分
      （非笼统失败）、且 MUST NOT 半读入（其余字段未被部分更新）；
      (b) 构造 `version` 高于当前程序的存档 → 同样 MUST 被拒绝（既有保护，MUST 保持）

### Implementation for User Story 4

- [X] T037 [US4] 新建 `res://save_data/meta_save.gd`：`class_name MetaSave extends SaveSection`，
      承载 `slot` / `saved_at` / `game_version` / `playtime` 四个**既有**字段（MUST NOT 新增字段）。
      **注意**：本任务新增 `class_name` → 运行前 MUST 先 `--import`（见 AGENTS.md）。
      **写入顺序**：本文件 MUST 先于 T038 落盘，且 `save_data.gd` MUST 是 `save_data/` 下最后被修改的文件，
      以免触发 lint 的 `save_data_version` warn（见 T032 的 warn 计数判据）
- [X] T038 [US4] 改 `res://save_data/save_data.gd`：`version` **1 → 2**；根上移除四个元数据字段、
      新增 `var meta: MetaSave = MetaSave.new()`；`metadata()` 对外**仍返回同一组平铺键**
      （`version` / `slot` / `saved_at` / `game_version` / `playtime`，值取自 `meta`）——FR-002 保护对外契约；
      `migrate()` 改为**显式拒绝**（返回 `{}`），注释写明"v1 旧档不迁移，理由见 contracts §5.2"
- [X] T039 [US4] 改 `res://core/save_service.gd` 中所有对根上元数据字段的引用
      （`_stamp()` 写 `save_data.meta.*`、设置档 `OptionsSave.SLOT` 播种、写入失败回滚 `previous_slot`、
      `_list_slots()` 经 `metadata()` 取值），保持事件名/结果字段/共享单对象语义不变。
      **与 T019/T020 同改一个文件 → MUST 串行，MUST NOT 并行**
- [X] T040 [US4] 引擎验证：先 `--import`，再跑 `-Probe res://_probe_us3.gd`（SCR-7a/7b）+
      主场景冒烟基线 diff + `-Scenario res://ui/options/options.tscn`，把命令与结论写入 `verification.md`。
      **注意**：本机既有 `options.sav` 是 v1，变更后会被显式拒绝并触发设置重新播种，可能产生基线新增行 ——
      若如此，MUST 先确认该行确由本次契约变更引起并在 `verification.md` 说明，再由人类确认后用
      `verify-engine.ps1 -UpdateBaseline` 重登（宪法原则 V：基线变化 MUST 说明）
- [X] T025 [P] [US4] 更新 `specs/001-core-save-refactor/contracts/save-file-format.md`：
      §1/§2 改为 v2 容器结构；§5.1 的实际状态表改为"`version` = 2、`migrate()` = 显式拒绝、
      本次确有一次性不兼容变更"；§5.2 写明"例外本次**被使用、已用尽**"；§7 的 SCR-7a/7b 判据与 T024 对齐
- [X] T026 [US4] 在 `AGENTS.md` 的「存档系统契约」一节同步（PR-005）：
      记录本次不兼容变更（元数据独立成段 `meta`、`version` 1 → 2、旧档**显式拒绝**、无半读入），
      并补面向未来的不变量：改结构 MUST 提升 `version` **并**记录"改了什么 / 从哪个版本到哪个版本 /
      为何允许不兼容"，且在"写迁移"与"显式拒绝"中 MUST 声明其一；MUST NOT 悄悄改结构而不动版本号；
      注明宪法原则 III 的一次性例外**本次已用尽**，此后结构变更 MUST 提供迁移路径
- [X] T027 [US4] 复核 `res://save_data/save_data.gd` 的 `version` 与 `migrate()` 注释是否与最终策略一致
      （本次**要改**：`version` 注释 MUST 说明"1 → 2 改了什么"；`migrate()` 注释 MUST 说明"为何选择显式拒绝"）

**Checkpoint**: 版本策略显式可查、旧档被明确拒绝且无半读入，"例外已用尽"这件事有据可查

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: 收尾、证据落盘与规格一致性复核

- [X] T028 [P] 逐条勾选 plan.md 的 Verification Plan 判据，把"命令 + 原始输出要点 + 结论"整理进
      `specs/001-core-save-refactor/verification.md`（SCR-1 ~ SCR-10 十条 MUST 齐全）
- [X] T029 [P] 复核 `AGENTS.md` 三处是否需要同步：硬规则 4（T008 已改）、「存档系统契约」（T026 已改）、
      「已知未完成事项」（若本次改变了任何存量状态则更新；本次预期不改，需显式说明）
- [X] T030 删除全部探针脚本：`res://_probe_us1.gd`、`res://_probe_us2.gd`、`res://_probe_us3.gd`
- [X] T031 用 `git status`（**只读查询，宪法原则 VII 允许**）确认无 `_*` 残留、无意外改动文件。
      **MUST NOT 执行 `git add` / `git commit` / `git restore` 等任何改变仓库状态的命令**
- [X] T032 跑 `.specify/scripts/powershell/godot-lint.ps1`，确认 `error=0` 且 `warn` 数量**不高于** T002 记录的 3。
      **注意**：`save_data/` 下若有分段类比 `save_data.gd` 更新，会多出一条 `save_data_version` warn（属提示性），
      按 T037 的写入顺序可避免；若仍触发，MUST 在 `verification.md` 说明而不是默默接受
- [X] T033 跑 `.specify/scripts/powershell/verify-engine.ps1` 主场景冒烟 + 三个探针全部删除后的收尾冒烟，
      确认相对基线无新增 ERROR/WARNING
- [X] T034 确认宪法原则 III 的修订已落地且版本号已按 Governance 调整
      （**MINOR：1.3.1 → 1.4.0**，级别理由见 T007(c)），
      并确认 `.specify/memory/constitution.md` 头部不再有过期的遗留注释
      （**已完成**：`Sync Impact Report` 临时块已删除，文件从 `# godot-template 项目宪法` 直接开始，
      210 → 193 行；修订记录改由本文件 T007 块、`verification.md` 与 `AGENTS.md` 存档契约条目承载）
- [X] T035 复核"未越界"：确认 `res://core/types.gd`、`res://core/paths.gd`、`res://core/ui_root.gd`、
      `res://save_data/options_save.gd`、`res://locale/*`、`res://ui/**`、`res://entry/**`、`res://addons/**`
      均**未被改动**；若有改动 MUST 在 `verification.md` 说明理由（FR-002 例外需举证）
- [X] T036 运行 `/speckit-converge` 复核代码与规格的差距，把未落地项补回本文件

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: 无依赖，**必须最先完成** —— 基线探针是后续一切"无回归"判定的前提（FR-001/VR-004）
- **Foundational (Phase 2)**: 依赖 Phase 1；T007 是 US4 的前置（例外措辞定稿），T008 必须在动 `core/events.gd` 前完成
- **User Stories (Phase 3~6)**: 依赖 Phase 2
- **Polish (Phase 7)**: 依赖所有目标故事完成

### User Story Dependencies

- **US1 (P1)**: 无依赖 —— 它就是其他故事的前提，且本身无生产代码改动
- **US2 (P2)**: 依赖 T008（文档修复）；T011/T012/T013 与 US3 无文件冲突，可并行
- **US3 (P2/P3)**: 依赖 US1 的基线；T017/T018/T019 之间存在构造顺序（先建新文件，再改 `save_service` 委派）
- **US4 (P3)**: 依赖 T007（宪法修订，例外已获授予并**由本故事使用**）；
  T024/T025/T026/T027 与 US3 无文件冲突，可并行；但 **T037 → T038 → T039 → T040** 是构造链，
  且 T039 与 T019/T020 同改 `core/save_service.gd`，MUST 串行

### 关键串行链（不可并行）

1. `T001 → T003/T004/T005 → T006`（基线必须先于一切实现改动）
2. `T014 → T016`（先写出失败的断言，再修 `apply_dict`）
3. `T017/T018 → T019 → T020`（先建新模块，再改造 `save_service` 委派，最后补写入校验）
4. `T007 → T026`（宪法先行，文档随后）
5. `T037 → T038 → T039 → T040`（先建 `MetaSave`，再改根与引用，最后引擎验证；
   T038/T039 必须在 T019/T020 之后或之前**整体串行**，不可交叉编辑同一文件）

### Parallel Opportunities

- Phase 1：T003 / T004 / T005 三个探针是不同文件，可并行编写
- Phase 5：T016（`save_section.gd`）/ T017（`save_storage.gd`）/ T018（`options_applier.gd`）三个不同文件可并行
- Phase 6：T025（契约文档）与 T026（`AGENTS.md`）可并行；T037（新文件）也可与 T025 并行
- **冲突提示**：T012 改 `core/events.gd` 与 T019 改 `core/save_service.gd` 是不同文件，可并行；
  但 T019 / T020 / T039 同改 `save_service.gd`，MUST 串行

---

## Parallel Example: Phase 5（US3 的三个独立文件）

```text
# 三个不同文件、无相互依赖，可并行：
Task: "T016 在 res://save_data/save_section.gd 的 apply_dict() 实现类型兼容校验"
Task: "T017 新建 res://core/save_storage.gd（纯文件 IO）"
Task: "T018 新建 res://core/options_applier.gd（纯引擎状态应用）"

# 完成后串行：
Task: "T019 改造 res://core/save_service.gd 改为委派新模块"
Task: "T020 在 _do_save() 写入路径补 validate_tree()"
```

---

## Implementation Strategy

### MVP First（仅 US1）

1. 完成 Phase 1（基线探针 + 记录改动前输出）
2. 完成 Phase 2 的 T008（文档修正，避免实现者读到反向指引）
3. 完成 Phase 3（确认基线可复现）
4. **STOP and VALIDATE**：此时 US1 的独立测试已完整成立 —— "行为基线可复现"本身就是可交付价值
5. 由于 US1 无生产代码改动，它单独完成时**没有可演示的功能**，这是重构类功能的正常形态

### Incremental Delivery

1. Phase 1 + Phase 2 → 基线就绪、治理一致
2. + US1 → 基线可复现（MVP）
3. + US2 → 事件契约自洽并被断言保护
4. + US3 → 校验缺陷已修、职责可辨认（**本次价值主体**）
5. + US4 → 版本策略显式可查，并**执行一次**不兼容结构变更（元数据独立成段 `meta`、`version` 1 → 2、旧档显式拒绝）
6. Phase 7 → 证据落盘、探针清理

### 交付顺序建议

US3 是本次价值主体，但它依赖 US1 的护栏。因此建议顺序为
`Phase 1 → Phase 2 → US1 → US3 → US2 → US4 → Phase 7`（US2 改动极小，可与 US4 一起收尾）。
若严格按优先级推进，则 `Phase 1 → Phase 2 → US1 → US2 → US3 → US4 → Phase 7`。

---

## Notes

- [P] 任务 = 不同文件、无相互依赖
- [Story] 标签用于把任务追溯到具体用户故事
- 验证 MUST 在真实引擎中进行；"代码看起来对"不构成完成依据
- `res://addons/godot_core_system/` MUST NOT 出现在任何任务的改动范围里
- **本计划新增 1 个 `class_name`（`MetaSave`，T037）**：因此 T040 的引擎验证 MUST 先跑 `--import`；
  其余新文件（`save_storage.gd` / `options_applier.gd`）刻意不加 `class_name`，用 `preload` 引用
- MUST NOT 执行任何改变仓库状态的 git 操作（宪法原则 VII）；`git status` 等只读查询允许
- 避免：模糊任务、同一文件冲突、破坏故事独立性的跨故事依赖
