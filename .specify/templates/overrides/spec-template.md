<!--
  项目覆盖层（解析优先级 1）。解析栈见 .specify/scripts/powershell/common.ps1 → Resolve-TemplateContent：
      overrides/  >  presets/<id>/  >  extensions/<id>/  >  templates/（core，受管文件）
  本文件是**整体替换** core 模板，不是在其上追加。由 create-new-feature.ps1:281 经解析器读取。

  core 模板编写时 sha256（用于漂移检测）:
      3945437fc35cd30a5b2bf7beea680337c3516826d3efa5a6b92c4a7eca1ba28e
  若哈希变化，说明上游模板已更新，需人工复核本覆盖层是否需要同步。
-->

# Feature Specification: [FEATURE NAME]

**Feature Branch**: `[###-feature-name]`

**Created**: [DATE]

**Status**: Draft

**Input**: User description: "$ARGUMENTS"

## User Scenarios & Testing *(mandatory)*

<!--
  用户故事 = 玩家（或调用方）旅程，按重要性排序并各自独立可测。
  每条故事 MUST 能在只实现它一个的情况下，交付可演示的价值（MVP 切片）。
  对本项目，"Independent Test" MUST 写成：在引擎里如何复现与观察（命令、按键序列或探针断言），
  禁止写"运行测试套件"这类本仓库不存在的验证方式。
-->

### User Story 1 - [Brief Title] (Priority: P1)

[用平实语言描述这条旅程：玩家在什么界面、做什么操作、得到什么反馈]

**Why this priority**: [价值与优先级理由]

**Independent Test**: [如何在引擎中独立验证，例如："headless 启动主场景并注入 OPEN_UI 事件后，断言界面已进入 ui_dict 并显示 3 个可选项"]

**Acceptance Scenarios**:

1. **Given** [初始状态], **When** [操作], **Then** [预期表现]
2. **Given** [初始状态], **When** [操作], **Then** [预期表现]

---

### User Story 2 - [Brief Title] (Priority: P2)

[描述]

**Why this priority**: [理由]

**Independent Test**: [引擎中的验证方式]

**Acceptance Scenarios**:

1. **Given** [初始状态], **When** [操作], **Then** [预期表现]

---

### User Story 3 - [Brief Title] (Priority: P3)

[描述]

**Why this priority**: [理由]

**Independent Test**: [引擎中的验证方式]

**Acceptance Scenarios**:

1. **Given** [初始状态], **When** [操作], **Then** [预期表现]

---

[按需增加更多用户故事，每条都要有优先级]

### Edge Cases

<!-- 填具体边界情况。游戏项目常见来源：窗口尺寸极端值、语言切换、存档缺失/损坏/版本过旧、
     快速重复点击、暂停中触发、退出时未保存、界面重复打开与关闭、缺翻译键。 -->

- 当 [边界条件] 时会发生什么？
- 系统如何处理 [错误场景]？

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: 系统 MUST [具体能力，例如"允许玩家在设置界面切换分辨率"]
- **FR-002**: 系统 MUST [具体能力，例如"在语言切换后立即刷新可见界面文本"]
- **FR-003**: 玩家 MUST 能够 [关键交互]
- **FR-004**: 系统 MUST [数据要求，例如"将设置持久化到 options 存档槽"]
- **FR-005**: 系统 MUST [行为要求，例如"在存档失败时保持界面可用并提示失败"]

*标记不明确需求的写法：*

- **FR-006**: 系统 MUST 通过 [NEEDS CLARIFICATION: 认证/校验方式未指定]
- **FR-007**: 系统 MUST 保留 [NEEDS CLARIFICATION: 保留时长未指定]

### Localization Requirements *(界面相关功能必填)*

- **LR-001**: 所有新增可见文本 MUST 使用 `ui.*` 翻译键；键清单：[`ui.xxx.yyy` → 中文文案 / English text]
- **LR-002**: 新增键 MUST 同时写入 `locale/en.po`、`locale/zh_CN.po`、`locale/texts.pot`
- **LR-003**: 语言自称名（如 简体中文 / English）MUST NOT 翻译，直接写原文
- **LR-004**: 界面 MUST 响应 `NOTIFICATION_TRANSLATION_CHANGED` 或在语言变更后重建文本

### Persistence Requirements *(涉及存档时必填，否则写 N/A)*

- **PR-001**: 需要落盘的数据：[字段清单]，归属分段：`[XxxSave`（`save_data/`）或 N/A
- **PR-002**: 存档结构是否变更：是/否；若是，`SaveData.version` 提升至 [N]，迁移策略：[描述]
- **PR-003**: 首次运行（无存档）时的默认值来源：[引擎当前状态 / 常量默认值]
- **PR-004**: 存档 MUST 保持纯二进制（魔数 `GTSV` + `var_to_bytes`），MUST NOT 引入对象/脚本引用

### Input Requirements *(涉及操作时必填，否则写 N/A)*

- **IR-001**: 需要新增/修改的 `[input]` 动作：[动作名 → 默认键位]
- **IR-002**: 是否需要运行时可重映射：是/否

### Engine Verification Requirements *(mandatory)*

- **VR-001**: 每条 FR MUST 对应至少一条可执行的引擎验证手段（headless 命令或探针断言）
- **VR-002**: 验证 MUST 覆盖被改动场景"被真实实例化"的路径，MUST NOT 仅静态阅读代码
- **VR-003**: 验证用的一次性脚本 MUST 在交付前删除

### Key Entities *(include if feature involves data)*

- **[Entity 1]**: [它代表什么；关键属性，不含实现细节；若是存档分段，注明所属 `SaveSection` 子类与是否需要 `validate()`]
- **[Entity 2]**: [它代表什么；与其他实体的关系]

## Success Criteria *(mandatory)*

### Measurable Outcomes

<!-- 必须技术无关、可测量。对游戏项目优先用玩家可感知或引擎可观测的指标。 -->

- **SC-001**: [可测指标，例如"设置修改后重新启动游戏，界面显示与生效值与上次一致"]
- **SC-002**: [可测指标，例如"主场景在目标平台稳定 60 fps，切换界面无卡顿超过 100 ms"]
- **SC-003**: [玩家体验指标，例如"首次进入设置界面的玩家能在 30 秒内完成语言切换"]
- **SC-004**: [质量指标，例如"新增功能在 headless 冒烟运行中不产生新的引擎 ERROR"]

## Non-Goals（本次明确不做）

<!--
  必填。本仓库有一批"已知未完成、且刻意不修"的存量（见 AGENTS.md「已知未完成事项」）：
  主菜单空按钮、5 个 orphan 翻译 key、无音量/按键重映射、无暂停菜单、未接 scene_manager 等。
  不写这一节，agent 很容易"顺手修好"它们，把不可评审的改动混进本次 diff。
  同时这也是"下一个游戏项目能否直接复用"这条通用性门的操作化入口。
-->

- [本次不做的能力，例如"不做按键重映射 UI，只登记 `[input]` 动作表"]
- [本次不碰的既有缺陷，例如"不清理 locale 里的 orphan key"]
- [本次不引入的依赖或架构，例如"不接 CoreSystem.scene_manager"]

## Assumptions

- [关于目标玩家/平台的假设，例如"目标平台为 Windows 桌面，键鼠操作，暂不考虑手柄"]
- [关于范围边界的假设，例如"复用现有 options 存档槽，不引入新的设置槽位"]
- [关于数据/环境的假设，例如"依赖 CoreSystem.event_bus 的现有事件语义"]
- [对既有系统/服务的依赖，例如"复用 core/ui_root.gd 现有的 ui_dict 记账，不改其结构"]
