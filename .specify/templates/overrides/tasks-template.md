<!--
  项目覆盖层（解析优先级 1）。解析栈见 .specify/scripts/powershell/common.ps1 → Resolve-TemplateContent：
      overrides/  >  presets/<id>/  >  extensions/<id>/  >  templates/（core，受管文件）
  本文件是**整体替换** core 模板，不是在其上追加。由 setup-tasks.ps1:59-60 经解析器读取。

  core 模板编写时 sha256（用于漂移检测）:
      fc29a233f6f5a27ca31f1aa46b596af6500c627441c6e62b2bc4a1d721525842
  若哈希变化，说明上游模板已更新，需人工复核本覆盖层是否需要同步。
-->

---

description: "Task list template for feature implementation"
---

# Tasks: [FEATURE NAME]

**Input**: Design documents from `/specs/[###-feature-name]/`

**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md, contracts/

**Verification**: 本仓库没有单元测试框架。宪法原则 V 规定：非平凡改动 MUST 经真实引擎验证。因此每条用户故事都 MUST 包含"引擎验证"任务，且 MUST NOT 被当作可选项跳过。验证手段是 headless 引擎运行与一次性探针脚本，不是单元测试。

**命令与基线语义不在此重复**：见 `AGENTS.md` 的「验证」一节（唯一权威）与 plan.md 的 Verification Plan。
用仓库自带的 `.specify/scripts/powershell/godot-lint.ps1` 与 `verify-engine.ps1`，**不要写裸 `godot`**（它不在 PATH 上）。

**组织**: 任务按用户故事分组，使每条故事可独立实现、独立验证、独立交付。

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

所有路径都是仓库根（`godot-template/`）下的 Godot 资源路径，任务描述里 MUST 写 `res://` 全路径：

- 约定层：`res://core/`（`paths.gd` 路径常量、`events.gd` 事件名、`types.gd` 结构体、`options_data.gd` 候选值）
- 存档结构：`res://save_data/`（每分段一个类，继承 `SaveSection`；新分段还要在 `save_data.gd` 注册一行）
- 界面：`res://ui/<screen>/`（`<screen>.tscn` + `<screen>.gd`），打开/关闭只经事件
- 翻译：`res://locale/`（`en.po`、`zh_CN.po`、`texts.pot` 三处同步）
- 启动：`res://entry/`；框架层 `res://addons/godot_core_system/` MUST NOT 出现在任何任务的改动范围里
- 规格产物：`specs/[###-feature-name]/`

<!--
  ============================================================================
  IMPORTANT: 下面的任务是示例，只用于说明粒度与格式。

  /speckit-tasks MUST 依据以下输入替换为真实任务：
  - spec.md 中的用户故事（含 P1/P2/P3 优先级）
  - plan.md 中的技术方案与 Verification Plan
  - data-model.md 中的实体（对应存档分段）
  - contracts/ 中的接口约定（对应事件名与结构体）

  任务 MUST 按用户故事组织，使每条故事可独立实现、独立验证、独立交付。

  DO NOT keep these sample tasks in the generated tasks.md file.
  ============================================================================
-->

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: 前置准备与结构确认，不产生玩法行为

- [ ] T001 在 `res://core/paths.gd` 登记本功能涉及的界面路径常量
- [ ] T002 在 `res://core/events.gd` 登记新增事件名，在 `res://core/types.gd` 定义请求/结果结构体
- [ ] T003 [P] 在 `res://locale/` 三处（`en.po`、`zh_CN.po`、`texts.pot`）同步新增翻译键
- [ ] T003b 跑 `.specify/scripts/powershell/godot-lint.ps1` 确认起点无 error 级违规（warn 为存量，不修）

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: 所有用户故事共同依赖的基础设施，未完成前 MUST NOT 开始任何故事

**⚠️ CRITICAL**: 本阶段完成前，任何用户故事都不得动工

- [ ] T004 在 `res://save_data/` 新增/扩展分段类并在 `save_data.gd` 注册（若本功能不涉及存档则标注 N/A 并说明）
- [ ] T005 [P] 在 `res://ui/<screen>/` 建立界面场景与脚本骨架，确认可经 `Events.OPEN_UI` 打开
- [ ] T006 [P] 接通 `CoreSystem` 所需模块（`event_bus` / `save_manager` / `input_manager` 等），不新增 autoload
- [ ] T007 确认改动未触碰 `res://addons/godot_core_system/`（若必须触碰，先更新 plan.md 的 Complexity Tracking）

**Checkpoint**: 基础设施就绪，用户故事可以并行开始

---

## Phase 3: User Story 1 - [Title] (Priority: P1) 🎯 MVP

**Goal**: [这条故事交付什么]

**Independent Test**: [如何在引擎中独立验证]

### Verification for User Story 1 (MANDATORY - 引擎验证，非单元测试) ⚠️

> **NOTE: 先写验证手段，再写实现。验证 MUST 在实现前处于失败状态（复现问题或断言缺失功能）**

- [ ] T008 [P] [US1] 编写一次性探针脚本 `res://_probe_us1.gd`（`extends SceneTree`）断言 [具体行为]
- [ ] T009 [US1] 运行 `.specify/scripts/powershell/verify-engine.ps1 -Probe res://_probe_us1.gd` 并记录失败输出作为起点

### Implementation for User Story 1

- [ ] T010 [P] [US1] 在 `res://ui/<screen>/<screen>.gd` 实现 [具体行为]
- [ ] T011 [US1] 在 `res://ui/<screen>/<screen>.tscn` 绑定信号与 `%唯一名` 引用（避免长节点路径）
- [ ] T012 [US1] 通过事件发出请求并在结果事件中处理 `ok == false`
- [ ] T013 [US1] 补齐 `res://locale/` 三处翻译键并验证语言切换后文本刷新
- [ ] T014 [US1] 运行 `.specify/scripts/powershell/verify-engine.ps1 -Scenario res://ui/<screen>/<screen>.tscn`，确认相对基线无新增 ERROR/WARNING
- [ ] T015 [US1] 删除 `res://_probe_us1.gd`，用 `git status`（只读）确认无临时文件残留

**Checkpoint**: 用户故事 1 可独立运行、独立验证

---

## Phase 4: User Story 2 - [Title] (Priority: P2)

**Goal**: [这条故事交付什么]

**Independent Test**: [如何在引擎中独立验证]

### Verification for User Story 2 (MANDATORY) ⚠️

- [ ] T016 [P] [US2] 编写探针脚本 `res://_probe_us2.gd` 断言 [具体行为]
- [ ] T017 [US2] 运行探针确认失败，再进入实现

### Implementation for User Story 2

- [ ] T018 [P] [US2] 在 `res://[路径]` 实现 [具体行为]
- [ ] T019 [US2] 与用户故事 1 的组件集成（若需要），确认不破坏 US1 的独立验证
- [ ] T020 [US2] 留存存档兼容性证据（写入后重载值一致；如涉及版本提升，验证旧档迁移）
- [ ] T021 [US2] 删除探针脚本，`git status`（只读）确认干净

**Checkpoint**: 用户故事 1 与 2 均可独立工作

---

## Phase 5: User Story 3 - [Title] (Priority: P3)

**Goal**: [这条故事交付什么]

**Independent Test**: [如何在引擎中独立验证]

### Verification for User Story 3 (MANDATORY) ⚠️

- [ ] T022 [P] [US3] 编写探针脚本 `res://_probe_us3.gd` 断言 [具体行为]
- [ ] T023 [US3] 运行探针确认失败，再进入实现

### Implementation for User Story 3

- [ ] T024 [P] [US3] 在 `res://[路径]` 实现 [具体行为]
- [ ] T025 [US3] 运行目标场景 headless 冒烟并记录输出
- [ ] T026 [US3] 删除探针脚本，`git status`（只读）确认干净

**Checkpoint**: 三条故事均可独立运行

---

[按需增加更多用户故事阶段，保持同一模式]

---

## Phase N: Polish & Cross-Cutting Concerns

**Purpose**: 影响多条故事的收尾工作

- [ ] TXXX [P] 更新 `AGENTS.md` 的目录速查与"已知未完成事项"（若本功能改变了目录结构或约定）
- [ ] TXXX [P] 复查 `res://locale/` 是否存在本次新增的 orphan key（加了没用到的键）
- [ ] TXXX 清理临时资源与探针脚本，用 `git status`（只读查询，允许）确认只剩预期改动的文件；MUST NOT 自行提交/暂存
- [ ] TXXX 跑 `.specify/scripts/powershell/godot-lint.ps1`，确认无 error 级违规（warn 是存量）
- [ ] TXXX 跑 `.specify/scripts/powershell/verify-engine.ps1` 主场景冒烟，确认相对基线无新增 ERROR/WARNING（基线自带日志/证书/泄漏噪声，不是回归）
- [ ] TXXX 逐条勾选 plan.md 的 Verification Plan 判据，并把命令 + 输出要点写入 `specs/[###-feature-name]/verification.md`
- [ ] TXXX 运行 `/speckit-converge` 复核代码与规格的差距，把未落地项补回本文件

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: 无依赖，可立即开始
- **Foundational (Phase 2)**: 依赖 Setup 完成，阻塞所有用户故事
- **User Stories (Phase 3+)**: 依赖 Foundational 完成，之后可并行或按 P1 → P2 → P3 顺序推进
- **Polish (最终阶段)**: 依赖所有目标故事完成

### User Story Dependencies

- **User Story 1 (P1)**: Foundational 完成后即可开始，不依赖其他故事
- **User Story 2 (P2)**: Foundational 完成后即可开始；可与 US1 集成，但 MUST 保持可独立验证
- **User Story 3 (P3)**: 同上

### Within Each User Story

- 验证手段 MUST 先于实现存在，且先观察到失败
- 约定层（`core/`）先于业务层，业务层先于界面绑定
- 存档结构变更先于依赖它的功能
- 每条故事完成后 MUST 清理自己的探针脚本

### Parallel Opportunities

- Setup 阶段所有 [P] 任务可并行
- Foundational 阶段 [P] 任务可并行（同属 Phase 2 时）
- Foundational 完成后各用户故事可并行
- 同一故事内不同文件的 [P] 任务可并行

---

## Parallel Example: User Story 1

```text
# 同一故事中可并行的任务（不同文件、无依赖）：
Task: "在 res://ui/<screen>/<screen>.gd 实现 [行为]"
Task: "在 res://locale/ 三处补齐翻译键"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. 完成 Phase 1: Setup
2. 完成 Phase 2: Foundational（关键，阻塞所有故事）
3. 完成 Phase 3: User Story 1
4. **STOP and VALIDATE**: 用探针与 headless 命令独立验证 US1
5. 判据全绿后再继续

### Incremental Delivery

1. Setup + Foundational → 基础就绪
2. 加入 US1 → 引擎验证 → 可演示（MVP）
3. 加入 US2 → 引擎验证 → 可演示
4. 加入 US3 → 引擎验证 → 可演示
5. 每条故事都 MUST 在加入下一条之前保持可独立验证

### Parallel Team Strategy

多人协作时：

1. 共同完成 Setup + Foundational
2. Foundational 完成后：开发者 A 做 US1，B 做 US2，C 做 US3
3. 各自独立验证后集成

---

## Notes

- [P] 任务 = 不同文件、无相互依赖
- [Story] 标签用于把任务追溯到具体用户故事
- 每条用户故事 MUST 可独立完成与独立验证
- 验证 MUST 在真实引擎中进行；"代码看起来对"不构成完成依据
- `res://addons/godot_core_system/` MUST NOT 出现在任何任务的改动范围里
- 新增/改名的 `class_name` 需要先跑 `godot --headless --path . --import`
- 每个任务或逻辑分组完成后提交；提交前确认无探针脚本残留
- 避免：模糊任务、同一文件冲突、破坏故事独立性的跨故事依赖
