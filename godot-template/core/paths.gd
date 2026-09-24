class_name Paths

## 项目所有资源路径的集中管理。
## 所有脚本都应从这里引用路径，禁止散落硬编码的 "res://..." 字符串。

# ===== UI 场景 =====
const UI_MAIN_MENU: String =   "res://ui/main_menu/main_menu.tscn"
const UI_OPTIONS: String =     "res://ui/options/options.tscn"
const UI_PAUSE_MENU: String =  "res://ui/pause_menu/pause_menu.tscn"
const UI_CREDITS: String =     "res://ui/credits/credits.tscn"

# ===== 关卡场景（模板自带的最小示例；游戏项目在这里换成自己的关卡）=====
const GAME_EXAMPLE_LEVEL: String = "res://game/example_level.tscn"

# ===== 脚本（刻意不加 class_name，用 preload 引用；脚本路径同样只写在本文件里）=====
const SCRIPT_SAVE_STORAGE: String =    "res://core/save_storage.gd"
const SCRIPT_OPTIONS_APPLIER: String = "res://core/options_applier.gd"