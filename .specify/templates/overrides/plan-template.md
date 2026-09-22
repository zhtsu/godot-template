<!--
  项目覆盖层（解析优先级 1）。解析栈见 .specify/scripts/powershell/common.ps1 → Resolve-TemplateContent：
      overrides/  >  presets/<id>/  >  extensions/<id>/  >  templates/（core，受管文件）
  本文件是**整体替换** core 模板，不是在其上追加。

  core 模板编写时 sha256（用于漂移检测）:
      7e637502d41eccf0ca672496636365691fdca62ef37b27ec07fcb412dbfa90d4
  若 .specify/templates/plan-template.md 的哈希变化，说明上游模板已更新，需人工复核本覆盖层是否需要同步。

  为什么不用 preset 的 append 组合：带 preset.yml 的 preset 在解析时强制要求 Python 3 + PyYAML，
  teammate 机器缺 PyYAML 会让 /speckit-plan 直接报错中断；overrides 层零依赖。
-->

# Implementation Plan: [FEATURE]

**Branch**: `[###-feature-name]` | **Date**: [DATE] | **Spec**: [link]

**Input**: Feature specification from `/specs/[###-feature-name]/spec.md`

**Note**: 本模板由 `/speckit-plan` 填充。所有 `[方括号]` 占位符 MUST 被替换为具体内容，禁止原样保留；确实未知的写 `NEEDS CLARIFICATION`。

## Summary

[从 spec.md 提取：主要需求 + Godot 侧技术方案。3-5 句，不写代码。]

## Technical Context

<!-- 逐项给出具体值。禁止留空、禁止写"按标准做法"。 -->

**Engine/Language**: Godot 4.7 + GDScript（以 `godot --version` 实测为准）

**Renderer/Stretch**: GL Compatibility；拉伸模式 `canvas_items`；基准画布 1152×648（改动 MUST 说明理由）

**Primary Dependencies**: `addons/godot_core_system`（冻结层，MUST NOT 修改；版本号以 `addons/godot_core_system/plugin.cfg` 实测为准）。本功能用到的 CoreSystem 模块（按需保留，删掉不用的）：`event_bus` / `save_manager` / `resource_manager` / `scene_manager` / `audio_manager` / `input_manager` / `config_manager` / `state_machine_manager` / `entity_manager` / `trigger_manager` / `tag_manager` / `time_manager` / `logger`

**Framework Reuse（宪法原则 VI，mandatory）**: 逐条给出本功能的能力 → 复用来源 → 依据。禁止只写"用了插件"。

| 需要的能力 | 复用来源（模块/类 + 调用入口） | 查询依据（读到的文件或方法签名） | 自研？ |
|---|---|---|---|
| [例如：界面切换动画] | `CoreSystem.scene_manager` + `scene_system/transitions/fade_transition.gd` | 读了 `source/scene_system/transitions/` 目录与方法签名 | 否 |
| [例如：XX 能力] | 无 | 在 `addons/godot_core_system/` 按关键词 `<kw>` 检索无命中；`core/` 亦无 | **是** → 已排除候选：[候选方案与排除理由] |

**Scenes & Scripts**: 新增或改动的 `.tscn`/`.gd`，`res://` 全路径。界面 MUST 经 `Events.OPEN_UI` 打开，其路径常量 MUST 登记在 `core/paths.gd`

**Events & Types**: 新增/改动的事件名（`core/events.gd`）与请求/结果结构（`core/types.gd`）。请求型事件 MUST 配对结果事件，订阅方 MUST 处理 `ok == false`

**Autoloads**: 是否新增或改动 autoload（默认不动，`CoreSystem` 由插件注册）。新增 MUST 说明初始化顺序影响

**Persistence**: 是否影响存档。若是，MUST 写清：涉及 `save_data/` 的哪个分段、是否新增分段、`SaveData.version` 是否提升、`migrate()` 迁移策略、首次运行的默认值来源（引擎状态还是常量）

**Localization**: 新增/改动的翻译键清单（`ui.*` 形式），并确认 `locale/en.po`、`locale/zh_CN.po`、`locale/texts.pot` 三处同步

**Input**: 是否改动 `project.godot` 的 `[input]` 动作表；动作名与默认键位

**Verification Approach**: 本仓库无单元测试框架 → 验证手段为 headless 引擎运行 + 一次性探针脚本（详见 Verification Plan）

**Target Platform**: [例如 Windows desktop（最低 Windows 10）/ Web / Android；给出最低目标]

**Performance Goals**: [例如 稳定 60 fps；界面切换 ≤ 100 ms；同屏节点 ≤ N]

**Constraints**: [例如 单槽存档 ≤ 8 MB；离线可玩；不改 `addons/`]

**Scale/Scope**: [例如 新增 1 个场景 + 2 个脚本 + 3 个翻译键]

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| 原则 | 本功能的落实方式（写具体证据，不写口号） | 结论 |
|------|------------------------------------------|------|
| I. 约定集中化 | 新增路径/事件/结构体分别登记在 `core/paths.gd`、`core/events.gd`、`core/types.gd`；场景与脚本内无硬编码路径或事件字符串 | PASS / FAIL |
| II. UI 与模块只经事件总线 | 界面只经 `Events.OPEN_UI`/`Events.CLOSE_UI`；不直接 `instantiate()`/`queue_free()`；跨模块只发事件；请求-结果配对且处理失败 | PASS / FAIL |
| III. 存档纯二进制、不可承载逻辑 | 分段继承 `SaveSection`；只放基础类型；无 `Object`/`Callable`/`Signal`/`RID`；版本与迁移已说明；写入原子 | PASS / FAIL |
| IV. 用户文本全走翻译键 | 键清单已列；`en.po`/`zh_CN.po`/`texts.pot` 三处同步 | PASS / FAIL |
| V. 改动必须经引擎验证 | Verification Plan 给出可执行命令与可观测判据 | PASS / FAIL |
| VI. 优先复用框架层已有能力 | Framework Reuse 一节给出查询方式、依据模块与调用入口；自研项已列出排除的框架层候选与理由 | PASS / FAIL |
| VII. Git 只读 | 只用 `git status`/`diff`/`log`/`ls-files` 等只读查询；没有任何改变仓库状态的 git 操作；需要提交时只列建议命令，交由人类执行 | PASS / FAIL |

任一项 FAIL MUST 在 Complexity Tracking 中给出理由，或修改方案直至 PASS。禁止带着 FAIL 进入实现阶段。

## Project Structure

### Documentation (this feature)

```text
specs/[###-feature]/
├── plan.md              # 本文件（/speckit-plan 输出）
├── research.md          # Phase 0 输出（/speckit-plan）
├── data-model.md        # Phase 1 输出（/speckit-plan）
├── quickstart.md        # Phase 1 输出（/speckit-plan）
├── contracts/           # Phase 1 输出（/speckit-plan）
└── tasks.md             # Phase 2 输出（/speckit-tasks 生成，非 /speckit-plan）
```

### Source Code (repository root)

<!-- 使用本仓库真实布局。MUST NOT 保留与 Godot 无关的示例树（src/、backend/、frontend/、ios/ 等）。 -->

```text
entry/                       # 启动：main.tscn + main.gd
core/                        # 约定与服务层
├── paths.gd                 # 所有 res:// 路径常量（Paths）
├── events.gd                # 所有事件名（Events）
├── types.gd                 # 请求/结果结构体（Types）
├── options_data.gd          # 设置候选值表（分辨率/语言）
├── ui_root.gd + .tscn       # UI 实例化、分层、记账
└── save_service.gd + .tscn  # 存档服务（事件驱动）
save_data/                   # 存档结构，每分段一个类，继承 SaveSection
├── save_section.gd          # 基类
├── save_data.gd             # 根（SaveData，含 version/migrate）
└── options_save.gd          # 设置分段（分辨率/语言）
ui/<screen>/                 # 每界面一目录：<screen>.tscn + <screen>.gd
locale/                      # en.po / zh_CN.po / texts.pot
addons/godot_core_system/    # 冻结框架层，MUST NOT 修改
specs/[###-feature]/         # 本功能的规格与计划产物
```

本功能新增/改动的文件（逐条列出，`res://` 全路径）：

- `res://[路径]`（新增）：[用途]
- `res://[路径]`（改动）：[改动点]

**Structure Decision**: [说明为何落在上述目录。若需新增顶层目录，给出理由，并说明是否同步更新 `AGENTS.md` 的目录速查]

## Verification Plan

<!-- 宪法原则 V：非平凡改动 MUST 经真实引擎运行验证。本节写清"怎么证明做完了"。 -->

**工具链**：**命令清单与基线语义的唯一权威在 `AGENTS.md` 的「验证」一节**，本节不重复抄写。
要点只有两条：

- 用仓库自带的 `.specify/scripts/powershell/godot-lint.ps1`（静态门禁）与 `verify-engine.ps1`（引擎验证 + 基线 diff）；
  两者都自己定位引擎，**不要写裸 `godot`**（它不在 PATH 上）。
- 基线语义：主场景冒烟本身稳定输出 5 行 ERROR/WARNING 而退出码仍为 0，
  所以判据 **MUST NOT** 写成"退出码 0 且没有 ERROR"，**MUST** 写成"相对
  `.specify/godot-verify-baseline.json` 无新增行"。

注意：新增或改名的 `class_name` 会让全局类缓存过期，先执行 `$godot --headless --path . --import`。
涉及节点的断言 MUST 等 ≥2 帧再检查。

**验收判据**（可观测、可复现、逐条勾选）：

- [ ] `godot-lint.ps1` 无 error 级违规（warn 为存量，不阻断但需说明是否有意新增）
- [ ] `verify-engine.ps1` 退出码 0，且相对基线**无新增** ERROR/WARNING（不是"没有 ERROR"）
- [ ] **回归验证**：除被改动场景外，主场景冒烟 MUST 一并复跑并与基线 diff（防止改动破坏既有链路）
- [ ] [具体断言，例如：打开界面后 `UiRoot` 的 `ui_dict` 中出现 `Paths.UI_XXX`，关闭后条目被清除]
- [ ] [存档相关，例如：写入后文件首 4 字节为 `GTSV`，重新载入后字段值与写入前一致]
- [ ] [本地化相关，例如：切换 locale 后界面文本随 `NOTIFICATION_TRANSLATION_CHANGED` 刷新，无残留旧语言文本]

**证据落盘**：命令 + 原始输出要点 + 判据结论 MUST 写入 `specs/[###-feature]/verification.md`，
MUST NOT 只在对话里声称"已通过"。

**收尾**：删除全部 `_probe*.gd` 等临时资源，用 `git status`（只读查询，宪法原则 VII 允许）或
`godot-lint.ps1` 的 `temp_files` 规则确认无残留。**MUST NOT 自行提交/暂存**；需要提交时只在报告中
给出建议命令与原因。

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| [例如：新增一个顶层目录] | [为什么必须] | [为什么不能复用现有目录] |
| [例如：修改框架层 `addons/`] | [为什么必须] | [为什么无法在项目层解决] |
