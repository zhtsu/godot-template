class_name SaveData
extends SaveSection

## 存档根：元数据 + 各个分段。分段都在这个目录下各自一个类。
## 落盘格式是纯二进制 Variant 数据（core/save_service.gd 负责读写），
## 磁盘上不含任何脚本 / 资源引用。
##
## 加一个新分段只要两步（详见 save_section.gd）：
##   1) 新建 xxx_save.gd：class_name XxxSave extends SaveSection
##   2) 在下面"分段"区加一行：var xxx: XxxSave = XxxSave.new()

## SaveService 启动时会把它指向自己持有的那一份，方便各处只读访问：
##   SaveData.current.options.language
## 只读用；改数据仍然发事件（Events.SAVE_REQUEST），不要直接改这个引用。
static var current: SaveData = null

## 存档结构版本：以后增删字段时 +1，并在下面的 migrate() 里写迁移
var version: int = 1
## 槽位 ID、保存时间、当时游戏版本、累计游戏时长（前三个由 SaveService 自动填）
var slot: String = ""
var saved_at: String = ""
var game_version: String = ""
var playtime: float = 0.0

# ===== 分段：加一行就多一块存档内容 =====

## 设置界面选中的项（分辨率 / 语言）；候选列表在 core/options_data.gd
var options: OptionsSave = OptionsSave.new()


## 只取元数据，给存档列表用
func metadata() -> Dictionary:
	return {
		"version": version,
		"slot": slot,
		"saved_at": saved_at,
		"game_version": game_version,
		"playtime": playtime,
	}


## 旧档迁移钩子：载入的存档 version 低于当前 version 时会先调用它。
## 默认原样返回（尽力按现有字段载入）；真要迁移就在这里按 from_version 逐级补字段。
## 返回空字典 = 拒绝载入这个存档。
func migrate(dict: Dictionary, _from_version: int) -> Dictionary:
	return dict
