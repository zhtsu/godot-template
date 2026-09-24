# Godot Template

基于 **Godot 4.7**（纯 GDScript）的游戏项目模板：框架能力、事件总线、UI 记账、存档系统、设置界面、
游戏流程层都已经接好，并自带一套可执行的静态检查与引擎验证脚本。

## 快速开始

1. 用 Godot **4.7** 打开 `godot-template/`（`project.godot` 所在目录）。
2. 运行主场景 `entry/main.tscn`：主菜单 → 开始（示例关卡）→ `ESC` 暂停 → 返回标题。
3. 设置界面可改分辨率 / 语言 / 音量（主音量、音乐、音效）/ 暂停键：**改动即存** ——
   改完立刻写进 `user://saves/options.sav` 并立即生效（没有 Apply / Cancel）。
   音量是**分档**的（档位见 `core/options_data.gd` 的 `VOLUME_STEPS`，当前 0~10、每档 1）：
   滑块只在档位之间跳，且只有档位变化才会写档。

## 目录结构

```
godot-template/                     ← Godot 工程根（用 Godot 打开这一层）
├── project.godot
├── addons/godot_core_system/       框架层（第三方插件，默认不改）
├── core/                           约定层 + 服务层
│   ├── paths.gd                    所有 res:// 路径常量（唯一来源）
│   ├── events.gd                   所有事件名（唯一来源）
│   ├── types.gd                    请求 / 结果结构体（唯一来源）
│   ├── options_data.gd             设置候选值（分辨率 / 语言）
│   ├── ui_root.gd                  UI 实例化 / 分层 / 记账
│   ├── save_service.gd             存档服务（事件驱动，持有唯一一份 SaveData）
│   ├── save_storage.gd             纯文件 IO（static、无状态、目录由参数传入）
│   ├── options_applier.gd          设置 → 引擎状态（语言 / 分辨率 / 全屏）
│   └── game_flow.gd                游戏流程（boot → title → gameplay → pause）
├── save_data/                      存档结构（一段一个类）
├── ui/                             界面：main_menu / options / pause_menu / credits
├── game/                           关卡场景（模板只放了一个示例关卡）
├── entry/main.tscn                 主场景（常驻壳：UiRoot + SaveService + GameFlow）
└── locale/                         翻译：en.po / zh_CN.po / texts.pot

scripts/                            验证脚本（见下）
```

## 三条主线

1. **事件总线**：模块之间不互相引用，只发事件（`CoreSystem.event_bus`）。
   `push_event(name, payload)` 的 payload **就是订阅者的参数表**（四种形态见 `core/events.gd` 的注释）。
2. **UI 记账**：界面只能经 `Events.OPEN_UI` / `Events.CLOSE_UI` 开关，
   由 `core/ui_root.gd` 统一实例化、分层、记账；不要在界面里自己 `instantiate()` / `queue_free()`。
3. **存档**：`GTSV` 魔数 + `var_to_bytes()` 的纯二进制，不承载任何逻辑；
   一段一个类；写入原子（`.tmp` → rename）；设置档独占 `options` 槽位。

游戏流程层是**常驻壳**：`entry/main.tscn` 上的 UiRoot / SaveService / GameFlow 不随关卡切换重建，
关卡场景只被换进 `GameFlow/SceneRoot`，所以存档状态与已开界面不受切场景影响。

## 验证

```powershell
pwsh scripts/godot-lint.ps1                                    # 静态规则门禁
pwsh scripts/verify-engine.ps1                                 # 引擎冒烟 + 与基线逐行比对
pwsh scripts/verify-engine.ps1 -Scenario res://ui/options/options.tscn
pwsh scripts/verify-engine.ps1 -Probe res://_probe_xxx.gd       # 一次性探针（交付前删除）
pwsh scripts/verify-engine.ps1 -UpdateBaseline                  # 人工确认后重登基线
```

判据是「相对基线 **无新增** ERROR/WARNING」，**不是**「退出码 0 且没有 ERROR」：
本机冒烟稳定输出 5 行噪声（`user://` 日志写不了 ×2、证书库读不到、ObjectDB 泄漏、资源残留），
而 Godot 退出码仍是 0。基线是机器相关的，换机器或存档状态大变后用 `-UpdateBaseline` 重登。

## 约定与未完成事项

面向 AI/协作者的约束（改代码前先看）：`AGENTS.md`。
已知未完成事项也在那份文件末尾。
