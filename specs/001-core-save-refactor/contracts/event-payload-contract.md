# Contract: 事件负载形态（Event Payload Shape）

**Feature**: `001-core-save-refactor` | **Version**: 1.0 | **对应**: FR-003 / SC-006 / US2

本契约固化的是一条**此前只存在于实现细节里**的规则。它不改变任何行为——
保存它是为了让"跨模块调用方"有据可依，并让规则可被 `SCR-5` 探针机械验证。

---

## 1. 唯一规则

> **`push_event(name, payload)` 的 `payload` 是「订阅者参数表」。**
> 非数组会被自动包成单元素参数表；**数组则原样作为参数表使用**。

`CoreSystem.event_bus.push_event()` 的实际行为：

```gdscript
if not payload is Array:
    payload = [payload]      # 非数组 → 单元素参数表
...
conn["callable"].callv(payload)   # 数组即参数表
```

### 1.1 四条实测形态（`_probe_us2.gd` 已验证，非推理）

| 发送方写法 | 订阅者实际收到 | 订阅者签名应写 |
|---|---|---|
| `push_event(N, {"k": 1})` | **1 个参数**：该字典本身 | `func(d: Dictionary)` |
| `push_event(N, [items])`（**单元素**） | **1 个参数**：`items` 本身 | `func(items: Array)` |
| `push_event(N, [a, b, c])`（**多元素**） | **3 个参数**：`a`、`b`、`c` 各自独立 | `func(a, b, c)` |
| `push_event(N, [])` | **0 个参数** | `func()` |

**最容易踩的坑（本仓库曾写反过）**：

| 意图 | 正确写法 | 错误写法与后果 |
|---|---|---|
| 传**一个数组**作为单个参数 | `push_event(N, [items])` | `push_event(N, [[items]])` → 订阅者收到 `[items]`（多了一层） |
| 传**多个位置参数** | `push_event(N, [a, b])` | `push_event(N, a)` → 只传了一个，订阅者第二个参数缺失 |

### 1.2 为什么 `SAVE_LIST_READY` 必须写成 `[saves]` 而不能写成 `saves`

这是本契约最容易被人"顺手简化"而破坏的地方：

- `push_event(Events.SAVE_LIST_READY, [saves])` → `saves` 是 `Array[Dictionary]`，
  包成单元素参数表后，订阅者收到 **`saves` 本身**（一个数组）。✅ 正确
- `push_event(Events.SAVE_LIST_READY, saves)` → 数组直接当参数表 → 订阅者收到
  **N 个 `Dictionary` 位置参数**（N = 存档数量）。❌ **行为完全不同**，且订阅者签名只有 1 个参数，
  多出来的参数会被丢弃，结果是"只有第一个存档可见"或直接报参数错误。

**因此：改动这两个调用点时 MUST 同时更新本契约，MUST NOT 只改代码。**

## 2. 订阅方契约

| 事件 | 订阅者签名 | 收到的参数 |
|---|---|---|
| `Events.OPEN_UI` | `func(request: Types.OpenUiRequest)` | 请求对象本身 |
| `Events.CLOSE_UI` | `func(ui_path: String)` | 路径字符串本身 |
| `Events.SAVE_REQUEST` | `func(request: Types.SaveRequest)` | 请求对象本身 |
| `Events.LOAD_REQUEST` | `func(request: Types.LoadRequest)` | 请求对象本身 |
| `Events.DELETE_SAVE_REQUEST` | `func(request: Types.DeleteSaveRequest)` | 请求对象本身 |
| `Events.SAVE_LIST_REQUEST` | `func()` | 无参数 |
| `Events.SAVE_FINISHED` | `func(result: Types.SaveResult)` | 结果对象本身 |
| `Events.LOAD_FINISHED` | `func(result: Types.SaveResult)` | 结果对象本身 |
| `Events.DELETE_SAVE_FINISHED` | `func(result: Types.SaveResult)` | 结果对象本身 |
| `Events.SAVE_LIST_READY` | `func(saves: Array)` | **数组本身**（`Array[Dictionary]`），不是嵌套数组 |

## 3. 本契约**不**包含的内容

- **不承诺** `immediate=false` 时的跨帧时序（该参数存在，但本框架的排队语义未在此固化）。
- **不承诺**同一事件多订阅者的执行顺序（受 `Priority` 影响，属框架层行为）。
- **不改变**任何事件名或结构体字段（FR-002 保护范围）。

## 4. 验证方式

`res://_probe_us2.gd`（`extends SceneTree`）必须断言：

1. 非数组负载 → 订阅者收到**该对象本身**，`typeof` 与发送方一致；
2. 数组负载 → 订阅者收到**该数组本身**，且 `typeof(received) == TYPE_ARRAY`、
   `received[0]` 不是 `Array`（**证明没有嵌套**）；
3. 多元素数组 → 订阅者按位置收到各元素。

判据：三条全部通过，0 例嵌套数组（对应 SC-006）。
