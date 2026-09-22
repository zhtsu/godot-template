# Phase 0 Research: core/ 与 save_data/ 审查重构

**Feature**: `001-core-save-refactor` | **Date**: 2026-09-23

本文件记录审查中**需要技术裁决**的项。已明确、无争议的项不在此重复。

---

## R1. 事件 payload 形态：文档与实现相反

### 现状（实测）

`addons/godot_core_system/source/event_system/event_bus.gd:30-32` 与 `:86-90`：

```gdscript
func push_event(event_name: String, payload : Variant = [], immediate: bool = true) -> void:
	if not payload is Array:
		payload = [payload]          # 非数组 → 自动包成单元素参数表
	...
	for conn in filtered_connections:
		if immediate:
			conn["callable"].callv(payload)   # 数组本身就是参数表
```

因此真实契约是：**payload 永远按「参数表」语义处理**。

| 发送方写法 | `callv` 实际收到的参数 | 订阅者签名 |
|---|---|---|
| `push_event(N, result)`（result 是对象） | `payload = [result]` → 1 个参数 | `func(result)` |
| `push_event(N, [items])`（items 是数组） | 1 个参数，**就是 items 本身** | `func(items)` |
| `push_event(N, [a, b])` | 2 个参数 | `func(a, b)` |

而 `AGENTS.md` 硬规则 4 写的是「payload 是**数组**时要再包一层（`push_event(NAME, [payload])`），
否则会被当成参数列表展开」。**这条与实现相反**：按它执行会得到 `[[items]]`，订阅者收到的是嵌套数组。
正确表述应是「**要传数组作为一个参数**时，直接传该数组——因为数组就是参数表」。

### 现有调用点核查（全部正确，无需改代码）

| 位置 | 写法 | 订阅者签名 | 判定 |
|---|---|---|---|
| `core/save_service.gd:461` `_emit` | `push_event(name, result)` | `_on_*` 收单个 `Types.SaveResult` | 正确 |
| `core/save_service.gd:215` | `push_event(SAVE_LIST_READY, [saves])` | 注释说明"收一个参数" | 正确 |
| `core/ui_root.gd:13-14` `subscribe_unique_script` | 订阅 `OPEN_UI`/`CLOSE_UI` | `_open_ui(request)` / `_close_ui(path)` | 正确 |
| `entry/main.gd:7`、`ui/main_menu/main_menu.gd:17` | `push_event(OPEN_UI, request)` | `_open_ui(request)` | 正确 |

**结论：代码没有 bug，bug 在文档。** 这解释了为什么两种写法看起来矛盾却都能工作。

- **Decision**: 不改任何 `push_event` 调用点（改了反而引入回归）。只修正规则描述，
  并用探针把该契约固化成可执行断言（spec 的 `SC-006`）。
- **Rationale**: 调用点是自洽的；错误信息只在人写的文档里。修文档 + 加断言，
  比"为对齐一条错描述去改正确代码"风险低得多。同时 FR-002 要求不改可观测行为。
- **Alternatives considered**:
  - 把 `AGENTS.md` 规则改写成"传数组要拆开"→ **排除**：会误导成 `push_event(N, items[0], items[1])` 这类错误写法。
  - 修改 `event_bus.gd` 让数组不自动展开 → **排除**：它是冻结的框架层（宪法原则 II/VI），
    且会破坏框架内既有订阅者。
- **落地位置**: `core/events.gd` 注释、`AGENTS.md` 硬规则 4、
  `specs/001-core-save-refactor/contracts/event-payload-contract.md`。

---

## R2. `apply_dict()` 无类型校验

### 现状

`save_data/save_section.gd:76-91`：

```gdscript
func apply_dict(patch: Dictionary) -> void:
	var fields: Dictionary = field_names()
	for key in patch:
		if not fields.has(key):
			push_warning(...)   # 未知字段：告警 + 忽略 ✓
			continue
		var current: Variant = get(key)
		var value: Variant = patch[key]
		if current is SaveSection:
			if value is Dictionary:
				current.apply_dict(value)
			else:
				push_warning(...)   # 分段被设成非字典：告警 + 忽略 ✓
		else:
			set(key, value)         # ← 无任何类型校验
```

已知保护：未知字段被忽略、分段不被非字典清空。**缺口**：`set(key, value)` 接受任意类型。
`save_data/save_service.gd:151` 在存档前调用它（`request.data` 来自事件 payload，是外部输入）。

### 后果推演

`options.resolution` 期望 `Vector2i`，若补丁传 `Vector2i.ZERO` 之外的类型（如 `"1920x1080"` 字符串）：
- 写入不会报错；`validate_tree()` 只在**载入后**调用（`:180`），写入路径不校验；
- 若补丁来自"设置界面之外"的调用方，错误值可能直接落盘；
- 载入时才被 `OptionsSave.validate()` 改回默认 —— 表现为"设置莫名其妙被重置"，
  与宪法原则 III「静默丢数据是 bug」同类。

### 选项评估

| 方案 | 行为 | 评价 |
|---|---|---|
| A. 用 `typeof(current) != typeof(value)` 拒绝 | 严格同型 | **排除**：Godot 里 `int`/`float` 在实践中常互通（如 JSON 解码、字面量 `1` 对 `float` 字段），会误伤合法补丁 |
| B. 只对数值类做放宽，其余严格 | `int`→`float` 与 `float`→`int`（无损）允许，其余要求同型 | **采纳** |
| C. 完全不做校验，改在写入前统一 `validate_tree()` | 复用既有校验钩子 | **排除（作为唯一手段）**：`validate()` 是"修正越界值"语义，不是"拒绝错误类型"；且它会**静默改正**而非告警，与 FR-004 要求"产生可观测告警"不符。可作为 B 的补充，但不能替代 |
| D. 抛错中断整次存档 | 强一致 | **排除**：`apply_dict` 是通用工具，抛错会让一个坏字段毁掉整次合法存档；且违反 Edge Case「空补丁不改任何字段」的宽松取向 |

- **Decision**: **B + C 组合** —— 在 `apply_dict()` 内部做逐字段类型兼容检查（不兼容则跳过该字段并
  `push_warning` 出字段名/期望类型/实际类型），同时**在写入路径补一次 `validate_tree()`**，
  让"范围/白名单类"问题也在落盘前被兜住。
- **Rationale**: 类型不兼容属于"调用方写错了"，应当可观测地拒绝（告警 + 保持原值），
  而不是静默改成别的值；范围问题则属于"值不合理"，继续用既有 `validate()` 修正。
  两者语义不同，因此不合并成一个机制。
- **Alternatives considered**: 见上表 A/C/D。
- **兼容性注意**: `int`↔`float` 放宽是**新增行为**（此前会静默 `set` 任意类型）。
  它对现有调用方的影响：不会有合法调用被拒绝——现状能通过的合法补丁要么同型、
  要么是数值互通，两者在新规则下仍然通过。这一点 MUST 由 SCR-6 探针覆盖（正确补丁仍成功）。
- **落地位置**: `save_data/save_section.gd` 的 `apply_dict()`；
  `core/save_service.gd` 的 `_do_save()`。

---

## R3. `save_service.gd` 拆分的边界

### 现状职责清单（463 行）

1. 事件订阅/退订（`:50-74`）
2. 请求校验（`:80-117`，槽位合法性）
3. 任务队列与 drain 上限（`:124-142`）
4. 存档/读档/删档/列表（`:149-217`）
5. 设置档启动处理与引擎状态播种（`:226-253`）
6. 把设置应用到引擎（`:257-278`）
7. 二进制序列化与原子文件 IO（`:287-365`）
8. 元数据补齐（`:443-446`）
9. 结果对象组装与发送（`:450-461`）

### 拆分原则

**只抽"无状态"部分。** 判断标准：抽出的代码是否需要访问 `save_data` / `_jobs` / `_save_dir`。
需要 → 留在 `save_service`；不需要 → 可抽。

| 抽出目标 | 内容 | 是否需要状态 | 判定 |
|---|---|---|---|
| `core/save_storage.gd` | 魔数/长度/大小上限校验、`bytes_to_var` 解码、原子写、目录枚举、槽位名过滤、路径拼接 | 需要 `_save_dir` 与几个常量 → **改为参数传入** | 抽（纯函数化） |
| `core/options_applier.gd` | `set_locale` / `window_set_size` / 全屏模式 | 不需要 | 抽 |
| 任务队列 | `_jobs` / `_draining` / `_drain_jobs` | 需要状态 | **留** |
| 事件订阅与结果发送 | `_emit` | 需要 `CoreSystem` 且属对外语义 | **留** |
| 存档数据所有权 | `save_data`、`SaveData.current` | 状态 | **留** |

- **Decision**: 抽出 `save_storage`（纯文件 IO，`_save_dir` 作为参数）与 `options_applier`（纯应用）。
  两者**都不加 `class_name`**，用 `preload` 常量引用；都**不订阅事件**、不持有存档数据。
- **Rationale**: 这是"改善可辨认性"（FR-008）与"零行为变化"（FR-002）之间代价最小的平衡点。
  全量拆成多类需要给它们传状态或引入回调，会把简单数据流变成依赖注入，收益不抵风险。
- **Alternatives considered**:
  - 拆成 `save_job_queue.gd` → **排除**：队列与 `_drain_jobs` 的"一次 16 个、剩余下一帧"语义
    与被调用的 job 闭包强耦合，抽出会让接口复杂化而看不出收益。
  - 给新类加 `class_name` → **排除**：会污染全局类缓存并强制 `--import`，
    与"本计划不新增 `class_name`"的验证前提冲突。
  - 建 `core/save/` 子目录 → **排除**：与 `core/` 现有平铺约定不一致，且宪法「目录契约」
    对新增结构有说明要求，本次不值得付这个代价。

---

## R4. 存档结构变更：本次**执行一次**不兼容变更（`version` 1 → 2）

**Decision**: **改变结构 —— 把既有元数据字段从存档根上平铺移入独立分段 `meta`（`MetaSave`），
`SaveData.version` 由 1 提升到 2；旧档策略为「显式拒绝」，不写迁移。**

变更内容（**不新增任何字段**，只调整分段组织，符合 spec `PR-001`）：

| | v1 | v2 |
|---|---|---|
| 根上字段 | `version` / `slot` / `saved_at` / `game_version` / `playtime` / `options` | `version` / `meta` / `options` |
| 元数据位置 | 根上平铺 | `meta` 分段（`MetaSave`：`slot` / `saved_at` / `game_version` / `playtime`） |
| 内存字段路径 | `save_data.slot` | `save_data.meta.slot` |
| 对外 `metadata()` 字典 | 5 个平铺键 | **不变**（仍返回同一组平铺键，值取自 `meta`；FR-002 保护范围） |

- **为什么允许不兼容**：模板尚未发布、不存在真实用户存档，旧档没有需要保留的价值；
  本次援引宪法原则 III 的一次性例外（**用后即尽**），并把理由与影响记录在
  `contracts/save-file-format.md` §5.2 与 `AGENTS.md` 的存档契约条目。
- **为什么选「显式拒绝」而不是「写迁移」**：迁移要对 v1 的四个字段重新归位，
  而目标集合是空的（没有任何真实旧档）；写了也无法被真实数据验证，属原则 V 意义上的不可验证代码。
  拒绝路径**可验证**（构造 v1 档 → 必须得到可区分失败且无半读入），因此优先选它。
- **对外行为（FR-002）**：`metadata()` 的键、事件名与结果字段**全部不变**；
  变的只是**磁盘字典结构与内存字段路径**。

**此前结论（已撤销，保留记录以免误读版本号）**：本文件初稿的 R4 结论是"不需要变更、
`SaveData.version` 保持 1"，理由是"三项待修内容没有一项涉及落盘字段，提升版本会伪造结构语义"。
用户裁定改为**执行**这次变更（spec `PR-002` 的契约本就写着"结构变更 = 是"），
并因此**消耗**宪法原则 III 的一次性例外。

**Alternatives considered**:
- 维持 v1、不改变结构（原结论）→ **排除**：用户明确裁定"本次真做一次不兼容结构变更并提升 `version`"。
- 顺手把 `options` 拆成独立版本号 → **排除**：属新增功能（spec Non-Goals 排除），且会引入
  "两个版本号谁说了算"的新问题。
- 为 v1 写迁移 → **排除**：目标集合为空，写出来的迁移无法被真实数据覆盖验证（见上）。
