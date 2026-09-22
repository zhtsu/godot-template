# AGENTS.md — godot-template

面向在本仓库工作的编码 agent。本文件是**约束**，与个人风格偏好冲突时以本文件为准。

## 这是什么

Godot **4.7** 项目模板（纯 GDScript），用来快速起各种游戏。分两层，写代码主要在第 2 层：

| 层 | 位置 | 说明 |
|---|---|---|
| 框架层 | `addons/godot_core_system/` | 第三方插件：autoload 单例 `CoreSystem` + 13 个模块（事件总线 / 资源 / 场景 / 输入 / 音频 / 存档 / 配置 / 时间 / 状态机 / 实体 / 触发器 / 标签 / 日志）+ 工具类。**默认不改**；确需改动要在提交信息里单独说明理由 |
| 项目层 | `core/`、`save_data/`、`entry/`、`ui/`、`locale/` | 约定层 + 业务层 |

启动链路：主场景 `entry/main.tscn` → `Main` 下挂 `UiRoot`（UI 层管理）与 `SaveService`（存档服务）→ `entry/main.gd` 发事件打开主菜单。

## 框架层能力速查（动手前先看这里）

**宪法原则 VI**：没有现成实现可参考时，**优先用框架层已有能力**，只有项目和插件都没有的方案才自研。
下面的清单就是为了让"先查插件"这一步不必每次重新 grep。

`CoreSystem` 单例暴露 **13 个模块**（`addons/godot_core_system/source/core_system.gd`）：

| 模块 | 目录 | 已提供的子能力（易被忽略的部分） |
|---|---|---|
| `event_bus` | `event_system/` | 事件订阅/派发，`subscribe_unique_script` |
| `save_manager` | `save_system/` | 4 种格式策略：`binary` / `json` / `resource` / `async_io` |
| `resource_manager` | `resource_system/` | 资源加载与缓存 |
| `scene_manager` | `scene_system/` | **内置转场**：`fade` / `slide` / `dissolve` + `base_transition`、`scene_base` |
| `input_manager` | `input_system/` | **功能类**：`input_buffer`（缓冲）、`input_virtual_axis`（虚拟轴）、`input_recorder`（录制）、`input_event_processor` |
| `config_manager` | `config_system/` | 配置读写 |
| `state_machine_manager` | `state_machine/` | `base_state_machine` / `base_state` |
| `entity_manager` | `entity_system/` | 实体管理 |
| `trigger_manager` | `trigger_system/` | 触发器 + 条件：`event_type` / `state` / `composite`（可组合） |
| `tag_manager` | `tag_system/` | GameplayTag：`gameplay_tag` / `gameplay_tag_container` |
| `time_manager` | `time_system/` | 时间/计时 |
| `audio_manager` | `audio_system/` | 音频播放 |
| `logger` | `logger/` | `core_logger` |

工具类（`CoreSystem` 直接暴露）：`FrameSplitter`（分帧）、`SingleThread` / `ModuleThread`（线程）、
`RandomPicker`（加权随机）、`AsyncIOManager`（异步 IO）。

查询方式（原则 VI 要求的依据）：读 `core_system.gd` 的模块/工具清单 → 在 `source/` 下按关键词检索
（`transition` / `buffer` / `async` / `tag` / `trigger` / `strategy`）→ 读目标模块的公开方法签名。
**注意**：模块可经 `godot_core_system/module_enable/<module_id>` 被关闭，此时取到 null，调用方不能假设可用。

## 硬规则（必须遵守）

1. **路径 / 事件名 / 类型三处集中**：`res://` 路径只写在 `core/paths.gd`（`Paths`），事件名只写在 `core/events.gd`（`Events`），请求与结果结构体只写在 `core/types.gd`（`Types`），设置候选值写在 `core/options_data.gd`。场景、脚本里禁止散落硬编码路径或事件字符串。
2. **UI 只能通过事件开关**：发 `Events.OPEN_UI`（payload `Types.OpenUiRequest`）与 `Events.CLOSE_UI`（payload 路径字符串），由 `core/ui_root.gd` 负责实例化、分层、记账。**不要**自己 `instantiate()` 界面，也不要自己 `queue_free()` 关闭界面（会绕过 `ui_dict` 记账，留悬挂引用）。
3. **界面文案一律用翻译 key**：场景里写 `text = "ui.xxx.yyy"`；新增 key 必须在 `locale/en.po`、`locale/zh_CN.po`、`locale/texts.pot` **三处同步**（`locale/fallback="zh_CN"`）。只有语言母语名这类不翻译的内容才写原文。
4. **事件总线语义**：`push_event(name, payload)` 的 `payload` **就是订阅者的参数表** —— 非数组会自动包成单元素参数表；**数组则原样当参数表用**。实测四种形态（探针已验证，别靠推理）：
   - `push_event(N, 对象)` → 订阅者收到 **1 个参数**（该对象本身）
   - `push_event(N, [items])`（**单元素**）→ 订阅者收到 **1 个参数**：`items` 本身 ← **想传一个数组时就这么写**
   - `push_event(N, [a, b, c])`（**多元素**）→ 订阅者收到 **3 个参数**（各自独立）
   - `push_event(N, [])` → **0 个参数**

   所以"数组时要再包一层"是**错的**（那会变成 `[[items]]`）。反过来，`SAVE_LIST_READY` 必须写成 `push_event(..., [saves])` 而**不能**写成 `push_event(..., saves)` —— 后者会把数组当参数表，订阅者收到的是一堆独立的 `Dictionary` 而不是一个数组。完整契约与踩坑说明见 `specs/001-core-save-refactor/contracts/event-payload-contract.md`。
   事件没有返回值 → 一律"请求事件 + 结果事件"配对，结果里**必须处理 `ok=false`**。跨帧/延迟要谨慎：事件回调里再发事件会被排队（每帧上限 16 个）。
5. **不要交"看起来对"的代码**：任何非平凡改动都要真跑一遍引擎验证（见下）。
6. **禁止改变仓库状态的 git 操作（宪法原则 VII，NON-NEGOTIABLE）**：`commit`/`push`/`pull`/`fetch`/`merge`/`rebase`/`reset`/`checkout`/`switch`/`restore`/`stash`（除 `list`）/`tag`/`branch`（增删改）/`clean`（除 `-n`）/`rm`/`mv`/`gc` 等**一律不许**，除非人类在当次对话里明确要求。任务完成、收尾检查**都不是**触发条件。需要提交时，在报告里写出**建议人类执行的命令和原因**，由人类决定。
   **只读查询是允许的、而且鼓励用**：`git status` / `diff` / `log` / `show` / `blame` / `ls-files` / `rev-parse` / `cat-file` / `remote -v` / `config --get` / `clean -n` 都可以随时跑，用来了解现状和自查。判断"文件是否被跟踪""工作区是否干净"**优先用这些**，不要靠手工扫描去模拟。拿不准某条命令会不会改状态时，问，不要试。

## 存档系统契约（改动前必读）

- **格式**：4 字节魔数 `GTSV` + `var_to_bytes(纯数据字典)`，扩展名 `.sav`；读用 `bytes_to_var()`（**不是** `bytes_to_var_with_objects()`）。因此存档文件里不可能承载任何逻辑/脚本/对象——这是刻意设计（此前评估过 json 明文与 `.tres` 方案，都因可承载逻辑而被否掉），**不要换回去**。
- **结构**：一个分段一个类，都在 `save_data/`，继承 `SaveSection`；根是 `save_data.gd` 的 `SaveData`。**加分段 = 新建类 + 在 `save_data.gd` 加一行 `var xxx: XxxSave = XxxSave.new()`**，`SaveService` 不需要改。元数据（`slot` / `saved_at` / `game_version` / `playtime`）自 v2 起在 `save_data/meta_save.gd` 的 `MetaSave` 段里。
- **分段里只放数据字段**（int/float/bool/String/`Vector2(i)`/Color/Array/Dictionary…）。放 `Object`/`Callable`/`Signal`/`RID` 会被 `to_dict()` 跳过并告警——**静默丢数据是 bug**，别用。
- **校验**：需要范围/白名单检查的分段覆写 `validate()`（载入后 `validate_tree()` 自动调用）。参考 `OptionsSave.validate()`：不在候选表里的分辨率/语言会被改回默认值。
- **事件**：`SAVE_REQUEST`→`SAVE_FINISHED`、`LOAD_REQUEST`→`LOAD_FINISHED`、`DELETE_SAVE_REQUEST`→`DELETE_SAVE_FINISHED`、`SAVE_LIST_REQUEST`→`SAVE_LIST_READY`。payload/结果字段见 `core/types.gd`。
- **设置单独存**：分辨率/语言存在 `OptionsSave.SLOT`（`options.sav`），游戏档里**不含** options 段；`_list_slots()` 会把它从存档列表里排除。没有存档、**或设置档无法载入**（版本过旧 / 损坏）时，`SaveService` 用**当前引擎状态**播种默认值（保证界面显示=实际生效）并告警。用户在设置界面改动 → 发 `SAVE_REQUEST`，写入成功后立即应用。
- **写入是原子的**（先写 `.tmp` 再 `DirAccess.rename_absolute` 覆盖）；槽位名会被过滤（拒绝 `..`、`/`、`\` 等）。纯文件 IO 在 `core/save_storage.gd`（不持状态、`save_dir` 由参数传入），设置应用在 `core/options_applier.gd`。
- **结构版本与兼容策略**：版本号在 `SaveData.version`（**当前 2**）。改结构 MUST 提升版本，并 MUST 在 `save_data.gd` 的 `migrate()` 里**声明策略**：**写迁移**（按 `from_version` 逐级补字段）或**显式拒绝**（返回 `{}`，由 `SaveService` 给出可区分原因）。MUST NOT 悄悄改结构而不动版本号；MUST NOT 出现半读入（部分字段已更新、部分保持原值）。
- **001-core-save-refactor 的这次不兼容变更（已落地）**：`version` **1 → 2** —— 元数据从根上平铺移入 `meta` 分段（`MetaSave`），字段本身**没有增删**，`SaveData.metadata()` 对外返回的键也不变；随之变化的是**补丁路径**（`{"playtime": 5}` → `{"meta": {"playtime": 5}}`）与内存路径（`save_data.slot` → `save_data.meta.slot`）。旧档（v1）**被显式拒绝**、不写迁移。它援引了宪法原则 III 的**一次性例外**（模板未发布、无真实用户存档），**该例外已用尽**：以后的结构变更 MUST 提供迁移路径。
- **补丁类型校验**：`SaveSection.apply_dict()` 会逐字段比对类型 —— 不兼容（除 `int` ↔ `float` 互通）时**拒绝该字段 + 告警 + 保持原值**。别指望 `set()` 兜底：Godot 对可转换的坏类型会静默转换（`float ← "abc"` → `0.0`），对不可转换的会静默忽略，两者都不告警。
- `save_data` 是**共享单个对象**，读档是原地更新（保留分段对象标识）。存档目录取自 `ProjectSettings` 的 `godot_core_system/save_system/save_directory`（默认 `user://saves`），测试时可临时改到 `res://` 下。

## 验证（本项目的强制动作）

没有运行时验证的改动不算完成。两条门禁命令（记不住就照抄）：

```powershell
# 静态规则门禁（宪法 I/II/III/IV 的可执行版本；宽松档只扫 .gd）
.specify/scripts/powershell/godot-lint.ps1

# 引擎验证：主场景冒烟 + 与已登记基线逐行 diff；退出码 1 = 有新增回归
.specify/scripts/powershell/verify-engine.ps1

# 场景直接实例化 / 一次性探针 / 登记基线
.specify/scripts/powershell/verify-engine.ps1 -Scenario res://ui/options/options.tscn
.specify/scripts/powershell/verify-engine.ps1 -Probe res://_probe_us1.gd
.specify/scripts/powershell/verify-engine.ps1 -UpdateBaseline
```

完整参数与基线语义见 `plan-template.md` 的 Verification Plan；现成技能是 `/speckit-godot-lint` 与 `/speckit-godot-verify`。

**引擎路径（本机事实，脚本可自动探测）**：`C:\portable\Godot\4.7.2\Godot_v4.7.2-stable_win64_console.exe`。
**本仓库不假设 `godot` 在 PATH 上，实测它通常不在**；用 `_console.exe` 才拿得到 stdout。

### 基线噪声（别把噪声当成本次回归）

主场景 headless 冒烟**稳定**输出下面 5 行 ERROR/WARNING，**而 Godot 退出码仍是 0**：
日志写不了 ×2、证书库读不到、`<n> ObjectDB instances were leaked`（本机 n=10）、`<n> resources still in use at exit`（本机 n=1）。

所以判据 **MUST NOT** 写成"退出码 0 且没有 ERROR"（既不可执行也不可证伪），
**MUST** 写成"相对 `.specify/godot-verify-baseline.json` 无新增行"。该基线是**机器相关**的
（首次运行有没有 `options.sav` 会影响启动日志），换机器或存档状态大变后用上面第 5 条命令重登。

**存档结构版本变更后的基线扰动（001-core-save-refactor 起适用）**：`SaveData.version` 已提升到 2，
本机遗留的 v1 `user://saves/options.sav` 会在启动时被**显式拒绝**，因此冒烟输出会多出 4 行
（"存档版本 1 较旧…" / "结构版本 1 过旧…" / "设置档无法载入，按首次运行处理…" 及其栈帧行）。
这不是回归，是契约变更的预期结果；登记基线前 MUST 先决定按哪种机器状态登记：
删掉那个 v1 文件（或让设置界面把它重写成 v2）后，这几行会消失。

- 新增/改名的 `class_name` 会让全局类缓存过期 → 先 `--import` 再跑：`& $godot --headless --path . --import`
- 探针脚本不要留在仓库里；收尾用 `git status`（只读，允许）或 lint 的 `temp_files` 规则确认没有 `_*` 残留。
- 涉及节点的断言要等 ≥2 帧再查（`SceneTree` 初始化阶段挂的节点此时还没 `_ready`）。
- 验证证据（命令 + 输出要点 + 结论）写入 `specs/<NNN>-<feature>/verification.md`，别只在对话里声称"已通过"。

## Godot 坑（踩过的，别再踩）

- **`.tscn` 里不存在的属性会被静默忽略**（不报错也不提示）→ "跑起来没报错"不能证明属性名正确；怀疑时用引擎文档核对（`--doctool` 导出 `doc/classes/*.xml`）。
- `var_to_bytes()` 在本版本只接受 **1 个参数**（没有 `full_objects` 参数）；多传会直接 Parse Error。
- `OptionButton.select()` **不会**触发 `item_selected`（只有用户交互会）→ 填充下拉框不会误触发存档回调。
- 脚本运行时报错会**中断所在函数**（例如访问 null 的属性，该函数后面的代码整段不执行）。
- `$长/节点/路径` 改名后要运行时才报错 → 新代码优先用唯一名 `%Name` 或 `@export` 引用。
- 全局类缓存、`.po` 翻译、`.uid` 都参与 `--import` 流程；手改 `.tscn` 的 `ext_resource` 时不要漏 `uid`。

## 目录速查

| 路径 | 内容 |
|---|---|
| `entry/` | `main.tscn`（主场景）、`main.gd` |
| `core/` | `paths.gd` / `events.gd` / `types.gd`（约定）、`ui_root.gd`+`.tscn`、`save_service.gd`+`.tscn`、`save_storage.gd`（纯文件 IO）、`options_applier.gd`（设置应用）、`options_data.gd` |
| `save_data/` | `save_section.gd`（基类）、`save_data.gd`（根）、`meta_save.gd`（元数据分段）、`options_save.gd`（设置分段） |
| `ui/main_menu/`、`ui/options/` | 界面场景 + 脚本 |
| `locale/` | `en.po`、`zh_CN.po`、`texts.pot` |
| `addons/godot_core_system/` | 框架插件，入口 `source/core_system.gd` |
| `.specify/`、`.dsh/skills/` | spec-kit 宪法/模板/脚本 与 `/speckit-*` 技能 |
| `.specify/godot-lint.json`、`.specify/godot-verify-baseline.json` | **本项目自有的非受管文件**：静态规则配置、引擎输出基线 |
| `.specify/scripts/powershell/godot-lint.ps1`、`verify-engine.ps1`、`restore-managed-files.ps1` | **本项目自有的非受管脚本**：静态门禁、引擎验证 + 基线 diff、受管文件漂移恢复 |

## 规格驱动开发（spec-kit）

仓库已初始化 spec-kit 1.0.9（`--integration dsh`），非平凡功能**先出规格再动代码**：

- 技能入口：`.dsh/skills/speckit-*/SKILL.md`（用 `/speckit-*` 触发）。注意技能只从 **DSH 项目根**（cwd 往上第一个含 `.git` 的目录）发现，工作区切到本仓库才可用。这里提到 `.git` 只是**说明技能的发现路径**
- 宪法（长期原则，已批准 **v1.4.0**）：`.specify/memory/constitution.md`。**原则 VI＝优先复用框架层已有能力**（见上面的能力速查）；**原则 VII＝git 只读**（改状态的操作用户没要求就不许做，只读查询随意）；原则 V 写明了"基线逐行比对"与"完成证据三元组"；原则 III 自带一条**一次性**不兼容例外（已被 `001-core-save-refactor` 用尽）。机器相关的内容（引擎路径、噪声清单、命令）**故意不写进宪法**，只在本文件与模板里
- 产物目录：`specs/<NNN>-<feature>/`（`spec.md` / `plan.md` / `tasks.md` …）
- 顺序：`/speckit-constitution` → `/speckit-specify` → `/speckit-plan` → `/speckit-tasks` → `/speckit-implement`；可选 `/speckit-clarify`、`/speckit-checklist`、`/speckit-analyze`、`/speckit-converge`
- 注意：`/speckit-plan` 只生成 `plan.md`；`tasks.md` 由 `/speckit-tasks` 落盘（`setup-plan.ps1` 不创建它）

### 模板分层与定制位置（改模板前必读）

模板解析栈见 `.specify/scripts/powershell/common.ps1` → `Resolve-TemplateContent`：

| 优先级 | 位置 | 说明 |
|---|---|---|
| 1 | `.specify/templates/overrides/<name>.md` | **项目定制的唯一正确位置**，零依赖，**整体替换** core |
| 2 | `.specify/presets/<id>/templates/` | 带 `preset.yml` 时强制要求 Python 3 + PyYAML，缺失会让命令报错中断 |
| 3 | `.specify/extensions/<id>/templates/` | 扩展提供 |
| 4 | `.specify/templates/<name>.md` | core，**受管文件** |

- `.specify/templates/*.md`、`.specify/scripts/*.ps1`、`.specify/.gitignore` 都是**受管文件**（见 `.specify/integrations/speckit.manifest.json`）：直接改会被 `specify integration status` 记为 modified，且 `specify init --force` 会覆盖。**定制一律写 overrides/**
- 已有覆盖层：`plan-template.md`、`spec-template.md`、`tasks-template.md`（内容按本仓库的 Godot 约定与宪法 **7 条**原则改写）。每个覆盖层文件头记录了对应 core 模板的 sha256，用于漂移检测——哈希对不上说明上游模板更新了，需人工复核覆盖层。`plan-template` 的 Constitution Check 表与 Technical Context 的 **Framework Reuse** 字段是原则 VI 的落地点
- `checklist-template` **无法用 overrides 定制**：`speckit-checklist` 技能硬编码读 `.specify/templates/checklist-template.md`，不走解析器
- 验证定制是否生效：`specify preset resolve <name>`，或 `.specify/scripts/powershell/resolve-template.ps1 <name> -Json`

### 受管文件 vs 本项目自有文件（加东西前必须分清）

manifest 里**列到的**才是受管文件；没列到的即使放在 `.specify/` 或 `.dsh/` 下也是本项目自己的，可以自由改、也不会被判 modified：

| 归属 | 文件 | 改动的后果 |
|---|---|---|
| 受管（spec-kit） | `.specify/scripts/powershell/{common,check-prerequisites,create-new-feature,resolve-template,setup-plan,setup-tasks}.ps1`、`.specify/templates/{spec,plan,tasks,checklist,constitution}-template.md`、`.specify/.gitignore`、`.dsh/skills/speckit-{specify,plan,tasks,implement,clarify,analyze,checklist,constitution,converge,taskstoissues}/SKILL.md` | 记为 modified；`specify init --force` 会覆盖。**不要改**，要定制走 overrides |
| 自有（本项目） | `.specify/scripts/powershell/godot-lint.ps1`、`verify-engine.ps1`、`restore-managed-files.ps1`、`.specify/godot-lint.json`、`.specify/godot-verify-baseline.json`、`.specify/templates/overrides/*.md`、`.dsh/skills/speckit-godot-*/SKILL.md` | 随本项目提交，随时可改；升级 spec-kit 不受影响 |

新增自有文件请沿用命名约定：脚本/配置用 `godot-*` 前缀，技能用 `speckit-godot-*` 目录名。

**漂移自查与恢复**：`restore-managed-files.ps1` 不带参数时只报告受管文件漂移（对应 `specify integration status`）；
被误改时用 `-File <路径>` 或 `-All` 恢复。它不猜内容——枚举常见行尾/末尾换行组合逐一比对 manifest 的 sha256，
命中才写；有实质内容改动时会拒绝并保持文件不动。**升级 spec-kit 或手工动过 `.specify/` 后值得跑一次。**
注意 `.specify/extensions/.cache/`（`specify extension search` 写出的目录缓存）已在**根 `.gitignore`** 里忽略；
之所以不放 `.specify/.gitignore`，是因为后者是受管文件，改了会被记为 modified。

### 两个自有技能（可选但推荐）

- `/speckit-godot-lint`：跑静态门禁（宽松档只扫 `.gd`），报告 `file:line` 证据并区分 error（违反宪法，必须修）与 warn（存量，别顺手改）
- `/speckit-godot-verify`：跑引擎验证 + 基线 diff + 探针，并把"命令 + 输出要点 + 结论"写进 `specs/<NNN>/verification.md`

lint 规则本体在 `.specify/godot-lint.json`（可改）：`paths` / `events` / `ui_bypass` 是 error，`scene_tree` / `locale_orphan` / `save_data_version` / `temp_files` 是 warn。
**场景层（`.tscn`）不在静态扫描范围内**——那里的 `res://` 是引擎自己写死的，grep 无法区分合规引用与散落硬编码，所以这部分由引擎运行验证兜底。

## 已知未完成事项（别当 bug 反复修）

- `ui/main_menu/main_menu.gd` 只接了「设置」按钮；开始 / 制作人员 / 退出按钮是空的。
- `locale/*.po` 有 5 个 orphan key：`ui.main_menu.settings.res`、`ui.main_menu.select`、`ui.options.text_language`、`ui.options.language_name`、`ui.options.select`。
- 设置界面只有分辨率 / 语言；没有音量、按键重映射、Apply / Cancel。
- 缺少游戏流程层（boot→title→gameplay→pause）与暂停菜单；`CoreSystem.scene_manager` / `state_machine_manager` 尚未接入。
- `project.godot` 缺 `application/config/version` 与 `[input]` 动作表；`[display]` 里没有显式的 `window/size/viewport_width|height`，所以"基准画布 1152×648"目前只是引擎默认值，不是项目显式声明。
- 存量静态违规 3 处（`scene_tree` warn）与 5 个 orphan key（`locale_orphan` warn）是**有意保留**的：lint 基线数为 5，修好 orphan 后请把 `.specify/godot-lint.json` 的 `locale.orphanBaseline` 一起调低。
