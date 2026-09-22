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

# Implementation Plan: core/ 与 save_data/ 审查重构

**Branch**: `001-core-save-refactor` | **Date**: 2026-09-23 | **Spec**: `specs/001-core-save-refactor/spec.md`

**Input**: Feature specification from `/specs/001-core-save-refactor/spec.md`

**Note**: 本模板由 `/speckit-plan` 填充。所有 `[方括号]` 占位符 MUST 被替换为具体内容，禁止原样保留；确实未知的写 `NEEDS CLARIFICATION`。

## Summary

对 `core/` 与 `save_data/` 做一次以**行为可验证**为前提的审查重构。核心内容三块：
(1) 在改动前先固化引擎基线 + 行为断言集，使"没坏"可判定（FR-001/VR-004）；
(2) 修正两处已确认缺陷——事件负载契约的文档与实现相反、`apply_dict()` 无类型校验；
(3) 把 `save_service.gd`（463 行、七种职责）中的**纯函数部分**抽到独立文件，状态与事件驱动部分留在原类。
同时按 US4 对宪法原则 III 追加**一次性例外**（原要求保留）：允许存档格式不兼容，但**只允许一次**且必须显式记录版本。
**本次使用该例外**：元数据独立成段 `meta`、`SaveData.version` 1 → 2、旧档显式拒绝（用后即尽）。

## Technical Context

**Engine/Language**: Godot 4.7.2.stable（实测 `Godot_v4.7.2-stable_win64_console.exe`）+ GDScript

**Renderer/Stretch**: GL Compatibility；拉伸模式 `canvas_items`；基准画布 1152×648（本功能不改动）

**Primary Dependencies**: `addons/godot_core_system` v0.0.1（冻结层，MUST NOT 修改）。本功能实际依赖的模块：
`event_bus`（订阅与派发语义，US2 的核心）、`logger`（告警可观测性）、`save_manager`（仅取其 `save_directory` 设置）、
`resource_manager`（`ui_root` 加载场景）。其余 9 个模块本功能不涉及。

**Framework Reuse（宪法原则 VI，mandatory）**

| 需要的能力 | 复用来源（模块/类 + 调用入口） | 查询依据（读到的文件或方法签名） | 自研？ |
|---|---|---|---|
| 事件订阅/派发与优先级 | `CoreSystem.event_bus`（`subscribe_unique_script` / `unsubscribe` / `push_event`） | 读 `source/event_system/event_bus.gd:30-32,86-90`（`push_event` 的 payload 归一化与 `callv`） | 否 |
| 存档目录来源 | `CoreSystem.save_manager.save_directory` | 读 `source/core_system.gd:68` 暴露的 `save_manager`；现有 `save_service.gd:57` 已在用 | 否 |
| 场景加载 | `CoreSystem.resource_manager.load_resource()` | 读 `source/core_system.gd:33`；现有 `ui_root.gd:33` 已在用 | 否 |
| 分帧/异步 IO 工具 | `AsyncIOManager` / `FrameSplitter`（`CoreSystem` 直接暴露） | 读 `core_system.gd:20,24` 的工具类清单 | **否（但本次不引入）**——见下方说明 |

> **关于存档写入未复用框架能力的说明（宪法原则 VI 要求给出排除理由）**：
> 框架 `save_manager` 的数据来源固定为「saveable 节点组 + `save()`」、落盘结构固定为 `{metadata, nodes}`，
> 无法承载项目自定义的 `SaveSection` 分段结构（`save_service.gd:20-21` 已记录该结论）。
> 候选方案与排除理由：
> - `save_manager.create_save()` → **排除**：结构与数据来源均不可定制，会丢弃分段模型。
> - `save_system/save_format_strategy/binary_save_strategy.gd` → **排除**：它是 `save_manager` 的格式策略，
>   仍受其数据结构约束；且为框架层内部实现，直接调用属跨层耦合（宪法原则 II）。
> - `AsyncIOManager`（异步写盘）→ **排除（本次）**：引入异步会让"写入成功后立即应用设置"的时序从
>   "同帧确定"变成"需等待"，改变 FR-002 保护的可观测行为。仅记录为将来候选，本次不动。
> 结论：继续在项目层持有自定义二进制格式，但 MUST 保持 `AGENTS.md` 的存档契约不变（FR-007/PR-004）。

**Scenes & Scripts**: 改动集中在 `res://core/save_service.gd`、`res://save_data/save_section.gd`、
`res://core/events.gd`（仅注释）、新文件见 Project Structure。`res://core/ui_root.gd` 预期**不改**
（其逻辑经审查未发现缺陷；若实现阶段发现必要改动，属 FR-002 保护范围的例外，需在证据中说明）。

**Events & Types**: 事件名与结构体字段**全部不变**（Non-Goals 明确排除改事件名）。
本功能只修正 **payload 形态的语义说明**，并补一个此前没有的契约：见 `contracts/event-payload-contract.md`。

**Autoloads**: 不新增、不改动 autoload。

**Persistence**: **影响存档代码，并执行一次不兼容的存档结构变更（`version` 1 → 2）。**

四项待修内容（事件 payload 契约、`apply_dict` 类型校验、`save_service` 职责拆分、版本策略）中，
前两项不涉及落盘字段；**结构变更来自用户的显式裁定**（spec `PR-002` 的契约本就是"结构变更 = 是"，
`research.md` R4 的初稿结论"不变更"已被撤销）。因此：

- **变更内容（不新增字段，只调整分段组织，符合 `PR-001`）**：根上平铺的
  `slot` / `saved_at` / `game_version` / `playtime` 移入新分段 `meta`（`MetaSave`，新文件
  `save_data/meta_save.gd`）；根上只剩 `version` + 各分段。
- `SaveData.version` **1 → 2**。版本号与结构真实对应：这次确实改了落盘字典的形状。
- `migrate()` 改为**显式拒绝**（返回 `{}`）：本次援引宪法原则 III 的**一次性例外**，
  迁移路径 MAY 省略；目标集合为空（无真实旧档），写迁移无法被真实数据验证（research.md R4）。
  拒绝 MUST 给出**可区分**的原因，且 MUST NOT 半读入（FR-006 / SCR-7）。
- **对外契约不变（FR-002）**：`metadata()` 仍返回同一组平铺键（`version` / `slot` / `saved_at` /
  `game_version` / `playtime`，值取自 `meta`）；事件名、请求/结果字段、共享单对象语义、读档原地更新
  语义全部不变。变的只是**磁盘字典结构与内存字段路径**（`save_data.slot` → `save_data.meta.slot`）。
- **例外用尽**：本次使用后，原则 III 恢复为"提升版本 **并提供迁移路径**"的完整要求；
  MUST NOT 再以同一条例外为由省略迁移。

首次运行默认值来源不变（当前引擎状态）。

**Localization**: 不新增翻译键。**不清理**存量 5 个 orphan key（Non-Goals）。

**Input**: 不改 `project.godot` 的 `[input]` 动作表。

**Verification Approach**: 本仓库无单元测试框架 → headless 引擎运行（`verify-engine.ps1`，基线 diff）+
一次性探针脚本（`res://_probe_us<N>.gd`）。**基线已于 2026-09-23 在改动前采集并验证无新增**（FR-001 已满足）。

**Target Platform**: Windows desktop（最低 Windows 10），与模板既有目标一致

**Performance Goals**: N/A —— spec 的 Non-Goals 明确不做性能优化，且本功能不触碰渲染/逻辑热点。
不设帧预算，避免出现"无法测量却要求勾选"的假判据。

**Constraints**: 不改 `addons/`；不新增翻译键；不引入测试框架；`save_service.gd` 的对外事件接口不变；
无真实用户存档，故**使用**一次性不兼容例外（本次用后即尽）。

**Scale/Scope**: 代码：改 3 个既有文件（`core/save_service.gd`、`save_data/save_section.gd`、
`save_data/save_data.gd`）+ 新增 3 个文件（`core/save_storage.gd`、`core/options_applier.gd`、
`save_data/meta_save.gd`）+ 改 1 处注释（`core/events.gd`）+ 删除 0 个。
文档：`AGENTS.md`、宪法原则 III、`verification.md`。**执行一次不兼容结构变更**（元数据独立成段 `meta`，
`version` 1 → 2，旧档显式拒绝）。

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| 原则 | 本功能的落实方式（写具体证据，不写口号） | 结论 |
|------|------------------------------------------|------|
| I. 约定集中化 | 不新增 `res://` 字面量与事件名字符串；新文件只经 `Paths`/`Events`/`Types` 引用既有常量。`godot-lint` 的 `paths`/`events` 规则为 error 级门禁 | PASS |
| II. UI 与模块只经事件总线 | 不改 `ui_root.gd` 的开关机制，不新增直接 `instantiate()`/`queue_free()`；新抽出的 `save_storage` / `options_applier` **不持事件订阅**，只被 `save_service` 调用，不引入跨模块直接引用 | PASS |
| III. 存档纯二进制、不可承载逻辑 | 全部保持：魔数 `GTSV`、`var_to_bytes`/`bytes_to_var`、只允许基础类型、每段一类、原子写入、`apply_dict` 分段不得被非字典值清空。**本次执行一次不兼容结构变更**（元数据独立成段 `meta`，`SaveData.version` 1 → 2，旧档显式拒绝、无半读入），并援引本条的一次性例外（原要求保留、例外用后即尽，见 Complexity Tracking） | PASS |
| IV. 用户文本全走翻译键 | 不新增可见文本、不新增翻译键；已确认不清理 5 个存量 orphan key | PASS |
| V. 改动必须经引擎验证 | 基线已在改动前采集（`verify-engine.ps1` 报"无新增 ERROR/WARNING"）；`verification.md` 记录命令+输出要点+结论；探针按故事编号并在交付前删除 | PASS |
| VI. 优先复用框架层已有能力 | Technical Context 的 Framework Reuse 表逐项给出复用来源与依据；存档写入给出 3 个候选方案的排除理由 | PASS |
| VII. Git 只读 | 全程只用 `git status`（只读）确认残留；不执行任何改变仓库状态的操作 | PASS |

任一项 FAIL MUST 在 Complexity Tracking 中给出理由，或修改方案直至 PASS。禁止带着 FAIL 进入实现阶段。

## Project Structure

### Documentation (this feature)

```text
specs/001-core-save-refactor/
├── plan.md                          # 本文件
├── spec.md                          # 规格
├── research.md                      # Phase 0 输出：两处缺陷的技术裁决
├── data-model.md                    # Phase 1 输出：存档实体与校验规则
├── quickstart.md                    # Phase 1 输出：验证剧本（可复制执行）
├── contracts/
│   ├── event-payload-contract.md    # 事件负载形态契约（US2 的产出）
│   └── save-file-format.md          # 存档文件格式契约（含 v1→v2 变更）
├── checklists/requirements.md       # 规格质量清单
├── verification.md                  # 证据台账（实现阶段产出）
└── tasks.md                         # 由 /speckit-tasks 生成
```

### Source Code (repository root)

```text
entry/                       # 启动：main.tscn + main.gd（本次不改）
core/                        # 约定与服务层
├── paths.gd                 # 路径常量（不改）
├── events.gd                # 事件名（仅改注释：补 payload 形态说明）
├── types.gd                 # 请求/结果结构体（不改，字段属 FR-002 保护范围）
├── options_data.gd          # 设置候选值表（不改）
├── ui_root.gd + .tscn       # UI 实例化/分层/记账（预期不改）
├── save_service.gd + .tscn  # 存档服务：保留状态、事件订阅、任务队列、对外接口
├── save_storage.gd          # 【新增】纯文件 IO：魔数/长度/槽位校验、原子写、目录枚举
└── options_applier.gd       # 【新增】纯引擎状态应用：set_locale / window_set_size / 全屏
save_data/                   # 存档结构
├── save_section.gd          # 基类（改：apply_dict 增加类型兼容校验）
├── save_data.gd             # 根（**改**：version 1 → 2、元数据移入 meta 段、migrate() 改显式拒绝）
├── meta_save.gd             # 【新增】元数据分段：slot / saved_at / game_version / playtime
└── options_save.gd          # 设置分段（不改）
locale/                      # en.po / zh_CN.po / texts.pot（不改）
addons/godot_core_system/    # 冻结框架层，MUST NOT 修改
```

本功能新增/改动的文件（逐条列出，`res://` 全路径）：

- `res://core/save_storage.gd`（新增）：承载"纯文件 IO"职责 —— 路径拼接、魔数/长度/槽位名校验、
  原子写（临时文件 + 改名）、目录枚举。**不持有存档数据、不订阅事件、不依赖 `SaveData`**。
- `res://core/options_applier.gd`（新增）：承载"把设置应用到引擎"职责 —— 语言、分辨率、全屏模式。
  **纯函数式，不持状态**。
- `res://core/save_service.gd`（改动）：删除已抽出的实现，改为委派；保留事件订阅、任务队列、
  存档数据所有权、结果事件组装与对外语义；元数据字段路径改到 `save_data.meta.*`（结构变更，见下）。
- `res://save_data/save_section.gd`（改动）：`apply_dict()` 增加类型兼容校验（FR-004）。
- `res://save_data/meta_save.gd`（新增）：元数据分段 `MetaSave`，承载 `slot` / `saved_at` /
  `game_version` / `playtime`（**既有字段搬家，不新增字段**）。**本次唯一新增的 `class_name`**。
- `res://save_data/save_data.gd`（改动）：`version` 1 → 2；根上元数据字段移入 `meta` 段；
  `metadata()` 对外键**不变**；`migrate()` 改为显式拒绝（FR-005 / FR-006）。
- `res://core/events.gd`（改动）：仅补注释，说明 payload 的真实形态（FR-003）。
- `AGENTS.md`（改动）：修正硬规则 4 的反向描述；补充本次不兼容变更（元数据成段、`version` 1 → 2、
  旧档显式拒绝）与"一次性例外已用尽"的存档契约说明（PR-005）。
- `.specify/memory/constitution.md`（改动）：为原则 III 追加**一次性例外**（原要求保留；
  **MINOR 级修订 1.3.1 → 1.4.0**），该例外**由本功能使用后用尽**。
- `specs/001-core-save-refactor/verification.md`（新增）：证据台账。

**Structure Decision**: 全部落在既有目录内，**不新增顶层目录**。
抽出的两个文件放在 `core/` 而非新建子目录，因为本仓库 `core/` 现有约定就是"约定 + 服务"平铺
（`paths.gd`/`events.gd`/`save_service.gd` 均平铺），新增子目录会与既有约定不一致，
且宪法「目录契约」要求新增顶层目录必须说明理由 —— 本次没有必要付这个代价。
两个新类**不加 `class_name`**，改用 `preload` 常量引用（与 `core_system.gd` 引用模块的方式一致），
避免污染全局类缓存、也避免 `--import` 依赖。

## Verification Plan

**工具链**：**命令清单与基线语义的唯一权威在 `AGENTS.md` 的「验证」一节**，本节不重复抄写。
要点只有两条：

- 用仓库自带的 `.specify/scripts/powershell/godot-lint.ps1`（静态门禁）与 `verify-engine.ps1`（引擎验证 + 基线 diff）；
  两者都自己定位引擎，**不要写裸 `godot`**（它不在 PATH 上）。
- 基线语义：主场景冒烟本身稳定输出 5 行 ERROR/WARNING 而退出码仍为 0，
  所以判据 **MUST NOT** 写成"退出码 0 且没有 ERROR"，**MUST** 写成"相对
  `.specify/godot-verify-baseline.json` 无新增行"。

注意：新增或改名的 `class_name` 会让全局类缓存过期，先执行 `$godot --headless --path . --import`。
本计划**新增 1 个 `class_name`（`MetaSave`，T037）**，因此引擎验证前 MUST 先 `--import`。
涉及节点的断言 MUST 等 ≥2 帧再检查。

**验收判据**（可观测、可复现、逐条勾选）：

- [ ] `godot-lint.ps1` 无 error 级违规（warn 为存量，不阻断但需说明是否有意新增）
- [ ] `verify-engine.ps1` 退出码 0，且相对基线**无新增** ERROR/WARNING（不是"没有 ERROR"）
- [ ] **回归验证**：除被改动场景外，主场景冒烟 MUST 一并复跑并与基线 diff（防止改动破坏既有链路）
- [ ] SCR-1（对应 SC-002）探针断言 `ui_dict`：经 `OPEN_UI` 打开后进入记账，`CLOSE_UI` 后条目被清除
- [ ] SCR-2（对应 SC-002/SC-003）探针断言存档往返：写入后文件首 4 字节为 `GTSV`，重新载入字段值与写入前一致；
      且落盘根键为 `version` / `meta`（+ `options`）、`version == 2`（v2 结构真实生效）
- [ ] SCR-3（对应 SC-002）探针断言设置档首启播种：无 `options.sav` 时，设置值等于当前引擎状态
- [ ] SCR-4（对应 SC-002）探针断言存档列表排除设置档，且 `SAVE_LIST_READY` 收到的是**数组本身**而非嵌套数组
- [ ] SCR-5（对应 SC-006）探针两种负载形态各推送一次：非数组 → 订阅者收到该对象；数组 → 订阅者收到该数组本身
- [ ] SCR-6（对应 FR-004）探针用类型错误的补丁：字段未被写成错误类型，且有可观测告警
- [ ] SCR-7a（对应 SC-004/FR-006）探针构造 v1 旧档（`version == 1`）：载入得到明确失败
      （`ok=false`、`error` 可区分：结构版本过旧 / 不提供迁移）且无半读入
- [ ] SCR-7b（对应 SC-004）探针构造 `version > 2` 的存档：被拒绝（既有保护，MUST 保持）
- [ ] SCR-8（对应 FR-007）探针断言非法槽位名被拒绝、`..` 不产生路径穿越
- [ ] SCR-9（对应 FR-007）探针断言原子性：写入后不残留 `.tmp`
- [ ] SCR-10（对应 FR-002）探针断言 `ui_layer` 传未知值时仍入树（按 MIDDLE 处理）

**本次预期的一次性基线扰动（必须解释，不得当作噪声）**：本机 `user://saves/options.sav` 目前是
v1 存档（`C:\Users\<user>\AppData\Roaming\Godot\app_userdata\godot-template\saves\options.sav`）。
结构提升到 v2 后，它会被**显式拒绝**，启动时改为按当前引擎状态重新播种设置 —— 这会在主场景冒烟中
新增与"结构版本过旧 / 设置重新播种"相关的日志行。处理方式：先确认新行确由该变更引起且理由成立，
再由人类确认后用 `verify-engine.ps1 -UpdateBaseline` 重登基线，并在 `verification.md` 记录
"基线为何变化"（宪法原则 V 要求基线变化 MUST 说明）。

**证据落盘**：命令 + 原始输出要点 + 判据结论 MUST 写入 `specs/001-core-save-refactor/verification.md`，
MUST NOT 只在对话里声称"已通过"。

**收尾**：删除全部 `_probe*.gd` 等临时资源，用 `git status`（只读查询，宪法原则 VII 允许）或
`godot-lint.ps1` 的 `temp_files` 规则确认无残留。**MUST NOT 自行提交/暂存**；需要提交时只在报告中
给出建议命令与原因。

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| 原则 III 的**一次性例外**（治理动作，非违规：原要求"变更须提供迁移路径"全部保留） | 本次**使用**该例外执行一次不兼容结构变更（元数据独立成段 `meta`、`version` 1 → 2、旧档显式拒绝）：模板尚未发布、无真实用户存档，兼容性没有保护对象，为一个空的旧档集合写迁移代码无法被真实数据验证。人类裁定：允许不兼容**只允许这一次**，宪法还是要保留 —— 故例外写进宪法、用后即尽 | 直接放宽为"迁移可选"（原计划）：会**永久移除**一条 NON-NEGOTIABLE 硬要求；为一次许可付 MAJOR 治理代价，成本高于收益 |
| 新增分段 `meta` 与 `version` 1 → 2 | 元数据（`slot` / `saved_at` / `game_version` / `playtime`）原为根上平铺，与"一段一个类"的既有约定不一致，且元数据增长会挤占根层级；移入 `MetaSave` 后根上只剩版本号与各分段，对外 `metadata()` 键不变 | 保持平铺（R4 初稿结论）：零结构变更、零治理代价，但用户已裁定本次要执行一次结构变更，且组织问题会原样留给下一个游戏项目 |
| `save_service.gd` 拆分引入 2 个新文件 | 该文件同时承担七种职责（请求校验/队列/存取/设置启动/序列化/文件 IO/元数据），单次改动需要在 463 行里定位边界，是本次审查发现的最大可维护性缺陷 | 不拆、只加注释分段：改动量最小，但职责耦合本身没解决，`apply_dict`/`migrate` 这类改动仍要跨职责阅读；且注释分段无法阻止后续继续堆叠 |
