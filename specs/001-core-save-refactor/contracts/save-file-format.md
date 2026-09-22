# Contract: 存档文件格式（Save File Format）

**Feature**: `001-core-save-refactor` | **Version**: 2（与 `SaveData.version = 2` 一致；**本次由 1 提升到 2**）
**对应**: FR-005 / FR-006 / FR-007 / PR-001 / PR-002 / PR-004

---

## 1. 格式（字节层**不变**；字典结构本次**变更**）

```
[4 字节 ASCII 魔数 "GTSV"] [var_to_bytes(纯数据字典) 的字节流]
```

- 扩展名 `.sav`；文件名即槽位 ID。
- 读回使用 `bytes_to_var()`（**不是** `bytes_to_var_with_objects()`）。
  `var_to_bytes` 本身不编码对象，因此存档文件**不可能**承载脚本、资源或任何可执行内容。
- **本次明确不改**：魔数、编码方式、扩展名。
- **本次明确要改**：字典结构（元数据从根上平铺移入 `meta` 分段）与 `SaveData.version`（1 → 2）。
  这是一次**不兼容**变更，援引宪法原则 III 的一次性例外（见 §5）。

## 2. 容器结构

### 2.1 落盘字典结构（v2）

```text
{
  "version": 2,
  "meta": { "slot": ..., "saved_at": ..., "game_version": ..., "playtime": ... },  # 本次由根上平铺搬入
  "options": { "resolution": ..., "language": ... }                                 # 仅设置档；游戏档写入前剔除
}
```

`MetaSave`（`save_data/meta_save.gd`）承载 `meta` 段，字段与 v1 **完全相同**（不新增字段）。

| | v1 | v2 |
|---|---|---|
| 根键 | `version` / `slot` / `saved_at` / `game_version` / `playtime` / `options` | `version` / `meta` / `options` |
| 内存字段路径 | `save_data.slot` | `save_data.meta.slot` |
| 补丁路径（`Types.SaveRequest.data`） | `{"playtime": 5}` | `{"meta": {"playtime": 5}}` |
| 对外 `metadata()` 字典 | 5 个平铺键 | **不变**（同一组键，值取自 `meta`；FR-002 保护） |

### 2.2 槽位与设置档分离（不变）

| 槽位 | 落盘内容 | 说明 |
|---|---|---|
| `OptionsSave.SLOT`（`"options"`） | 元数据 + `options` 段 | **仅**设置；与游戏进度物理分离 |
| 其他任意合法槽位 | `to_dict()` 结果**去掉 `options` 键** | 游戏进度；不含机器级设置 |

`_list_slots()` MUST 排除设置档（由 `SCR-4` 验证）。

## 3. 字段类型约束（宪法原则 III）

分段字段只允许基础数据类型：`int` / `float` / `bool` / `String` / `Vector2(i)` / `Color` /
`Array` / `Dictionary`，以及嵌套 `SaveSection`。

禁止：`Object` / `Node` / `Resource` / `Callable` / `Signal` / `RID`。
`save_section.gd` 的 `UNSUPPORTED_TYPES` 与 `godot-lint` 的 `save_data_type` 规则（error 级）
共同保证这一点。

## 4. 拒绝载入的判定条件（MUST 保持，FR-007）

按判定顺序：

| 条件 | 结果 |
|---|---|
| 文件不存在 | 拒绝（`_read` 返回 `{}`） |
| 长度 < 魔数长度（4） | 拒绝 + 日志"文件太小" |
| 长度 > `MAX_SAVE_BYTES`（8 MiB） | 拒绝 + 日志"文件过大" |
| 前 4 字节 ≠ `"GTSV"` | 拒绝 + 日志"不是本项目的存档" |
| `bytes_to_var` 结果不是 `Dictionary` | 拒绝 + 日志"解码失败" |
| 槽位名非法（空 / 以 `.` 开头 / 含 `..` `/` `\` `:` `*` `?` `"` `<` `>` `\|`） | 请求阶段拒绝，不进入 IO |
| 文件版本 **<** 程序版本（本次即 `1 < 2`） | 走 `migrate()`；**本次策略 = 显式拒绝**（`migrate()` 返回 `{}`），给出**可区分**的原因：结构版本过旧、本版本不提供迁移 |
| 文件版本 **>** 程序版本 | 拒绝 + 提示用新版程序打开（既有保护，MUST 保持） |

这些拒绝理由**必须保持可区分**——重构 MUST NOT 把它们合并成笼统的失败。
版本不兼容的拒绝 MUST NOT 产生半读入（不得出现部分字段已更新、部分保持原值的混合状态，FR-006）。

## 5. 版本与兼容策略（本功能的核心变更）

### 5.1 本次的实际状态

**本次改变结构 → 提升版本 1 → 2 → 产生一次不兼容变更（援引一次性例外）。**

| 项 | 本次取值 |
|---|---|
| 变更内容 | 根上平铺的 `slot` / `saved_at` / `game_version` / `playtime` 移入 `meta` 分段（`MetaSave`）；**不新增字段** |
| `SaveData.version` | **2**（由 1 提升） |
| `migrate()` | **改为显式拒绝**（返回 `{}`，由 `_prepare_load` 给出可区分原因） |
| 是否产生不兼容变更 | **是**（v1 旧档不再可读） |
| 对外 `metadata()` 键 | **不变**（FR-002） |
| 对既有设置档的影响 | 本机既有的 v1 `options.sav` 会被**拒绝一次**，启动时按当前引擎状态重新播种设置（模板未发布、无真实用户，故可接受）；可能引起引擎基线新增行，MUST 在 `verification.md` 说明并按需重登 |

变更理由与备选方案见 `research.md` R4 的最终结论。

### 5.2 面向未来的策略（宪法原则 III + 一次性例外）

宪法要求「存档结构变更 MUST 提升结构版本号**并提供迁移路径**」**保持不变**。
本次裁定只追加一条**一次性例外**：模板尚未发布、不存在真实用户存档时，允许**一次**不兼容变更，
迁移路径 MAY 省略。该例外**只允许使用一次**，MUST NOT 被延期、重复援引或当作先例，
且**本次已被使用**（见 5.1：`version` 1 → 2，策略 = 显式拒绝）—— **用完即尽**：
此后任何结构变更 MUST 回到"提升版本 **并提供迁移路径**"的完整要求。

> **改结构时的硬要求（不变量）**
> 1. MUST 提升 `SaveData.version`；
> 2. MUST 记录：改了什么字段、从哪个版本到哪个版本、**为什么允许不兼容**；
> 3. MUST 选择并声明策略之一：
>    - **写迁移**：在 `migrate()` 中按 `from_version` 逐级补齐字段，返回新字典；
>    - **显式拒绝**：`migrate()` 返回 `{}`，并由 `_prepare_load` 给出可区分的失败原因。
>    （**只有**在援引上述一次性例外时，「写迁移」才 MAY 省略；例外只能被援引一次）
> 4. MUST NOT 悄悄改结构而不动版本号；
> 5. MUST NOT 出现"半读入"——部分字段已更新、部分保持原值的混合状态。

**例外的理由**：模板尚未发布，不存在真实用户存档，兼容性没有保护对象。
把它写成"一次性、可收回的许可"而不是删除原要求，是为了在重新出现真实用户后仍有一条明确的收回路径：
模板发布或出现真实用户存档后，MUST 通过一次专门修订收回该例外。

### 5.3 仍然不变的版本比较规则

`_prepare_load()` 的既有判定 MUST 保留：

- 文件版本 **==** 程序版本 → 直接载入；
- 文件版本 **>** 程序版本 → **拒绝**并提示用新版程序打开（防降级损坏数据）；
- 文件版本 **<** 程序版本 → 走 `migrate()`（策略见 5.2）。

## 6. 写入原子性（MUST 保持，FR-007）

1. 写入 `<slot>.sav.tmp`；
2. 检查 `get_error()`，失败则删除 tmp 并返回 `false`；
3. `DirAccess.rename_absolute(tmp, final)` 覆盖；
4. 改名失败则删除 tmp 并返回 `false`。

**不变量**：任何时刻都不存在"半写的正式存档文件"；中断只会留下 `.tmp`。
写入完成后 MUST NOT 残留 `.tmp`（由 `SCR-9` 验证）。

## 7. 验证方式

| 判据 | 探针 | 断言 |
|---|---|---|
| SCR-2 | `_probe_us1.gd` | 写入后首 4 字节 == `GTSV`；重新载入字段值与写入前逐字段一致；**落盘根键为 `version` / `meta`（+ `options`）且 `version == 2`**（v2 结构真实生效） |
| SCR-4 | `_probe_us1.gd` | 存档列表不含 `options`；`SAVE_LIST_READY` 收到数组本身 |
| SCR-7a | `_probe_us3.gd` | 构造 v1 旧档（`version == 1`、平铺元数据）→ `ok == false` 且 `error` 可区分（结构版本过旧 / 不提供迁移）；无半读入 |
| SCR-7b | `_probe_us3.gd` | 构造 `version > 2` 的存档 → `ok == false`（既有保护，MUST 保持） |
| SCR-8 | `_probe_us3.gd` | 非法槽位被拒绝；`..` 不产生路径穿越 |
| SCR-9 | `_probe_us3.gd` | 写入后目录中无 `.tmp` 残留 |
