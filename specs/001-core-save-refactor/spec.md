<!--
  项目覆盖层（解析优先级 1）。解析栈见 .specify/scripts/powershell/common.ps1 → Resolve-TemplateContent：
      overrides/  >  presets/<id>/  >  extensions/<id>/  >  templates/（core，受管文件）
  本文件是**整体替换** core 模板，不是在其上追加。由 create-new-feature.ps1:281 经解析器读取。

  core 模板编写时 sha256（用于漂移检测）:
      3945437fc35cd30a5b2bf7beea680337c3516826d3efa5a6b92c4a7eca1ba28e
  若哈希变化，说明上游模板已更新，需人工复核本覆盖层是否需要同步。
-->

# Feature Specification: core/ 与 save_data/ 审查重构

**Feature Branch**: `001-core-save-refactor`

**Created**: 2026-09-23

**Status**: Draft

**Input**: User description: "阅读检查并优化重构 core/ 与 save_data/ 现有代码"

**范围**：`core/`（paths / events / types / options_data / ui_root / save_service）与 `save_data/`（save_section / save_data / options_save）。
**深度**：允许改存档契约与事件语义（宪法原则 III 以**一次性例外**方式放宽向后兼容要求，且只允许这一次）。

## User Scenarios & Testing *(mandatory)*

<!--
  本功能是重构，没有"新玩家旅程"。因此每条故事写成"维护者视角的可验证目标"，
  并按项目覆盖层要求把 Independent Test 写成引擎里可执行的观察方式。
  头号约束：除明确列为契约变更的项之外，行为与对外接口 MUST 保持不变。
-->

### User Story 1 - 建立可复现的行为基线，重构全程可判定"没坏" (Priority: P1)

作为模板维护者，我需要一份**在改动前就存在**的基线，这样"重构没改变行为"才是可验证的断言，而不是感觉。

**Why this priority**: 这是其他所有故事的前提。没有先行基线，任何"优化"都无法证明无回归，原则 V 也就无从落地。

**Independent Test**: 跑 `.specify/scripts/powershell/verify-engine.ps1`（主场景冒烟 + 基线逐行 diff），
并用一次性探针断言：`ui_dict` 记账、存档写入后重载字段一致、设置档首启播种、存档列表排除设置档。

**Acceptance Scenarios**:

1. **Given** 基线已登记，**When** 执行主场景 headless 冒烟，**Then** 相对基线无新增 ERROR/WARNING，退出码 0。
2. **Given** 探针断言全部通过，**When** 重构后复跑同一组探针，**Then** 断言结果与重构前逐条一致。
3. **Given** 任一断言在重构后失败，**When** 检查该断言，**Then** 能区分"行为真的变了"与"断言本身写错了"。

---

### User Story 2 - 让事件 payload 契约自洽且可执行 (Priority: P2)

作为使用者，我需要事件负载的语义**与实现一致**，因为当前文档描述的规则与事件总线实际行为相反，
照着文档写代码会得到嵌套数组。

**Why this priority**: 这是已确认的契约缺陷，且直接决定后面重构能否安全地动事件签名。修正它同时消除一类隐性 bug。

**Independent Test**: 探针分别以「非数组」`push_event(NAME, result)` 与「数组」`push_event(NAME, [items])`
两种方式推送，断言订阅者收到的参数个数与类型符合约定。

**Acceptance Scenarios**:

1. **Given** 订阅者接收单参数结构体，**When** 发送方传入非数组对象，**Then** 订阅者收到该对象本身（自动包成单元素参数表）。
2. **Given** 订阅者接收单参数数组，**When** 发送方传入数组，**Then** 订阅者收到该数组本身，**不是**嵌套数组。
3. **Given** 订阅者接收多参数，**When** 发送方传入多元素数组，**Then** 订阅者按位置收到各元素。
4. **Given** 修正后的契约，**When** 查阅 `AGENTS.md` 与 `core/types.gd` 的说明，**Then** 描述与上述行为一致，不再出现"数组时要再包一层"这类反向指引。

---

### User Story 3 - 消除已确认的类型与校验缺陷 (Priority: P2)

作为使用者，我需要补丁数据不能把存档字段改成错误类型或结构，否则损坏是静默发生的。

**Why this priority**: `save_data.apply_dict()` 当前**不做任何类型校验**就 `set()`。补丁里给 `Vector2i` 字段传 `String`
不会报错，只会在下次读档时表现为"值莫名其妙"。这是与宪法原则 III「静默丢数据是 bug」同类的静默破坏。

**Independent Test**: 探针用错误类型的补丁调用存档请求，断言返回 `ok=false` 或字段保持原值，且能观测到明确告警；
再用正确类型补丁断言正常写入。

**Acceptance Scenarios**:

1. **Given** 补丁字段类型与目标字段不符，**When** 应用补丁，**Then** 该字段不被写入为错误类型，且产生可观测告警。
2. **Given** 补丁把分段字段设成非字典值，**When** 应用补丁，**Then** 该分段不被清空（现状已有保护，MUST 保持）。
3. **Given** 补丁含未知字段，**When** 应用补丁，**Then** 保持现有行为：忽略并告警。

---

### User Story 4 - 用明确的分段版本策略取代"隐含兼容" (Priority: P3)

作为模板维护者，我决定**允许存档格式不向后兼容**，但要求这件事是*显式记录*的，
而不是靠没人知道的隐式行为。

**Why this priority**: 它直接影响宪法原则 III 的措辞。不先把"允许不兼容"写进宪法，
后续任何存档结构改动都会与宪法冲突，实现阶段会卡住。

> **先决条件（阻塞本故事）**：宪法原则 III 要求「存档结构变更 MUST 提升结构版本号并提供迁移路径」。
> 本次裁定：该要求**全部保留**，只追加一条**一次性例外**（模板尚未发布、无真实用户存档时允许**一次**
> 不兼容变更，迁移路径 MAY 省略，但 MUST 显式记录）。这属于**新增限定范围的指引**，因此是一次
> **MINOR 级宪法修订**（1.3.1 → 1.4.0），MUST 先完成并记录理由；该例外总计只可使用一次，
> MUST NOT 被延期或援引为先例。

**Independent Test**: 把结构版本提升到 2 后，断言：v1 旧档被**明确拒绝**并给出可区分的原因，
而不是被"静默按新结构读入"（也不得出现半读入）；`version` 高于程序的存档同样被拒绝；
首次运行无存档时仍用当前引擎状态播种设置默认值。

**Acceptance Scenarios**:

1. **Given** 结构版本已由 1 提升到 2（元数据移入 `meta` 段），**When** 载入 v1 旧档，**Then** 得到明确失败结果且 `error` 说明原因（版本不兼容），不产生半读入状态。
2. **Given** 存档版本高于程序版本，**When** 载入，**Then** 保持现有行为：拒绝并提示用新版程序打开。
3. **Given** 首次运行且无任何存档，**When** 启动，**Then** 设置默认值来自当前引擎状态（界面显示 = 实际生效）。
4. **Given** 本次确实做了不兼容的存档结构改动，**When** 查阅变更记录，**Then** 能查到"哪个版本、改了什么、为什么允许不兼容"。

---

### User Story 5 - 让存档服务与 UI 记账的职责可辨认 (Priority: P3)

作为维护者，我需要单个文件不再同时承担"请求校验、队列、存取、设置启动、序列化、文件 IO、元数据"七件事，
否则每次改动都要在 460 行里找边界。

**Why this priority**: 纯结构收益，风险最低但独立价值也最低，因此排在行为修正之后。

**Independent Test**: 跑 `/speckit-godot-lint`（无 error 级违规）+ 主场景冒烟基线 diff + US1 的全套探针，
证明拆分为纯结构调整、对外可观测行为不变。

**Acceptance Scenarios**:

1. **Given** 拆分完成，**When** 复跑 US1 全部探针，**Then** 逐条结果与基线一致。
2. **Given** 拆分完成，**When** 检查对外接口，**Then** 事件名、请求/结果字段、`save_data` 共享对象语义均未变（除非 US2/US4 明确变更）。
3. **Given** 拆分完成，**When** 依赖关系审视，**Then** 不出现反向依赖（不会为了拆而让服务层依赖 UI 层）。

---

### Edge Cases

<!-- 游戏项目常见来源：窗口尺寸极端值、语言切换、存档缺失/损坏/版本过旧、快速重复点击、暂停中触发、退出时未保存、界面重复打开与关闭、缺翻译键。 -->

- **存档缺失 / 文件头不是 `GTSV` / 长度小于魔数 / 超过上限**：行为与现状一致（拒绝 + 日志），MUST NOT 因重构而改变拒绝理由的可区分性。
- **槽位名非法**（含 `..`、`/`、`\`、以 `.` 开头）：保持拒绝，且 MUST NOT 出现路径穿越。
- **重复打开同一界面**：现状是"先清理旧实例再重新实例化"，MUST 保持；`ui_dict` MUST NOT 残留悬空引用。
- **界面自行 `queue_free` 离开场景树**：`ui_dict` 记录 MUST 被清理（现有 `tree_exited` 机制）。
- **写入过程中断**：MUST 仍保持原子性（临时文件 + 改名），MUST NOT 产生半写存档。
- **设置档存在但内容损坏**：MUST 回落到默认值并告警，MUST NOT 让界面显示与生效值不一致。
- **空补丁**：`request.data` 为空时 MUST 不改变任何字段（现状如此）。
- **补丁类型错误 / 分段被设成非字典**：见 US3。
- **`ui_layer` 传入未知值**：现状是告警并按 MIDDLE 处理，MUST 保持——实例 MUST NOT 出现"已实例化但不入树"。
- **配置模块被禁用**：框架模块可经 `ProjectSettings` 关闭并返回 null，重构后的代码 MUST NOT 假设模块必然可用（宪法原则 VI）。

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: 系统 MUST 在改动开始前产出可复现的行为基线（引擎输出基线 + 一组行为断言），且该基线 MUST 先记录现状再进入重构。
- **FR-002**: 除本规格明确列为契约变更的项之外，重构 MUST NOT 改变任何对外可观测行为，包括：事件名、请求/结果字段名与语义、`save_data` 共享单对象语义、存档文件名与扩展名、拒绝载入的判定条件。
- **FR-003**: 事件负载语义 MUST 与其实际实现一致并被文档化：非数组负载按单元素参数表处理；数组负载**即**参数表本身。MUST NOT 存在要求"数组再包一层"的指引。
- **FR-004**: 补丁应用 MUST NOT 把字段写成与目标字段不兼容的类型；不兼容时 MUST 保持原值（或拒绝该次请求）并产生可观测告警。
- **FR-005**: 存档结构版本 MUST 与其结构真实对应；本次发生**一次**不兼容变更（元数据独立成段 `meta`），
  因此 MUST 提升版本（1 → 2）并显式记录（改了什么、为何允许不兼容）；该次变更援引宪法原则 III 的
  **一次性例外**，用后即尽 —— 此后结构变更 MUST 提升版本**并提供迁移路径**。
- **FR-006**: 载入结构版本低于当前的存档时，MUST 返回可区分的失败原因，MUST NOT 半读入（不得出现部分字段被更新、部分保持原值的混合状态）。
- **FR-007**: 原子写入、槽位名过滤、大小上限、魔数校验、设置档与游戏档分离等既有保护 MUST 全部保留。
- **FR-008**: 重构后 MUST 能指出每个模块的单一职责边界；MUST NOT 出现职责重叠或循环依赖。
- **FR-009**: 重构 MUST NOT 引入任何游戏特有的美术、玩法或文案内容（宪法「通用性门」）。
- **FR-010**: 重构 MUST NOT 修改 `addons/godot_core_system/`（宪法原则 II/VI）；框架能力不足时在项目层包装并记录缺口。

### Localization Requirements *(界面相关功能必填)*

- **LR-001**: 本功能不新增可见文本；MUST NOT 新增翻译键。若因重构而删除可见文本，MUST 同步清理 `locale/en.po`、`locale/zh_CN.po`、`locale/texts.pot` 三处对应键。
- **LR-002**: 存量 5 个 orphan key（`ui.main_menu.settings.res`、`ui.main_menu.select`、`ui.options.text_language`、`ui.options.language_name`、`ui.options.select`）属"已知未完成事项"，MUST NOT 在本次清理。
- **LR-003**: 重构 MUST NOT 改变语言切换的生效路径（设置档应用 → `TranslationServer.set_locale`）。

### Persistence Requirements *(涉及存档时必填，否则写 N/A)*

- **PR-001**: 需要落盘的数据：本功能**不新增字段**；调整的是既有分段的组织 ——
  把根上平铺的元数据（`slot` / `saved_at` / `game_version` / `playtime`）移入独立分段 `meta`（新增 `MetaSave` 类）。
- **PR-002**: 存档结构是否变更：**是**（不兼容）。`SaveData.version` MUST 由 1 提升到 2，MUST 记录不兼容理由
  （改了什么、从哪个版本到哪个版本、为何允许不兼容）；本次援引宪法原则 III 的**一次性例外**，
  迁移路径 MAY 省略 —— 本次选择**显式拒绝**旧档（可区分原因、无半读入），例外随之用尽。
  对外契约 MUST 不变：`SaveData.metadata()` 仍返回同一组平铺键。
- **PR-003**: 首次运行（无存档）时的默认值来源：保持现状——**当前引擎状态**（`TranslationServer.get_locale()` / `DisplayServer.window_get_size()`）。
- **PR-004**: 存档 MUST 保持纯二进制（魔数 `GTSV` + `var_to_bytes`），MUST NOT 引入对象/脚本引用，MUST NOT 改用 `bytes_to_var_with_objects()`。
- **PR-005**: 存档格式若发生任何变化，MUST 同步更新 `AGENTS.md` 的「存档系统契约」一节。

### Input Requirements *(涉及操作时必填，否则写 N/A)*

- **IR-001**: N/A —— 本功能不新增或修改 `[input]` 动作表。
- **IR-002**: N/A

### Engine Verification Requirements *(mandatory)*

- **VR-001**: 每条 FR MUST 对应至少一条可执行的引擎验证手段（`verify-engine.ps1` 的 `-Scenario` / `-Probe`，或 `godot-lint.ps1`）。
- **VR-002**: 验证 MUST 覆盖被改动脚本"被真实实例化"的路径；MUST NOT 仅静态阅读代码。
- **VR-003**: 一次性脚本 MUST 在交付前删除；用 `git status`（只读）或 `temp_files` 规则确认。
- **VR-004**: 行为基线 MUST 在重构**之前**采集（FR-001），否则无回归判定不成立。

### Key Entities *(include if feature involves data)*

- **SaveData（`save_data/save_data.gd`）**: 存档根。持结构版本（本次 1 → 2）、元数据分段与各分段；
  分段以"一段一个类"注册。承担版本比较与迁移钩子的调用入口（本次 `migrate()` 改为**显式拒绝**旧档）。
- **MetaSave（`save_data/meta_save.gd`，本次新增）**: 元数据分段。承载 slot / saved_at / game_version / playtime
  —— 本次从根上平铺**搬入**，不新增字段；对外仍经 `SaveData.metadata()` 以同一组平铺键暴露。
- **SaveSection（`save_data/save_section.gd`）**: 分段基类。决定"哪些字段能进纯数据存档"（拒绝 `Object`/`Callable`/`Signal`/`RID`）、字段字典的序列化与回填、以及载入后的自检入口。
- **OptionsSave（`save_data/options_save.gd`）**: 设置分段。独占 `options` 槽位，含分辨率与语言，并带白名单校验（不在候选表内则回退默认值）。
- **Events（`core/events.gd`）**: 事件名唯一来源。本次可能因负载契约修正而调整说明，但事件名本身 MUST NOT 变更（变更需单独立项）。
- **Types（`core/types.gd`）**: 请求与结果结构体唯一来源。结构体字段是跨模块契约的一部分，属 FR-002 保护范围。
- **SaveService（`core/save_service.gd`）**: 事件驱动的存档服务，持唯一一份 SaveData，负责请求校验、排队、存取、设置启动应用与元数据补齐。

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 重构前后，主场景 headless 冒烟相对已登记基线**无新增 ERROR/WARNING**（基线自带 5 行已知噪声不计）。
- **SC-002**: 行为断言集在重构前后**逐条结论一致**；断言集覆盖界面开关记账、存档存/读/删/列表、设置首启播种与非法值回退，不少于 8 条。
- **SC-003**: 存档读写往返（写入 → 重新载入 → 逐字段比对）在本次改造后仍保持一致，且文件头仍为 `GTSV`。
- **SC-004**: 存档结构版本有变更时，旧版本存档被载入会得到**明确且可区分**的失败原因，0 例出现半读入。
- **SC-005**: `godot-lint.ps1` 无 error 级违规；存量 warn 数量不增加。
- **SC-006**: 事件负载契约的说明与实测行为一致：以两种负载形态各做一次推送，订阅者收到的参数形态 100% 符合约定，0 例嵌套数组。
- **SC-007**: 重构后代码中不存在"一个文件同时承担 3 个以上不相关职责"的模块，且无循环依赖。

## Non-Goals（本次明确不做）

<!--
  必填。本仓库有一批"已知未完成、且刻意不修"的存量（见 AGENTS.md「已知未完成事项」）。
  不写这一节，agent 很容易"顺手修好"它们，把不可评审的改动混进本次 diff。
-->

- **不实现任何新功能**：不接 `CoreSystem.scene_manager` / `state_machine_manager`，不做暂停菜单、游戏流程层、音量或按键重映射。
- **不补全主菜单空按钮**（开始 / 制作人员 / 退出）。
- **不清理 5 个 orphan 翻译键**（属已知存量）。
- **不做 `ui/` 与 `entry/` 的重构**：本次范围仅 `core/` + `save_data/`；`ui/options/options.gd` 里 3 处长节点路径属已知存量，本次不动。
- **不改事件名本身**：允许修正负载契约与说明，但 `Events.*` 的字符串值变更需单独立项。
- **不改 `addons/`**：框架层冻结。
- **不引入单元测试框架**：验证手段仍为引擎运行 + 一次性探针。
- **不做性能优化**：本功能不设帧率目标（无渲染/逻辑热点改动）；若发现热点，只记录不修。
- **不处理 `project.godot` 缺失的 `application/config/version` 与 `[input]` 动作表**（属已知存量，且 `_stamp()` 已对其缺失做了容错）。

## Assumptions

- 目标平台为 Windows 桌面，验证在本机 Godot 4.7.x headless 下进行；引擎路径见 `AGENTS.md`。
- 存档**没有真实用户**（模板尚未发布），因此"允许不兼容"不会影响任何玩家的既有进度——这是本次一次性例外的前提。
- 依赖 `CoreSystem.event_bus` / `save_manager` / `resource_manager` / `logger` 的现有语义，不修改框架层。
- 复用现有 `save_data/` 分段机制与 `OptionsSave.SLOT` 的独立槽位设计，不引入新的设置槽位。
- 本次会同步修订宪法原则 III（**MINOR 级：原要求保留 + 一次性例外**），**并使用**该例外
  （元数据独立成段 `meta`、`SaveData.version` 1 → 2、旧档显式拒绝，用后即尽），
  变更理由与影响记录在 `AGENTS.md` 的「存档系统契约」一节。
- 行为断言以一次性探针脚本承载（`res://_probe_us<N>.gd`），交付前删除；不落成长期测试套件。
