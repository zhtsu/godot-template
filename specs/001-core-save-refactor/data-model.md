# Phase 1 Data Model: core/ 与 save_data/ 审查重构

**Feature**: `001-core-save-refactor` | **Date**: 2026-09-23

本文件描述**既有**实体、本功能**新增的 `MetaSave` 分段**，以及本功能施加的校验规则与一次结构变更。
字段清单以源代码为准，此处记录的是**契约与校验语义**，不是字段的重复抄写。

---

## 1. 实体关系

```text
SaveData (存档根, version = 2)
├── 根上只留: version
├── meta: MetaSave                ← 本次新增分段：slot / saved_at / game_version / playtime
├── options: OptionsSave          ← 独占 "options" 槽位
└── (将来) 其他分段: SaveSection 子类

SaveSection (分段基类, extends RefCounted)
├── SaveData        extends SaveSection
├── MetaSave        extends SaveSection   ← 本次新增（元数据搬家，不新增字段）
├── OptionsSave     extends SaveSection
└── UNSUPPORTED_TYPES = [TYPE_OBJECT, TYPE_CALLABLE, TYPE_SIGNAL, TYPE_RID]

SaveService (core/save_service.gd, Node)
├── 持有: save_data: SaveData（唯一一份，并赋给 SaveData.current）
├── 持有: _jobs: Array[Callable] / _draining: bool / _save_dir: String
└── 订阅: SAVE / LOAD / DELETE / SAVE_LIST_REQUEST 四个请求事件
        └── 发送: SAVE_FINISHED / LOAD_FINISHED / DELETE_SAVE_FINISHED / SAVE_LIST_READY
```

**共享对象语义（FR-002 保护范围）**：`save_data` 是**单个共享对象**，读档是**原地更新**
（保留分段对象标识）。`SaveData.current` 指向它，供各处只读访问。本功能 MUST NOT 改为替换对象。

---

## 2. SaveSection（`save_data/save_section.gd`）

### 2.1 职责

决定"哪些字段能进纯数据存档"，并提供三个方向的数据转换：

| 方法 | 方向 | 关键行为 |
|---|---|---|
| `field_names()` | 内省 | 经 `get_property_list()` + `PROPERTY_USAGE_SCRIPT_VARIABLE` 收集普通 `var`；**不需要 `@export`** |
| `to_dict()` | 内存 → 字典 | 嵌套分段递归下钻；命中 `UNSUPPORTED_TYPES` 则**跳过并告警** |
| `from_dict(dict)` | 字典 → 内存 | 递归下钻；字典里没有的字段保持原值（旧档缺新字段时用默认值）；**分段字段只认字典**，非字典值拒绝并告警 |
| `apply_dict(patch)` | 字典 → 内存（部分） | 只认同名字段；**本次新增类型校验**（见 2.2） |
| `validate_tree()` | 自检 | 先递归所有分段，再调用本类 `validate()` |
| `validate()` | 自检钩子 | 子类覆写；默认空 |

### 2.2 `apply_dict()` 的类型校验规则（行为性改动之一；另一处是 §3 的结构变更）

对应 FR-004 / US3。规则按以下顺序判定：

| 目标字段当前值 | 补丁值 | 判定 |
|---|---|---|
| 是 `SaveSection` | 是 `Dictionary` | 递归 `apply_dict` |
| 是 `SaveSection` | 其他 | **拒绝该字段**，告警"分段必须是字典"（**现状已有，MUST 保持**） |
| `int` | `float`（无损） | 接受 |
| `float` | `int` | 接受 |
| 其他任意 | `typeof` 不相同 | **拒绝该字段**，告警"类型不符：字段 `<名>` 期望 `<A>` 实际 `<B>`" |
| 任意 | `typeof` 相同 | 接受 |
| 未知字段名 | — | **忽略 + 告警**（**现状已有，MUST 保持**） |

**不变量**：
- 拒绝 MUST NOT 清空或重置该字段——保持原值（对照 `from_dict` 的既有保护取向）。
- 空补丁 MUST NOT 改变任何字段。
- 一次补丁里的坏字段 MUST NOT 阻止同批次其他合法字段被应用。

### 2.3 为什么收紧这里（与 `from_dict` 不对称是有意的）

`from_dict` 面向**磁盘数据**（可能来自旧版本或损坏文件），采取"能修就修、修不了告警并保持"的宽松取向。
`apply_dict` 面向**同进程调用方的即时补丁**（`Types.SaveRequest.data`），类型写错属调用方缺陷，
应当**立即可见**。两者输入来源不同，因此校验强度不同——这不是不一致。

---

## 3. SaveData（`save_data/save_data.gd`）

| 字段 | 类型 | 本次 |
|---|---|---|
| `version` | `int` | **1 → 2**（结构变更，见 `research.md` R4） |
| `meta` | `MetaSave` | **新增分段**：`slot` / `saved_at` / `game_version` / `playtime` 由根上平铺搬入，仍由 `_stamp()` 补齐 |
| `options` | `OptionsSave` | 不变 |
| `current`（`static var`） | `SaveData` | 共享对象指针，语义不变 |

| 方法 | 语义 | 本次 |
|---|---|---|
| `metadata()` | 返回元数据字典（供存档列表用） | **键不变**：仍返回 `version` / `slot` / `saved_at` / `game_version` / `playtime`，值取自 `meta`（FR-002 保护） |
| `migrate(dict, _from_version)` | 迁移钩子；返回 `{}` 表示拒绝载入 | **改为显式拒绝**（`return {}`）：本次援引一次性例外、不写迁移，理由见 R4 与契约 §5.2 |

### 3.1 MetaSave（`save_data/meta_save.gd`，本次新增）

| 字段 | 类型 | 说明 |
|---|---|---|
| `slot` | `String` | 槽位 ID，由 `SaveService._stamp()` 写 `save_data.meta.slot` |
| `saved_at` | `String` | 保存时间（既有格式不变） |
| `game_version` | `String` | 保存时的游戏版本（来自 `ProjectSettings`，缺失时容错为空） |
| `playtime` | `float` | 累计游戏时长 |

**不新增字段**：v1 → v2 只把根上这四个字段**搬家**到 `meta` 段；`MetaSave` 不覆写 `validate()`（无范围约束）。
**内存路径变化**：`save_data.slot` → `save_data.meta.slot`（其余同理）。

**约束（例外已用尽）**：本次已消耗宪法原则 III 的一次性例外。此后任何结构变更 MUST 提升 `version`
**并提供迁移路径**（在 `migrate()` 中按 `from_version` 逐级补齐字段），并按
`contracts/save-file-format.md` §5.2 记录"改了什么 / 从哪个版本到哪个版本 / 为何允许不兼容"；
MUST NOT 悄悄改结构而不动版本号。

---

## 4. OptionsSave（`save_data/options_save.gd`）

| 字段 | 类型 | 校验 |
|---|---|---|
| `resolution` | `Vector2i` | MUST ∈ `OptionsData.RESOLUTIONS`，或 == `OptionsData.FULLSCREEN`（`Vector2i.ZERO`）；否则改回 `DEFAULT_RESOLUTION` |
| `language` | `String` | MUST ∈ `OptionsData.LANGUAGES[*].locale`；否则改回 `DEFAULT_LANGUAGE` |

- `SLOT = "options"`：独立槽位常量。
- `DEFAULT_RESOLUTION = Vector2i(1152, 648)`；`DEFAULT_LANGUAGE = "en"`。
- **注意（本次不顺带修）**：`DEFAULT_LANGUAGE = "en"` 与 `project.godot` 的 `locale/fallback="zh_CN"`
  不一致。首次运行时 `_options_ready()` 用**当前引擎 locale** 播种，所以该常量只在"存档里的值非法"时起作用。
  属既有设计，本次 Non-Goals 未包含，**只记录不改**。

本文件本次**不改动**。

---

## 5. SaveService（`core/save_service.gd`）

### 5.1 对外接口（FR-002 保护，全部不变）

| 事件 | 方向 | payload 形态 |
|---|---|---|
| `Events.SAVE_REQUEST` | 订阅 | 单参数 `Types.SaveRequest` |
| `Events.LOAD_REQUEST` | 订阅 | 单参数 `Types.LoadRequest` |
| `Events.DELETE_SAVE_REQUEST` | 订阅 | 单参数 `Types.DeleteSaveRequest` |
| `Events.SAVE_LIST_REQUEST` | 订阅 | 无参数 |
| `Events.SAVE_FINISHED` | 发送 | 单参数 `Types.SaveResult` |
| `Events.LOAD_FINISHED` | 发送 | 单参数 `Types.SaveResult`（含启动时读设置档后也发一次） |
| `Events.DELETE_SAVE_FINISHED` | 发送 | 单参数 `Types.SaveResult` |
| `Events.SAVE_LIST_READY` | 发送 | 单参数 `Array[Dictionary]`（**数组本身**，见事件契约） |

### 5.2 状态转移（存档请求的完整路径）

```text
接收到 SAVE_REQUEST
  ├─ request 为 null                    → 立即 SAVE_FINISHED(ok=false, "请求为空")
  ├─ slot 非法                          → 立即 SAVE_FINISHED(ok=false, "非法槽位名")
  └─ 合法 → 入队 _do_save
        ├─ request.data 非空 → save_data.apply_dict(patch)   ← 本次改：逐字段类型校验
        ├─ 本次新增：save_data.validate_tree()                ← 让范围/白名单问题在落盘前兜住
        ├─ slot 为空 → 自动生成 save_<unix>[_n]
        ├─ _stamp(slot)：写 meta.slot / meta.saved_at / meta.game_version
        ├─ _write(slot)：tmp → rename（原子）
        │    └─ 失败 → 回滚 save_data.slot 为 previous_slot
        ├─ slot == "options" 且成功 → _apply_options()（立即生效）
        └─ SAVE_FINISHED(ok, slot, error, metadata[, data])
```

### 5.3 拆分后的职责边界（FR-008）

| 归属 | 职责 |
|---|---|
| `core/save_service.gd` | 事件订阅/退订、请求校验、任务队列、存档数据所有权、元数据补齐、结果组装与发送、设置档启动流程 |
| `core/save_storage.gd`（新） | 纯文件 IO：路径拼接、槽位名过滤、魔数/长度/大小校验、解码、原子写、目录枚举。**`save_dir` 由参数传入；不持状态；不订阅事件** |
| `core/options_applier.gd`（新） | 纯引擎状态应用：语言、分辨率、全屏。**不持状态；不订阅事件；不读存档** |

**依赖方向（MUST 单向）**：`save_service` → `save_storage` / `options_applier`。
反向依赖 MUST NOT 出现（`SCR` 由人工审阅 + lint 的 `ui_bypass`/`paths` 规则辅助保证）。
