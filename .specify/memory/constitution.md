# godot-template 项目宪法

## Core Principles

### I. 约定集中化（Single Source of Truth）

所有 `res://` 路径 MUST 只在 `core/paths.gd` 中定义；所有事件名 MUST 只在 `core/events.gd` 中定义；
跨模块传递的请求与结果结构 MUST 只在 `core/types.gd` 中定义；候选值表（分辨率、语言等）MUST 只在
`core/options_data.gd` 中定义。场景文件与脚本中 MUST NOT 出现硬编码的路径字面量或事件名字符串。

理由：本仓库是会被复制到多个游戏项目的基础模板，重命名或搬移目录时只允许存在一个修改点；散落的
字面量在改名后不会在编译期报错，只会在运行时失败。

### II. UI 与模块只经事件总线通信

界面 MUST 只通过 `Events.OPEN_UI` 与 `Events.CLOSE_UI` 打开和关闭，由 `core/ui_root.gd` 统一负责
实例化、分层与记账；MUST NOT 直接 `instantiate()` 界面，MUST NOT 自行 `queue_free()` 关闭界面。
模块之间 MUST NOT 持有彼此的直接引用，跨模块调用 MUST 走事件总线。请求型操作 MUST 采用「请求事件 +
结果事件」配对，订阅方 MUST 显式处理失败结果（`ok == false`）。框架层 `addons/godot_core_system/`
MUST NOT 被修改；确需修改时 MUST 在规格与提交信息中给出理由。

理由：界面生命周期集中在一处才能避免悬挂引用与重复实例化；模块间只经事件通信，才能在不改框架的前提下
替换具体实现。

### III. 存档纯二进制、不可承载逻辑（NON-NEGOTIABLE）

存档 MUST 使用「魔数 + `var_to_bytes()` / `bytes_to_var()`」的自定义二进制格式；MUST NOT 使用 JSON、
明文或 `.tres`/`.res` 等可承载脚本与对象的载体；读取时 MUST NOT 使用 `bytes_to_var_with_objects()`。
存档结构 MUST 由继承 `SaveSection` 的 GDScript 类定义并按分段落盘；分段内 MUST 只允许基础数据类型，
MUST NOT 出现 `Object`、`Node`、`Resource`、`Callable`、`Signal`、`RID`。新增分段 MUST 只新增一个类
并在根数据类中注册一行；`SaveService` MUST NOT 因新增分段而被修改（除非存档格式契约本身变更）。需要
取值范围约束的分段 MUST 实现 `validate()`。存档结构变更 MUST 提升结构版本号并提供迁移路径。写入
MUST 原子完成（临时文件 + 改名），MUST NOT 产生半写状态。

**唯一例外（一次性，MUST NOT 延期、重复援引或扩大）**：在模板尚未发布、不存在任何真实用户存档的
前提下，允许**一次**不兼容的存档结构变更 —— 此时迁移路径 MAY 省略，但 MUST 显式记录「改了什么、
从哪个版本到哪个版本、为何允许不兼容」，MUST 在「写迁移」与「显式拒绝」中声明其一，且 MUST NOT
出现半读入（部分字段已更新、部分保持原值的混合状态）。该例外是**一次性许可**，MUST NOT 被当作
一般规则或先例，MUST NOT 覆盖到第二次变更；其授予与使用情况 MUST 记录在对应功能的
`specs/<NNN>-<feature>/` 与 `AGENTS.md` 的存档契约条目中。一旦模板发布或出现真实用户存档，MUST
通过一次专门修订收回该例外，本条恢复为无例外的强制要求。

理由：二进制存档无法承载逻辑，因此存档文件不能成为代码执行载体；结构由 GD 类定义，使字段与类型受
编译器、校验与迁移机制覆盖。例外条款的理由：模板尚未发布、不存在真实用户存档，兼容性在当前阶段
没有保护对象，强制为一个空的旧档集合写迁移代码要付出永久维护成本；而把它写成「一次性、可收回的
许可」而不是删除原要求，是为了在重新出现真实用户后仍有一条明确的收回路径。

### IV. 面向用户的文本全部走翻译键

所有面向用户的文本 MUST 使用 `ui.*` 形式的翻译键，MUST NOT 在场景或脚本中硬编码可见文案（语言的自称
名等不翻译内容除外）。新增键 MUST 在 `locale/en.po`、`locale/zh_CN.po`、`locale/texts.pot` 三处同步，
缺失键 MUST 视为缺陷而非可选项。需要动态组合的文案 SHOULD 使用带占位符的完整句键，而不是拼接片段；
纯数值与专有名词不受此限。

理由：模板要服务多语言项目；散落文案会在新增语言时才暴露，届时修改成本已不可控。

### V. 改动必须经引擎运行验证（NON-NEGOTIABLE）

任何非平凡改动 MUST 在真实 Godot 引擎中运行验证后才算完成；MUST NOT 以「代码看起来正确」或静态阅读
无问题作为完成依据。验证 MUST 覆盖被改动场景与脚本实际被实例化的执行路径。验证 MUST 使用项目提供的
验证脚本进行，MUST NOT 依赖裸 `godot` 命令 —— 本仓库 MUST NOT 假设引擎可执行文件在 `PATH` 上。
验证用的一次性探针脚本与临时资源 MUST 在完成前删除。

**基线判定**：引擎输出 MUST 与项目已登记的基线逐行比对；比对 MUST 以「相对基线无新增 ERROR/WARNING」
为判据，MUST NOT 写成「退出码为 0 且输出中无 ERROR」—— 本项目的基线本身稳定含有已知噪声，
而引擎退出码仍为 0，该判据既不可执行也不可证伪。基线内的已知噪声 MUST NOT 被当作本次回归；
基线之外新出现的引擎 ERROR 或 WARNING MUST 被解释或修复。基线 MUST 视为机器相关状态，
其内容变化 MUST 在规格或提交信息中说明。

**完成证据**：每个任务的完成证据 MUST 是「命令 + 原始输出要点 + 判据结论」三元组，并 MUST 落盘到该功能的
`verification.md`；MUST NOT 仅以对话中的「已实现」「已通过」作为证据。判据 MUST 可追溯到规格中的
功能需求或成功标准，或任务清单中的任务标识。

理由：Godot 对场景文件中的未知属性与部分类型错误保持静默，「能跑起来没报错」本身不构成正确性证据；
本仓库的历史缺陷（静默丢数据、迁移时清空数据）全部由运行时验证才发现；而根据退出码或 ERROR 字样
做判断会在本项目稳定产生误报与漏报。

### VI. 优先复用框架层已有能力

实现任何功能前，MUST 先查清框架层 `addons/godot_core_system/`（经 `CoreSystem` 单例暴露的 13 个模块与
工具类）以及项目层 `core/`、`save_data/` 是否已提供该能力。**没有现成实现可参考时，MUST 优先用框架层
已有能力实现**；只有当项目层与框架层都确实没有对应方案时，才考虑新增自研方案。

- 判据 MUST 可执行，MUST NOT 只凭印象断言「插件里没有」：查询方式限于
  (a) 读 `CoreSystem` 单例暴露的模块与工具类清单；
  (b) 在 `addons/godot_core_system/` 下按能力关键词检索（如 *transition*、*buffer*、*async*、*tag*、*trigger*）；
  (c) 读对应模块的公开方法签名。
- 规格与计划中 MUST 给出复用结论，并注明依据；结论 MUST 落到具体模块名与调用入口，
  MUST NOT 只写「用了插件」这类无法验证的表述。
- 决定自研时 MUST 明确写出「已排除的框架层候选方案」及排除理由，否则该结论 MUST 视为未完成调研。
- MUST NOT 重新实现框架层已覆盖的能力，例如：自建事件/信号分发替代 `CoreSystem.event_bus`、
  自建存档写入替代 `CoreSystem.save_manager` 与 `save_data/` 分段、
  自建场景切换与转场替代 `CoreSystem.scene_manager` 及其 transitions、
  自建输入缓冲/虚拟轴替代 `CoreSystem.input_manager` 的功能类、
  自建状态机或触发器替代 `state_machine_manager` / `trigger_manager`。
- 框架层能力不足时 MUST NOT 直接修改 `addons/`（原则 II 仍然适用）；MUST 在项目层包一层，
  并在规格中记录框架层的具体缺口，作为将来上游升级或替换的依据。
- 复用框架层时 MUST 显式处理失败与空返回：模块可经 `ProjectSettings` 的
  `godot_core_system/module_enable/<module_id>` 被关闭，此时取到的模块为 null，调用方 MUST NOT 假设其可用。

理由：本仓库是会被复制到多个游戏项目的基础模板，框架层已经沉淀了事件总线、场景与转场、输入处理、
资源加载、存档、状态机、触发器、标签、时间、日志等横切能力；在项目层重复造一遍会同时带来三处代价
——维护两套语义、丢失框架层已有的边界处理、以及在模板升级时产生分叉。优先复用也让「这个能力从哪来」
在规格里就有据可查，而不是散落在实现细节中。

### VII. Git 只读，禁止改变仓库状态（NON-NEGOTIABLE）

**区分标准是「是否改变仓库状态」，不是「是否碰 git」。**

- **禁止（除非人类在当次对话中明确要求）**：任何会改变仓库或工作区状态的 Git 操作。包含但不限于
  `git add` / `git commit` / `git push` / `git pull` / `git fetch` / `git merge` / `git rebase` /
  `git reset` / `git checkout` / `git switch` / `git restore` / `git stash`（不带 `list`）/ `git tag` /
  `git branch`（创建、改名、删除）/ `git remote`（增删改）/ `git config`（写入）/ `git init` /
  `git worktree`（增删）/ `git clean`（不带 `-n`）/ `git rm` / `git mv` / `git gc` / `git apply`，
  以及经其他工具间接达成同样效果的等价操作。
- **允许、且鼓励使用**：只读取仓库信息的查询，用于了解现状与自查，无需事先请示。例如
  `git status` / `git diff` / `git log` / `git show` / `git blame` / `git ls-files` / `git ls-tree` /
  `git rev-parse` / `git cat-file` / `git stash list` / `git clean -n` / `git remote -v` /
  `git config --get`。**需要仓库信息时 MUST 优先用这些命令，而不是靠猜或用手工文件扫描去模拟。**
- **灰区判定**：拿不准某条命令属于哪一侧时，MUST 按「它在正常执行中是否会写入 `.git/`、索引、
  工作区或远端」来判断；会写就按禁止处理，不确定时 MUST 先询问人类，MUST NOT 试一下看看。
- `git status` 会因刷新索引 stat 缓存而触碰 `.git/index`，属于纯优化、不改变提交或工作区内容，
  **按允许处理**。
- 禁用侧的操作**与任务状态无关**：MUST NOT 因为「任务完成了」「到了收尾步骤」「惯例上应该提交」
  而在任何时候自行执行。任务完成不是触发条件。
- 自动化脚本与工具 MUST NOT 执行禁用侧的操作；允许侧的只读查询可以自由使用
  （例如用 `git ls-files` 判断文件是否被跟踪，比手工解析 `.gitignore` 更准确）。
- 禁止 MUST NOT 通过改变工作目录、复制仓库、调用外部程序或间接工具等方式绕过。
- 需要改变仓库状态时，正确做法是**在报告中说明需要人类执行什么命令及原因**，由人类决定并执行。

理由：Git 的**历史与状态**属于人类所有者的领域，而**信息**属于任何需要它的人。agent 自行提交或切换
分支会掩盖中间状态、破坏人工审阅节奏、使变更无法按人类意图组织，且一旦发生就不可无痕撤销；
但读取 `git status`、`git log`、`git diff` 只是观察，不会遗留任何后果，禁止它反而会逼迫 agent 用
不精确的文件扫描去模拟仓库状态，得不偿失。把「什么时候形成提交」的决定权留在人类手里，
同时把「看清现状」的能力留给 agent，是本仓库协作模型的一部分。

## 技术约束（Technical Constraints）

- 引擎与语言：Godot 4.7 + GDScript。渲染后端为 GL Compatibility，拉伸模式为 `canvas_items`，基准画布为
  引擎默认的 1152×648。引入需要其他渲染后端或改变基准分辨率上限的特性时，MUST 同步更新本节。
- 依赖策略：MUST NOT 引入 C#、GDExtension 或外部运行时依赖；确需引入时 MUST 在规格中论证。
- 框架层边界：`addons/godot_core_system/` 为冻结层，MUST NOT 修改（原则 II、VI）。项目层 MUST NOT 在
  `core/` 中重复实现框架层已覆盖的能力。凡发现框架层能力不足，MUST 在项目层包装并在规格中记录缺口，
  MUST NOT 把缺口通过改 `addons/` 就地填掉。复用框架层前 MUST 确认模块已启用
  （`godot_core_system/module_enable/<module_id>`，未设置时默认启用）。
- 目录契约：`core/` 放约定与服务，`save_data/` 放存档结构，`ui/` 放界面，`entry/` 放启动，`locale/` 放
  翻译，`addons/` 为冻结的框架层。新增顶层目录 MUST 在规格中说明，并 MUST 同步更新 `AGENTS.md`。
- 命名与引用：文件与类名使用 snake_case，`class_name` 全局类型 MUST 唯一且语义明确。节点引用
  SHOULD 使用唯一名 `%Name` 或 `@export`，MUST NOT 新增依赖长节点路径（`$A/B/C`）的代码。
- 单例与初始化：框架模块 MUST 只经 `CoreSystem` 单例访问；新增 autoload MUST 在规格中说明并评估其
  初始化顺序影响。
- 存档位置：存档目录 MUST 由 `ProjectSettings` 的 `godot_core_system/save_system/save_directory` 配置，
  MUST NOT 在代码中硬编码 `user://` 子路径。
- 验证工具链：验证 MUST 经项目自有脚本（`godot-lint.ps1` 静态门禁、`verify-engine.ps1` 引擎验证与基线
  比对）执行，这两个脚本与 `godot-lint.json`/`godot-verify-baseline.json` 均为项目自有文件，
  MUST NOT 与 spec-kit 受管文件混同；引擎可执行文件的实际位置与基线噪声清单 MUST 记录在 `AGENTS.md`，
  MUST NOT 写死进本宪法（宪法会被复制到下游项目，机器相关状态 MUST NOT 进入其中）。
- 性能与规模预算：非平凡功能 MUST 在计划中给出帧率目标与界面切换时间上限，并在交付时给出实测结果，
  或明确记录豁免理由；MUST NOT 只留占位符而不测。

## 开发流程与质量门（Development Workflow & Quality Gates）

- 规格驱动：非平凡功能 MUST 先出规格与任务再动代码，流程为 `/speckit-specify` → `/speckit-plan` →
  `/speckit-tasks` → `/speckit-implement`；产物落在 `specs/<NNN>-<feature>/`。可选使用
  `/speckit-clarify`、`/speckit-checklist`、`/speckit-analyze`、`/speckit-converge`。
- 完成标准：每个任务的完成证据 MUST 是引擎验证的命令与结果，而不是「已实现」的描述；证据的落盘格式
  见原则 V。
- 交付前门禁：MUST 确认工作区内无临时文件与探针脚本残留（`git status` 只读查询、`godot-lint.ps1` 的
  `temp_files` 规则、或 `Get-ChildItem` 均可）；
  MUST 确认改动的翻译键三处同步；MUST 确认未修改框架层，若修改则 MUST 附上框架层改动的文件与内容摘要、
  上游版本号与升级回滚方案（仅一句「因为必须」不构成理由）。
  MUST NOT 自行提交、暂存或整理 Git 状态；需要提交时 MUST 在报告中说明建议的命令与原因，交由人类执行。
- 复用门：新增自研机制前 MUST 有原则 VI 要求的调研结论（查询方式 + 依据 + 已排除的框架层候选方案）；
  缺少该结论的规格或计划 MUST 视为未完成，MUST NOT 进入实现阶段。
- 通用性门：作为基础模板，每项改动 MUST 通过「下一个游戏项目能否直接复用」的检验；项目特有的美术与
  玩法内容 MUST NOT 混入 `core/`、`save_data/` 等通用层。规格产物 MUST 只描述可复用的通用能力，
  MUST NOT 承载某个具体游戏的美术或玩法资产。
- 文档同步门：目录结构、约定或工作流发生变化时 MUST 同步更新 `AGENTS.md`。
- 模板维护门：spec-kit 或上游 core 模板发生变更后，MUST 重算 `.specify/templates/overrides/*.md`
  头部记录的 sha256 并人工复核覆盖层是否需同步；本仓库自有脚本、配置与技能 MUST 沿用 `godot-*` /
  `speckit-godot-*` 命名约定，以便与受管文件区分。

## Governance

本宪法 MUST 优先于其他实践约定；与本宪法冲突的代码或流程 MUST 在合并前修正，或在规格中记录并获得
明确批准。修订 MUST 留下可追溯记录（提交信息；提交由人类执行，见原则 VII），并按语义化版本调整版本号：MAJOR 用于移除或
重定义原则，MINOR 用于新增原则或实质性扩展指引，PATCH 用于澄清与文字修正。
所有代码复查 MUST 验证与本宪法的一致性；复杂度增加与对框架层的修改 MUST 给出理由。
运行时开发指引以 `AGENTS.md` 为准，它承载具体命令、目录速查、引擎可执行文件位置、基线噪声清单
与已知引擎坑位清单；本宪法 MUST NOT 复制这些机器相关或易变的内容，两者冲突时以本宪法为准。
每次 `/speckit-analyze` 与 `/speckit-converge` MUST 以本宪法作为判定基准。

**Version**: 1.4.0 | **Ratified**: 2026-09-23 | **Last Amended**: 2026-09-23
